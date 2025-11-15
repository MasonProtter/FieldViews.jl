module FieldViews

export FieldViewable, FieldView, Renamed, FieldLens!!

using Accessors:
    Accessors,
    PropertyLens,
    set,
    ComposedOptic,
    opticcompose

using Base: Broadcast

if VERSION > v"1.11.0-DEV.469"
    # public fieldmap, mappedfieldschema
    eval(Expr(:public, :fieldmap, :mappedfieldschema, :IsStrided, :Unknown, :StridedArrayTrait))
end

#=======================================================================
StridedArrayTrait
=======================================================================#

"""
    StridedArrayTrait(::Type{T}) :: StridedArrayTrait
    StridedArrayTrait(x) :: StridedArrayTrait

Query or define whether an array type has strided memory layout.

Returns `IsStrided()` if the array has constant stride offsets in memory,
or `Unknown()` otherwise. Arrays which support `IsStrided()` auotmatically
get more efficient `getindex`/`setindex!` implementations for their
`isbits` fields.

`IsStrided` arrays must support `pointer(v, i)` methods, and linear indexing.

# Default Behavior
- `StridedArray` types return `IsStrided()`
- Other `AbstractArray` types return `Unknown()`

# Extending Support
To opt into the strided interface for a custom array type: 
```julia
FieldViews.StridedArrayTrait(::Type{<:MyArrayType}) = FieldViews.IsStrided()
```

# Examples
```julia
StridedArrayTrait(Vector{Int})  # IsStrided()
StridedArrayTrait(view([1,2,3,4], 1:2:4))  # IsStrided()
StridedArrayTrait(view([1,2,3,4], [1,3,4]))  # Unknown() - non-contiguous indices
```

A strided array is one where elements are stored at fixed offsets from each other
in memory. For example, `[1, 2, 3, 4]` is strided, as is `view(v, 1:2:4)` (every
other element), but `view(v, [1, 3, 4])` is not strided (arbitrary indices).

# See also
- [`IsStrided`](@ref): Trait for strided arrays
- [`Unknown`](@ref): Trait for non-strided arrays
"""
abstract type StridedArrayTrait end

"""
    IsStrided <: StridedArrayTrait

Trait indicating that an array type has strided (constant offset) memory layout.

Used by FieldViews to dispatch on array types that support efficient field access
through pointer arithmetic.

# See also
- [`StridedArrayTrait`](@ref): The trait function for querying array layout
- [`Unknown`](@ref): Trait for non-strided arrays
"""
struct IsStrided <: StridedArrayTrait end

"""
    Unknown <: StridedArrayTrait

Trait indicating that an array type's memory layout is unknown or non-strided.

For arrays with this trait, FieldViews will fall back on accessing/modifying field elements
by loading/storing the entire containing struct, and then using [`FieldLens!!`](@ref) to
manipulate and set the required field. This can be slower in some circumstances.

# See also
- [`StridedArrayTrait`](@ref): The trait function for querying array layout
- [`IsStrided`](@ref): Trait for strided arrays
"""
struct Unknown <: StridedArrayTrait end

StridedArrayTrait(x::Store) where {Store <: AbstractArray} = StridedArrayTrait(Store)
StridedArrayTrait(::Type{Store}) where {Store <: StridedArray} = IsStrided()
StridedArrayTrait(::Type{Store}) where {Store <: AbstractArray} = Unknown()

# Define this method to avoid invalidations
StridedArrayTrait(::Type{Union{}}) = error("This should be unreachable")

is_strided(x) = StridedArrayTrait(x) == IsStrided()

#=======================================================================
FieldViewable
=======================================================================#

