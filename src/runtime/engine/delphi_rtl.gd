class_name DelphiRtl
extends RefCounted
## The Delphi RTL string / file-name functions (System.SysUtils) the ports need, with their Windows semantics:
## path delimiters are '\' and the drive delimiter ':' ('/' is an ordinary character).

const PATH_DELIMITERS = "\\:"


## LastDelimiter(Delimiters, S): the 0-based index of the last char of S in Delimiters, or -1.
static func LastDelimiter(Delimiters: String, S: String) -> int:
	for i in range(S.length() - 1, -1, -1):
		if Delimiters.contains(S[i]):
			return i
	return -1


## ExtractFilePath: up to and including the last '\' or ':'; '' without one.
static func ExtractFilePath(FileName: String) -> String:
	return FileName.substr(0, LastDelimiter(PATH_DELIMITERS, FileName) + 1)


## ExtractFileName: after the last '\' or ':'.
static func ExtractFileName(FileName: String) -> String:
	return FileName.substr(LastDelimiter(PATH_DELIMITERS, FileName) + 1)


## ChangeFileExt: replaces the extension (from the last '.' after the last delimiter) or appends Extension.
static func ChangeFileExt(FileName: String, Extension: String) -> String:
	var i := LastDelimiter("." + PATH_DELIMITERS, FileName)
	if i < 0 or FileName[i] != ".":
		i = FileName.length()
	return FileName.substr(0, i) + Extension


## CompareText: case-insensitive for 'a'..'z' only; the difference of the first differing (upper-cased) chars,
## else of the lengths.
static func CompareText(S1: String, S2: String) -> int:
	var Count := mini(S1.length(), S2.length())
	for i in range(Count):
		var a := _UpperAscii(S1.unicode_at(i))
		var b := _UpperAscii(S2.unicode_at(i))
		if a != b:
			return a - b
	return S1.length() - S2.length()


## SameText: CompareText = 0.
static func SameText(S1: String, S2: String) -> bool:
	return CompareText(S1, S2) == 0


static func _UpperAscii(Code: int) -> int:
	return Code - 32 if Code >= 97 and Code <= 122 else Code
