#pragma once

// Stand-in for the TStream an entity is serialized into (TEntity.Serialize, TBlackboard.SaveToStream) and read back
// from on the client (TEntity.Deserialize): the values in write order, read back with a cursor. The byte format of the
// network comes with the network's move to C++.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class TEntityStream : public RefCounted {
	GDCLASS(TEntityStream, RefCounted)

protected:
	static void _bind_methods();

public:
	Array Data;
	int64_t Position = 0;

	void Write(const Variant &p_value) { Data.append(p_value); }
	Variant Read();
	int64_t Size() const { return Data.size(); }

	Array GetData() const { return Data; }
	void SetData(const Array &p_value) { Data = p_value; }
	int64_t GetPosition() const { return Position; }
	void SetPosition(int64_t p_value) { Position = p_value; }
};

} // namespace godot
