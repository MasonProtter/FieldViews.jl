using Documenter, FieldViews
using FieldViews: fieldmap, mappedfieldschema, IsStrided, StridedArrayTrait, Renamed, mappedfieldschema, Unknown, can_use_fast_path

const ci = get(ENV, "CI", "") == "true"

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
        repo = "github.com/MasonProtter/FieldViews.jl.git",
        devbranch = "master",
        push_preview = true)
end
