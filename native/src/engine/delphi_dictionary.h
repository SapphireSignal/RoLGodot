#pragma once

// Delphi's TDictionary<K, V> with a custom equality comparer (System.Generics.Collections): an open-addressing table
// with linear probing, capacity a power of two, Knuth's backward-shift delete. Ports use it where the original walks a
// dictionary (enumeration follows the slots, i.e. hash order) or removes while walking: removing shifts later entries
// back, so a live walk (NextSlot) can skip one, exactly as the original's `for Key in Dict.Keys`.
// Assumption: the reference snapshot has no RTL; the grow threshold is Berlin's 75% (Delphi 12+ uses 50%). Creation
// with capacity 0: the first Add grows to 4 slots, then the table doubles when Count reaches the threshold.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace godot {

class DelphiDictionary : public RefCounted {
	GDCLASS(DelphiDictionary, RefCounted)

	static constexpr int64_t EMPTY_HASH = -1;
	static constexpr int64_t POSITIVE_MASK = 0x7FFFFFFF;

	Callable FHashFunc; // Key -> int (the comparer's GetHashCode)
	Callable FEqualsFunc; // (Left, Right) -> bool (the comparer's Equals)
	LocalVector<int64_t> FHashes;
	LocalVector<Variant> FKeys;
	LocalVector<Variant> FValues;
	int64_t FCount = 0;
	int64_t FGrowThreshold = 0;

	// The slot of Key, or the complement (-1 - slot) of its insertion point.
	int64_t GetBucketIndex(const Variant &p_key, int64_t p_hash_code) const;
	void Rehash(int64_t p_new_cap_pow2);
	void Grow();
	static bool InCircularRange(int64_t p_bottom, int64_t p_item, int64_t p_top_inc);

protected:
	static void _bind_methods();

public:
	Ref<DelphiDictionary> Create(const Callable &p_hash_func, const Callable &p_equals_func);
	int64_t GetCount() const { return FCount; }
	// the number of slots (Length(FItems))
	int64_t GetCapacity() const { return int64_t(FHashes.size()); }
	// TDictionary.Hash: positive, never EMPTY_HASH.
	int64_t Hash(const Variant &p_key) const;
	// Add: a duplicate key is an error (EListError in the original).
	void Add(const Variant &p_key, const Variant &p_value);
	bool ContainsKey(const Variant &p_key) const;
	// Items[Key]; a missing key is an error (EListError), null here.
	Variant GetItem(const Variant &p_key) const;
	void Remove(const Variant &p_key);
	// TKeyEnumerator.MoveNext: the next used slot after Slot (start with -1), or -1. Walks the live table.
	int64_t NextSlot(int64_t p_slot) const;
	Variant KeyAt(int64_t p_slot) const;
	Variant ValueAt(int64_t p_slot) const;
	// The keys in enumeration (slot) order, a snapshot.
	Array Keys() const;
	void Clear();
};

} // namespace godot
