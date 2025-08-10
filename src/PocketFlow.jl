module PocketFlow

export SharedStore, AbstractNode, Flow,
       NodeConfig, node_config, cur_retry,
       prep, exec, exec_fallback, post,
       run!, set_params, action, (>>), (-)

using Logging
import Base: -, >>

# ---------------- Core Data ----------------

"Mutable shared store for node communication."
mutable struct SharedStore
    data::Dict{String,Any}
end
SharedStore() = SharedStore(Dict{String,Any}())

"Retry/backoff config (per-node). Defaults: 1 try, no wait."
struct NodeConfig
    max_retries::Int
    wait::Float64
end
NodeConfig() = NodeConfig(1, 0.0)

"Per-node config hook (override per node type if needed)."
node_config(::Any) = NodeConfig()

# Track current retry count per node during execution (for diagnostics/logic).
const _CUR_RETRY = IdDict{Any,Int}()
cur_retry(n) = get(_CUR_RETRY, n, 0)

# ---------------- Node Protocol ----------------

"Nodes implement prep/exec/post (and optional exec_fallback)."
abstract type AbstractNode end

# NOTE: Framework defaults intentionally use ::Any for non-node args to avoid
# cross-arg specificity ambiguities with user overrides.
prep(::AbstractNode, ::Any) = nothing

"Compute step. Must be pure w.r.t. shared store."
exec(::AbstractNode, ::Any) = nothing

"Override to gracefully continue after all retries. Default: rethrow."
exec_fallback(::AbstractNode, ::Any, exc) = throw(exc)

"Write to shared & choose next action (String) or nothing => \"default\"."
post(::AbstractNode, ::Any, ::Any, ::Any) = nothing

# ---------------- Transitions / Graph DSL ----------------

const _TRANSITIONS = IdDict{AbstractNode, Dict{String,AbstractNode}}()

struct _ActionRef
    node::AbstractNode
    action::String
end

(-)(n::AbstractNode, a::String) = _ActionRef(n, a)
action(n::AbstractNode, a::String) = _ActionRef(n, a)

function Base.:>>(a::AbstractNode, b::AbstractNode)
    ft = get!(_TRANSITIONS, a, Dict{String,AbstractNode}())
    ft["default"] = b
    b
end

function Base.:>>(ar::_ActionRef, b::AbstractNode)
    ft = get!(_TRANSITIONS, ar.node, Dict{String,AbstractNode}())
    ft[ar.action] = b
    b
end

"Clear all currently wired edges (useful between graph builds/tests)."
clear_edges!() = (empty!(_TRANSITIONS); nothing)

# ---------------- Flow (also a Node) ----------------

mutable struct Flow <: AbstractNode
    start::AbstractNode
    transitions::IdDict{AbstractNode, Dict{String,AbstractNode}}
    params::Dict{String,Any}
end

"Snapshot the currently wired graph into this Flow and (optionally) clear global edges."
function Flow(; start::AbstractNode, clear_after::Bool=true)
    snap = IdDict{AbstractNode, Dict{String,AbstractNode}}()
    for (k,v) in _TRANSITIONS
        snap[k] = copy(v)
    end
    clear_after && clear_edges!()
    Flow(start, snap, Dict{String,Any}())
end

function set_params(f::Flow, p::Dict{String,Any})
    merge!(f.params, p); f
end

# ---------------- Engine ----------------

# Internal worker for regular (non-batch) nodes
function _run_node_core(n::AbstractNode, shared::SharedStore)::String
    # Flow as Node: run its subgraph
    if n isa Flow
        run(n::Flow, shared)
        act = post(n, shared, nothing, nothing)
        return something(act, "default")
    end

    prep_res = prep(n, shared)
    cfg = node_config(n)
    for attempt in 0:cfg.max_retries-1
        _CUR_RETRY[n] = attempt
        try
            @debug "exec($(typeof(n))) attempt=$(attempt)"
            exec_res = exec(n, prep_res)
            act = post(n, shared, prep_res, exec_res)
            return something(act, "default")
        catch err
            if attempt < cfg.max_retries-1
                cfg.wait > 0 && sleep(cfg.wait)
                continue
            end
            fb = exec_fallback(n, prep_res, err)
            act = post(n, shared, prep_res, fb)
            return something(act, "default")
        end
    end
    return "default"
end

abstract type AbstractBatchNode <: AbstractNode end

# Internal worker for batch nodes
function _run_node_batch(n::AbstractBatchNode, shared::SharedStore)::String
    items = prep_batch(n, shared)
    cfg = node_config(n)
    results = Vector{Any}(undef, length(items))

    for (i, item) in enumerate(items)
        for attempt in 0:cfg.max_retries-1
            _CUR_RETRY[n] = attempt
            try
                results[i] = exec_item(n, item, item)
                break  # success for this item
            catch err
                if attempt < cfg.max_retries - 1
                    cfg.wait > 0 && sleep(cfg.wait)
                    continue
                end
                try
                    results[i] = exec_item_fallback(n, item, err)
                catch _
                    results[i] = err  # surface to post_batch if desired
                end
            end
        end
    end

    act = post_batch(n, shared, items, results)
    return something(act, "default")
end

"Single public entry: routes to batch or core as needed."
function _run_node(n::AbstractNode, shared::SharedStore)::String
    if n isa AbstractBatchNode
        return _run_node_batch(n::AbstractBatchNode, shared)
    else
        return _run_node_core(n, shared)
    end
end

"Follow action-labeled edges until no successor exists (Flow-local transitions)."
function run(f::Flow, shared::SharedStore)
    cur = f.start
    while true
        act = _run_node(cur, shared)
        nxt = get(get(f.transitions, cur, Dict{String,AbstractNode}()), act, nothing)
        nxt === nothing && break
        cur = nxt
    end
    nothing
end
const run! = run

"Convenience: run a single node (debug)."
function run(n::AbstractNode, shared::SharedStore)
    _ = _run_node(n, shared)
    nothing
end

# =======================
# Batch support (sync)
# =======================
export AbstractBatchNode, prep_batch, exec_item, exec_item_fallback, post_batch

"Batch nodes map over an iterable, then reduce once."
# abstract type AbstractBatchNode <: AbstractNode end

"Return an iterable of items to process."
prep_batch(::AbstractBatchNode, ::Any) = Any[]

"Compute for ONE item (pure wrt shared)."
exec_item(::AbstractBatchNode, ::Any, item) = item

"Optional graceful fallback for a single item."
exec_item_fallback(::AbstractBatchNode, ::Any, exc) = throw(exc)

"Reduce across all item results; return action label or `nothing` (=> default)."
post_batch(::AbstractBatchNode, ::Any, prep_items, exec_results) = nothing

"Engine path for batch nodes (per-node retries apply per item)."
function _run_node(n::AbstractBatchNode, shared::SharedStore)
    items = prep_batch(n, shared)
    cfg = node_config(n)
    results = Vector{Any}(undef, length(items))

    # Iterate with indices so we can store results deterministically
    for (i, item) in enumerate(items)
        for attempt in 0:cfg.max_retries-1
            _CUR_RETRY[n] = attempt
            try
                results[i] = exec_item(n, item, item)
                break  # success for this item
            catch err
                if attempt < cfg.max_retries - 1
                    cfg.wait > 0 && sleep(cfg.wait)
                    continue
                end
                # final attempt failed: try item-level fallback
                try
                    results[i] = exec_item_fallback(n, item, err)
                catch _
                    results[i] = err  # surface the error object to post_batch if desired
                end
            end
        end
    end

    act = post_batch(n, shared, items, results)
    return something(act, "default")
end

end # module
