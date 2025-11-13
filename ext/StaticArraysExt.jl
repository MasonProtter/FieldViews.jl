module StaticArraysExt

using FieldViews, StaticArrays

function FieldViews.fieldmap(::Type{SA}) where {SA <: SVector}
    if length(SA) <= 4
        names = (:x, :y, :z, :w)
        ntuple(Val(length(SA))) do i
            :data => Renamed(i, names[i])
        end
    else
        ()
    end
end

FieldViews.StridedArrayTrait(::Type{<:MArray}) = FieldViews.IsStrided()
FieldViews.StridedArrayTrait(::Type{SizedArray{Sz, T, N, M, Store}}) where {Sz, T, N, M, Store} = FieldViews.StridedArrayTrait(Store)

end
