# FieldViews.jl

A `FieldViewable` is an array that wraps a `StridedArray` without copying and allows one to access and manipulate views of selected fields of the structs stored in the underlying data. FieldViews.jl provides an API similar to [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl), but without copying and with an array-of-structs memory layout instead of a struct-of-array memory layout.

```julia
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

```julia
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

julia> points_fv.x[1]
10.0

julia> points_fv.y[2]
5.0

julia> points_fv.x[1] = 10.0 # Modify values in-place
10.0

julia> points[1].x # original array is modified!
10.0
```

Instead of the `getproperty` syntax, you can directly construct views of particular field using the `FieldView{field}` constructor:
```julia
julia> FieldView{:x}(points)
3-element FieldView{:x, Float64, 1, Point{Float64}, Vector{Point{Float64}}}:
 10.0
  4.0
  7.0
```


You can take views of `FieldViews` to work with a slice of the array:

```julia
# Create a view of a subset
julia> points_fv_slice = view(points_fv, 2:3)
2-element FieldViewable{Point{Float64}, 1, SubArray{Point{Float64}, 1, Vector{Point{Float64}}, Tuple{UnitRange{Int64}}, true}}:
 Point{Float64}(4.0, 5.0, 6.0)
 Point{Float64}(7.0, 8.0, 9.0)

# Access fields of the view
julia> points_fv_slice.x[1] = 99.0
99.0

# Original array is modified
julia> points[2]
Point{Float64}(99.0, 5.0, 6.0)
```

## Warning: Fields versus Properties

Be aware that unlike StructArrays.jl, FieldViews.jl operates on the **fields** of structs, not their properties. Mutating the fields of a struct in an array using FieldViews.jl can therefore violate the API of certain types, and bypass internal constructors, thus creating potentially invalid objects. You should only use FieldViews.jl with arrays of structs you control, or whose field layout is a public part of their API.

## Performance characteristics of `FieldView`s

Getting and setting to `FieldView` arrays is most efficient when the following are satisfied:

1. The underlying array (e.g. `points`) satisfies the [`IsStrided`](@ref) trait
2. The `eltype` of the array (e.g. `Point{Int}`) is concrete and not 'pointer-backed' (i.e. `Base.allocatedinline` should give `true`).
3. The type of the field (e.g. `x::Int`) is concrete and an `isbitstype`.

When all of the above conditions are satisfied, FieldViews can use efficient pointer methods to get and set fields in the array directly without needing to manipulate the entire struct.

If any of the above conditions is *not* satisfied, then we need to fetch the entire struct,
and then either return the requested field of the struct (`getindex`), or construct and store a version of the struct where the field has been modified (`setindex!`).  If the struct is a mutable type, `setindex!` expressions will call `setfield!` on the stored struct, otherwise we construct a new version of immutable structs where the requested field is modified (see  [Accessors.jl](https://github.com/JuliaObjects/Accessors.jl), and our custom [`FieldLens!!`](@ref) object).


Note that even when the above conditions are not satisfied, the "slow" path is only slow relative to regular strided memory views, or something like [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl) (although note that StructArrays.jl cannot handle non-concrete types). It should still remain just as quick as working directly with the underlying storage array and interacting with whole elements.
