#include "engine/t_priority_queue.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include "engine/delphi_math.h"

namespace godot {

void TPriorityQueue::_bind_methods() {
	ClassDB::bind_method(D_METHOD("GetCount"), &TPriorityQueue::GetCount);
	ClassDB::bind_method(D_METHOD("Insert", "Data", "Priority"), &TPriorityQueue::Insert);
	ClassDB::bind_method(D_METHOD("ExtractMin"), &TPriorityQueue::ExtractMin);
	ClassDB::bind_method(D_METHOD("Peek"), &TPriorityQueue::Peek);
	ClassDB::bind_method(D_METHOD("PeekPriority"), &TPriorityQueue::PeekPriority);
	ClassDB::bind_method(D_METHOD("Contains", "Item"), &TPriorityQueue::Contains);
	ClassDB::bind_method(D_METHOD("Remove", "Item"), &TPriorityQueue::Remove);
	ClassDB::bind_method(D_METHOD("DecreaseKey", "Item", "NewPriority"), &TPriorityQueue::DecreaseKey);
	ClassDB::bind_method(D_METHOD("Clear"), &TPriorityQueue::Clear);
	ClassDB::bind_method(D_METHOD("IsEmpty"), &TPriorityQueue::IsEmpty);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Count"), "", "GetCount");
}

int TPriorityQueue::Compare(const Variant &p_a, const Variant &p_b) const {
	return delphi::CompareValue(double(p_a), double(p_b));
}

void TPriorityQueue::Insert(const Variant &p_data, const Variant &p_priority) {
	int64_t i = int64_t(FItems.size()) - 1;
	// shift every item the new one is greater than (GreaterThanValue) one up
	while (i >= 0 && Compare(p_priority, FItems[i].Priority) == 1) {
		i--;
	}
	FItems.insert(uint32_t(i + 1), RItem{ p_data, p_priority });
}

Variant TPriorityQueue::ExtractMin() {
	ERR_FAIL_COND_V_MSG(FItems.is_empty(), Variant(), "TPriorityQueue.ExtractMin: Called with Count = 0!");
	const Variant result = FItems[FItems.size() - 1].Data;
	FItems.resize(FItems.size() - 1);
	return result;
}

Variant TPriorityQueue::Peek() const {
	ERR_FAIL_COND_V_MSG(FItems.is_empty(), Variant(), "TPriorityQueue.Peek: Called with Count = 0!");
	return FItems[FItems.size() - 1].Data;
}

Variant TPriorityQueue::PeekPriority() const {
	ERR_FAIL_COND_V_MSG(FItems.is_empty(), Variant(), "TPriorityQueue.PeekPriority: Called with Count = 0!");
	return FItems[FItems.size() - 1].Priority;
}

bool TPriorityQueue::Contains(const Variant &p_item) const {
	for (const RItem &item : FItems) {
		if (item.Data == p_item) {
			return true;
		}
	}
	return false;
}

void TPriorityQueue::Remove(const Variant &p_item) {
	for (uint32_t i = 0; i < FItems.size(); i++) {
		if (FItems[i].Data == p_item) {
			FItems.remove_at(i);
			return;
		}
	}
}

void TPriorityQueue::DecreaseKey(const Variant &p_item, const Variant &p_new_priority) {
	Remove(p_item);
	Insert(p_item, p_new_priority);
}

void TPriorityQueue::Clear() {
	FItems.clear();
}

int TIntPriorityQueue::Compare(const Variant &p_a, const Variant &p_b) const {
	const int64_t a = p_a;
	const int64_t b = p_b;
	if (a == b) {
		return 0;
	}
	return a < b ? -1 : 1;
}

} // namespace godot
