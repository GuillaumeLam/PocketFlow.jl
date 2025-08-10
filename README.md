# PocketFlow.jl

[![Build Status](https://github.com/yourusername/PocketFlow.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/yourusername/PocketFlow.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/yourusername/PocketFlow.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/yourusername/PocketFlow.jl)
[![Stable Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://yourusername.github.io/PocketFlow.jl/stable/)
[![Dev Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://yourusername.github.io/PocketFlow.jl/dev/)

PocketFlow.jl is a Julia port of the [PocketFlow](https://github.com/original_author/PocketFlow) framework, designed for building and executing modular, composable flows.  
It provides a clean API for defining **nodes**, **shared state**, and **execution flows** with retry/backoff logic and extensible hooks.

## Installation

PocketFlow.jl is registered in the [General registry](https://github.com/JuliaRegistries/General), so you can install it with:

```julia
using Pkg
Pkg.add("PocketFlow")
```

## Quick Start
```julia
using PocketFlow

# Define a simple node
struct MyNode <: AbstractNode end

function prep(node::MyNode, store::SharedStore)
    store.data["x"] = 42
end

function exec(node::MyNode, store::SharedStore)
    println("x is ", store.data["x"])
end

# Build and run the flow
flow = Flow([MyNode()])
run!(flow)
```

## Key Concepts

   - `AbstractNode` – Base type for all nodes in a flow.

   - `SharedStore` – Mutable dictionary for inter-node data sharing.

   - Lifecycle Hooks:

       - `prep(node, store)` – Prepare state before execution.

       - `exec(node, store)` – Core execution logic.

       - `exec_fallback(node, store)` – Optional fallback on error.

       - `post(node, store)` – Optional post-processing after execution.

   - Operators:

       - `>>` – Sequence nodes in a flow.

       - `-` – Alternative flow-building syntax.

## Features

   - Composable node-based flow definitions.

   - Configurable retry & backoff per node.

   - Shared mutable state for inter-node communication.

   - Operator overloads for concise flow building (`>>`, `-`).

## Roadmap

   - Parallel & async execution of flows.

   - Built-in node libraries for common tasks.

   - Extended diagnostics & logging tools.

## Attribution

PocketFlow.jl is a Julia port of the original [PocketFlow](https://github.com/original_author/PocketFlow) (MIT License) by Original Author.
The Julia version adapts core concepts and structure for idiomatic Julia, with additional enhancements for type safety and multiple dispatch.

Parts of this code were developed with assistance from OpenAI's ChatGPT. All outputs were reviewed, tested, and integrated by the package maintainer.

## License

This project is licensed under the MIT License – see the LICENSE file for details.