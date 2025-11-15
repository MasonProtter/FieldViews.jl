using FieldViews
using Test
using Accessors: @set

@testset "Basic FieldViewable functionality" begin
    struct Point{T}
        x::T
        y::T
        z::T
    end
    
    points = [Point(1.0, 2.0, 3.0), Point(4.0, 5.0, 6.0), Point(7.0, 8.0, 9.0)]
    fv = FieldViewable(points)
    
    @test size(fv) == (3,)
    @test fv[1] == Point(1.0, 2.0, 3.0)
    @test fv[2] == Point(4.0, 5.0, 6.0)
    @test fv[3] == Point(7.0, 8.0, 9.0)
    
    # Test mutation through FieldViewable
    fv[1] = Point(10.0, 20.0, 30.0)
    @test points[1] == Point(10.0, 20.0, 30.0)
    
    # Test propertynames
    @test propertynames(fv) == (:x, :y, :z)

    # Test that it also works with non-strided arrays
    v2 = view(points, [1, 3])
    @test_throws Exception pointer(v2, 1)
    @test FieldViewable(v2).z[2] == 9.0
end

@testset "FieldView access and mutation" begin
    struct Particle{T}
        position::T
        velocity::T
        mass::T
    end
    
    particles = [Particle(1.0, 0.5, 2.0), Particle(2.0, 1.0, 3.0), Particle(3.0, 1.5, 4.0)]
    fv = FieldViewable(particles)
    
    # Test field access
    positions = fv.position
    velocities = fv.velocity
    masses = fv.mass
    
    @test positions isa FieldView
    @test size(positions) == (3,)
    @test positions[1] == 1.0
    @test positions[2] == 2.0
    @test positions[3] == 3.0
    
    @test velocities[1] == 0.5
    @test masses[2] == 3.0
    
    # Test field mutation
    positions[1] = 99.0
    @test particles[1].position == 99.0
    @test positions[1] == 99.0
    
    velocities[2] = 5.5
    @test particles[2].velocity == 5.5
end

@testset "Views of FieldViewable" begin
    struct Vec3{T}
        x::T
        y::T
        z::T
    end
    
    vecs = [Vec3(i, i+1, i+2) for i in 1.0:5.0]
    fv = FieldViewable(vecs)
    
    # Create a view
    fv_subset = view(fv, 2:4)
    @test size(fv_subset) == (3,)
    @test fv_subset[1] == Vec3(2.0, 3.0, 4.0)
    
    # Access fields of the view
    x_subset = fv_subset.x
    @test x_subset[1] == 2.0
    @test x_subset[2] == 3.0
    @test x_subset[3] == 4.0
    
    # Mutate through view
    x_subset[1] = 99.0
    @test vecs[2].x == 99.0
end

@testset "Multi-dimensional arrays" begin
    struct RGB{T}
        r::T
        g::T
        b::T
    end
    
    # Create a 2x3 array
    colors = [RGB(i+j, i-j, i*j) for i in 1:2, j in 1:3]
    fv = FieldViewable(colors)
    
    @test size(fv) == (2, 3)
    @test fv[1, 1] == RGB(2, 0, 1)
    @test fv[2, 3] == RGB(5, -1, 6)
    
    # Test field access on 2D array
    r_channel = fv.r
    @test size(r_channel) == (2, 3)
    @test r_channel[1, 1] == 2
    @test r_channel[2, 3] == 5
    
    # Test mutation
    r_channel[1, 2] = 99
    @test colors[1, 2].r == 99
end

@testset "mappedschema" begin
    struct TestStruct{T}
        a::T
        b::Int
        c::Float64
    end
    
    schema = FieldViews.mappedfieldschema(TestStruct{Float32})
    
    @test haskey(schema, :a)
    @test haskey(schema, :b)
    @test haskey(schema, :c)
    
    @test schema.a.type == Float32
    @test schema.b.type == Int
    @test schema.c.type == Float64
    
    @test schema.a.offset == 0x0000000000000000
    @test schema.b.offset > schema.a.offset
    @test schema.c.offset > schema.b.offset
    
    # Test that offsets match Julia's fieldoffset
    @test schema.a.offset == fieldoffset(TestStruct{Float32}, 1)
    @test schema.b.offset == fieldoffset(TestStruct{Float32}, 2)
    @test schema.c.offset == fieldoffset(TestStruct{Float32}, 3)
