using .PocketFlow

# Map: uppercase each chunk
struct UpperMap <: PocketFlow.AbstractBatchNode end
PocketFlow.prep_batch(::UpperMap, shared) = get(shared.data, "chunks", String[])
PocketFlow.exec_item(::UpperMap, ::Any, item) = uppercase(String(item))
PocketFlow.post_batch(::UpperMap, shared, prep_items, exec_results) = (
    shared.data["mapped"] = exec_results; "default"
)

# Reduce: join with spaces
struct JoinReduce <: PocketFlow.AbstractNode end
PocketFlow.prep(::JoinReduce, shared) = get(shared.data, "mapped", String[])
PocketFlow.exec(::JoinReduce, items) = join(items, " ")
PocketFlow.post(::JoinReduce, shared, _, result) = (shared.data["reduced"] = result; nothing)

# Wire + run
mapn = UpperMap()
reduc = JoinReduce()
mapn >> reduc

shared = SharedStore()
shared.data["chunks"] = ["pocket", "flow", "rocks"]
flow = Flow(start = mapn)
run!(flow, shared)

@info "Mapped" shared.data["mapped"]
@info "Reduced" shared.data["reduced"]
