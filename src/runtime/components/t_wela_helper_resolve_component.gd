class_name TWelaHelperResolveComponent
extends TEntityComponent
## Port of TWelaHelperResolveComponent (BaseConflict.EntityComponents.Shared.Wela.pas:941, implementation :2687).
## Answers reads of wela values (eiWelaUnitPattern, eiWelaCount, eiWelaDamage, eiCooldown, ...) at epFirst with the
## blackboard value saved under the index of the current source (team ID, level, a resource, the game's tier or the
## owner's tier) in the group the read was called to; falls back to the previous value if nothing is saved there.
## Quirk kept: ResolveTier (owner tier) gives 1 for upTier1 and upTier2 and 3 otherwise.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

enum { rsTeamID, rsLevel, rsResource, rsTier, rsOwnerTier }

var FLevelGroup: Array = []
var FSource := rsTeamID
var FResource: int = C.reNone


func _DeclareEvents(e: Array) -> void:
	super(e)
	for Event in [C.eiWelaUnitPattern, C.eiWelaCount, C.eiWelaTargetCount, C.eiWelaDamage, C.eiWelaAreaOfEffect,
			C.eiWelaSplashfactor, C.eiWelaRange, C.eiArmorType, C.eiCooldown]:
		e.append(XEvent("OnFetch", Event, C.epFirst, C.etRead))


func GetCurrentIndex() -> int:
	match FSource:
		rsTeamID:
			return Owner.TeamID()
		rsLevel:
			return RParam.AsInteger(Owner.Balance(C.reLevel, FLevelGroup))
		rsResource:
			return RParam.AsInteger(Owner.Balance(FResource, FLevelGroup))
		rsTier:
			if RParam.AsInteger(GlobalEventbus().Read(C.eiGameEventTimeTo, [C.GAME_EVENT_TECH_LEVEL_2])) > 0:
				return 0
			elif RParam.AsInteger(GlobalEventbus().Read(C.eiGameEventTimeTo, [C.GAME_EVENT_TECH_LEVEL_3])) > 0:
				return 1
			return 2
		rsOwnerTier:
			var UnitProperties: Array = Owner.UnitProperties()
			if UnitProperties.has(C.upTier1):
				return 1
			elif UnitProperties.has(C.upTier2):
				return 1
			return 3
	MakeException("GetCurrentIndex: Missing implementation of resolve source!")
	return 0


## Resolves the right index.
func OnFetch(Previous):
	var Result = Owner.Blackboard.GetIndexedValue(TEventbus.CurrentEvent_EventIdentifier, TEventbus.CurrentEvent_CalledToGroup, GetCurrentIndex())
	if RParam.IsEmpty(Result):
		Result = Previous
	return Result


## Resolve the tier the game currently is in.
func ResolveCurrentTier() -> TWelaHelperResolveComponent:
	FSource = rsTier
	return self


## Sets the group which contains the level.
func ResolveLevel(LevelGroup: Array) -> TWelaHelperResolveComponent:
	FSource = rsLevel
	FLevelGroup = DSet.Make(LevelGroup)
	return self


## Sets the group which contains the level.
func ResolveResource(Resource: int, ResourceGroup: Array) -> TWelaHelperResolveComponent:
	FSource = rsResource
	FLevelGroup = DSet.Make(ResourceGroup)
	FResource = Resource
	assert(BC.IsIntResource(FResource), "TWelaHelperResolveComponent.ResolveResource: Only integer resources supported.")
	return self


func ResolveTeamID() -> TWelaHelperResolveComponent:
	FSource = rsTeamID
	return self


## Resolves the tier of the owner.
func ResolveTier() -> TWelaHelperResolveComponent:
	FSource = rsOwnerTier
	return self
