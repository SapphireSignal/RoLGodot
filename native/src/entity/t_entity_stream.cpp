#include "entity/t_entity_stream.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void TEntityStream::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Write", "value"), &TEntityStream::Write);
	ClassDB::bind_method(D_METHOD("Read"), &TEntityStream::Read);
	ClassDB::bind_method(D_METHOD("Size"), &TEntityStream::Size);
	ClassDB::bind_method(D_METHOD("GetData"), &TEntityStream::GetData);
	ClassDB::bind_method(D_METHOD("SetData", "value"), &TEntityStream::SetData);
	ClassDB::bind_method(D_METHOD("GetPosition"), &TEntityStream::GetPosition);
	ClassDB::bind_method(D_METHOD("SetPosition", "value"), &TEntityStream::SetPosition);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "Data"), "SetData", "GetData");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Position"), "SetPosition", "GetPosition");
}

Variant TEntityStream::Read() {
	const Variant value = Data[Position];
	Position++;
	return value;
}

} // namespace godot
