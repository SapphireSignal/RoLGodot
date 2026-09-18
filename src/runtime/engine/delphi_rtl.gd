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


## StrToIntDef (TryStrToInt, i.e. Val): leading blanks, an optional sign, then decimal digits or '$' / '0x' hex
## digits, nothing after them, within the 32-bit range; else Default.
static func StrToIntDef(S: String, Default: int) -> int:
	var i := 0
	while i < S.length() and S[i] == " ":
		i += 1
	var Negative := false
	if i < S.length() and (S[i] == "+" or S[i] == "-"):
		Negative = S[i] == "-"
		i += 1
	var Base := 10
	if i < S.length() and S[i] == "$":
		Base = 16
		i += 1
	elif i + 1 < S.length() and S[i] == "0" and (S[i + 1] == "x" or S[i + 1] == "X"):
		Base = 16
		i += 2
	if i >= S.length():
		return Default
	var Limit := 0xFFFFFFFF if Base == 16 else (0x80000000 if Negative else 0x7FFFFFFF)
	var Value := 0
	while i < S.length():
		var Digit := "0123456789ABCDEF".find(S[i].to_upper())
		if Digit < 0 or Digit >= Base:
			return Default
		Value = Value * Base + Digit
		if Value > Limit:
			return Default
		i += 1
	# hex literals wrap into the signed range
	if Value > 0x7FFFFFFF and Base == 16:
		Value -= 0x100000000
	return -Value if Negative else Value


static func _UpperAscii(Code: int) -> int:
	return Code - 32 if Code >= 97 and Code <= 122 else Code
