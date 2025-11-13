module FieldViews

export FieldViewable, get_store, FieldView, Renamed, FieldLens

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
abstract type StridedArrayTrait end
struct IsStrided <: StridedArrayTrait end
struct Unknown <: StridedArrayTrait end

StridedArrayTrait(x::Store) where {Store <: AbstractArray} = StridedArrayTrait(Store)
StridedArrayTrait(::Type{Store}) where {Store <: StridedArray} = IsStrided()
StridedArrayTrait(::Type{Store}) where {Store <: AbstractArray} = Unknown()

# Define this method to avoid invalidations
StridedArrayTrait(::Type{Union{}}) = error("Unreachable")

@noinline function throw_if_not_strided_array(::Type{T}) where {T}
    if StridedArrayTrait(T) != IsStrided()
        throw(ArgumentError("""
FieldViews only supports strided array storage types, got $T.

A strided array is an array whose elements of the array are stored at
fixed offsets from one another in memory. E.g. v = [:a, :b, :c, :d]
is a strided array, so is view(v, 1:2:4), but view(v, [1, 3, 4])
is *not* a strided array.

If your array type T actually does have constant strides, you can define

FieldViews.StridedArrayTrait(::Type{<:T}) = FieldViews.IsStrided()

to opt into support from FieldViews.jl
"""))
    end
end

#=======================================================================
FieldViewable
=======================================================================# 

struct FieldViewable{T, N, Store <: AbstractArray} <: AbstractArray{T, N}
    parent::Store
    function FieldViewable(v::Store) where {T, N, Store <: AbstractArray{T, N}}
        @assert isconcretetype(T)
        throw_if_not_strided_array(Store)
        new{T, N, Store}(v)
    end
end
FieldViewable(v::FieldViewable) = v

Base.parent(v::FieldViewable) = getfield(v, :parent)
Base.size(v::FieldViewable) = size(parent(v))
Base.IndexStyle(::Type{<:FieldViewable}) = IndexLinear()
StridedArrayTrait(::Type{<:FieldViewable}) = IsStrided()

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

struct FieldView{prop, FT, N, T, Store <: AbstractArray{T, N}} <: AbstractArray{FT, N}
    parent::Store
    function FieldView{prop}(v::Store) where {prop, T, N, Store <: AbstractArray{T, N}}
        @assert isconcretetype(T) && !ismutabletype(T)
        throw_if_not_strided_array(Store)
        FT = mappedfieldschema(T)[prop].type
        new{prop, FT, N, T, Store}(v)
    end
end
FieldView{FT}(v::FieldViewable) where {FT} = FieldView{FT}(parent(v))
Base.parent(v::FieldView) = getfield(v, :parent)
Base.size(v::FieldView) = size(parent(v))
Base.IndexStyle(::Type{<:FieldView}) = IndexLinear()
StridedArrayTrait(::Type{<:FieldView}) = IsStrided()

Base.@propagate_inbounds function Base.getindex(v::FieldView{prop, FT, N, T}, i::Integer) where {prop, FT, N, T}
    store = parent(v)
    @boundscheck checkbounds(store, i)
    schema = mappedfieldschema(T)[prop]
    if isbitstype(FT)
        GC.@preserve store begin
            ptr::Ptr{FT} = pointer(store, i) + schema.offset
            unsafe_load(ptr)
        end
    else
        schema.lens(@inbounds store[i])
    end
end

Base.@propagate_inbounds function Base.setindex!(v::FieldView{prop, FT, N, T}, x, i::Integer) where {prop, FT, N, T}
    store = parent(v)
    @boundscheck checkbounds(store, i)
    schema = mappedfieldschema(T)[prop]
    if isbitstype(FT)
        GC.@preserve store begin
            ptr::Ptr{FT} = pointer(store, i) + schema.offset
            unsafe_store!(ptr, convert(FT, x)::FT)
        end
    else
        @inbounds setindex!(store, set(store[i], schema.lens, x), i)
    end
end

Base.dataids(v::FieldView) = Base.dataids(parent(v))
Base.copy(fv::FieldView{prop}) where {prop} = FieldView{prop}(copy(parent(fv)))
get_offset(f::FieldView{prop, FT, N, Store}) where {prop, FT, N, Store} = mappedfieldschema(Store)[prop].offset

#=======================================================================
Field layout API
=======================================================================# 

function fieldmap(::Type{T}) where {T}
    fieldnames(T)
end

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
struct Renamed
    actual::Union{Int, Symbol}
    alias::Symbol
end
             
as_field_lens(prop::Union{Symbol, Int}) = FieldLens{prop}()
as_field_lens(prop::Renamed) = FieldLens{prop.actual}()
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
FieldLens
=======================================================================# 

struct FieldLens{field}
    FieldLens(field::Union{Symbol, Int}) = new{field}()
    FieldLens{field}() where {field} = new{field}()
end
(l::FieldLens{prop})(o) where {prop} = getfield(o, prop)

function Accessors.set(o, l::FieldLens{prop}, val) where {prop}
    setfield(o, val, Val(prop))
end

@generated function setfield(obj::T, val, ::Val{name}) where {T, name}
    fields = fieldnames(T)
    name ∈ fields || error("$(repr(name)) is not a field of $T, expected one of ", fields)
    Expr(:new, T, (name == field ? :val : :(getfield(obj, $(QuoteNode(field)))) for field ∈ fields)...)
end


end # module FieldViews
