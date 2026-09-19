#include "entity/r_param.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

static double to_single_bound(double p_x) {
	return RParam::ToSingle(p_x);
}

void RParam::_bind_methods() {
	ClassDB::bind_static_method("RParam", D_METHOD("ToSingle", "x"), &to_single_bound);
	ClassDB::bind_static_method("RParam", D_METHOD("IsEmpty", "p"), &RParam::IsEmpty);
	ClassDB::bind_static_method("RParam", D_METHOD("Copy", "p"), &RParam::Copy);
	ClassDB::bind_static_method("RParam", D_METHOD("AsInteger", "p"), &RParam::AsInteger);
	ClassDB::bind_static_method("RParam", D_METHOD("AsIntegerDefault", "p", "DefaultValue"), &RParam::AsIntegerDefault);
	ClassDB::bind_static_method("RParam", D_METHOD("AsSingle", "p"), &RParam::AsSingle);
	ClassDB::bind_static_method("RParam", D_METHOD("AsSingleDefault", "p", "DefaultValue"), &RParam::AsSingleDefault);
	ClassDB::bind_static_method("RParam", D_METHOD("AsBoolean", "p"), &RParam::AsBoolean);
	ClassDB::bind_static_method("RParam", D_METHOD("AsBooleanDefaultTrue", "p"), &RParam::AsBooleanDefaultTrue);
	ClassDB::bind_static_method("RParam", D_METHOD("AsString", "p"), &RParam::AsString);
	ClassDB::bind_static_method("RParam", D_METHOD("AsVector2", "p"), &RParam::AsVector2);
	ClassDB::bind_static_method("RParam", D_METHOD("AsVector2Default", "p", "DefaultValue"), &RParam::AsVector2Default);
	ClassDB::bind_static_method("RParam", D_METHOD("AsVector3", "p"), &RParam::AsVector3);
	ClassDB::bind_static_method("RParam", D_METHOD("AsVector3Default", "p", "DefaultValue"), &RParam::AsVector3Default);
	ClassDB::bind_static_method("RParam", D_METHOD("AsIntVector2", "p"), &RParam::AsIntVector2);
	ClassDB::bind_static_method("RParam", D_METHOD("AsEnumType", "p"), &RParam::AsEnumType);
	ClassDB::bind_static_method("RParam", D_METHOD("AsSet", "p"), &RParam::AsSet);
	ClassDB::bind_static_method("RParam", D_METHOD("AsArray", "p"), &RParam::AsArray);
	ClassDB::bind_static_method("RParam", D_METHOD("AsObject", "p"), &RParam::AsObject);
	ClassDB::bind_static_method("RParam", D_METHOD("Equal", "a", "b"), &RParam::Equal);
}

bool RParam::IsEmpty(const Variant &p) {
	return p.get_type() == Variant::NIL;
}

Variant RParam::Copy(const Variant &p) {
	switch (p.get_type()) {
		case Variant::ARRAY:
			return Array(p).duplicate(true);
		case Variant::DICTIONARY:
			return Dictionary(p).duplicate(true);
		default:
			return p;
	}
}

int64_t RParam::AsInteger(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return 0;
		case Variant::INT:
			return int64_t(p);
		case Variant::BOOL:
			return bool(p) ? 1 : 0;
		case Variant::FLOAT:
			return SingleBitsAsInt(float(double(p)));
		case Variant::VECTOR2:
			return SingleBitsAsInt(Vector2(p).x);
		case Variant::VECTOR3:
			return SingleBitsAsInt(Vector3(p).x);
		case Variant::VECTOR2I:
			return Vector2i(p).x;
		default:
			UtilityFunctions::push_error("RParam.AsInteger: no integer view of ", Variant::get_type_name(p.get_type()));
			return 0;
	}
}

int64_t RParam::AsIntegerDefault(const Variant &p, int64_t p_default) {
	return p.get_type() == Variant::NIL ? p_default : AsInteger(p);
}

