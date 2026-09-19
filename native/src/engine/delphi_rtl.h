#pragma once

// The Delphi RTL string / file-name functions (System.SysUtils) the ports need, with their Windows semantics: path
// delimiters are '\' and the drive delimiter ':' ('/' is an ordinary character).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>

namespace godot {

class DelphiRtl : public RefCounted {
	GDCLASS(DelphiRtl, RefCounted)

protected:
	static void _bind_methods();

public:
	// LastDelimiter(Delimiters, S): the 0-based index of the last char of S in Delimiters, or -1.
	static int64_t LastDelimiter(const String &p_delimiters, const String &p_s);
	// ExtractFilePath: up to and including the last '\' or ':'; '' without one.
	static String ExtractFilePath(const String &p_file_name);
	// ExtractFileName: after the last '\' or ':'.
	static String ExtractFileName(const String &p_file_name);
	// ChangeFileExt: replaces the extension (from the last '.' after the last delimiter) or appends Extension.
	static String ChangeFileExt(const String &p_file_name, const String &p_extension);
	// CompareText: case-insensitive for 'a'..'z' only; the difference of the first differing (upper-cased) chars, else
	// of the lengths.
	static int64_t CompareText(const String &p_s1, const String &p_s2);
	// SameText: CompareText = 0.
	static bool SameText(const String &p_s1, const String &p_s2);
	// StrToIntDef (TryStrToInt, i.e. Val): leading blanks, an optional sign, then decimal digits or '$' / '0x' hex
	// digits, nothing after them, within the 32-bit range; else Default.
	static int64_t StrToIntDef(const String &p_s, int64_t p_default);
};

} // namespace godot
