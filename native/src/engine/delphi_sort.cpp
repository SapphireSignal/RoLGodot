#include "engine/delphi_sort.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void DelphiSort::_bind_methods() {
	ClassDB::bind_static_method("DelphiSort", D_METHOD("Sort", "Values", "Comparer"), &DelphiSort::Sort);
}

void DelphiSort::Sort(Array p_values, const Callable &p_comparer) {
	if (p_values.size() > 1) {
		QuickSortT(
				p_values, [&p_comparer](const Variant &p_l, const Variant &p_r) { return int64_t(p_comparer.call(p_l, p_r)); },
				0, p_values.size() - 1);
	}
}

} // namespace godot
