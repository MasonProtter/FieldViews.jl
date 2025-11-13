## Custom Data Layouts

### Working with nested data-layouts

Sometimes you have nested data but want to treat it as a flattened struct, e.g. adapting an example from the [StructArrays.jl docs](https://juliaarrays.github.io/StructArrays.jl/stable/advanced/#Structures-with-non-standard-data-layout)

``` julia
struct MyType{T, NT<:NamedTuple}
    x::T
    rest::NT
end
MyType(x; kwargs...) = MyType(x, values(kwargs))

function Base.getproperty(s::MyType, prop::Symbol)
    if prop == :x
        getfield(s, prop)
    else
        getfield(getfield(s, :rest), prop)
    end
end
Base.propertynames(s::MyType) = (:data, propertynames(getfield(x, :rest))) 
```

``` julia
julia> mt = MyType(1.0; a=1, b=2)
MyType{Float64, @NamedTuple{a::Int64, b::Int64}}(1.0, (a = 1, b = 2))

julia> mt.a
1

julia> mt.b
2
```
We can support this 'flattened' structure in `FieldViews` by defining a custom method on `fieldmap` that tells `FieldViews` how to traverse the nested fields.

To teach `FieldViews` how to handle `MyType`, we'd do
``` julia
function FieldViews.fieldmap(::Type{MyType{T, NamedTuple{rest_names, rest_types}}}) where {T, rest_names, rest_types}
	(:x, map(name -> :rest => name, rest_names)...)
end
```

``` julia
julia> FieldViews.fieldmap(typeof(mt))
(:x, :rest => :a, :rest => :b)
```
This says that there is one field `:x` which is not redirected, and two inner fields `:a` and `:b` which are redirected from `:rest`. Now our nested struct is compatible with FieldViews.jl
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

### Renaming fields

In addition to flattening out nested field structures, FieldViews.jl is also able to support "renamed" fields, e.g. 

``` julia
struct Foo
    a::Int
	data::@NamedTuple{_b::Int, _c::Int}
end

function FieldViews.fieldmap(::Type{Foo})
    (:a, :data => Renamed(:_b, :b), :data => Renamed(:_c, :c))
end
```

``` julia
julia> v = FieldViewable([Foo(1, (_b=1, _c=2))]);

julia> v.c
1-element FieldView{:c, Int64, 1, Foo, Vector{Foo}}:
 2
```

This is used for e.g. `StaticArray` support to rename `Tuple` fields to `:x`, `:y`, `:z`, `:w`.