double RParam::AsSingle(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return 0.0;
		case Variant::FLOAT:
			return double(p);
		case Variant::INT:
			return IntBitsAsSingle(int32_t(int64_t(p)));
		case Variant::BOOL:
			return IntBitsAsSingle(bool(p) ? 1 : 0);
		case Variant::VECTOR2:
			return Vector2(p).x;
		case Variant::VECTOR3:
			return Vector3(p).x;
		case Variant::VECTOR2I:
			return IntBitsAsSingle(Vector2i(p).x);
		default:
			UtilityFunctions::push_error("RParam.AsSingle: no single view of ", Variant::get_type_name(p.get_type()));
			return 0.0;
	}
}

double RParam::AsSingleDefault(const Variant &p, double p_default) {
	return p.get_type() == Variant::NIL ? p_default : AsSingle(p);
}

bool RParam::AsBoolean(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return false;
		case Variant::BOOL:
			return bool(p);
		case Variant::INT:
			return (int64_t(p) & 0xFF) != 0;
		case Variant::FLOAT:
			return (SingleBitsAsInt(float(double(p))) & 0xFF) != 0;
		default:
			return (AsInteger(p) & 0xFF) != 0;
	}
}

bool RParam::AsBooleanDefaultTrue(const Variant &p) {
	return p.get_type() == Variant::NIL || AsBoolean(p);
}

String RParam::AsString(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return String();
		case Variant::STRING:
		case Variant::STRING_NAME:
			return String(p);
		default:
			UtilityFunctions::push_error("RParam.AsString: ", Variant::get_type_name(p.get_type()), " is not a string");
			return String();
	}
}

Vector2 RParam::AsVector2(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return Vector2();
		case Variant::VECTOR2:
			return Vector2(p);
		case Variant::VECTOR3: {
			const Vector3 v = p;
			return Vector2(v.x, v.y);
		}
		default:
			UtilityFunctions::push_error("RParam.AsVector2: ", Variant::get_type_name(p.get_type()), " is not a vector");
			return Vector2();
	}
}

Vector2 RParam::AsVector2Default(const Variant &p, const Vector2 &p_default) {
	return p.get_type() == Variant::NIL ? p_default : AsVector2(p);
}

Vector3 RParam::AsVector3(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return Vector3();
		case Variant::VECTOR3:
			return Vector3(p);
		case Variant::VECTOR2: {
			const Vector2 v = p;
			return Vector3(v.x, v.y, 0.0);
		}
		default:
			UtilityFunctions::push_error("RParam.AsVector3: ", Variant::get_type_name(p.get_type()), " is not a vector");
			return Vector3();
	}
}

Vector3 RParam::AsVector3Default(const Variant &p, const Vector3 &p_default) {
	return p.get_type() == Variant::NIL ? p_default : AsVector3(p);
}

Vector2i RParam::AsIntVector2(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return Vector2i();
		case Variant::VECTOR2I:
			return Vector2i(p);
		default:
			UtilityFunctions::push_error("RParam.AsIntVector2: ", Variant::get_type_name(p.get_type()), " is not an int vector");
			return Vector2i();
	}
}

int64_t RParam::AsEnumType(const Variant &p) {
	return AsInteger(p) & 0xFF;
}

Array RParam::AsSet(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return Array();
		case Variant::ARRAY:
			return Array(p);
		default:
			UtilityFunctions::push_error("RParam.AsSet: ", Variant::get_type_name(p.get_type()), " is not a set");
			return Array();
	}
}

Array RParam::AsArray(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return Array();
		case Variant::ARRAY:
			return Array(p);
		default:
			UtilityFunctions::push_error("RParam.AsArray: ", Variant::get_type_name(p.get_type()), " is not an array");
			return Array();
	}
}

Object *RParam::AsObject(const Variant &p) {
	switch (p.get_type()) {
		case Variant::NIL:
			return nullptr;
		case Variant::OBJECT:
			return p;
		default:
			UtilityFunctions::push_error("RParam.AsObject: ", Variant::get_type_name(p.get_type()), " is not an object");
			return nullptr;
	}
}

bool RParam::Equal(const Variant &p_a, const Variant &p_b) {
	if (p_a.get_type() != p_b.get_type()) {
		return false;
	}
	if (p_a.get_type() == Variant::ARRAY) {
		UtilityFunctions::push_error("RParam.equal: Array not implemented yet.");
		return false;
	}
	return p_a == p_b;
}

} // namespace godot
