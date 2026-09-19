#pragma once

// Delphi's TList<T>.Sort / TArray.Sort<T> with a comparer (System.Generics.Collections, Delphi 10.1 Berlin, the
// original's compiler): an unstable quicksort, pivot = middle element, recursing into the left part and looping on the
// right. Elements that compare equal end up in this algorithm's order, so ports that sort with ties use it instead of
// Array.sort_custom. Note two equal neighbours get swapped (later RTLs skip that swap).
// Assumption: the reference snapshot has no RTL; this is Berlin's TArray.QuickSort, before the Tokyo/Rio rewrite.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>

#include <cstdint>
#include <utility>

namespace godot {

class DelphiSort : public RefCounted {
	GDCLASS(DelphiSort, RefCounted)

protected:
	static void _bind_methods();

public:
	// TArray.QuickSort over any indexable container; p_compare(L, R) returns < 0, 0 or > 0 (a Delphi IComparer).
	template <typename TValues, typename TCompare>
	static void QuickSortT(TValues &r_values, const TCompare &p_compare, int64_t p_l, int64_t p_r) {
		if (p_r - p_l <= 0) {
			return;
		}
		int64_t i;
		while (true) {
			i = p_l;
			int64_t j = p_r;
			const auto pivot = r_values[p_l + ((p_r - p_l) >> 1)];
			while (true) {
				while (p_compare(r_values[i], pivot) < 0) {
					i++;
				}
				while (p_compare(r_values[j], pivot) > 0) {
					j--;
				}
				if (i <= j) {
					if (i != j) {
						const auto temp = r_values[i];
						r_values[i] = r_values[j];
						r_values[j] = temp;
					}
					i++;
					j--;
				}
				if (i > j) {
					break;
				}
			}
			if (p_l < j) {
				QuickSortT(r_values, p_compare, p_l, j);
			}
			p_l = i;
			if (i >= p_r) {
				break;
			}
		}
	}

	// Sorts Values in place; Comparer(L, R) returns < 0, 0 or > 0.
	static void Sort(Array p_values, const Callable &p_comparer);
};

} // namespace godot
