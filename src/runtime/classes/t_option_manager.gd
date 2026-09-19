class_name TOptionManager
extends RefCounted
## Part of TOptionManager (BaseConflict.Settings.Client.pas:360, the client's Settings): options as strings with
## the original's defaults (GetDefaultOption, :476) and the typed getters. Only the options ported code reads so
## far are listed; the settings file, option events and the rest of the defaults come with the settings / GUI port.

const C = preload("res://src/runtime/dws/dws_const.gd")

## GetDefaultOption values of the options in use.
const DEFAULTS := {
	C.coEngineGlobalShadingReduction: "0.5",
	C.coGameplayFixedTeamColors: "True",
	C.coGameplayShowEffectRadius: "True",
	C.coGameplayShowTechnicalPanel: "True",
	C.coGraphicsPostEffectSSAO: "False",
	C.coGraphicsPostEffectToon: "True",
	C.coGraphicsPostEffectGlow: "True",
	C.coGraphicsPostEffectFXAA: "True",
	C.coGraphicsPostEffectUnsharpMasking: "True",
	C.coGraphicsPostEffectDistortion: "True",
}

static var FOptions := {}


static func GetStringOption(Option: int) -> String:
	if FOptions.has(Option):
		return FOptions[Option]
	if not DEFAULTS.has(Option):
		push_error("TOptionManager: option %d has no ported default yet" % Option)
		return ""
	return DEFAULTS[Option]


static func SetOption(Option: int, Value) -> void:
	FOptions[Option] = str(Value)


## Port: back to the defaults (tests).
static func ResetOptions() -> void:
	FOptions.clear()


## StrToBool or 'true' (any case).
static func GetBooleanOption(Option: int) -> bool:
	var s := GetStringOption(Option)
	if s.is_valid_int():
		return int(s) != 0
	return s.to_lower() == "true"


static func GetSingleOption(Option: int) -> float:
	var s := GetStringOption(Option).replace(",", ".")
	if s.is_valid_float():
		return RParam.ToSingle(float(s))
	var d := String(DEFAULTS.get(Option, "")).replace(",", ".")
	return RParam.ToSingle(float(d)) if d.is_valid_float() else 0.0
