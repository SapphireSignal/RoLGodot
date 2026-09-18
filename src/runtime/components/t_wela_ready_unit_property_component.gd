class_name TWelaReadyUnitPropertyComponent
extends TWelaReadyComponent
## Port of TWelaReadyUnitPropertyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:669, implementation
## :2224). Ready while the owner (or its commander, ChecksCommander; none: ready) has all MustHave properties, any
## of MustHaveAny, none of MustNotHave and not all of MustNotHaveAll.

var FMustNotList: Array = []
var FMustList: Array = []
var FMustNotAllList: Array = []
var FMustAnyList: Array = []
var FChecksCommander := false


func IsReady() -> bool:
	var TargetEntity = Owner
	if FChecksCommander:
		var game = GlobalEventbus().Game
		TargetEntity = game.EntityManager.GetOwningCommander(Owner) if game != null else null
	if TargetEntity == null:
		return true
	var UnitProperties := RParam.AsSet(TargetEntity.Eventbus.Read(C.eiUnitProperties, []))
	return DSet.Difference(FMustList, UnitProperties).is_empty() \
		and (FMustAnyList.is_empty() or DSet.Intersects(FMustAnyList, UnitProperties)) \
		and not DSet.Intersects(FMustNotList, UnitProperties) \
		and (FMustNotAllList.is_empty() or not DSet.Difference(FMustNotAllList, UnitProperties).is_empty())


func MustHave(Properties: Array) -> TWelaReadyUnitPropertyComponent:
	FMustList = DSet.Make(Properties)
	return self


func MustHaveAny(Properties: Array) -> TWelaReadyUnitPropertyComponent:
	FMustAnyList = DSet.Make(Properties)
	return self


func MustNotHave(Properties: Array) -> TWelaReadyUnitPropertyComponent:
	FMustNotList = DSet.Make(Properties)
	return self


func MustNotHaveAll(Properties: Array) -> TWelaReadyUnitPropertyComponent:
	FMustNotAllList = DSet.Make(Properties)
	return self


func ChecksCommander() -> TWelaReadyUnitPropertyComponent:
	FChecksCommander = true
	return self
