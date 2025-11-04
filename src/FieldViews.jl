module FieldViews

export FieldViewable, get_store, FieldView
using Accessors: Accessors, @set, PropertyLens, set

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
Base.propertynames(v::FieldViewable{T}) where {T} = fieldnames(T)

function staticschema(::Type{T}) where {T}
    NamedTuple{fieldnames(T)}(ntuple(i -> (; fieldtype=fieldtype(T, i), fieldoffset=fieldoffset(T,i)), Val(fieldcount(T))))
end

struct FieldView{prop, FT, N, T, Store <: StridedArray{T, N}} <: AbstractArray{FT, N}
    parent::Store
    function FieldView{prop}(v::Store) where {prop, T, N, Store <: StridedArray{T, N}}
        @assert isconcretetype(T) && !ismutabletype(T)
        FT = staticschema(T)[prop].fieldtype
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
    if isbitstype(FT)
        GC.@preserve store begin
            ptr::Ptr{FT} = pointer(store, i) + staticschema(T)[prop].fieldoffset
            unsafe_load(ptr)
        end
    else
        @inbounds getproperty(store[i], prop)
    end
end

Base.@propagate_inbounds function Base.setindex!(v::FieldView{prop, FT, N, T}, x, i::Integer) where {prop, FT, N, T}
    store = parent(v)
    @boundscheck checkbounds(store, i)
    if isbitstype(FT)
        GC.@preserve store begin
            ptr::Ptr{FT} = pointer(store, i) + staticschema(T)[prop].fieldoffset
            unsafe_store!(ptr, convert(FT, x)::FT)
        end
    else
        @inbounds setindex!(store, set(store[i], PropertyLens{prop}(), x), i)
    end
end

end # module FieldViews
