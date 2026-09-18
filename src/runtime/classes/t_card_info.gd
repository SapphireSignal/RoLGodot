class_name TCardInfo
extends TObject
## Port of TCardInfo (BaseConflict.Constants.Cards.pas:87, implementation :429-779): what a card is (UID, script
## file, skin, tech level, type, colors) at one league / level. TCardInfoManager makes them; scripts read Filename,
## League, Level and SkinID.
## Port: the stat functions read the original's global EntityDataCache; here the cache is per side (the global
## eventbus carries it), so they take it as their parameter. Name / ShortDescription / Description / SkillList /
## Skills / HasSkills / Keywords / HasKeywords are translation texts: they come with the localization (client UI).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

var FUID := ""
var FBaseUID := ""
var FFilename := ""
var FSkinID := ""
var FTechlevel := 0
var FCardType: int = C.ctDrop
var FCardColors: Array = []
var FLeague := 0
var FLevel := 0

var UID: String:
	get:
		return FUID
var BaseUID: String:
	get:
		return FBaseUID
var Filename: String:
	get:
		return FFilename
var SkinID: String:
	get:
		return FSkinID
var Techlevel: int:
	get:
		return FTechlevel
var CardType: int:
	get:
		return FCardType
var CardColors: Array:
	get:
		return FCardColors
var Level: int:
	get:
		return FLevel
var League: int:
	get:
		return FLeague


## Starts at MAX_LEAGUE / MAX_LEVEL.
func Create(CardType_: int = C.ctDrop, Colors: Array = [], Filename_: String = "", Techlevel_: int = 0) -> TCardInfo:
	FLeague = BC.MAX_LEAGUE
	FLevel = BC.MAX_LEVEL
	FCardType = CardType_
	FCardColors = DSet.Make(Colors)
	FFilename = Filename_
	FTechlevel = Techlevel_
	return self


func Clone(League_: int, Level_: int) -> TCardInfo:
	var Result := TCardInfo.new().Create(CardType, CardColors, Filename, Techlevel)
	Result.FLeague = League_
	Result.FLevel = Level_
	Result.FUID = UID
	Result.FBaseUID = BaseUID
	Result.FSkinID = SkinID
	return Result


func HasSkin() -> bool:
	return SkinID != ""


func SkinFileSuffix() -> String:
	return "_" + SkinID if HasSkin() else ""


# --- type ---

func IsSpell() -> bool:
	return CardType == C.ctSpell


func IsBuilding() -> bool:
	return CardType == C.ctBuilding


func IsSpawner() -> bool:
	return CardType == C.ctSpawner


func IsDrop() -> bool:
	return CardType == C.ctDrop


func IsLegendary(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upLegendary)


func IsEpic(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upEpic)


# --- cost ---

func GoldCost(Cache: TEntityDataCache) -> int:
	return L.Round(RParam.AsSingle(Cache.Read(Filename, League, Level, C.eiResourceCost, [], C.reGold)))


func WoodCost(Cache: TEntityDataCache) -> int:
	return L.Round(RParam.AsSingle(Cache.Read(Filename, League, Level, C.eiResourceCost, [], C.reWood)))


func MaxCost(Cache: TEntityDataCache) -> int:
	return L.Round(maxf(RParam.AsSingle(Cache.Read(Filename, League, Level, C.eiResourceCost, [], C.reGold)),
		RParam.AsSingle(Cache.Read(Filename, League, Level, C.eiResourceCost, [], C.reWood))))


func ChargeCount(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(Filename, League, Level, C.eiResourceCap, [], C.reCharge))


## A spell's charge cooldown sits in group 1, a unit card's in no group.
func ChargeCooldown(Cache: TEntityDataCache) -> int:
	if IsSpell():
		return RParam.AsInteger(Cache.Read(Filename, League, Level, C.eiCooldown, [1]))
	return RParam.AsInteger(Cache.Read(Filename, League, Level, C.eiCooldown, []))


# --- stats (of the unit a drop / spawner / building makes) ---

func AttackDamage(Cache: TEntityDataCache) -> float:
	return RParam.AsSingle(Cache.Read(UnitFilename(), League, Level, C.eiWelaDamage, [C.GROUP_MAINWEAPON]))


func AttackCooldown(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiCooldown, [C.GROUP_MAINWEAPON]))


func AttackRange(Cache: TEntityDataCache) -> float:
	return RParam.AsSingle(Cache.Read(UnitFilename(), League, Level, C.eiWelaRange, [C.GROUP_MAINWEAPON]))


## Damage per second of the main weapon; 0 without a cooldown.
func DPS(Cache: TEntityDataCache) -> float:
	var Result := float(RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiCooldown, [C.GROUP_MAINWEAPON])))
	if Result <= 0:
		return 0.0
	return RParam.ToSingle(RParam.AsSingle(Cache.Read(UnitFilename(), League, Level, C.eiWelaDamage,
		[C.GROUP_MAINWEAPON])) / RParam.ToSingle(Result / 1000.0))


