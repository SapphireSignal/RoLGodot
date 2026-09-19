#include "engine/delphi_dictionary.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <utility>

namespace godot {

void DelphiDictionary::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "HashFunc", "EqualsFunc"), &DelphiDictionary::Create);
	ClassDB::bind_method(D_METHOD("GetCount"), &DelphiDictionary::GetCount);
	ClassDB::bind_method(D_METHOD("Hash", "Key"), &DelphiDictionary::Hash);
	ClassDB::bind_method(D_METHOD("Add", "Key", "Value"), &DelphiDictionary::Add);
	ClassDB::bind_method(D_METHOD("ContainsKey", "Key"), &DelphiDictionary::ContainsKey);
	ClassDB::bind_method(D_METHOD("GetItem", "Key"), &DelphiDictionary::GetItem);
	ClassDB::bind_method(D_METHOD("Remove", "Key"), &DelphiDictionary::Remove);
	ClassDB::bind_method(D_METHOD("NextSlot", "Slot"), &DelphiDictionary::NextSlot);
	ClassDB::bind_method(D_METHOD("KeyAt", "Slot"), &DelphiDictionary::KeyAt);
	ClassDB::bind_method(D_METHOD("ValueAt", "Slot"), &DelphiDictionary::ValueAt);
	ClassDB::bind_method(D_METHOD("Keys"), &DelphiDictionary::Keys);
	ClassDB::bind_method(D_METHOD("Clear"), &DelphiDictionary::Clear);
	ClassDB::bind_method(D_METHOD("GetCapacity"), &DelphiDictionary::GetCapacity);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Count"), "", "GetCount");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Capacity"), "", "GetCapacity");
}

Ref<DelphiDictionary> DelphiDictionary::Create(const Callable &p_hash_func, const Callable &p_equals_func) {
	FHashFunc = p_hash_func;
	FEqualsFunc = p_equals_func;
	return Ref<DelphiDictionary>(this);
}

int64_t DelphiDictionary::Hash(const Variant &p_key) const {
	return POSITIVE_MASK & ((POSITIVE_MASK & int64_t(FHashFunc.call(p_key))) + 1);
}

int64_t DelphiDictionary::GetBucketIndex(const Variant &p_key, int64_t p_hash_code) const {
	const int64_t len = int64_t(FHashes.size());
	if (len == 0) {
		return -1 - 0x7FFFFFFFFFFFFFFFLL; // not High(NativeInt)
	}
	int64_t result = p_hash_code & (len - 1);
	while (true) {
		const int64_t hc = FHashes[result];
		if (hc == EMPTY_HASH) {
			return -1 - result;
		}
		if (hc == p_hash_code && bool(FEqualsFunc.call(FKeys[result], p_key))) {
			return result;
		}
		result++;
		if (result >= len) {
			result = 0;
		}
	}
}

void DelphiDictionary::Rehash(int64_t p_new_cap_pow2) {
	if (p_new_cap_pow2 == int64_t(FHashes.size())) {
		return;
	}
	LocalVector<int64_t> old_hashes = std::move(FHashes);
	LocalVector<Variant> old_keys = std::move(FKeys);
	LocalVector<Variant> old_values = std::move(FValues);
	FHashes.clear();
	FHashes.resize(p_new_cap_pow2);
	for (int64_t i = 0; i < p_new_cap_pow2; i++) {
		FHashes[i] = EMPTY_HASH;
	}
	FKeys.clear();
	FKeys.resize(p_new_cap_pow2);
	FValues.clear();
	FValues.resize(p_new_cap_pow2);
	FGrowThreshold = (p_new_cap_pow2 >> 1) + (p_new_cap_pow2 >> 2); // 75%
	for (uint32_t i = 0; i < old_hashes.size(); i++) {
		if (old_hashes[i] != EMPTY_HASH) {
			const int64_t j = -1 - GetBucketIndex(old_keys[i], old_hashes[i]);
			FHashes[j] = old_hashes[i];
			FKeys[j] = old_keys[i];
			FValues[j] = old_values[i];
		}
	}
}

void DelphiDictionary::Grow() {
	int64_t new_cap = int64_t(FHashes.size()) * 2;
	if (new_cap == 0) {
		new_cap = 4;
	}
	Rehash(new_cap);
}

void DelphiDictionary::Add(const Variant &p_key, const Variant &p_value) {
	if (FCount >= FGrowThreshold) {
		Grow();
	}
	const int64_t hc = Hash(p_key);
	int64_t index = GetBucketIndex(p_key, hc);
	if (index >= 0) {
		UtilityFunctions::push_error("DelphiDictionary.Add: Duplicates not allowed");
		return;
	}
	index = -1 - index;
	FHashes[index] = hc;
	FKeys[index] = p_key;
	FValues[index] = p_value;
	FCount++;
}

bool DelphiDictionary::ContainsKey(const Variant &p_key) const {
	return GetBucketIndex(p_key, Hash(p_key)) >= 0;
}

Variant DelphiDictionary::GetItem(const Variant &p_key) const {
	const int64_t index = GetBucketIndex(p_key, Hash(p_key));
	if (index < 0) {
		UtilityFunctions::push_error("DelphiDictionary.GetItem: Item not found");
		return Variant();
	}
	return FValues[index];
}

void DelphiDictionary::Remove(const Variant &p_key) {
	int64_t index = GetBucketIndex(p_key, Hash(p_key));
	if (index < 0) {
		return;
	}
	const int64_t len = int64_t(FHashes.size());
	FHashes[index] = EMPTY_HASH;
	int64_t gap = index;
	while (true) {
		index++;
		if (index == len) {
			index = 0;
		}
		const int64_t hc = FHashes[index];
		if (hc == EMPTY_HASH) {
			break;
		}
		const int64_t bucket = hc & (len - 1);
		if (!InCircularRange(gap, bucket, index)) {
			FHashes[gap] = FHashes[index];
			FKeys[gap] = FKeys[index];
			FValues[gap] = FValues[index];
			gap = index;
			FHashes[gap] = EMPTY_HASH;
		}
	}
	FHashes[gap] = EMPTY_HASH;
	FKeys[gap] = Variant();
	FValues[gap] = Variant();
	FCount--;
}

bool DelphiDictionary::InCircularRange(int64_t p_bottom, int64_t p_item, int64_t p_top_inc) {
	return (p_bottom < p_item && p_item <= p_top_inc) || (p_top_inc < p_bottom && p_item > p_bottom) ||
			(p_top_inc < p_bottom && p_item <= p_top_inc);
}

int64_t DelphiDictionary::NextSlot(int64_t p_slot) const {
	while (p_slot < int64_t(FHashes.size()) - 1) {
		p_slot++;
		if (FHashes[p_slot] != EMPTY_HASH) {
			return p_slot;
		}
	}
	return -1;
}

Variant DelphiDictionary::KeyAt(int64_t p_slot) const {
	return FKeys[p_slot];
}

Variant DelphiDictionary::ValueAt(int64_t p_slot) const {
	return FValues[p_slot];
}

Array DelphiDictionary::Keys() const {
	Array result;
	int64_t slot = NextSlot(-1);
	while (slot >= 0) {
		result.append(FKeys[slot]);
		slot = NextSlot(slot);
	}
	return result;
}

void DelphiDictionary::Clear() {
	FHashes.clear();
	FKeys.clear();
	FValues.clear();
	FCount = 0;
	FGrowThreshold = 0;
}

} // namespace godot