end

@testset "Custom staticschema - nested data layout" begin
    # Example from documentation: flattened nested struct
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
    Base.propertynames(s::MyType) = (:data, propertynames(getfield(s, :rest))...)
    
    # Custom staticschema for flattened access
    function FieldViews.fieldmap(::Type{MyType{T, NamedTuple{rest_names, rest_types}}}) where {T, rest_names, rest_types}
        (:data, map(name -> :rest => name, rest_names)...)
    end
    
    # And a mutable version!
    struct MyTypeMutable{T, NT<:NamedTuple}
        data::T
        rest::NT
    end
    MyTypeMutable(x; kwargs...) = MyTypeMutable(x, values(kwargs))
    
    function Base.getproperty(s::MyTypeMutable, prop::Symbol)
        if prop == :data
            getfield(s, prop)
        else
            getfield(getfield(s, :rest), prop)
        end
    end
    Base.propertynames(s::MyTypeMutable) = (:data, propertynames(getfield(s, :rest))...)
    
    # Custom staticschema for flattened access
    function FieldViews.fieldmap(::Type{MyTypeMutable{T, NamedTuple{rest_names, rest_types}}}) where {T, rest_names, rest_types}
        (:data, map(name -> :rest => name, rest_names)...)
    end
    
    @testset "" for Typ ∈ (MyType, MyTypeMutable,)
        # Test the custom schema
        schema = FieldViews.mappedfieldschema(Typ{Float32, @NamedTuple{b::Int, c::Float64}})
        
        @test haskey(schema, :data)
        @test haskey(schema, :b)
        @test haskey(schema, :c)
        
        @test schema.data.type == Float32
        @test schema.b.type == Int
        @test schema.c.type == Float64
        
        @test schema.data.offset == 0x0000000000000000
        @test schema.b.offset > schema.data.offset
        @test schema.c.offset > schema.b.offset
        
        # Test that offsets match Julia's fieldoffset
        @test schema.data.offset == fieldoffset(@NamedTuple{data::Float32, b::Int, c::Float32}, 1)
        @test schema.b.offset == fieldoffset(@NamedTuple{data::Float32, b::Int, c::Float32}, 2)
        @test schema.c.offset == fieldoffset(@NamedTuple{data::Float32, b::Int, c::Float32}, 3)

        # Test using the schema    
        s = FieldViewable([Typ(i/5, a=6-i, b=2, c=string(i)) for i in 1:5])
        
        @test size(s) == (5,)
        @test s[1].data == 0.2
        @test s[1].a == 5
        @test s[1].b == 2
        @test s[1].c == "1"
        
        # Test field views
        data_view = s.data
        @test data_view[1] == 0.2
        @test data_view[2] == 0.4
        @test data_view[5] == 1.0
        
        a_view = s.a
        @test a_view[1] == 5
        @test a_view[2] == 4
        @test a_view[5] == 1
        
        b_view = s.b
        @test all(b_view .== 2)

        @test s.c[1] == "1"
        @test s.c[2] == "2"
        
        # Test mutation through field views
        data_view[3] = 99.0
        @test s[3].data == 99.0
        
        a_view[4] = 42
        @test s[4].a == 42

        s.c[3] = "boo!"
        @test s.c[3] == "boo!"
    end
end


@testset "Non-bits types" begin
    struct Container{T}
        id::Int
        data::T
    end
    
    # Test with String (non-bits type)
    containers = [Container(i, "string_$i") for i in 1:3]
    fv = FieldViewable(containers)
    
    ids = fv.id
    datas = fv.data
    
    @test ids[1] == 1
    @test datas[1] == "string_1"
    @test datas[2] == "string_2"
    
    # Mutation of non-bits fields uses Accessors
    datas[1] = "modified"
    @test containers[1].data == "modified"
