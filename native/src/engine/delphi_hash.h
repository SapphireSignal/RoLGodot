#pragma once

// Delphi's default hash functions (System.Hash / System.Generics.Defaults) for DelphiDictionary keys.
// THashBobJenkins.HashLittle is Bob Jenkins' lookup3 hashlittle() (a = b = c = $DEADBEEF + Len + InitVal); the string
// comparer hashes the UTF-16 code units (little endian, 2 bytes each) with InitVal 0.
// Assumption: the original's RTL is not in the snapshot; its string comparer is taken as Bob Jenkins (Delphi 10.x;
// Delphi 11+ uses FNV-1a). Results are Delphi Integers (signed 32 bit).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstddef>
#include <cstdint>

namespace godot {

class DelphiHash : public RefCounted {
	GDCLASS(DelphiHash, RefCounted)

protected:
	static void _bind_methods();

public:
	static int32_t HashLittleBytes(const uint8_t *p_data, size_t p_len, uint32_t p_init_val);
	// THashBobJenkins.HashLittle(Data, Len, InitVal)
	static int64_t HashLittle(const PackedByteArray &p_data, int64_t p_init_val = 0);
	// The string comparer's GetHashCode: HashLittle over the UTF-16 code units.
	static int64_t StringHash(const String &p_value);
};

} // namespace godot
