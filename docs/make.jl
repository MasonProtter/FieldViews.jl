
using Documenter, FieldViews
using FieldViews: fieldmap, mappedfieldschema, IsStrided, StridedArrayTrait, Renamed, mappedfieldschema, Unknown

const ci = get(ENV, "CI", "") == "true"
@info "" ci

makedocs(
    sitename = "FieldViews.jl Documentation",
    pages = [
        "index.md",
        "API Docstrings" => "api.md",
    ],
    modules=[FieldViews],
)


if ci
    @info "Deploying documentation to GitHub"
    deploydocs(;
        repo = "https://github.com/MasonProtter/FieldViews.jl.git",
        devbranch = "master",
        push_preview = true)
end