func Health(Cache: TEntityDataCache) -> float:
	return RParam.AsSingle(Cache.Read(UnitFilename(), League, Level, C.eiResourceCap, [], C.reHealth))


func Energy(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiResourceBalance, [], C.reMana))


func EnergyCap(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiResourceCap, [], C.reMana))


func HasEnergy(Cache: TEntityDataCache) -> bool:
	return EnergyCap(Cache) > 0


## eiWelaCount of the drop / spawner group; 1 when unset.
func SquadSize(Cache: TEntityDataCache) -> int:
	var Value = Cache.Read(Filename, League, Level, C.eiWelaCount, [C.GROUP_DROP_SPAWNER])
	return 1 if Value == null else RParam.AsInteger(Value)


func IsRanged(Cache: TEntityDataCache) -> bool:
	return _MainWeaponHasDamageType(Cache, C.dtRanged)


func IsSiege(Cache: TEntityDataCache) -> bool:
	return _MainWeaponHasDamageType(Cache, C.dtSiege)


func IsSupporter(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSupporter)


func DamageType(Cache: TEntityDataCache) -> int:
	if IsSiege(Cache):
		return C.dtSiege
	if IsRanged(Cache):
		return C.dtRanged
	return C.dtMelee


func ArmorType(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiArmorType, []))


func AttackValue(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiCardStats, [], C.reMetaAttack))


func DefenseValue(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiCardStats, [], C.reMetaDefense))


func UtilityValue(Cache: TEntityDataCache) -> int:
	return RParam.AsInteger(Cache.Read(UnitFilename(), League, Level, C.eiCardStats, [], C.reMetaUtility))


# --- spell meta data ---

func SpellIsSingleTarget(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellSingle)


func SpellIsAreaTarget(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellArea)


func SpellIsCharmTarget(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellCharm)


func SpellIsAllyTarget(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellAlly)


func SpellIsEnemyTarget(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellEnemy)


func SpellHasTwoTargets(Cache: TEntityDataCache) -> bool:
	return _HasUnitProperty(Cache, C.upSpellDoubleArea)


# --- meta ---

## If the card is a spawner, drop or building, the spawned unit's file (path + card identifier), else the card's.
func UnitFilename() -> String:
	if CardType in [C.ctDrop, C.ctSpawner, C.ctBuilding]:
		return DelphiRtl.ExtractFilePath(Filename) + TCardInfoManager.ScriptFilenameToCardIdentifier(Filename)
	return Filename


func SkinnedUnitFilename() -> String:
	var Unit := UnitFilename()
	if Unit.contains("."):
		return Unit.replace(".", SkinFileSuffix() + ".")
	return Unit + SkinFileSuffix()


## Deck order: spawners last, then by tech level, spells after units, buildings after drops, then file name
## (case-insensitive), league, level; nil sorts before spawners and after the rest.
static func Compare(Left: TCardInfo, Right: TCardInfo) -> int:
	var Result := 0
	var Lc := Left
	var Rc := Right
	if Rc == null and Lc == null:
		return 0
	var Inverse := Rc != null and Lc == null
	if Inverse:
		var Swap := Lc
		Lc = Rc
		Rc = Swap
	if Lc != null:
		if Rc == null:
			Result = 1 if Lc.IsSpawner() else -1
		elif Lc.IsSpawner() and not Rc.IsSpawner():
			Result = 1
		elif not Lc.IsSpawner() and Rc.IsSpawner():
			Result = -1
		elif Lc.Techlevel != Rc.Techlevel:
			Result = Lc.Techlevel - Rc.Techlevel
		elif Lc.IsSpell() and not Rc.IsSpell():
			Result = 1
		elif not Lc.IsSpell() and Rc.IsSpell():
			Result = -1
		elif Lc.IsBuilding() and not Rc.IsBuilding():
			Result = 1
		elif not Lc.IsBuilding() and Rc.IsBuilding():
			Result = -1
		elif Lc.Filename != Rc.Filename:
			Result = DelphiRtl.CompareText(Lc.Filename, Rc.Filename)
		elif Lc.League != Rc.League:
			Result = Lc.League - Rc.League
		else:
			Result = Lc.Level - Rc.Level
	return -Result if Inverse else Result


func _HasUnitProperty(Cache: TEntityDataCache, Property: int) -> bool:
	return RParam.AsArray(Cache.Read(UnitFilename(), League, Level, C.eiUnitProperties, [])).has(Property)


func _MainWeaponHasDamageType(Cache: TEntityDataCache, DamageType_: int) -> bool:
	return RParam.AsArray(Cache.Read(UnitFilename(), League, Level, C.eiDamageType, [C.GROUP_MAINWEAPON])).has(DamageType_)
