using Test
include("../src/PocketFlow.jl")
using .PocketFlow

@testset "Transitions & default action" begin
    struct A <: AbstractNode end
    struct B <: AbstractNode end
    PocketFlow.exec(::A, _) = "x"
    PocketFlow.post(::A, shared, _, x) = (shared.data["a"]=x; nothing) # default
    PocketFlow.exec(::B, _) = 42
    PocketFlow.post(::B, shared, _, y) = (shared.data["b"]=y; nothing)

    a = A(); b = B()
    a >> b
    shared = SharedStore()
    run(Flow(start=a), shared)
    @test shared.data["a"] == "x"
    @test shared.data["b"] == 42
end

@testset "Labeled action" begin
    struct C <: AbstractNode end
    struct D <: AbstractNode end
    PocketFlow.exec(::C, _) = nothing
    PocketFlow.post(::C, _, _, _) = "go"
    PocketFlow.exec(::D, _) = 1
    PocketFlow.post(::D, s, _, r) = (s.data["d"]=r; nothing)

    c = C(); d = D()
    (c - "go") >> d
    shared = SharedStore()
    run(Flow(start=c), shared)
    @test shared.data["d"] == 1
end

@testset "Per-node retries + fallback" begin
    mutable struct Flaky <: AbstractNode end
    PocketFlow.node_config(::Flaky) = NodeConfig(3, 0.0)
    PocketFlow.exec(::Flaky, _) = (cur_retry(Flaky()) < 10 ? error("boom") : 1) # force fail
    PocketFlow.exec_fallback(::Flaky, _, _) = 7
    PocketFlow.post(::Flaky, s, _, x) = (s.data["x"]=x; nothing)

    f = Flaky()
    shared = SharedStore()
    run(f, shared)
    @test shared.data["x"] == 7
end

@testset "Flow-as-Node" begin
    struct Q <: AbstractNode end
    struct R <: AbstractNode end
    PocketFlow.exec(::Q, _) = 2
    PocketFlow.post(::Q, s, _, r) = (s.data["q"]=r; nothing)
    PocketFlow.exec(::R, _) = 3
    PocketFlow.post(::R, s, _, r) = (s.data["r"]=r; nothing)

    q = Q(); r = R()
    q >> r
    sub = Flow(start=q)

    # Parent flow uses subflow as a node
    parent_start = sub
    shared = SharedStore()
    run(Flow(start=parent_start), shared)
    @test shared.data["q"] == 2
    @test shared.data["r"] == 3
end

@testset "Batch map-reduce" begin
    struct UpMap <: AbstractBatchNode end
    PocketFlow.prep_batch(::UpMap, s) = ["a","b"]
    PocketFlow.exec_item(::UpMap, ::Any, item) = uppercase(item)
    PocketFlow.post_batch(::UpMap, s, _, res) = (s.data["mapped"]=res; "default")

    struct JoinR <: AbstractNode end
    PocketFlow.prep(::JoinR, s) = s.data["mapped"]
    PocketFlow.exec(::JoinR, items) = join(items, "-")
    PocketFlow.post(::JoinR, s, _, y) = (s.data["out"]=y; nothing)

    m = UpMap(); j = JoinR()
    m >> j
    s = SharedStore()
    run(Flow(start=m), s)
    @test s.data["out"] == "A-B"
end
