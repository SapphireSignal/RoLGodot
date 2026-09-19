#include "engine/delphi_rtl.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

static const char *PATH_DELIMITERS = "\\:";

void DelphiRtl::_bind_methods() {
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("LastDelimiter", "Delimiters", "S"), &DelphiRtl::LastDelimiter);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("ExtractFilePath", "FileName"), &DelphiRtl::ExtractFilePath);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("ExtractFileName", "FileName"), &DelphiRtl::ExtractFileName);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("ChangeFileExt", "FileName", "Extension"), &DelphiRtl::ChangeFileExt);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("CompareText", "S1", "S2"), &DelphiRtl::CompareText);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("SameText", "S1", "S2"), &DelphiRtl::SameText);
	ClassDB::bind_static_method("DelphiRtl", D_METHOD("StrToIntDef", "S", "Default"), &DelphiRtl::StrToIntDef);
}

int64_t DelphiRtl::LastDelimiter(const String &p_delimiters, const String &p_s) {
	for (int64_t i = p_s.length() - 1; i >= 0; i--) {
		if (p_delimiters.contains(String::chr(p_s[i]))) {
			return i;
		}
	}
	return -1;
}

String DelphiRtl::ExtractFilePath(const String &p_file_name) {
	return p_file_name.substr(0, LastDelimiter(PATH_DELIMITERS, p_file_name) + 1);
}

String DelphiRtl::ExtractFileName(const String &p_file_name) {
	return p_file_name.substr(LastDelimiter(PATH_DELIMITERS, p_file_name) + 1);
}

String DelphiRtl::ChangeFileExt(const String &p_file_name, const String &p_extension) {
	int64_t i = LastDelimiter(String(".") + PATH_DELIMITERS, p_file_name);
	if (i < 0 || p_file_name[i] != '.') {
		i = p_file_name.length();
	}
	return p_file_name.substr(0, i) + p_extension;
}

static inline int64_t upper_ascii(int64_t p_code) {
	return (p_code >= 'a' && p_code <= 'z') ? p_code - 32 : p_code;
}

int64_t DelphiRtl::CompareText(const String &p_s1, const String &p_s2) {
	const int64_t count = p_s1.length() < p_s2.length() ? p_s1.length() : p_s2.length();
	for (int64_t i = 0; i < count; i++) {
		const int64_t a = upper_ascii(p_s1.unicode_at(i));
		const int64_t b = upper_ascii(p_s2.unicode_at(i));
		if (a != b) {
			return a - b;
		}
	}
	return p_s1.length() - p_s2.length();
}

bool DelphiRtl::SameText(const String &p_s1, const String &p_s2) {
	return CompareText(p_s1, p_s2) == 0;
}

int64_t DelphiRtl::StrToIntDef(const String &p_s, int64_t p_default) {
	const int64_t len = p_s.length();
	int64_t i = 0;
	while (i < len && p_s[i] == ' ') {
		i++;
	}
	bool negative = false;
	if (i < len && (p_s[i] == '+' || p_s[i] == '-')) {
		negative = p_s[i] == '-';
		i++;
	}
	int64_t base = 10;
	if (i < len && p_s[i] == '$') {
		base = 16;
		i++;
	} else if (i + 1 < len && p_s[i] == '0' && (p_s[i + 1] == 'x' || p_s[i + 1] == 'X')) {
		base = 16;
		i += 2;
	}
	if (i >= len) {
		return p_default;
	}
	const int64_t limit = base == 16 ? 0xFFFFFFFFLL : (negative ? 0x80000000LL : 0x7FFFFFFFLL);
	int64_t value = 0;
	while (i < len) {
		const char32_t c = p_s[i];
		int64_t digit = -1;
		if (c >= '0' && c <= '9') {
			digit = c - '0';
		} else if (c >= 'A' && c <= 'F') {
			digit = c - 'A' + 10;
		} else if (c >= 'a' && c <= 'f') {
			digit = c - 'a' + 10;
		}
		if (digit < 0 || digit >= base) {
			return p_default;
		}
		value = value * base + digit;
		if (value > limit) {
			return p_default;
		}
		i++;
	}
	// hex literals wrap into the signed range
	if (value > 0x7FFFFFFFLL && base == 16) {
		value -= 0x100000000LL;
	}
	return negative ? -value : value;
}

} // namespace godot
