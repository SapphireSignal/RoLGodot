#include "entity/d_set.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void DSet::_bind_methods() {
	ClassDB::bind_static_method("DSet", D_METHOD("Make", "values"), &DSet::Make);
	ClassDB::bind_static_method("DSet", D_METHOD("Intersects", "a", "b"), &DSet::Intersects);
	ClassDB::bind_static_method("DSet", D_METHOD("Union", "a", "b"), &DSet::Union);
	ClassDB::bind_static_method("DSet", D_METHOD("Difference", "a", "b"), &DSet::Difference);
	ClassDB::bind_static_method("DSet", D_METHOD("Intersection", "a", "b"), &DSet::Intersection);
	ClassDB::bind_static_method("DSet", D_METHOD("IsSubset", "a", "b"), &DSet::IsSubset);
	ClassDB::bind_static_method("DSet", D_METHOD("Equal", "a", "b"), &DSet::Equal);
	ClassDB::bind_static_method("DSet", D_METHOD("ToArray", "s"), &DSet::ToArray);
}

// Adds the members of an array-like value (int() of each, as GDScript's int(v): floats truncate).
static void add_members(Array &r_result, const Variant &p_values) {
	switch (p_values.get_type()) {
		case Variant::NIL:
			return;
		case Variant::ARRAY: {
			const Array values = p_values;
			const int64_t count = values.size();
			// fast paths (hot in every event call): no or one member
			if (count == 0) {
				return;
			}
			if (count == 1) {
				r_result.append(int64_t(values[0]));
				return;
			}
			for (int64_t i = 0; i < count; i++) {
				const int64_t b = values[i];
				if (!r_result.has(b)) {
					r_result.append(b);
				}
			}
			return;
		}
		default: {
			// packed arrays and anything else iterable by index
			const Array values = Array(p_values);
			for (int64_t i = 0; i < values.size(); i++) {
				const int64_t b = values[i];
				if (!r_result.has(b)) {
					r_result.append(b);
				}
			}
			return;
		}
	}
}

Array DSet::Make(const Variant &p_values) {
	Array result;
	add_members(result, p_values);
	if (result.size() > 1) {
		result.sort();
	}
	return result;
}

bool DSet::Intersects(const Array &p_a, const Array &p_b) {
	for (int64_t i = 0; i < p_a.size(); i++) {
		if (p_b.has(p_a[i])) {
			return true;
		}
	}
	return false;
}

Array DSet::Union(const Array &p_a, const Array &p_b) {
	Array joined = p_a.duplicate();
	joined.append_array(p_b);
	return Make(joined);
}

Array DSet::Difference(const Array &p_a, const Array &p_b) {
	Array result;
	const Array a = Make(p_a);
	for (int64_t i = 0; i < a.size(); i++) {
		if (!p_b.has(a[i])) {
			result.append(a[i]);
		}
	}
	return result;
}

Array DSet::Intersection(const Array &p_a, const Array &p_b) {
	Array result;
	const Array a = Make(p_a);
	for (int64_t i = 0; i < a.size(); i++) {
		if (p_b.has(a[i])) {
			result.append(a[i]);
		}
	}
	return result;
}

bool DSet::IsSubset(const Array &p_a, const Array &p_b) {
	for (int64_t i = 0; i < p_a.size(); i++) {
		if (!p_b.has(p_a[i])) {
			return false;
		}
	}
	return true;
}

bool DSet::Equal(const Array &p_a, const Array &p_b) {
	return Make(p_a) == Make(p_b);
}

Array DSet::ToArray(const Array &p_s) {
	return Make(p_s);
}

} // namespace godot