"""
    FieldViewable(array::AbstractArray{T,N}) :: FieldViewable{T,N,Store}

Wrap an array to enable zero-copy field access via properties.

`FieldViewable` provides a view-like interface for accessing individual fields of 
structs stored in an array, without copying data. Field access returns `FieldView`
objects that can be indexed and modified in-place, with changes reflected in the
original array.

# Examples
```julia
struct Point{T}
    x::T
    y::T
    z::T
end

points = [Point(1.0, 2.0, 3.0), Point(4.0, 5.0, 6.0)]
fv = FieldViewable(points)

# Access field views
fv.x  # Returns FieldView{:x, Float64, ...}
fv.x[1]  # Returns 1.0

# Modify in-place (modifies original array)
fv.x[1] = 10.0
points[1].x  # Now 10.0

# Take views
slice = view(fv, 1:1)
slice.y[1] = 99.0
points[1].y  # Now 99.0
```

# Performance Note:
Getting and setting to `FieldView` vectors is most efficient when
the following are satisfied:
1. The underlying vector (e.g. `arr`) satisfies the [`IsStrided`](@ref) trait
2. The `eltype` of the array (e.g. `Data{Int}`) is concrete and immutable
3. The type of the field (e.g. `value::Int`) is an `isbitstype`.

When all three of the above are satisfied, FieldViews can use efficient pointer
methods to get and set fields in the array directly, otherwise we must use a slower
fallback that loads the entire struct, modify it, and then sets the entire struct
back into the array.

# See also
- [`FieldView`](@ref): The view type returned by field property access
- [`fieldmap`](@ref): Customize field layout for nested structures
"""
struct FieldViewable{T, N, Store <: AbstractArray} <: AbstractArray{T, N}
    parent::Store
    function FieldViewable(v::Store) where {T, N, Store <: AbstractArray{T, N}}
        new{T, N, Store}(v)
    end
end
FieldViewable(v::FieldViewable) = v

Base.parent(v::FieldViewable) = getfield(v, :parent)
Base.size(v::FieldViewable) = size(parent(v))
Base.IndexStyle(::Type{FieldViewable{T, N, Store}}) where {T, N, Store} = IndexStyle(Store)
StridedArrayTrait(::Type{FieldViewable{T, N, Store}}) where {T, N, Store} = StridedArrayTrait(Store)

Base.@propagate_inbounds Base.getindex(v::FieldViewable, i...) = parent(v)[i...]
Base.@propagate_inbounds Base.setindex!(v::FieldViewable, x, i...) = setindex!(parent(v), x, i...)

function Base.view(v::FieldViewable, inds...)
    vstore = view(parent(v), inds...)
    FieldViewable(vstore)
end

function Base.getproperty(v::FieldViewable{T, N, Store}, prop::Symbol) where {T, N, Store}
   FieldView{prop}(v)
end
Base.propertynames(v::FieldViewable{T}) where {T} = get_final.(fieldmap(T))

Base.similar(::Type{FieldViewable{T, N, Store}}, axes) where {T, N, Store} = FieldViewable(similar(Store, axes))
Base.similar(a::FieldViewable, ::Type{T}, dims::Tuple{Vararg{Int}}) where {T} = FieldViewable(similar(parent(a), T, dims))
Base.copyto!(v::FieldViewable, bc::Broadcast.Broadcasted) = copyto!(parent(v), bc)

function Broadcast.broadcast_unalias(dest::FieldViewable, src::AbstractArray)
    FieldViewable(Broadcast.broadcast_unalias(parent(dest), src))
end
Base.copy(v::FieldViewable) = FieldViewable(copy(parent(v)))
Base.dataids(v::FieldViewable) = Base.dataids(parent(v))


#=======================================================================
FieldView
=======================================================================# 

