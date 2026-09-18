class_name DelphiSort
extends RefCounted
## Delphi's TList<T>.Sort / TArray.Sort<T> with a comparer (System.Generics.Collections, Delphi 10.1 Berlin, the
## original's compiler): an unstable quicksort, pivot = middle element, recursing into the left part and looping on
## the right. Elements that compare equal end up in this algorithm's order, so ports that sort with ties use it
## instead of Array.sort_custom. Note two equal neighbours get swapped (later RTLs skip that swap).
## Assumption: the reference snapshot has no RTL; this is Berlin's TArray.QuickSort, before the Tokyo/Rio rewrite.


## Sorts Values in place; Comparer(L, R) returns < 0, 0 or > 0 (a Delphi IComparer).
static func Sort(Values: Array, Comparer: Callable) -> void:
	if Values.size() > 1:
		QuickSort(Values, Comparer, 0, Values.size() - 1)


static func QuickSort(Values: Array, Comparer: Callable, L: int, R: int) -> void:
	if Values.is_empty() or (R - L) <= 0:
		return
	var I: int
	while true:
		I = L
		var J := R
		var pivot = Values[L + ((R - L) >> 1)]
		while true:
			while int(Comparer.call(Values[I], pivot)) < 0:
				I += 1
			while int(Comparer.call(Values[J], pivot)) > 0:
				J -= 1
			if I <= J:
				if I != J:
					var temp = Values[I]
					Values[I] = Values[J]
					Values[J] = temp
				I += 1
				J -= 1
			if I > J:
				break
		if L < J:
			QuickSort(Values, Comparer, L, J)
		L = I
		if I >= R:
			break
