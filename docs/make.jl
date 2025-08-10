#!/usr/bin/env julia
using Documenter
using PocketFlow  # your package

# If your package has modules to doctest, add them here:
DocMeta.setdocmeta!(PocketFlow, :DocTestSetup, :(using PocketFlow); recursive=true)

makedocs(;
    sitename = "PocketFlow.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",  # pretty URLs on CI
        edit_link = "main",                               # points "Edit on GitHub" at main
        assets = String[],
    ),
    modules = [PocketFlow],
    pages = [
        "Home" => "index.md",
        # "API" => "api.md",    # add when ready
    ],
)

deploydocs(;  # Documenter will push to gh-pages using GITHUB_TOKEN
    repo = "github.com/yourusername/PocketFlow.jl",
    devbranch = "main",
    push_preview = true,  # PR previews under gh-pages:previews/PR###
)
