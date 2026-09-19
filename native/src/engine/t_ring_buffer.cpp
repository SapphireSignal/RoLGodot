#include "engine/t_ring_buffer.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

namespace godot {

void TRingBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "Size", "ZeroValue"), &TRingBuffer::Create, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("GetLastIndex"), &TRingBuffer::GetLastIndex);
	ClassDB::bind_method(D_METHOD("GetSize"), &TRingBuffer::GetSize);
	ClassDB::bind_method(D_METHOD("GetDefaultValue"), &TRingBuffer::GetDefaultValue);
	ClassDB::bind_method(D_METHOD("SetDefaultValue", "value"), &TRingBuffer::SetDefaultValue);
	ClassDB::bind_method(D_METHOD("GetEnableDefaultValue"), &TRingBuffer::GetEnableDefaultValue);
	ClassDB::bind_method(D_METHOD("SetEnableDefaultValue", "value"), &TRingBuffer::SetEnableDefaultValue);
	ClassDB::bind_method(D_METHOD("GetItem", "Index"), &TRingBuffer::GetItem);
	ClassDB::bind_method(D_METHOD("SetItem", "Index", "Value"), &TRingBuffer::SetItem);
	ClassDB::bind_method(D_METHOD("IsIndexSet", "Index"), &TRingBuffer::IsIndexSet);
	ClassDB::bind_method(D_METHOD("Append", "Value"), &TRingBuffer::Append);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "LastIndex"), "", "GetLastIndex");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Size"), "", "GetSize");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "DefaultValue", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT),
			"SetDefaultValue", "GetDefaultValue");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "EnableDefaultValue"), "SetEnableDefaultValue", "GetEnableDefaultValue");
}

Ref<TRingBuffer> TRingBuffer::Create(int64_t p_size, const Variant &p_zero_value) {
	ERR_FAIL_COND_V(p_size <= 0, Ref<TRingBuffer>(this));
	FIndices.resize(uint32_t(p_size));
	FValues.resize(uint32_t(p_size));
	for (int64_t i = 0; i < p_size; i++) {
		FIndices[i] = 0;
		FValues[i] = p_zero_value;
	}
	FDefaultValue = p_zero_value;
	return Ref<TRingBuffer>(this);
}

int64_t TRingBuffer::GetCellIndex(int64_t p_index) const {
	DEV_ASSERT(p_index >= 0);
	return p_index % int64_t(FIndices.size());
}

Variant TRingBuffer::GetItem(int64_t p_index) const {
	const int64_t cell_index = GetCellIndex(p_index);
	if (!FEnableDefaultValue || FIndices[cell_index] == p_index) {
		return FValues[cell_index];
	}
	return FDefaultValue;
}

void TRingBuffer::SetItem(int64_t p_index, const Variant &p_value) {
	const int64_t cell_index = GetCellIndex(p_index);
	FIndices[cell_index] = p_index;
	FValues[cell_index] = p_value;
	FLastIndex = p_index;
}

bool TRingBuffer::IsIndexSet(int64_t p_index) const {
	return FIndices[GetCellIndex(p_index)] == p_index;
}

void TRingBuffer::Append(const Variant &p_value) {
	SetItem(FLastIndex + 1, p_value);
}

} // namespace godot
