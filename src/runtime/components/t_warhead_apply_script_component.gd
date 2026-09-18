class_name TWarheadApplyScriptComponent
extends TEntityComponent
## Port of TWarheadApplyScriptComponent (BaseConflict.EntityComponents.Shared.Wela.pas:855, implementation :2317).
## Applies a script (routine 'Apply' or Methodname) to entities: by default to every entity target of eiFireWarhead
## called to its group; ApplyToProducedUnits: to the units of eiWelaUnitProduced instead; ApplyToSelfAtCreate: to
## its owner at eiAfterCreate, then frees itself; ApplyToSelfAfterDelay: to its owner at the first global eiIdle after
## the delay, then frees itself. The Pass* methods add parameters after the obligatory entity, in call order.
## Port: the original's Pass* methods fill a local record without clearing it first (fields they do not set hold
## stack garbage, e.g. UsesGroupOverride); here unset fields are zero/false.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

enum { ptNone, ptInteger, ptSingle, ptBoolean, ptBooleanSameTeam, ptDirectionToTarget, ptOffsetToTarget,
	ptIntegerEvent, ptSingleEvent, ptRVector2Event, ptResource }


## The original's RParameter record.
class RWarheadParameter:
	extends RefCounted
	var ParameterEvent := 0
	var ParameterIntValue := 0
	var ParameterSingleValue := 0.0
	var ParameterBooleanValue := false
	var ParameterType := ptNone
	var ParameterResource := 0
	var ParameterGroup: Array = []
	var UsesGroupOverride := false
	var PublicEvent := false
	var Index := 0

	## Owner: the component (the record's Owner field, the port passes it instead of storing a back-reference).
	func GetValue(Owner: TWarheadApplyScriptComponent, Eventbus: TEventbus, ComponentGroup: Array):
		if PublicEvent:
			ComponentGroup = []
		if UsesGroupOverride:
			ComponentGroup = ParameterGroup
		match ParameterType:
			ptIntegerEvent:
				return RParam.AsInteger(Eventbus.Read(ParameterEvent, [], ComponentGroup))
			ptSingleEvent:
				return RParam.AsSingle(Eventbus.Read(ParameterEvent, [], ComponentGroup))
			ptRVector2Event:
				if ParameterEvent == C.eiWelaSavedTargets:
					var Targets := ATarget.FromRParam(Eventbus.Read(ParameterEvent, [], ComponentGroup))
					if Targets.size() < Index + 1:
						push_error("TWarheadApplyScriptComponent.RParameter.GetValue(eiWelaSavedTargets): Not enough targets saved!")
						return null
					return Targets[Index].GetTargetPosition(Owner.GlobalEventbus().Game)
				return RParam.AsVector2(Eventbus.Read(ParameterEvent, [], ComponentGroup))
			ptInteger:
				return ParameterIntValue
			ptSingle:
				return ParameterSingleValue
			ptBoolean:
				return ParameterBooleanValue
			ptBooleanSameTeam:
				assert(Owner.FCurrentTarget != null, "TWarheadApplyScriptComponent.RParameter.GetValue(ptBooleanSameTeam): Invalid target, probably due to usage of ptBooleanSameTeam with other triggers than a entity target!")
				return Eventbus.Owner.TeamID() == Owner.FCurrentTarget.TeamID()
			ptDirectionToTarget:
				assert(Owner.FCurrentTarget != null, "TWarheadApplyScriptComponent.RParameter.GetValue(ptDirectionToTarget): Invalid target, probably due to usage of ptDirectionToTarget with other triggers than FireWarhead!")
				return (Owner.FCurrentTarget.Position - Eventbus.Owner.Position).normalized()
			ptOffsetToTarget:
				assert(Owner.FCurrentTarget != null, "TWarheadApplyScriptComponent.RParameter.GetValue(ptOffsetToTarget): Invalid target, probably due to usage of ptOffsetToTarget with other triggers than FireWarhead!")
				return Owner.FCurrentTarget.Position - Eventbus.Owner.Position
			ptResource:
				if BC.IsIntResource(ParameterResource):
					return RParam.AsInteger(Eventbus.Owner.Balance(ParameterResource, ComponentGroup))
				return RParam.AsSingle(Eventbus.Owner.Balance(ParameterResource, ComponentGroup))
		push_error("TWarheadApplyScriptComponent.RParameter.GetValue: Unknown parameter type!")
		return null


## for passing direction to target on fire warhead
var FCurrentTarget: TEntity = null
var FAtUnitProduced := false
var FNotAtFire := false
var FAfterCreate := false
var FScriptName := ""
var FMethodname := ""
var FParameters: Array = []  # of RWarheadParameter
var FTimer: TTimer = null


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnFireWarhead", C.eiFireWarhead, C.epLast, C.etTrigger))
	e.append(XEvent("OnWelaUnitProduced", C.eiWelaUnitProduced, C.epLast, C.etTrigger))
	e.append(XEvent("OnIdle", C.eiIdle, C.epLast, C.etTrigger, C.esGlobal))


