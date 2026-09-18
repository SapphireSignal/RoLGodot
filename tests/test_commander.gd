extends "res://tests/test_case.gd"
## The commander family: the card database (TCardInfo, TCardInfoManager: BaseConflict.Constants.Cards.pas),
## TCommanderAbilityComponent (...Shared.pas:236), TCommanderAbility (GameServer/...Server.pas:473),
## TCommanderComponent (...Client.pas:199), plus DelphiHash / DelphiRtl.
## Real data: the card list (src/content/cards.json) and the server scripts Commander\CommanderMethods (AddDrop,
## AddBuilding, AddSpawner) and Spells\Black\Freeze.sps (AddSpell). VoidSkeletonDrop at league 4, level 2: 100.0
## gold, 4 charges, cooldown 27250 (see test_entity_data_cache.gd); its CreateData sets eiWelaCount [0] = 2.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")

const ARCHER_SPAWNER = "30b4f36d-03d4-413c-8e9c-dc9f70346c15"
const ARCHER_SPAWNER_ROFL = "417f384a-7eb4-49d2-ad88-5b3904a01398"
const VOID_SKELETON_DROP = "bb588865-ea26-4cec-930a-7753ca688afe"
const GATLING_TURRET_BUILDING = "d03f561e-257e-4ed0-8b60-3b75b93f04f8"
const FREEZE = "b5c11a5b-3f35-465a-a625-c6d97a27586c"
const SAPLING_CHARGE = "6cccc3b4-4a60-4da9-bb06-04576bd9c2a9"

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent


class FakeGame:
	extends RefCounted
	var InGameStatus := 0  # gsLoading
	var EntityManager = null
	var Statistics := TGameStatisticManager.new().Create()
	var Commanders: Array = []

	func IsShuttingDown() -> bool:
		return false

	func IsSandbox() -> bool:
		return false


## Logs eiUseAbility in its group.
class UseProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnUseAbility", C.eiUseAbility, C.epFirst, C.etTrigger))

	func OnUseAbility(Targets) -> bool:
		Log.append([ComponentGroup, Targets])
		return true


func _setup(side: int = C.nsServer) -> void:
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = side
	_bus.Game = FakeGame.new()
	_bus.EntityDataCache = TEntityDataCache.new().Create(_bus)
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager


func after_each() -> void:
	if _game_entity != null:
		_game_entity.Free()
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	super()


func _commander() -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiOwnerCommander, [], e.ID)
	e.Blackboard.SetValue(C.eiTeamID, [], 1)
	e.Deploy()
	return e


func _cards() -> TCardInfoManager:
	return TCardInfoManager.Instance()


# --- Delphi helpers ---

## lookup3.c's published values (driver5); Delphi returns them as signed Integers.
func test_hash_vectors() -> void:
	check_eq(DelphiHash.HashLittle(PackedByteArray(), 0), 0xDEADBEEF - 0x100000000, "empty, seed 0")
	var four := "Four score and seven years ago".to_ascii_buffer()
	check_eq(DelphiHash.HashLittle(four, 0), 0x17770551, "30 bytes, seed 0")
	check_eq(DelphiHash.HashLittle(four, 1), 0xCD628161 - 0x100000000, "30 bytes, seed 1")
	check_eq(DelphiHash.StringHash("ab"), DelphiHash.HashLittle(PackedByteArray([97, 0, 98, 0]), 0), "UTF-16 code units")


func test_rtl_file_names() -> void:
	check_eq(DelphiRtl.ExtractFilePath("Units\\White\\ArcherSpawner"), "Units\\White\\", "path with the delimiter")
	check_eq(DelphiRtl.ExtractFilePath("Archer"), "", "no path")
	check_eq(DelphiRtl.ExtractFileName("Spells\\Black\\Freeze.sps"), "Freeze.sps", "file name")
	check_eq(DelphiRtl.ChangeFileExt("Freeze.sps", ""), "Freeze", "extension dropped")
	check_eq(DelphiRtl.ChangeFileExt("a.b\\Freeze", ".x"), "a.b\\Freeze.x", "a dot in the path is no extension")
	check(DelphiRtl.CompareText("abc", "ABD") < 0, "case-insensitive order")
	check_eq(DelphiRtl.CompareText("Units\\a", "UNITS\\A"), 0, "equal ignoring case")
	check(DelphiRtl.CompareText("ab", "abc") < 0, "shorter first")
	check(DelphiRtl.CompareText("_", "a") > 0, "'a' compares as 'A' (65) below '_' (95)")


