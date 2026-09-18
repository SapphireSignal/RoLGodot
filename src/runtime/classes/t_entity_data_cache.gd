class_name TEntityDataCache
extends TObject
## Port of TEntityDataCache (BaseConflict.Classes.Shared.pas:27, implementation :465). One data entity per
## (script file, league, level), built on first use with the script's CreateData (spells, '.sps': a bare entity
## with card level/league in group 0 and the spell's CreateData(Entity, 0, 1)), and a cache of the values read.
## Read caches every result, empty ones too, until ByPassCache; for spells every group except [1] reads [0].
## Port: the original's per-game-thread global (the client's is per process); here the global eventbus carries it
## (TEventbus.EntityDataCache, set by the game, freed with the bus). Data entities are never deployed.

const C = preload("res://src/runtime/dws/dws_const.gd")
const FILE_EXTENSION_SPELL = ".sps"  # BaseConflict.Constants.Cards.pas:211


class TEntityWrapper:
	extends RefCounted
	var DataEntity: TEntity = null
	var IsSpell := false
	## [Event, ComponentGroup, Index] -> RParam
	var CachedValues := {}


var FGlobalEventbus: TEventbus = null
## "Scriptfile|League|Level" -> TEntityWrapper
var FCache := {}


func Create(GlobalEventbus = null) -> TEntityDataCache:
	FGlobalEventbus = GlobalEventbus
	return self


func Destroy() -> void:
	for Wrapper in FCache.values():
		if Wrapper.DataEntity != null:
			Wrapper.DataEntity.Free()
	FCache.clear()
	FGlobalEventbus = null
	super()


## Returns the cached entity. ATTENTION: Do not modify this in any kind or free it. Null if the script failed.
func GetEntity(Scriptfile: String, League: int, Level: int) -> TEntity:
	return GetEntityCache(Scriptfile, League, Level).DataEntity


func GetEntityCache(Scriptfile: String, League: int, Level: int) -> TEntityWrapper:
	var Key := "%s|%d|%d" % [Scriptfile, League, Level]
	if FCache.has(Key):
		return FCache[Key]
	var Result := TEntityWrapper.new()
	if Scriptfile.contains(FILE_EXTENSION_SPELL):
		Result.DataEntity = TEntity.new().Create(FGlobalEventbus)
		Result.DataEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [0], C.reCardLevel, Level)
		Result.DataEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [0], C.reCardLeague, League)
		Result.IsSpell = true
		Result.DataEntity.ApplyScript(Scriptfile, "CreateData", [Result.DataEntity, 0, 1])
	else:
		var Init := func(Entity: TEntity) -> void:
			Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, Level)
			Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, League)
		Result.DataEntity = TEntity.CreateDataFromScript(Scriptfile, FGlobalEventbus, Init)
	FCache[Key] = Result
	return Result


## Index < 0: an eventbus read of Event in Group, else the blackboard's indexed value.
func Read(Scriptfile: String, League: int, Level: int, Event: int, Group: Array = [], Index: int = -1, ByPassCache: bool = false):
	if Scriptfile == "":
		return null
	var EntityCache := GetEntityCache(Scriptfile, League, Level)
	Group = DSet.Make(Group)
	if EntityCache.IsSpell and Group != [1]:
		Group = [0]
	var Key := [Event, Group, Index]
	if not ByPassCache and EntityCache.CachedValues.has(Key):
		return EntityCache.CachedValues[Key]
	var Result = null
	# port: the original crashes on a script that failed to build (nil entity); here the value stays empty
	if EntityCache.DataEntity != null:
		if Index < 0:
			Result = EntityCache.DataEntity.Eventbus.Read(Event, [], Group)
		else:
			Result = EntityCache.DataEntity.Blackboard.GetIndexedValue(Event, Group, Index)
	EntityCache.CachedValues[Key] = Result
	return Result


## Triggers an event on the cached entity. Used for initializing tooltips by components.
func Trigger(Scriptfile: String, League: int, Level: int, Event: int, Values: Array, Group: Array = []) -> void:
	var EntityCache := GetEntityCache(Scriptfile, League, Level)
	if EntityCache.DataEntity != null:
		EntityCache.DataEntity.Eventbus.Trigger(Event, Values, Group)


## Writes a value to the cached entity. Use with care as it could introduce side effects to other useages.
func Write(Scriptfile: String, League: int, Level: int, Event: int, Values: Array, Group: Array = []) -> void:
	var EntityCache := GetEntityCache(Scriptfile, League, Level)
	if EntityCache.DataEntity != null:
		EntityCache.DataEntity.Eventbus.Write(Event, Values, Group)
