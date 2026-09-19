#include "engine/delphi_hash.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void DelphiHash::_bind_methods() {
	ClassDB::bind_static_method("DelphiHash", D_METHOD("HashLittle", "Data", "InitVal"), &DelphiHash::HashLittle, DEFVAL(0));
	ClassDB::bind_static_method("DelphiHash", D_METHOD("StringHash", "Value"), &DelphiHash::StringHash);
}

static inline uint32_t rot(uint32_t p_x, int p_k) {
	return (p_x << p_k) | (p_x >> (32 - p_k));
}

static inline uint32_t read_u32(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}

int32_t DelphiHash::HashLittleBytes(const uint8_t *p_data, size_t p_len, uint32_t p_init_val) {
	uint32_t a = 0xDEADBEEFu + uint32_t(p_len) + p_init_val;
	uint32_t b = a;
	uint32_t c = a;
	size_t len = p_len;
	const uint8_t *k = p_data;
	while (len > 12) {
		a += read_u32(k);
		b += read_u32(k + 4);
		c += read_u32(k + 8);
		// Mix
		a -= c; a ^= rot(c, 4); c += b;
		b -= a; b ^= rot(a, 6); a += c;
		c -= b; c ^= rot(b, 8); b += a;
		a -= c; a ^= rot(c, 16); c += b;
		b -= a; b ^= rot(a, 19); a += c;
		c -= b; c ^= rot(b, 4); b += a;
		len -= 12;
		k += 12;
	}
	if (len == 0) {
		return int32_t(c);
	}
	// the tail: the last 1..12 bytes as little-endian words, missing bytes zero
	uint32_t tail[3] = { 0, 0, 0 };
	for (size_t j = 0; j < len; j++) {
		tail[j >> 2] |= uint32_t(k[j]) << (8 * (j & 3));
	}
	a += tail[0];
	b += tail[1];
	c += tail[2];
	// Final
	c ^= b; c -= rot(b, 14);
	a ^= c; a -= rot(c, 11);
	b ^= a; b -= rot(a, 25);
	c ^= b; c -= rot(b, 16);
	a ^= c; a -= rot(c, 4);
	b ^= a; b -= rot(a, 14);
	c ^= b; c -= rot(b, 24);
	return int32_t(c);
}

int64_t DelphiHash::HashLittle(const PackedByteArray &p_data, int64_t p_init_val) {
	return HashLittleBytes(p_data.ptr(), size_t(p_data.size()), uint32_t(p_init_val));
}

int64_t DelphiHash::StringHash(const String &p_value) {
	const Char16String utf16 = p_value.utf16();
	// length() excludes the terminating zero; the code units are little endian in memory on x86
	return HashLittleBytes(reinterpret_cast<const uint8_t *>(utf16.get_data()), size_t(utf16.length()) * 2, 0);
}

} // namespace godot