# --- the card database ---

func test_card_list() -> void:
	var uids := _cards().GetAllCardUIDs()
	check_eq(uids.size(), 228, "161 cards + 67 skins")
	var unique := {}
	for uid in uids:
		unique[uid] = true
	check_eq(unique.size(), 228, "no duplicate UIDs")
	check(unique.has(FREEZE) and unique.has(ARCHER_SPAWNER_ROFL), "cards and skins listed")


func test_resolve_and_cache() -> void:
	var info := _cards().ResolveCardUID(ARCHER_SPAWNER, 3, 2)
	check(info != null, "known card")
	if info == null:
		return
	check_eq(info.Filename, "Units\\White\\ArcherSpawner", "file name")
	check_eq(info.CardType, C.ctSpawner, "spawner")
	check_eq(info.CardColors, [C.ecWhite], "white")
	check_eq(info.Techlevel, 1, "tech level")
	check_eq([info.League, info.Level], [3, 2], "league and level of the resolve")
	check_eq(info.UID, ARCHER_SPAWNER, "UID")
	check_eq(info.BaseUID, ARCHER_SPAWNER, "an unskinned card is its own base")
	check_eq(info.SkinID, C.SKIN_GROUP_DEFAULT, "a card with skins is the default skin")
	check(_cards().ResolveCardUID(ARCHER_SPAWNER, 3, 2) == info, "one instance per league / level")
	check(_cards().ResolveCardUID(ARCHER_SPAWNER.replace("-", "_"), 3, 2) == info, "'_' reads as '-'")
	check(_cards().ResolveCardUID(ARCHER_SPAWNER, 1, 1) != info, "another level: another instance")
	check_eq(_cards().ResolveCardUID("00000000-0000-0000-0000-000000000000", 1, 1), null, "unknown card: nil")
	var plain := _cards().ResolveCardUID(FREEZE, 1, 1)
	check_eq(plain.SkinID, "", "no skins: no skin id")
	check(not plain.HasSkin(), "no skin")
	check_eq(_cards().ResolveCardUID(SAPLING_CHARGE, 1, 1).SkinID, C.SKIN_GROUP_DEFAULT, "AddCard with a skin id")


func test_skins() -> void:
	var skin := _cards().ResolveCardUID(ARCHER_SPAWNER_ROFL, 2, 1)
	check_eq(skin.SkinID, C.SKIN_GROUP_ROFL, "skin id")
	check_eq(skin.BaseUID, ARCHER_SPAWNER, "base UID")
	check_eq(skin.UID, ARCHER_SPAWNER_ROFL, "own UID")
	check_eq(skin.Filename, "Units\\White\\ArcherSpawner", "the base card's script")
	check_eq(skin.SkinFileSuffix(), "_rofl", "suffix")
	check_eq(skin.SkinnedUnitFilename(), "Units\\White\\Archer_rofl", "skinned unit")
	var found := _cards().ScriptFilenameToCardInfo("units\\white\\archerspawner", "ROFL", 1, 1)
	check(found != null and found.UID == ARCHER_SPAWNER_ROFL, "by script file and skin, ignoring case")
	check_eq(_cards().ScriptFilenameToCardInfo("Units\\White\\ArcherSpawner", "", 1, 1), null,
		"the base card is the 'default' skin now")
	check_eq(_cards().ScriptFilenameToCardInfo("Spells\\Black\\Freeze.sps", "", 4, 3).UID, FREEZE, "a spell")


