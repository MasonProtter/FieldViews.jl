module StaticArraysExt

using FieldViews, StaticArrays

function FieldViews.fieldmap(::Type{SA}) where {SA <: SVector}
    if length(SA) < 4
        names = (:x, :y, :z, :w)
        ntuple(Val(length(SA))) do i
            :data => Renamed(i, names[i])
        end
    else
        ()
    end
end

end
