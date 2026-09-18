extends "res://tests/test_case.gd"
## Transpiled scripts (src/content/scripts) and their runtime library. Expected values are derived from the
## original sources named in each test.

const L = preload("res://src/runtime/dws/dws_lib.gd")
const C = preload("res://src/runtime/dws/dws_const.gd")
const INDEX = preload("res://src/content/scripts/script_index.gd")
const FREEZE_SERVER = "res://src/content/scripts/server/Spells/Black/Freeze.sps.gd"


func test_index_covers_both_sides() -> void:
	check_eq(INDEX.CLIENT.size(), 500, "client scripts")
	check_eq(INDEX.SERVER.size(), 500, "server scripts")
	check_eq(INDEX.SERVER.get("spells\\black\\freeze.sps"), FREEZE_SERVER, "lower-case lookup")


func test_card_template_functions() -> void:
	# HelperScripts/CardTemplate.dws, included by Freeze.sps through SpellTemplate.dws
	var script = load(FREEZE_SERVER).new()
	# ii(table, League 1, Level 1) = 37000; tier 2: Result * 3 div 2
	check_eq(script.GetCardBaseChargeCooldown(2, 1, 1, false, false, false), 55500, "tier 2 cooldown")
	# legendary: * 5 div 2 (integer division truncates)
	check_eq(script.GetCardBaseChargeCooldown(1, 5, 5, true, false, false), 55000, "legendary cooldown")
	# 100 + 100 (tier 3) + 100 (legendary) - 20 (spell)
	check_eq(script.GetCardBaseCost(3, 1, 1, true, true, false), 280.0, "tier 3 legendary spell cost")
	# (100 + 50) * i([8, 10, 12], 2)
	check_eq(script.GetCardBaseCost(2, 1, 1, false, false, true), 1500.0, "tier 2 spawner cost")


func test_original_compile_error_is_kept() -> void:
	# AI/MegaRootDude.dws assigns the undeclared ArcherDrop: the original server cannot compile it
	var server = load(INDEX.SERVER["ai\\megarootdude.dws"])
	check(server.get_script_constant_map().has("ORIGINAL_COMPILE_ERROR"), "server side carries the error")
	var client = load(INDEX.CLIENT["ai\\megarootdude.dws"])
	check(not client.get_script_constant_map().has("ORIGINAL_COMPILE_ERROR"), "client side compiles (all SERVER)")


func test_constants() -> void:
	# BaseConflict.Constants.pas: GROUP_SOUL = 11; EnumDamageType: dtCharge is the 17th value
	check_eq(C.GROUP_SOUL, 11, "GROUP_SOUL")
	check_eq(C.dtCharge, 16, "dtCharge")
	check_eq(C.ZONE_WALK, "Walkzone", "ZONE_WALK")


func test_lib_math_dws() -> void:
	check_eq(L.i([8, 10, 12], 3), 12, "i is 1-based")
	check_eq(L.ii([[1, 2], [3, 4]], 2, 1), 3, "ii is 1-based")
	# ff: arr[Index][0] + (arr[Index][1] - arr[Index][0]) * ((Index2 - 1) / 4)
	check_eq(L.ff([[10.0, 20.0]], 1, 3), 15.0, "ff interpolates by level")
	check_eq(L.RVariedSingle_Create(0.3, 0.05).Mean, 0.3, "RVariedSingle mean")


func test_lib_builtins() -> void:
	check_eq(L.Div(7, 2), 3, "div")
	check_eq(L.Div(-7, 2), -3, "div truncates toward zero")
	check_eq(L.Round(2.5), 2, "Round half to even (down)")
	check_eq(L.Round(3.5), 4, "Round half to even (up)")
	check_eq(L.Round(-2.5), -2, "Round negative half")
	check_eq(L.Round(2.6), 3, "Round up")
