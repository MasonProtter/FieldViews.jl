# v0.3.0

### Breaking Changes
+ `FieldLens` has been renamed to `FieldLens!!`, and `Accessors.set(obj, ::FieldLens!!, val)` will mutate `obj` if it is mutable

### Enhancements
+ `FieldViewable` and `FieldView` now support non-concrete and mutable storage types, they just hit the slow fallback like for non-strided arrays, and non-isbits fields.

# v0.2.3

+ Non-strided arrays can now be used with field views, but they hit the slow fallback. Custom array types can opt into the strided array stuff by overloading `FieldViews.StridedArrayTrait(::Type{CustomType}) = FieldViews.IsStrided()`