end

@testset "Abstract types" begin
    # Test that abstract types are rejected
    v = FieldViewable(Any[(a=1, b=2, c=3), (a=1.0, x=2.0, c=3.0)])
    @test v.a == Any[1, 1.0]
    @test_throws Exception v.x[1] #One of the elements doesn't have an x field!
end

@testset "Mutable types" begin
    mutable struct MutablePoint
        x::Float64
        y::Float64
    end
    mp1 = MutablePoint(1.0, 2.0)
    mp2 = MutablePoint(3.0, 4.0)
    mutable_points = FieldViewable([mp1, mp2])
    @test mutable_points.x[1] == 1.0
    @test mutable_points.y[2] == 4.0

    mutable_points.x[2] *= -1
    mutable_points.y[1] *= -1
    # The underlying mutable objects are mutated!
    @test mutable_points.x[2] == mp2.x == -3.0
    @test mutable_points.y[1] == mp1.y == -2.0
end

@testset "Linear indexing" begin
    struct Point2D
        x::Float64
        y::Float64
    end
    
    points = [Point2D(i, j) for i in 1:3, j in 1:4]
    fv = FieldViewable(points)
    
    x_view = fv.x
    
    # Test linear indexing
    @test x_view[1] == 1.0
    @test x_view[4] == 1.0  # Column-major order
    @test x_view[5] == 2.0
    
    # Test mutation with linear indexing
    x_view[7] = 99.0
    @test points[1, 3].x == 99.0
end

@testset "Edge cases" begin
    struct Single{T}
        value::T
    end
    
    # Single element array
    single = FieldViewable([Single(42)])
    @test single.value[1] == 42
    
    single.value[1] = 99
    @test single[1].value == 99
    
    # Empty array handling
    empty_array = Single{Float64}[]
    fv_empty = FieldViewable(empty_array)
    @test size(fv_empty) == (0,)
    @test size(fv_empty.value) == (0,)
end

using StaticArrays

@testset "StaticArrays" begin
    points = [SVector(x, 2.0) for x in 1:0.5:2]
    fv = FieldViewable(points)

    @test fv.x == [1.0, 1.5, 2.0]
    @test fv.y == [2.0, 2.0, 2.0]
    fv.x[1] = -1
    @test points[1].x == -1

    points2 = MVector{3}([SVector(x, 2.0) for x in 1:0.5:2])
    fv2 = FieldViewable(points2)
    @test fv2.x == [1.0, 1.5, 2.0]
    @test fv2.y == [2.0, 2.0, 2.0]
    fv2.x[1] = -1
    @test points2[1].x == -1

    points3 = SVector{3}([SVector(x, 2.0) for x in 1:0.5:2])
    fv3 = FieldViewable(points3)
    @test fv3.x == [1.0, 1.5, 2.0]
    @test fv3.y == [2.0, 2.0, 2.0]
end


@testset "Non-concrete parametric types" begin
    struct Container2{T}
        value::T
    end
    
    # Vector{Container2} - not Container2{T} for specific T
    mixed = FieldViewable(Container2[Container2(1), Container2(2.0), Container2("hi")])
    @test mixed.value[1] == 1
    @test mixed.value[2] == 2.0
    @test mixed.value[3] == "hi"
    
    mixed.value[1] = 42
    @test parent(mixed)[1].value == 42

    mixed.value[3] = "bye"
    @test parent(mixed)[3].value == "bye"
end

@testset "Mutable structs with non-isbits fields" begin
    mutable struct MutableContainer
        id::Int
        data::String
        metadata::Vector{Int}
    end
    
    items = [MutableContainer(1, "a", [1,2]), MutableContainer(2, "b", [3,4])]
    fv = FieldViewable(items)
    
    fv.data[1] = "modified"
    @test items[1].data == "modified"
    
    fv.metadata[2] = [9, 9, 9]
    @test items[2].metadata == [9, 9, 9]