"""
    FieldView{field}(parent::AbstractArray)

A view of a specific field across all elements in an array.

`FieldView` provides element-wise access to a single field of the structs in the parent array.
For `isbits` fields and strided array containers, it uses efficient pointer methods for direct
field access. For non-`isbits` fields, or non-strided arrays it uses a slower fallback
which loads the full struct and extracts the  field value.

Users typically obtain `FieldView` objects through property access on `FieldViewable`:
```julia
fv = FieldViewable(points)
x_view = fv.x  # Returns a FieldView{:x, ...}
```

# Indexing
`FieldView` supports standard array indexing operations:
- `fv.x[i]` - Get field value at index i
- `fv.x[i] = val` - Set field value at index i (modifies parent array)

# Examples
```julia
struct Data{T}
    value::T
    weight::Float64
end

arr = [Data(1, 0.5), Data(2, 1.5)]
fv = FieldViewable(arr)

# Access field view
values = fv.value  # FieldView{:value, Int64, ...}
values[1]  # 1

# Modify through view
fv.weight[2] = 2.0
arr[2].weight  # 2.0


# Performance Note:
Getting and setting to `FieldView` vectors is most efficient when
the following are satisfied:
1. The underlying vector (e.g. `arr`) satisfies the [`IsStrided`](@ref) trait
2. The `eltype` of the array (e.g. `Data{Int}`) is concrete and immutable
3. The type of the field (e.g. `value::Int`) is an `isbitstype`.

When all three of the above are satisfied, FieldViews can use efficient pointer
methods to get and set fields in the array directly, otherwise we must use a slower
fallback that loads the entire struct, modify it, and then sets the entire struct
back into the array.

# See also
- [`FieldViewable`](@ref): The view type returned by field property access
- [`fieldmap`](@ref): Customize field layout for nested structures
```
"""
struct FieldView{prop, FT, N, T, Store <: AbstractArray{T, N}} <: AbstractArray{FT, N}
    parent::Store
    function FieldView{prop}(v::Store) where {prop, T, N, Store <: AbstractArray{T, N}}
        FT = if isconcretetype(T)
            mappedfieldschema(T)[prop].type
        else
            Any
        end
        new{prop, FT, N, T, Store}(v)
    end
end
FieldView{FT}(v::FieldViewable) where {FT} = FieldView{FT}(parent(v))
Base.parent(v::FieldView) = getfield(v, :parent)
Base.size(v::FieldView) = size(parent(v))
Base.IndexStyle(::Type{FieldView{prop, FT, N, T, Store}}) where {prop, FT, N, T, Store} = IndexStyle(Store)
StridedArrayTrait(::Type{FieldView{prop, FT, N, T, Store}}) where {prop, FT, N, T, Store} = StridedArrayTrait(Store)

to_linear_indices(v, inds::Tuple{}) = 1
to_linear_indices(v, inds::Tuple{Integer}) = inds[1]
to_linear_indices(v, inds::Tuple{Integer, Integer, Vararg{Integer}}) = LinearIndices(v)[inds...]

function can_use_fast_path(::Type{FieldView{prop, FT, N, T, Store}}) where {prop, FT, N, T, Store}
    is_strided(Store) && isconcretetype(T) && !ismutabletype(T) && isbitstype(FT)
end

Base.@propagate_inbounds function Base.getindex(v::FieldView{field, FT, N, T}, inds::Integer...) where {field, FT, N, T}
    store = parent(v)
    @boundscheck checkbounds(store, inds...)
    if can_use_fast_path(typeof(v))
        # Fast happy path when we are allowed to read and write directly from memory
        schema = mappedfieldschema(T)[field]
        GC.@preserve store begin
            i = to_linear_indices(v, inds)
            ptr::Ptr{FT} = pointer(store, i) + schema.offset
            unsafe_load(ptr)
        end
    else
        # Slow fallback that works with any of
        # 1. non-strided storage
        # 2. non-concrete eltype
        # 3. mutable eltype
        # 4. non-isbits fields
        elem = @inbounds store[inds...]
        schema = mappedfieldschema(typeof(elem))[field]
        schema.lens(elem)
    end
end

Base.@propagate_inbounds function Base.setindex!(v::FieldView{field, FT, N, T}, x, inds::Integer...) where {field, FT, N, T}
    store = parent(v)
    @boundscheck checkbounds(store, inds...)
    if can_use_fast_path(typeof(v))
        # Fast happy path when we are allowed to read and write directly from memory
        schema = mappedfieldschema(T)[field]
        GC.@preserve store begin
            i = to_linear_indices(v, inds)
            ptr::Ptr{FT} = pointer(store, i) + schema.offset
            unsafe_store!(ptr, convert(FT, x)::FT)
        end
    else
        # Slow fallback that works with any of
        # 1. non-strided storage
        # 2. non-concrete eltype
        # 3. mutable eltype
        # 4. non-isbits fields
        elem   = @inbounds store[inds...]
        schema = mappedfieldschema(typeof(elem))[field]
        x′::FT = x
        elem′  = set(elem, schema.lens, x′)
        @inbounds setindex!(store, elem′, inds...)
    end
end

