class_name DelphiHash
extends RefCounted
## Delphi's default hash functions (System.Hash / System.Generics.Defaults) for DelphiDictionary keys.
## THashBobJenkins.HashLittle is Bob Jenkins' lookup3 hashlittle() (a = b = c = $DEADBEEF + Len + InitVal); the
## string comparer hashes the UTF-16 code units (little endian, 2 bytes each) with InitVal 0.
## Assumption: the original's RTL is not in the snapshot; its string comparer is taken as Bob Jenkins (Delphi 10.x;
## Delphi 11+ uses FNV-1a). Results are Delphi Integers (signed 32 bit).

const MASK := 0xFFFFFFFF


static func _Rot(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK


## THashBobJenkins.HashLittle(Data, Len, InitVal)
static func HashLittle(Data: PackedByteArray, InitVal: int = 0) -> int:
	var Len := Data.size()
	var a := (0xDEADBEEF + Len + InitVal) & MASK
	var b := a
	var c := a
	var i := 0
	while Len > 12:
		a = (a + Data.decode_u32(i)) & MASK
		b = (b + Data.decode_u32(i + 4)) & MASK
		c = (c + Data.decode_u32(i + 8)) & MASK
		# Mix
		a = (a - c) & MASK; a ^= _Rot(c, 4); c = (c + b) & MASK
		b = (b - a) & MASK; b ^= _Rot(a, 6); a = (a + c) & MASK
		c = (c - b) & MASK; c ^= _Rot(b, 8); b = (b + a) & MASK
		a = (a - c) & MASK; a ^= _Rot(c, 16); c = (c + b) & MASK
		b = (b - a) & MASK; b ^= _Rot(a, 19); a = (a + c) & MASK
		c = (c - b) & MASK; c ^= _Rot(b, 4); b = (b + a) & MASK
		Len -= 12
		i += 12
	if Len == 0:
		return _ToInteger(c)
	# the tail: the last 1..12 bytes as little-endian words, missing bytes zero
	var Tail := [0, 0, 0]
	for j in range(Len):
		Tail[j >> 2] |= Data[i + j] << (8 * (j & 3))
	a = (a + Tail[0]) & MASK
	b = (b + Tail[1]) & MASK
	c = (c + Tail[2]) & MASK
	# Final
	c ^= b; c = (c - _Rot(b, 14)) & MASK
	a ^= c; a = (a - _Rot(c, 11)) & MASK
	b ^= a; b = (b - _Rot(a, 25)) & MASK
	c ^= b; c = (c - _Rot(b, 16)) & MASK
	a ^= c; a = (a - _Rot(c, 4)) & MASK
	b ^= a; b = (b - _Rot(a, 14)) & MASK
	c ^= b; c = (c - _Rot(b, 24)) & MASK
	return _ToInteger(c)


## The string comparer's GetHashCode: HashLittle over the UTF-16 code units.
static func StringHash(Value: String) -> int:
	return HashLittle(Value.to_utf16_buffer(), 0)


static func _ToInteger(x: int) -> int:
	return x - 0x100000000 if x >= 0x80000000 else x
