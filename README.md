# FieldViews.jl

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://masonprotter.github.io/FieldViews.jl/dev/

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://masonprotter.github.io/FieldViews.jl/stable/

[![][docs-stable-img]][docs-stable-url] [![][docs-dev-img]][docs-dev-url] 

A `FieldViewable` is an array that wraps another array without copying and allows one to access and manipulate views of selected fields of the structs stored in the underlying data. FieldViews.jl provides an API similar to [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl), but without copying and with an array-of-structs memory layout instead of a struct-of-array memory layout.

``` julia
using FieldViews

# Define a struct type
struct Point{T}
    x::T
    y::T
    z::T
end

# Create an array of Points
points = [Point(1.0, 2.0, 3.0), Point(4.0, 5.0, 6.0), Point(7.0, 8.0, 9.0)]
```

``` julia
julia> points_fv = FieldViewable(points)
3-element FieldViewable{Point{Float64}, 1, Vector{Point{Float64}}}:
 Point{Float64}(10.0, 2.0, 3.0)
 Point{Float64}(4.0, 5.0, 6.0)
 Point{Float64}(7.0, 8.0, 9.0)

julia> points_fv.x
3-element FieldView{:x, Float64, 1, Point{Float64}, Vector{Point{Float64}}}:
 10.0
  4.0
  7.0

julia> points_fv.y
3-element FieldView{:y, Float64, 1, Point{Float64}, Vector{Point{Float64}}}:
 2.0
 5.0
 8.0

julia> println(points_fv.x[1]) 
10.0

julia> println(points_fv.y[2])
5.0

# Modify values in-place
julia> points_fv.x[1] = 10.0
10.0

# original array is modified!
julia> points[1].x 
10.0
```

### Warning: Fields versus Properties

Be aware that unlike StructArrays.jl, FieldViews.jl operates on the **fields** of structs, not their properties. Mutating the fields of a struct in an array using FieldViews.jl can therefore violate the API of certain types, and bypass internal constructors, thus creating potentially invalid objects. You should only use FieldViews.jl with arrays of structs you control, or whose field layout is a public part of their API.

FieldViews.jl *does* however optionally support the flattening of nested field accesses, and the renaming of fields. See the documentation for more details.


## See also
+ [RecordArrays.jl](https://github.com/tkf/RecordArrays.jl) Similar concept but has no zero-copy wrapper for normal arrays, and no custom schema support. At the time of writing, RecordArrays is unmaintained.
+ [StructViews.jl](https://github.com/Vitaliy-Yakovchuk/StructViews.jl) Similar concept but with serious performance problems, and no support for custom schemas. At the time of writing, StructViews is unmaintained.
+ [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl) Similar concept except it works in terms of properties instead of fields, and it ses an struct-of-arrays instead of array-of-structs memory layout, which thus causes allocations to construct out of a regular `Array`, and has certain performance tradeoffs relative to array-of-structs layouts. StructArrays.jl is mature, widely used, and actively developed.
