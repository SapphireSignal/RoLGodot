class_name RParam
extends RefCounted
## RParam (Engine/Engine.Helferlein.Windows.pas:214) is a Variant in the port: `null` is RPARAMEMPTY, anything
## else is a value. This class holds the accessors. The original reads a value by memory cast, not by
## conversion ("Read any data from a RParam will NOT convert any data"), and the shipped builds had no DEBUG type
## checks, so AsSingle on an integer reinterprets its bits. The accessors below reproduce that.
## Sets and byte arrays are Arrays of ints (see DSet); Delphi `single` values are rounded to 32 bit on entry
## from the scripts (TBlackboard / TEventbus script side).

const RPARAMEMPTY = null


static func IsEmpty(p) -> bool:
	return p == null


## A value as RParam.SerializeIntoStream / DeserializeFromStream hand it on: arrays and dictionaries deep copied,
## objects (records the port keeps as objects) shared.
static func Copy(p):
	if p is Array or p is Dictionary:
		return p.duplicate(true)
	return p


## Round a float to the nearest 32-bit single, as a Delphi `single` variable holds it.
## The buffer is per thread (TThreadContext.SingleBuffer): the server game may run on its own thread.
static func ToSingle(x: float) -> float:
	var Buffer := TThreadContext.Current().SingleBuffer
	Buffer[0] = x
	return Buffer[0]


static func _int_bits_as_single(i: int) -> float:
	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_s32(0, i)
	return buf.decode_float(0)


static func _single_bits_as_int(f: float) -> int:
	var buf := PackedByteArray()
	buf.resize(4)
	buf.encode_float(0, f)
	return buf.decode_s32(0)


## FInteger: the first 4 bytes of the union.
static func AsInteger(p) -> int:
	match typeof(p):
		TYPE_NIL:
			return 0
		TYPE_INT:
			return p
		TYPE_BOOL:
			return 1 if p else 0
		TYPE_FLOAT:
			return _single_bits_as_int(p)
		TYPE_VECTOR2, TYPE_VECTOR3:
			return _single_bits_as_int(p.x)
		TYPE_VECTOR2I:
			return p.x
	push_error("RParam.AsInteger: no integer view of %s" % type_string(typeof(p)))
	return 0


static func AsIntegerDefault(p, DefaultValue: int) -> int:
	return DefaultValue if p == null else AsInteger(p)


## FSingle: the first 4 bytes of the union.
static func AsSingle(p) -> float:
	match typeof(p):
		TYPE_NIL:
			return 0.0
		TYPE_FLOAT:
			return p
		TYPE_INT:
			return _int_bits_as_single(p)
		TYPE_BOOL:
			return _int_bits_as_single(1 if p else 0)
		TYPE_VECTOR2, TYPE_VECTOR3:
			return p.x
		TYPE_VECTOR2I:
			return _int_bits_as_single(p.x)
	push_error("RParam.AsSingle: no single view of %s" % type_string(typeof(p)))
	return 0.0


static func AsSingleDefault(p, DefaultValue: float) -> float:
	return DefaultValue if p == null else AsSingle(p)


## FBoolean: the first byte of the union.
static func AsBoolean(p) -> bool:
	match typeof(p):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return p
		TYPE_INT:
			return (p & 0xFF) != 0
		TYPE_FLOAT:
			return (_single_bits_as_int(p) & 0xFF) != 0
	return AsInteger(p) & 0xFF != 0


## IsEmpty or AsBoolean
static func AsBooleanDefaultTrue(p) -> bool:
	return p == null or AsBoolean(p)


static func AsString(p) -> String:
	if p == null:
		return ""
	if p is String or p is StringName:
		return String(p)
	push_error("RParam.AsString: %s is not a string" % type_string(typeof(p)))
	return ""


static func AsVector2(p) -> Vector2:
	match typeof(p):
		TYPE_NIL:
			return Vector2.ZERO
		TYPE_VECTOR2:
			return p
		TYPE_VECTOR3:
			return Vector2(p.x, p.y)
	push_error("RParam.AsVector2: %s is not a vector" % type_string(typeof(p)))
	return Vector2.ZERO


static func AsVector2Default(p, DefaultValue: Vector2) -> Vector2:
	return DefaultValue if p == null else AsVector2(p)


static func AsVector3(p) -> Vector3:
	match typeof(p):
		TYPE_NIL:
			return Vector3.ZERO
		TYPE_VECTOR3:
			return p
		TYPE_VECTOR2:
			return Vector3(p.x, p.y, 0.0)
	push_error("RParam.AsVector3: %s is not a vector" % type_string(typeof(p)))
	return Vector3.ZERO


static func AsVector3Default(p, DefaultValue: Vector3) -> Vector3:
	return DefaultValue if p == null else AsVector3(p)


static func AsIntVector2(p) -> Vector2i:
	if p == null:
		return Vector2i.ZERO
	if p is Vector2i:
		return p
	push_error("RParam.AsIntVector2: %s is not an int vector" % type_string(typeof(p)))
	return Vector2i.ZERO


## AsEnumType<T> for the one-byte enums (EnumArmorType, ...): the first byte of the union, empty = ord 0.
static func AsEnumType(p) -> int:
	return AsInteger(p) & 0xFF


## AsSetType<T> / AsType<SetX>: a set is an Array of ints; empty RParam = empty set.
static func AsSet(p) -> Array:
	if p == null:
		return []
	if p is Array:
		return p
	push_error("RParam.AsSet: %s is not a set" % type_string(typeof(p)))
	return []


## AsArray<T>
static func AsArray(p) -> Array:
	if p == null:
		return []
	if p is Array:
		return p
	push_error("RParam.AsArray: %s is not an array" % type_string(typeof(p)))
	return []


## AsType<TObject descendant>
static func AsObject(p) -> Object:
	if p == null or p is Object:
		return p
	push_error("RParam.AsObject: %s is not an object" % type_string(typeof(p)))
	return null


## `a = b` (class operator equal): same type and same data; two empties are equal. Port: an int never equals a
## float (different FType), and 0.0 equals -0.0 (the original compared memory). Arrays raised ENotImplemented.
static func Equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Array:
		push_error("RParam.equal: Array not implemented yet.")
		return false
	return a == b
