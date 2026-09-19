#pragma once

// TRingBuffer<T> (Engine/Engine.Helferlein.DataStructures.pas:615, implementation :1304): Size cells, index i lives in
// cell i mod Size and remembers which index set it. Reading an index whose cell was set by another index returns
// DefaultValue (with EnableDefaultValue). Every cell starts as index 0 with the zero value of T (the original
// FillChars the buffer), so index 0 counts as set from the start.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace godot {

class TRingBuffer : public RefCounted {
	GDCLASS(TRingBuffer, RefCounted)

	LocalVector<int64_t> FIndices;
	LocalVector<Variant> FValues;
	int64_t FLastIndex = -1;
	Variant FDefaultValue;
	bool FEnableDefaultValue = true;

	int64_t GetCellIndex(int64_t p_index) const;

protected:
	static void _bind_methods();

public:
	// Create(Size); ZeroValue is default(T) (false for booleans), also the initial DefaultValue.
	Ref<TRingBuffer> Create(int64_t p_size, const Variant &p_zero_value = Variant());
	int64_t GetLastIndex() const { return FLastIndex; }
	int64_t GetSize() const { return int64_t(FIndices.size()); }
	Variant GetDefaultValue() const { return FDefaultValue; }
	void SetDefaultValue(const Variant &p_value) { FDefaultValue = p_value; }
	bool GetEnableDefaultValue() const { return FEnableDefaultValue; }
	void SetEnableDefaultValue(bool p_value) { FEnableDefaultValue = p_value; }
	Variant GetItem(int64_t p_index) const;
	void SetItem(int64_t p_index, const Variant &p_value);
	// Returns True is the cell that the index points is set by the index, else false.
	bool IsIndexSet(int64_t p_index) const;
	// Add value to end of ringbuffer using last index + 1.
	void Append(const Variant &p_value);
};

} // namespace godot
