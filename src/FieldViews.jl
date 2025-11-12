module FieldViews

export FieldViewable, get_store, FieldView
using Accessors:
    Accessors,
    PropertyLens,
    set,
    ComposedOptic,
    opticcompose

using Base: Broadcast

if VERSION > v"1.11.0-DEV.469"
    # public fieldmap, mappedfieldschema
    eval(Expr(:public, :fieldmap, :mappedfieldschema))
end

struct FieldViewable{T, N, Store <: StridedArray{T, N}} <: AbstractArray{T, N}
    parent::Store
    function FieldViewable(v::StridedArray{T, N}) where {T, N}
        @assert isconcretetype(T)
        new{T, N, typeof(v)}(v)
    end
end
Base.parent(v::FieldViewable) = getfield(v, :parent)

Base.size(v::FieldViewable) = size(parent(v))
Base.@propagate_inbounds Base.getindex(v::FieldViewable, i...) = parent(v)[i...]
Base.@propagate_inbounds Base.setindex!(v::FieldViewable, x, i...) = setindex!(parent(v), x, i...)

function Base.view(v::FieldViewable, inds...)
    vstore = view(parent(v), inds...)
    FieldViewable(vstore)
end

function Base.getproperty(v::FieldViewable{T, N, Store}, prop::Symbol) where {T, N, Store}
   FieldView{prop}(v)
end

Base.similar(::Type{FieldViewable{T, N, Store}}, axes) where {T, N, Store} = FieldViewable(similar(Store, axes))
Base.similar(a::FieldViewable, ::Type{T}, dims::Tuple{Vararg{Int}}) where {T} = FieldViewable(similar(parent(a), T, dims))
Base.copyto!(v::FieldViewable, bc::Broadcast.Broadcasted) = copyto!(parent(v), bc)

function Broadcast.broadcast_unalias(dest::FieldViewable, src::AbstractArray)
    FieldViewable(Broadcast.broadcast_unalias(parent(dest), src))
end
Base.copy(v::FieldViewable) = FieldViewable(copy(parent(v)))
Base.dataids(v::FieldViewable) = Base.dataids(parent(v))
Base.IndexStyle(::Type{<:FieldViewable}) = IndexLinear()
#-------------------

Base.propertynames(v::FieldViewable{T}) where {T} = fieldnames(T)

function staticschema(::Type{T}) where {T}
    NamedTuple{fieldnames(T)}(ntuple(i -> (; fieldtype=fieldtype(T, i), fieldoffset=fieldoffset(T,i)), Val(fieldcount(T))))
end

struct FieldView{prop, FT, N, T, Store <: StridedArray{T, N}} <: AbstractArray{FT, N}
    parent::Store
    function FieldView{prop}(v::Store) where {prop, T, N, Store <: StridedArray{T, N}}
        @assert isconcretetype(T) && !ismutabletype(T)
        FT = mappedfieldschema(T)[prop].type
        new{prop, FT, N, T, Store}(v)
    end
end
FieldView{FT}(v::FieldViewable) where {FT} = FieldView{FT}(parent(v))
Base.parent(v::FieldView) = getfield(v, :parent)
Base.size(v::FieldView) = size(parent(v))
Base.IndexStyle(::Type{<:FieldView}) = IndexLinear()

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

#-------------------

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
as_field_lens(prop::Symbol) = FieldLens{prop}() 
as_field_lens((l, r)::Pair) = opticcompose(as_field_lens(l), as_field_lens(r))

get_final(x) = x
get_final((l, r)::Pair) = get_final(r)

function nested_fieldoffset(::Type{T}, field::Symbol) where {T}
    idx = Base.fieldindex(T, field)
    fieldoffset(T, idx)
end

function nested_fieldoffset(::Type{T}, (outer, inner)::Pair{Symbol}) where {T}
    idx = Base.fieldindex(T, outer)
    fieldoffset(T, idx) + nested_fieldoffset(fieldtype(T, idx), inner)
end

function nested_fieldtype(::Type{T}, field::Symbol) where {T}
    idx = Base.fieldindex(T, field)
    fieldtype(T, idx)
end
function nested_fieldtype(::Type{T}, (outer, inner)::Pair{Symbol}) where {T}
    idx = Base.fieldindex(T, outer)
    nested_fieldtype(fieldtype(T, idx), inner)
end

#-------------------
struct FieldLens{field}
    FieldLens(field::Symbol) = new{field}()
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