Base.dataids(v::FieldView) = Base.dataids(parent(v))
Base.copy(fv::FieldView{field}) where {field} = FieldView{field}(copy(parent(fv)))
get_offset(f::FieldView{field, FT, N, Store}) where {field, FT, N, Store} = mappedfieldschema(Store)[field].offset

#=======================================================================
Field layout API
=======================================================================# 



"""
    fieldmap(::Type{T}) :: Tuple

Define the field layout for type `T` to be used by FieldViews.

Add methods to this function to customize how FieldViews accesses fields in your types.
This is essential for:
- Flattening nested structures
- Renaming fields
- Exposing only certain fields

# Default Behavior
By default, returns `fieldnames(T)`, exposing all fields with their original names.

# Return Value
A tuple where each element is one of:
- `Symbol` or `Int`: Direct field access
- `Pair{Symbol,Symbol}`: Nested field (e.g., `:outer => :inner`)
- `Pair{Symbol,Renamed}`: Nested field with rename
- `Renamed`: Renamed direct field

# Examples

## Flattening nested structures
```julia
struct MyType{T}
    x::T
    rest::@NamedTuple{a::Int, b::Int}
end

function FieldViews.fieldmap(::Type{MyType{T}}) where T
    (:x, :rest => :a, :rest => :b)
end

fv = FieldViewable([MyType(1.0, (a=1, b=2))])
fv.a[1]  # Access nested field directly, returns 1
```

## Renaming fields
```julia
struct Foo
    data::@NamedTuple{_internal::Int}
end

function FieldViews.fieldmap(::Type{Foo})
    (:data => Renamed(:_internal, :public),)
end

fv = FieldViewable([Foo((_internal=42,))])
fv.public[1]  # Returns 42
```

# See also
- [`Renamed`](@ref): For field aliasing
- [`mappedfieldschema`](@ref): The processed schema generated from `fieldmap`
"""
function fieldmap(::Type{T}) where {T}
    fieldnames(T)
end

"""
    mappedfieldschema(::Type{T}) -> NamedTuple

Compute the complete field schema for type `T`, computed using its `fieldmap`.

Returns a `NamedTuple` mapping field names (after renaming) to schema information
containing:
- `lens`: An optic for accessing the field
- `offset`: Byte offset of the field in memory (for `isbits` fields)
- `type`: The field's data type

This function processes the output of `fieldmap` to generate the internal schema
used by FieldViews for efficient field access.

# Examples
```julia
struct Point{T}
    x::T
    y::T
    z::T
end

schema = FieldViews.mappedfieldschema(Point{Float64})
# Returns: (x = (lens=..., offset=0, type=Float64),
#           y = (lens=..., offset=8, type=Float64),
#           z = (lens=..., offset=16, type=Float64))

schema.x.offset  # 0
schema.y.offset  # 8
schema.z.type    # Float64
```

# Implementation Note
This is typically called internally by FieldViews and rarely needs to be called
directly by users. Adding methods to `mappedfieldschema` incorrectly could cause
undefined behaviour.

# See also
- [`fieldmap`](@ref): The user-facing API for defining field layouts
"""
function mappedfieldschema(::Type{T}) where {T}
    fm = fieldmap(T)
    names = get_final.(fm)
    schema = ntuple(Val(length(fm))) do i
        lens = as_field_lens(fm[i])
        offset = nested_fieldoffset(T, fm[i])
        type = nested_fieldtype(T, fm[i])
        (; lens, offset, type)
    end
    NamedTuple{names}(schema)
end


"""
    Renamed(actual::Union{Int,Symbol}, alias::Symbol)

Specify a field rename in custom field mappings.

Used within `fieldmap` definitions to expose an internal field under a different 
name. This is useful when you want to expose a given field using a different name,
or access `Tuple` fields (since their fields are just integers).

# Arguments
- `actual`: The real field name or field index in the struct
- `alias`: The name to expose in the `FieldViewable` interface

# Examples
```julia
struct Foo
    data::@NamedTuple{_x::Int, _y::Int}
end

function FieldViews.fieldmap(::Type{Foo})
    (:data => Renamed(:_x, :x), :data => Renamed(:_y, :y))
end

fv = FieldViewable([Foo((_x=1, _y=2))])
fv.x[1]  # Access via alias 'x', returns 1
```

# See also
- [`fieldmap`](@ref): Define custom field layouts using `Renamed`
"""
struct Renamed
    actual::Union{Int, Symbol}
    alias::Symbol
