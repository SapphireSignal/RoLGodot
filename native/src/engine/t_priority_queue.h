#pragma once

// TPriorityQueue<T : class> (Engine/Engine.Helferlein.DataStructures.pas:416, base TPriorityQueue<T, U> :369,
// implementation :979): a sorted array, highest priority first, so ExtractMin takes the last item. Priorities are
// singles compared with CompareValue, so priorities within a relative 1E-4 count as equal; an item inserted among
// equal priorities comes out before them (last in, first out). TIntPriorityQueue compares exactly. The Order property
// (poDescending) is never used by the game: ascending only.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace godot {

class TPriorityQueue : public RefCounted {
	GDCLASS(TPriorityQueue, RefCounted)

	struct RItem {
		Variant Data;
		Variant Priority;
	};

	LocalVector<RItem> FItems;

protected:
	static void _bind_methods();

	// -1, 0 or 1
	virtual int Compare(const Variant &p_a, const Variant &p_b) const;

public:
	int64_t GetCount() const { return int64_t(FItems.size()); }
	// Inserts a new item to the queue. Priority is fetched once at insertion.
	void Insert(const Variant &p_data, const Variant &p_priority);
	// Returns the first item in relation to order and removes it from the queue.
	Variant ExtractMin();
	Variant Peek() const;
	Variant PeekPriority() const;
	bool Contains(const Variant &p_item) const;
	// Removes the first entry of the item (lowest index = highest priority).
	void Remove(const Variant &p_item);
	// Changes the priority of an item: remove and insert again.
	void DecreaseKey(const Variant &p_item, const Variant &p_new_priority);
	void Clear();
	bool IsEmpty() const { return FItems.is_empty(); }
};

// TIntPriorityQueue<T : class> (Engine/Engine.Helferlein.DataStructures.pas:422): Int64 priorities, compared exactly
// (the server's delayed events).
class TIntPriorityQueue : public TPriorityQueue {
	GDCLASS(TIntPriorityQueue, TPriorityQueue)

protected:
	static void _bind_methods() {}

	int Compare(const Variant &p_a, const Variant &p_b) const override;
};

} // namespace godot