end

@testset "Union types" begin
    struct MaybeData
        value::Union{Int, Nothing}
    end
    
    data = [MaybeData(1), MaybeData(nothing), MaybeData(3)]
    fv = FieldViewable(data)
    
    @test fv.value[1] == 1
    @test fv.value[2] === nothing
    @test fv.value[3] == 3
    
    fv.value[2] = 42
    @test data[2].value == 42
end

@testset "Mutable nested structures" begin
    mutable struct Inner
        x::Int
    end
    
    mutable struct Outer
        inner::Inner
        y::Float64
    end
    
    items = [Outer(Inner(1), 2.0), Outer(Inner(3), 4.0)]
    fv = FieldViewable(items)
    
    # This should work since we're replacing the whole Inner object
    fv.inner[1] = Inner(99)
    @test items[1].inner.x == 99
end

@testset "Abstract array with consistent fields" begin
    abstract type AbstractData end
    
    struct DataA <: AbstractData
        x::Int
        y::Float64
    end
    
    struct DataB <: AbstractData
        x::Int
        y::Float64
    end
    
    # All have same field layout
    mixed = AbstractData[DataA(1, 2.0), DataB(3, 4.0)]
    fv = FieldViewable(mixed)
    
    @test fv.x[1] == 1
    @test fv.x[2] == 3
    
    fv.y[1] = 99.0
    @test mixed[1].y == 99.0
end

@testset "2D array with mutable structs" begin
    mutable struct Cell
        value::Int
    end
    
    cells = [Cell(i*j) for i in 1:3, j in 1:4]
    fv = FieldViewable(cells)
    
    @test size(fv.value) == (3, 4)
    fv.value[2, 3] = 999
    @test cells[2, 3].value == 999
end

@testset "Non-strided views with abstract types" begin
    data = Any[(x=i, y=i*2) for i in 1:10]
    v = view(data, [1, 3, 5, 7])
    fv = FieldViewable(v)
    
    @test fv.x[1] == 1
    @test fv.x[2] == 3
    
    fv.y[2] = 999
    @test data[3].y == 999
end

@testset "Type inference for slow path" begin
    mutable struct M
        x::Int
    end
    
    items = [M(1), M(2)]
    fv = FieldViewable(items)
    
    # Should still infer return type correctly
    @inferred Int fv.x[1]
    
    # But abstract types won't infer
    abstract_items = Any[(x=1,), (x=2,)]
    fv_abstract = FieldViewable(abstract_items)
    @test fv_abstract.x[1] == 1  # Works but won't infer
end

@testset "Broadcasting with mutable types" begin
    mutable struct Data
        value::Float64
    end
    
    items = [Data(1.0), Data(2.0), Data(3.0)]
    fv = FieldViewable(items)
    
    fv.value .*= 2
    @test items[1].value == 2.0
    @test items[2].value == 4.0
    @test items[3].value == 6.0
end

@testset "Zero-sized and empty types" begin
    struct EmptyStruct end

    items = [EmptyStruct() for i ∈ 1:3]
    fv = FieldViewable(items)
    @test fv[1] == EmptyStruct()
    
    struct WithEmpty
        empty::EmptyStruct
        value::Int
    end
    
    items = [WithEmpty(EmptyStruct(), i) for i in 1:3]
    fv = FieldViewable(items)
    
    @test fv.value[2] == 2
    fv.value[2] = 99
    @test items[2].value == 99
end

@testset "Slow path verification" begin
    
    # Verify mutable types use slow path
    @test !FieldViews.can_use_fast_path(
        FieldView{:x, Int, 1, M, Vector{M}}
    )
    
    # Verify abstract types use slow path
    @test !FieldViews.can_use_fast_path(
        FieldView{:x, Any, 1, Any, Vector{Any}}
    )
end