end
             
as_field_lens(prop::Union{Symbol, Int}) = FieldLens!!{prop}()
as_field_lens(prop::Renamed) = FieldLens!!{prop.actual}()
as_field_lens((l, r)::Pair) = opticcompose(as_field_lens(l), as_field_lens(r))

get_final(x) = x
get_final(x::Renamed) = x.alias
get_final((l, r)::Pair) = get_final(r)

function nested_fieldoffset(::Type{T}, field::Symbol) where {T}
    idx = Base.fieldindex(T, field)
    fieldoffset(T, idx)
end
nested_fieldoffset(::Type{T}, idx::Int) where {T} = fieldoffset(T, idx)
nested_fieldoffset(::Type{T}, field::Renamed) where {T} = nested_fieldoffset(T, field.actual)
function nested_fieldoffset(::Type{T}, (outer, inner)::Pair{<:Union{Symbol, Int}}) where {T}
    idx = Base.fieldindex(T, outer)
    fieldoffset(T, idx) + nested_fieldoffset(fieldtype(T, idx), inner)
end

nested_fieldtype(::Type{T}, field::Renamed) where {T} = nested_fieldtype(T, field.actual)
function nested_fieldtype(::Type{T}, field::Symbol) where {T}
    idx = Base.fieldindex(T, field)
    fieldtype(T, idx)
end
function nested_fieldtype(::Type{T}, idx::Int) where {T}
    fieldtype(T, idx)
end

function nested_fieldtype(::Type{T}, (outer, inner)::Pair{<:Union{Symbol, Int}}) where {T}
    idx = Base.fieldindex(T, outer)
    nested_fieldtype(fieldtype(T, idx), inner)
end

#=======================================================================
FieldLens!!
=======================================================================# 

"""
    FieldLens!!{field}

An optic for accessing and modifying a specific field of a struct.

`FieldLens!!` implements the lens interface from Accessors.jl, providing functional
field access, immutable or mutable updates. It is primarily used internally by
FieldViews for fallback field access/modification, but can also be used directly
with the Accessors.jl API.

The `!!` in its name is a convention from [BangBang.jl](https://github.com/juliafolds2/bangbang.jl)
which signifies that it will mutate when possible, and perform out-of-place updates
when mutation is not possible.

# Constructor
```julia
FieldLens!!(field::Union{Symbol,Int})
FieldLens!!{field}()
```

# Examples
```julia
struct Point{T}
    x::T
    y::T
end

lens = FieldLens!!{:x}()

p = Point(1, 2)
lens(p)  # Get: returns 1

using Accessors
set(p, lens, 10)  # Set: returns Point(10, 2)
```

```
mutable struct MPoint{T}
    x::T
    y::T
end

mp = MPoint(1, 2)
lens(mp)  # Get: returns 1

set(mp, lens, 10)  # Set: returns Point(10, 2)
lens(mp)           # Get: returns 10 now since we mutated the object
```


# See also
- Accessors.jl documentation for general lens usage
"""
struct FieldLens!!{field}
    FieldLens!!(field::Union{Symbol, Int}) = new{field}()
    FieldLens!!{field}() where {field} = new{field}()
end
(l::FieldLens!!{prop})(o) where {prop} = getfield(o, prop)

function Accessors.set(o, l::FieldLens!!{prop}, val) where {prop}
    setfield!!(o, Val(prop), val)
end

@generated function setfield!!(obj::T, ::Val{name}, val) where {T, name}
    if ismutabletype(T)
        :(setfield!(obj, name, val); obj)
    else
        fields = fieldnames(T)
        idx = findfirst(==(name), fields)
        if isnothing(idx)
            error("$(repr(name)) is not a field of $T, expected one of ", fields)
        end
        Expr(:new, T, (name == field ? :val : :(getfield(obj, $(QuoteNode(field)))) for field in fields)...)
    end
end

end # module FieldViews
