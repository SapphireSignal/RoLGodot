class_name DSet
extends RefCounted
## Delphi `set of Byte` / `set of <enum>` values (SetComponentGroup, SetUnitProperty, SetDamageType, ...) are
## Arrays of ints in the port. A normalised set is sorted and free of duplicates: `for i in Group` in Delphi
## walks the members in ascending order, and TBlackboard.GetIndexedValue depends on that order.


## ByteArrayToComponentGroup / IntArrayToComponentGroup and every other array -> set conversion.
static func Make(values) -> Array:
	var result: Array = []
	if values == null:
		return result
	for v in values:
		var b := int(v)
		if not result.has(b):
			result.append(b)
	result.sort()
	return result


## `A * B <> []`
static func Intersects(a: Array, b: Array) -> bool:
	for v in a:
		if b.has(v):
			return true
	return false


## `A = B`
static func Equal(a: Array, b: Array) -> bool:
	return Make(a) == Make(b)


## ComponentGroupToByteArray: members in ascending order.
static func ToArray(s: Array) -> Array:
	return Make(s)
