# FieldViews.jl

A `FieldViewable` is an array that wraps a `StridedArray` without copying and allows one to access and manipulate views of selected fields of the structs stored in the underlying data. FieldViews.jl provides an API similar to [StructArrays.jl](https://github.com/JuliaArrays/StructArrays.jl), but without copying and with an array-of-structs memory layout instead of a struct-of-array memory layout.

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

julia> points_fv.x[1] = 10.0 # Modify values in-place
10.0

julia> println(points[1].x)# original array is modified!
10.0
```

```julia
# Wrap in FieldViewable
points_fv = FieldViewable(points)

# Access fields as arrays - no allocation!
points_fv.x  # Returns a FieldView{:x, ...}
points_fv.y  # Returns a FieldView{:y, ...}

# Read values
println(points_fv.x[1])  # 1.0
println(points_fv.y[2])  # 5.0

# Modify values in-place
points_fv.x[1] = 10.0
println(points[1].x)  # 10.0 - original array is modified!
```

You can take views of `FieldViews` to work with a subset of the array:

``` julia
# Create a view of a subset
julia> points_fv_subset = view(points_fv, 2:3)
2-element FieldViewable{Point{Float64}, 1, SubArray{Point{Float64}, 1, Vector{Point{Float64}}, Tuple{UnitRange{Int64}}, true}}:
 Point{Float64}(4.0, 5.0, 6.0)
 Point{Float64}(7.0, 8.0, 9.0)

# Access fields of the view
julia> points_fv_subset.x[1] = 99.0
99.0

julia> points[2]  # Original array is modified
Point{Float64}(99.0, 5.0, 6.0)
```

### Limitations
- FieldViews.jl only supports arrays whose eltype are concrete, immutable structs. However, fields of the struct do not have this limitation.
- Reading or writing to a `FieldView` whose corresponding field is not `isbits` can be slower than non-isbits fields if the corresponding struct has many fields. This is because for non-`isbits` fields we need to load the whole struct entry, manipulate it, and then write back to the array. In contrast, for an `isbits` field, we are able to read and write the individual field.

### Working with custom data-layouts

Sometimes you have nested data but want to treat it as a flattened struct, e.g. adapting an example from the [StructArrays.jl docs](https://juliaarrays.github.io/StructArrays.jl/stable/advanced/#Structures-with-non-standard-data-layout)

``` julia
struct MyType{T, NT<:NamedTuple}
    data::T
    rest::NT
end
MyType(x; kwargs...) = MyType(x, values(kwargs))

function Base.getproperty(s::MyType, prop::Symbol)
    if prop == :data
        getfield(s, prop)
    else
        getfield(getfield(s, :rest), prop)
    end
end
Base.propertynames(s::MyType) = (:data, propertynames(getfield(x, :rest))) 
using ConstructionBase
function ConstructionBase.setproperties(s::MyType{T, NT}, patch::PNT) where {PNT <: NamedTuple}
    if hasfield(PNT, :data)
	    data = patch.data
	else
        data = s.data
	end
	rest = getfield(s, :rest)
	patch_rest = Base.structdiff(patch, NamedTuple{(:data,)})
	MyType(data, merge(rest, patch_rest))
end
```

``` julia
julia> MyType(1.0; a=1, b=2).a
1

julia> MyType(1.0; a=1, b=2).b
2
```

We can support this flattened structure in `FieldViews` by defining a custom `staticschema` with the relevant fieldtypes and fieldoffsets. Here's what the generated schema for a `NamedTuple` looks like:

``` julia
julia> FieldViews.staticschema(@NamedTuple{a::Int, b::String})
(a = (fieldtype = Int64, fieldoffset = 0x0000000000000000), b = (fieldtype = String, fieldoffset = 0x0000000000000008))
```
So to generate a flattened schema for `MyType`, we do
``` julia
function FieldViews.staticschema(::Type{MyType{T, NamedTuple{rest_names, rest_types}}}) where {T, rest_names, rest_types}
    RestNT = NamedTuple{rest_names, rest_types}
	rest_offset = fieldoffset(MyType{T, RestNT}, 2)
    rest_schema = FieldViews.staticschema(RestNT)
	rest_schema_offset = map(rest_schema) do row
        # Tell FieldViews there are more fields at certain offsets from the start of the struct
        (; fieldtype=row.fieldtype, fieldoffset=row.fieldoffset+rest_offset)
    end
    (data=(fieldtype=T, fieldoffset=UInt(0)), rest_schema_offset...)
end
```

and now our nested struct is compatible with FieldViews.jl
``` julia
julia> s = FieldViewable([MyType(i/5, a=6-i, b=2) for i in 1:5])
5-element FieldViewable{MyType{Float64, @NamedTuple{a::Int64, b::Int64}}, 1, Vector{MyType{Float64, @NamedTuple{a::Int64, b::Int64}}}}:
 MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(0.2, (a = 5, b = 2))
 MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(0.4, (a = 4, b = 2))
 MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(0.6, (a = 3, b = 2))
 MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(0.8, (a = 2, b = 2))
 MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(1.0, (a = 1, b = 2))

julia> s.x[1]
0.2

julia> s.a[2]
4

julia> s.b[3]
2
```

**WARNING:** Be very careful when overloading `FieldViews.staticschema`, as mistakes could cause memory corruption if the fieldtypes and fieldoffsets are incorrect. Only use this feature if you are very confident 
