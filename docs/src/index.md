# PocketFlow.jl

Welcome to the documentation for **PocketFlow.jl** — a modular, composable flow engine for Julia.

```julia
using PocketFlow

struct MyNode <: AbstractNode end

function prep(::MyNode, store::SharedStore)
    store.data["x"] = 42
end

function exec(::MyNode, store::SharedStore)
    @info "x = $(store.data["x"])"
end

flow = Flow([MyNode()])
run!(flow)
```

## Installation

```julia
using Pkg
Pkg.add("PocketFlow")
```

## Links
- GitHub: https://github.com/yourusername/PocketFlow.jl
- README: See examples and ...
```