func test_file_name_helpers() -> void:
	check_eq(TCardInfoManager.ScriptFilenameToCardIdentifier("Units\\White\\ArcherSpawner"), "Archer", "spawner")
	check_eq(TCardInfoManager.ScriptFilenameToCardIdentifier("Spells\\Black\\Freeze.sps"), "Freeze", "spell")
	check_eq(TCardInfoManager.ScriptFilenameToCardIdentifier("Units\\Blue\\GatlingTurretBuilding.ets"), "GatlingTurret",
		"building")
	check_eq(TCardInfoManager.ScriptFilenameToCardIdentifier("x\\HealingSpell"), "Healing", "Spell dropped")
	check_eq(TCardInfoManager.EntityColorsToFolder([C.ecWhite, C.ecBlack]), "BlackWhite\\", "folder order")
	check_eq(TCardInfoManager.EntityColorsToFolder([]), "\\", "no colors")
	check_eq(_cards().ResolveCardUID(VOID_SKELETON_DROP, 1, 1).UnitFilename(), "Units\\Black\\VoidSkeleton", "drop unit")
	check_eq(_cards().ResolveCardUID(FREEZE, 1, 1).UnitFilename(), "Spells\\Black\\Freeze.sps", "a spell is its unit")
	check_eq(_cards().ResolveCardUID(SAPLING_CHARGE, 1, 1).SkinnedUnitFilename(), "Spells\\Green\\SaplingCharge_default.sps",
		"skin suffix before the extension")


func test_compare() -> void:
	var spawner := _cards().ResolveCardUID(ARCHER_SPAWNER, 1, 1)
	var drop := _cards().ResolveCardUID(VOID_SKELETON_DROP, 1, 1)
	var building := _cards().ResolveCardUID(GATLING_TURRET_BUILDING, 1, 1)
	var spell := _cards().ResolveCardUID(FREEZE, 1, 1)
	check(TCardInfo.Compare(spawner, drop) > 0, "spawners last")
	check(TCardInfo.Compare(drop, building) < 0, "drop (tech 1) before building (tech 1)")
	check(TCardInfo.Compare(spell, drop) > 0, "tech 2 spell after tech 1 drop")
	check(TCardInfo.Compare(drop, _cards().ResolveCardUID(VOID_SKELETON_DROP, 2, 1)) < 0, "lower league first")
	check(TCardInfo.Compare(drop, _cards().ResolveCardUID(VOID_SKELETON_DROP, 1, 2)) < 0, "lower level first")
	check(TCardInfo.Compare(null, spawner) < 0, "nil before a spawner")
	check(TCardInfo.Compare(null, drop) > 0, "nil after the rest")
	check_eq(TCardInfo.Compare(null, null), 0, "nil = nil")


func test_card_stats() -> void:
	_setup()
	var cache: TEntityDataCache = _bus.EntityDataCache
	var drop := _cards().ResolveCardUID(VOID_SKELETON_DROP, 4, 2)
	check_eq(drop.GoldCost(cache), 100, "gold cost")
	check_eq(drop.WoodCost(cache), 0, "no wood")
	check_eq(drop.MaxCost(cache), 100, "max cost")
	check_eq(drop.ChargeCount(cache), 4, "charges")
	check_eq(drop.ChargeCooldown(cache), 27250, "charge cooldown")
	check_eq(drop.SquadSize(cache), 2, "squad size")
	check_eq(TEntity.LastScriptError, "", "no script error")


# --- commander abilities ---

func _card_group(commander: TEntity, pattern: String) -> int:
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			return g
	return -1


func _abilities(commander: TEntity) -> Array:
	return RParam.AsArray(commander.Eventbus.Read(C.eiEnumerateCommanderAbilities, []))


