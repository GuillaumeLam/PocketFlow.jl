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

"Transitions keyed by node *identity*."
const _TRANSITIONS = IdDict{AbstractNode, Dict{String,AbstractNode}}()

"Internal: reference used by `node - \"label\" >> next`."
struct _ActionRef
    node::AbstractNode
    action::String
end

(-)(n::AbstractNode, a::String) = _ActionRef(n, a)
action(n::AbstractNode, a::String) = _ActionRef(n, a)

"Default-edge: a >> b (i.e., label == \"default\")."
function Base.:>>(a::AbstractNode, b::AbstractNode)
    ft = get!(_TRANSITIONS, a, Dict{String,AbstractNode}())
    ft["default"] = b
    b
end

"Labeled-edge: (a - \"ok\") >> b."
function Base.:>>(ar::_ActionRef, b::AbstractNode)
    ft = get!(_TRANSITIONS, ar.node, Dict{String,AbstractNode}())
    ft[ar.action] = b
    b
end

# ---------------- Flow (also a Node) ----------------

"Flows orchestrate nodes; can also be used as a Node (nesting)."
mutable struct Flow <: AbstractNode
    start::AbstractNode
    params::Dict{String,Any}
end
Flow(; start::AbstractNode) = Flow(start, Dict{String,Any}())

"Optional param bag (semantic sugar for Batch/Async patterns later)."
function set_params(f::Flow, p::Dict{String,Any})
    merge!(f.params, p); f
end

# ---------------- Engine ----------------

"Run a single node with its per-node retry/fallback; return action label."
function _run_node(n::AbstractNode, shared::SharedStore)
    # Special case: Flow as Node => run its subgraph as a unit
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
            # Final fallback (graceful)
            fb = exec_fallback(n, prep_res, err)
            act = post(n, shared, prep_res, fb)
            return something(act, "default")
        end
    end
    "default"
end

"Follow action-labeled edges until no successor exists."
function run(f::Flow, shared::SharedStore)
    cur = f.start
    while true
        act = _run_node(cur, shared)
        nxt = get(get(_TRANSITIONS, cur, Dict{String,AbstractNode}()), act, nothing)
        nxt === nothing && break
        cur = nxt
    end
    nothing
end
const run! = run

"Convenience: run a single node (debug)."
function run(n::AbstractNode, shared::SharedStore)
    _ = _run_node(n, shared); nothing
end

# --- Batch support ---
abstract type AbstractBatchNode <: AbstractNode end

# Default batch hooks (override in your nodes)
prep_batch(::AbstractBatchNode, ::Any) = Any[]            # returns iterable (Vector by default)
exec_item(::AbstractBatchNode, ::Any, item) = item        # compute for one item
post_batch(::AbstractBatchNode, ::Any, prep_items, exec_results) = nothing  # return action or nothing

# Engine path for batch nodes
function _run_node(n::AbstractBatchNode, shared::SharedStore)
    prep_items = prep_batch(n, shared)
    cfg = node_config(n)
    results = Vector{Any}(undef, length(prep_items))
    for (i, item) in pairs(prep_items)
        last_err = nothing
        for attempt in 0:cfg.max_retries-1
            _CUR_RETRY[n] = attempt
            ok = true
            try
                results[i] = exec_item(n, item, item)
            catch err
                ok = false
                if attempt < cfg.max_retries-1
                    cfg.wait > 0 && sleep(cfg.wait)
                else
                    # Give node a chance to recover on an item
                    try
                        results[i] = exec_item_fallback(n, item, err)
                        ok = true
                    catch _
                        # store the error; node can inspect later if desired
                        results[i] = err
                    end
                end
            end
            ok && break
        end
    end
    act = post_batch(n, shared, prep_items, results)
    return something(act, "default")
end

# Optional per-item fallback
exec_item_fallback(::AbstractBatchNode, ::Any, exc) = throw(exc)

end # module