func CreateGrouped(Owner = null, Group = [], ScriptToApply = "") -> TEntityComponent:
	super(Owner, Group)
	FScriptName = ScriptToApply
	FParameters = []
	return self


func Destroy() -> void:
	FParameters = []
	FTimer = null
	FCurrentTarget = null
	super()


func Apply(Entity: TEntity) -> void:
	var Parameters: Array = []
	if FParameters.size() > 0:
		Parameters.append(Entity)
		for Parameter in FParameters:
			Parameters.append(Parameter.GetValue(self, Eventbus(), ComponentGroup))
	var Method := FMethodname if FMethodname != "" else "Apply"
	Entity.ApplyScript(FScriptName, Method, Parameters)


func ApplyToProducedUnits() -> TWarheadApplyScriptComponent:
	FAtUnitProduced = true
	return self


func ApplyToSelfAfterDelay(Duration: int) -> TWarheadApplyScriptComponent:
	FTimer = TTimer.new().CreateAndStart(Duration)
	return self


## Applies the script to the entity itself after creation and frees this.
func ApplyToSelfAtCreate() -> TWarheadApplyScriptComponent:
	FAfterCreate = true
	return self


func Methodname(Methodname_: String) -> TWarheadApplyScriptComponent:
	FMethodname = Methodname_
	return self


## Apply the script to the targets.
func OnAfterCreate() -> bool:
	if FAfterCreate:
		Apply(Owner)
		DeferFree()
	return true


## Apply the script to the targets.
func OnFireWarhead(Targets) -> bool:
	if not FAtUnitProduced and not FNotAtFire and IsLocalCall():
		var TargetsArray := ATarget.FromRParam(Targets)
		for Target in TargetsArray:
			if not Target.IsEntity():
				continue
			var Entity = Target.TryGetTargetEntity(GlobalEventbus().Game)
			if Entity != null:
				FCurrentTarget = Entity
				Apply(Entity)
				FCurrentTarget = null
	return true


## Apply the script to self if delayed.
func OnIdle() -> bool:
	if FTimer != null and FTimer.Expired:
		Apply(Owner)
		FTimer = null
		DeferFree()
	return true


## Apply the script to produced units.
func OnWelaUnitProduced(EntityID) -> bool:
	if FAtUnitProduced and IsLocalCall():
		var game = GlobalEventbus().Game
		var Entity = game.EntityManager.TryGetEntityByID(RParam.AsInteger(EntityID)) if game != null else null
		if Entity != null:
			Apply(Entity)
	return true


func OverrideLastParameterGroup(Group: Array) -> TWarheadApplyScriptComponent:
	var Parameter: RWarheadParameter = FParameters.back()
	Parameter.ParameterGroup = DSet.Make(Group)
	Parameter.UsesGroupOverride = true
	return self


## Passes additional parameters to the Apply-Method. The order of the passmethod determines their index. The
## parameters are placed AFTER the obligatory entity parameter.
func PassValueFromEvent(Event: int) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterEvent = Event
	match Event:
		C.eiCooldown, C.eiColorIdentity, C.eiTeamID:
			Parameter.ParameterType = ptIntegerEvent
		C.eiWelaDamage, C.eiWelaRange, C.eiWelaAreaOfEffect:
			Parameter.ParameterType = ptSingleEvent
		C.eiFront:
			Parameter.ParameterType = ptRVector2Event
		_:
			# the original raises here: the parameter is not added
			MakeException("PassValueFromEvent: %d is not supported yet, maybe you can add it? :)" % Event)
			return self
	Parameter.PublicEvent = Event in [C.eiColorIdentity, C.eiTeamID, C.eiFront]
	FParameters.append(Parameter)
	return self


func PassSavedTargetPosition(Index: int) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptRVector2Event
	Parameter.ParameterEvent = C.eiWelaSavedTargets
	Parameter.Index = Index
	FParameters.append(Parameter)
	return self


func PassResource(Resource: int) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptResource
	Parameter.ParameterResource = Resource
	FParameters.append(Parameter)
	return self


func PassIntValue(Value: int) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptInteger
	Parameter.ParameterIntValue = Value
	FParameters.append(Parameter)
	return self


func PassSingleValue(Value: float) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptSingle
	Parameter.ParameterSingleValue = RParam.ToSingle(Value)
	FParameters.append(Parameter)
	return self


func PassBooleanValue(Value: bool) -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptBoolean
	Parameter.ParameterBooleanValue = Value
	FParameters.append(Parameter)
	return self


func PassSameTeam() -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptBooleanSameTeam
	Parameter.PublicEvent = true
	FParameters.append(Parameter)
	return self


func PassDirectionToTarget() -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptDirectionToTarget
	FParameters.append(Parameter)
	return self


func PassOffsetToOwner() -> TWarheadApplyScriptComponent:
	var Parameter := RWarheadParameter.new()
	Parameter.ParameterType = ptOffsetToTarget
	FParameters.append(Parameter)
	return self