func test_commander_ability_component_applies_cards() -> void:
	_setup()
	var commander := _commander()
	TCommanderAbilityComponent.new().CreateGroupedSlot(commander, [], RCommanderCard.Create(VOID_SKELETON_DROP, 4, 2), 0)
	TCommanderAbilityComponent.new().CreateGroupedSlot(commander, [], RCommanderCard.Create(GATLING_TURRET_BUILDING, 1, 1), 1)
	TCommanderAbilityComponent.new().CreateGroupedSlot(commander, [], RCommanderCard.Create(ARCHER_SPAWNER, 1, 1), 2)
	TCommanderAbilityComponent.new().CreateGroupedSlot(commander, [], RCommanderCard.Create(FREEZE, 1, 1), 3)
	check_eq(TEntity.LastScriptError, "", "no script error")
	var drop_group := _card_group(commander, "Units\\Black\\VoidSkeletonDrop")
	check(drop_group >= 0, "AddDrop ran")
	check_eq(commander.Blackboard.GetValue(C.eiAbilityTargetType, [drop_group]), C.ctCoordinate, "a drop targets a spot")
	var building_group := _card_group(commander, "Units\\Blue\\GatlingTurretBuilding")
	check(building_group >= 0, "AddBuilding ran")
	var spawner_group := _card_group(commander, "Units\\White\\ArcherSpawner")
	check(spawner_group >= 0, "AddSpawner ran")
	check_eq(commander.Blackboard.GetValue(C.eiAbilityTargetType, [spawner_group]), C.ctBuildZone, "a spawner targets a field")
	var abilities := _abilities(commander)
	var files: Array = []
	for ability: TCommanderAbility in abilities:
		files.append(ability.GetCardInfo.Filename)
	check_eq(files, ["Units\\Black\\VoidSkeletonDrop", "Units\\Blue\\GatlingTurretBuilding", "Units\\White\\ArcherSpawner",
		"Spells\\Black\\Freeze.sps"], "one ability per card, in deck order")
	var drop: TCommanderAbility = abilities[0]
	check_eq(drop.ComponentGroup, [drop_group], "the ability sits in the card's group")
	check_eq(drop.GetCardInfo.League, 4, "card league")
	check_eq(drop.MaxCharges(), 4, "charge cap of the card")
	check_eq(drop.CurrentCharges(), 4, "charges")
	check_eq(drop.GetChargeGroup.size(), 1, "one charge group")
	check(not drop.GetChargeGroup.has(drop_group), "the charge group is its own")
	check_eq(drop.ModeCount(), 0, "single mode")
	var freeze: TCommanderAbility = abilities[3]
	check_eq(commander.Balance(C.reCardLeague, freeze.ComponentGroup), 1, "the spell's league in its group")


## Before the game starts no card is ready: the brain refuses, so a use stops before the statistics count it.
func test_commander_ability_not_ready_before_game_start() -> void:
	_setup()
	var commander := _commander()
	TCommanderAbilityComponent.new().CreateGroupedSlot(commander, [], RCommanderCard.Create(VOID_SKELETON_DROP, 4, 2), 0)
	var drop: TCommanderAbility = _abilities(commander)[0]
	check(not drop.IsReady(), "not ready while loading")
	var targets := [RCommanderAbilityTarget.Create(Vector2(0, 0))]
	check(not drop.CanUseAbility(targets), "cannot be used")
	drop.UseAbility(targets)
	check_eq(_bus.Game.Statistics.GetCount(commander.ID, "global_drops"), 0, "not played")
	check_eq(TEntity.LastScriptError, "", "no script error")


func test_commander_ability_modes() -> void:
	_setup()
	var commander := _commander()
	var ability: TCommanderAbility = TCommanderAbility.new().CreateGrouped(commander, [5]).IsMultiMode([7, 9])
	var in_card := UseProbe.new().CreateGrouped(commander, [5])
	var in_mode := UseProbe.new().CreateGrouped(commander, [9])
	check_eq(ability.ModeCount(), 1, "Min(1, 2) = 1")
	ability.UseAbility([], 1)
	check_eq(in_mode.Log.size(), 1, "mode 1: its group")
	check_eq(in_card.Log.size(), 0, "not the card's group")
	ability.UseAbility([], 2)
	check_eq(in_card.Log.size(), 1, "no such mode: the card's group")
	ability.UseAbility([RCommanderAbilityTarget.CreateTargetLess()])
	check_eq(in_mode.Log.size(), 1, "mode 0 is group 7")
	var plain: TCommanderAbility = TCommanderAbility.new().CreateGrouped(commander, [6])
	var in_plain := UseProbe.new().CreateGrouped(commander, [6])
	var targets := [RCommanderAbilityTarget.CreateTargetLess()]
	plain.UseAbility(targets)
	check_eq(in_plain.Log.size(), 1, "no modes: the card's group")
	check(not is_same(in_plain.Log[0][1], targets) and in_plain.Log[0][1] == targets, "the targets travel as a copy")


func test_commander_component_enumerates() -> void:
	_setup(C.nsClient)
	var a := _commander()
	var b := _commander()
	TCommanderComponent.new().Create(a)
	TCommanderComponent.new().Create(b)
	var list := RParam.AsArray(_bus.Read(C.eiEnumerateCommanders, []))
	check_eq(list.size(), 2, "both commanders")
	check(list.has(a) and list.has(b), "the commander entities")
