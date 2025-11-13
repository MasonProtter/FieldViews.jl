# v0.2.3

+ Non-strided arrays can now be used with field views, but they hit the slow fallback. Custom array types can opt into the strided array stuff by overloading `FieldViews.StridedArrayTrait(::Type{CustomType}) = FieldViews.IsStrided()`
