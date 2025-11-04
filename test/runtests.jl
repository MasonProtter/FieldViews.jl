using FieldViews
using Test
using Accessors: @set
using ConstructionBase

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

@testset "staticschema" begin
    struct TestStruct{T}
        a::T
        b::Int
        c::Float64
    end
    
    schema = FieldViews.staticschema(TestStruct{Float32})
    
    @test haskey(schema, :a)
    @test haskey(schema, :b)
    @test haskey(schema, :c)
    
    @test schema.a.fieldtype == Float32
    @test schema.b.fieldtype == Int
    @test schema.c.fieldtype == Float64
    
    @test schema.a.fieldoffset == 0x0000000000000000
    @test schema.b.fieldoffset > schema.a.fieldoffset
    @test schema.c.fieldoffset > schema.b.fieldoffset
    
    # Test that offsets match Julia's fieldoffset
    @test schema.a.fieldoffset == fieldoffset(TestStruct{Float32}, 1)
    @test schema.b.fieldoffset == fieldoffset(TestStruct{Float32}, 2)
    @test schema.c.fieldoffset == fieldoffset(TestStruct{Float32}, 3)
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
    function ConstructionBase.setproperties(s::MyType, patch::PNT) where {PNT <: NamedTuple}
        if hasfield(PNT, :data)
	        data = patch.data
	    else
            data = s.data
	    end
	    rest = getfield(s, :rest)
	    patch_rest = Base.structdiff(patch, NamedTuple{(:data,)})
	    MyType(data, merge(rest, patch_rest))
    end
    
    # Custom staticschema for flattened access
    function FieldViews.staticschema(::Type{MyType{T, NamedTuple{rest_names, rest_types}}}) where {T, rest_names, rest_types}
        RestNT = NamedTuple{rest_names, rest_types}
        rest_offset = fieldoffset(MyType{T, RestNT}, 2)
        rest_schema = FieldViews.staticschema(RestNT)
        rest_schema_offset = map(rest_schema) do row
            (; fieldtype=row.fieldtype, fieldoffset=row.fieldoffset+rest_offset)
        end
        (data=(fieldtype=T, fieldoffset=UInt(0)), rest_schema_offset...)
    end
    
    # Test the custom schema
    s = FieldViewable([MyType(i/5, a=6-i, b=2, c=string(i)) for i in 1:5])
    
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

@testset "Type assertions" begin
    # Test that abstract types are rejected
    abstract_array = Vector{Any}([1, 2, 3])
    @test_throws AssertionError FieldViewable(abstract_array)
    
    # Test that mutable structs are rejected in FieldView creation
    mutable struct MutablePoint
        x::Float64
        y::Float64
    end
    
    mutable_points = [MutablePoint(1.0, 2.0)]
    fv = FieldViewable(mutable_points)
    @test_throws AssertionError fv.x
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
