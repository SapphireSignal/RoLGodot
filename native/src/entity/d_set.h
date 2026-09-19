#pragma once

// Delphi `set of Byte` / `set of <enum>` values (SetComponentGroup, SetUnitProperty, SetDamageType, ...) are Arrays of
// ints in the port. A normalised set is sorted and free of duplicates: `for i in Group` in Delphi walks the members
// in ascending order, and TBlackboard.GetIndexedValue depends on that order. Static helpers (DSet.Make(...) etc.).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class DSet : public RefCounted {
	GDCLASS(DSet, RefCounted)

protected:
	static void _bind_methods();

public:
	// ByteArrayToComponentGroup / IntArrayToComponentGroup and every other array -> set conversion.
	static Array Make(const Variant &p_values);
	// `A * B <> []`
	static bool Intersects(const Array &p_a, const Array &p_b);
	// `A + B`, a new set.
	static Array Union(const Array &p_a, const Array &p_b);
	// `A - B`, a new set.
	static Array Difference(const Array &p_a, const Array &p_b);
	// `A * B`, a new set.
	static Array Intersection(const Array &p_a, const Array &p_b);
	// `A <= B` (every member of A is in B)
	static bool IsSubset(const Array &p_a, const Array &p_b);
	// `A = B`
	static bool Equal(const Array &p_a, const Array &p_b);
	// ComponentGroupToByteArray: members in ascending order.
	static Array ToArray(const Array &p_s);
};

} // namespace godot
