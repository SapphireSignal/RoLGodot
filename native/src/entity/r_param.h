#pragma once

// RParam (Engine/Engine.Helferlein.Windows.pas:214) is a Variant: nil is RPARAMEMPTY, anything else is a value. This
// class holds the accessors. The original reads a value by memory cast, not by conversion ("Read any data from a
// RParam will NOT convert any data"), and the shipped builds had no DEBUG type checks, so AsSingle on an integer
// reinterprets its bits. The accessors reproduce that. Sets and byte arrays are Arrays of ints (see DSet); Delphi
// `single` values are rounded to 32 bit on entry from the scripts (TBlackboard / TEventbus script side).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <cstring>

namespace godot {

class RParam : public RefCounted {
	GDCLASS(RParam, RefCounted)

protected:
	static void _bind_methods();

public:
	// Round a double to the nearest 32-bit single, as a Delphi `single` variable holds it.
	static inline double ToSingle(double p_x) { return double(float(p_x)); }

	static inline float IntBitsAsSingle(int32_t p_i) {
		float f;
		std::memcpy(&f, &p_i, sizeof(f));
		return f;
	}

	static inline int32_t SingleBitsAsInt(float p_f) {
		int32_t i;
		std::memcpy(&i, &p_f, sizeof(i));
		return i;
	}

	static bool IsEmpty(const Variant &p);
	// A value as RParam.SerializeIntoStream / DeserializeFromStream hand it on: arrays and dictionaries deep copied,
	// objects (records kept as objects) shared.
	static Variant Copy(const Variant &p);
	// FInteger: the first 4 bytes of the union.
	static int64_t AsInteger(const Variant &p);
	static int64_t AsIntegerDefault(const Variant &p, int64_t p_default);
	// FSingle: the first 4 bytes of the union.
	static double AsSingle(const Variant &p);
	static double AsSingleDefault(const Variant &p, double p_default);
	// FBoolean: the first byte of the union.
	static bool AsBoolean(const Variant &p);
	// IsEmpty or AsBoolean
	static bool AsBooleanDefaultTrue(const Variant &p);
	static String AsString(const Variant &p);
	static Vector2 AsVector2(const Variant &p);
	static Vector2 AsVector2Default(const Variant &p, const Vector2 &p_default);
	static Vector3 AsVector3(const Variant &p);
	static Vector3 AsVector3Default(const Variant &p, const Vector3 &p_default);
	static Vector2i AsIntVector2(const Variant &p);
	// AsEnumType<T> for the one-byte enums (EnumArmorType, ...): the first byte of the union, empty = ord 0.
	static int64_t AsEnumType(const Variant &p);
	// AsSetType<T> / AsType<SetX>: a set is an Array of ints; empty RParam = empty set.
	static Array AsSet(const Variant &p);
	// AsArray<T>
	static Array AsArray(const Variant &p);
	// AsType<TObject descendant>
	static Object *AsObject(const Variant &p);
	// `a = b` (class operator equal): same type and same data; two empties are equal. An int never equals a float
	// (different FType), and 0.0 equals -0.0 (the original compared memory). Arrays raised ENotImplemented.
	static bool Equal(const Variant &p_a, const Variant &p_b);
};

} // namespace godot
