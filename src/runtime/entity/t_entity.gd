class_name TEntity
extends TObject
## Port of TEntity (BaseConflict.Entity.pas:323, implementation :507). An entity is its eventbus, blackboard and
## components; everything else lives in components.
## Not ported yet: CreateFromScript / CreateMetaFromScript / CreateDataFromScript / ApplyScript /
## ApplyScriptReturnGroups (the script runner, phase 2 step 2), Serialize / Deserialize (client-server sync,
## phase 3), OwningCommander (needs the entity manager, phase 3).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
## TResourceManagerComponent (BaseConflict.EntityComponents.Shared.pas:386): every entity gets one in Create.
## Loaded by path so the entity core works before the shared components are ported.
const RESOURCE_MANAGER_PATH := "res://src/runtime/components/t_resource_manager_component.gd"

## reserve the first n groups, so the user can hardcode something
const RESERVED_GROUPS = 20

var FCollisionRadius := 0.0
var FPosition := Vector2.ZERO
var FFront := Vector2.ZERO
## {$IFDEF CLIENT} display transform
var DisplayPosition := Vector3.ZERO
var DisplayFront := Vector3.ZERO
var DisplayUp := Vector3.ZERO

var FEventbus: TEventbus = null
var FGlobalEventbus: TEventbus = null
var FBlackboard: TBlackboard = null
var FAbstract := false
var FID := 0
var FCreatedTimestamp := 0
var FScriptFile := ""
var FUID := ""
var FSkinID := ""
var FCurrentComponentID := 0
## Count of entity components in each group. If 0 group is free to use, if <0 group is reserved by someone
var FGroupsInUse: Array = []

var ID: int:
	get:
		return FID
	set(value):
		FID = value
var UID: String:
	get:
		return FUID
	set(value):
		FUID = value
var ScriptFile: String:
	get:
		return FScriptFile
	set(value):
		FScriptFile = value
## The local eventbus of this entity.
var Eventbus: TEventbus:
	get:
		return FEventbus
var Blackboard: TBlackboard:
	get:
		return FBlackboard
var GlobalEventbus: TEventbus:
	get:
		return FGlobalEventbus
## Determines whether entity is a final entity in world or only abstract.
var IsAbstract: bool:
	get:
		return FAbstract
	set(value):
		FAbstract = value
var CreatedTimestamp: int:
	get:
		return FCreatedTimestamp
var SkinID: String:
	get:
		return FSkinID
	set(value):
		FSkinID = value
var Position: Vector2:
	get:
		return FPosition
	set(value):
		SetPosition(value)
var Front: Vector2:
	get:
		return FFront
	set(value):
		SetFront(value)
var CollisionRadius: float:
	get:
		return FCollisionRadius
	set(value):
		FCollisionRadius = RParam.ToSingle(value)


## Creates the entity. Now components can be added.
func Create(GlobalEventbus = null, ID: int = 0) -> TEntity:
	FID = ID
	FEventbus = TEventbus.new().Create(self)
	FGlobalEventbus = GlobalEventbus
	if FGlobalEventbus != null:
		FEventbus.ApplicationType = FGlobalEventbus.ApplicationType
	FBlackboard = TBlackboard.new().Create(self)
	FGroupsInUse = []
	FCreatedTimestamp = Time.get_ticks_msec()  # TimeManager.GetTimeStamp: TTimeManager is ported in phase 3
	# {$IFDEF SERVER} low(integer) {$ENDIF} {$IFDEF CLIENT} high(integer) {$ENDIF}
	FCurrentComponentID = -2147483648 if IsServer() else 2147483647
	if ResourceLoader.exists(RESOURCE_MANAGER_PATH):
		load(RESOURCE_MANAGER_PATH).new().CreateGroupedAll(self)
	return self


func Destroy() -> void:
	FEventbus.Trigger(C.eiBeforeFree, [])
	FEventbus.Trigger(C.eiFree, [])
	FEventbus.Free()
	FBlackboard.Free()
	FGroupsInUse = []
	super()


## Port: which side this entity lives on ({$IFDEF SERVER} in the original).
func IsServer() -> bool:
	return FEventbus.ApplicationType == C.nsServer


## Same as ScriptFile, but without file path and extension.
func ScriptFileName() -> String:
	return FScriptFile.replace("\\", "/").get_file().get_basename()


func SkinFileSuffix() -> String:
	return "_" + FSkinID if HasSkin() else ""


func HasSkin() -> bool:
	return FSkinID != ""


func GetSkinID(ComponentGroup: Array) -> String:
	var Result := RParam.AsString(Eventbus.ReadHierarchic(C.eiSkinIdentifier, [], ComponentGroup))
	if Result == "":
		Result = SkinID
	return Result


func GetSkinFileSuffix(ComponentGroup: Array) -> String:
	var Result := GetSkinID(ComponentGroup)
	if Result != "":
		Result = "_" + Result
	return Result


func SetFront(Value: Vector2) -> void:
	FFront = Value
	Eventbus.Write(C.eiFront, [Value])


func SetPosition(Value: Vector2) -> void:
	FPosition = Value
	Eventbus.Write(C.eiPosition, [Value])


func GetNewComponentID() -> int:
	var Result := FCurrentComponentID
	if IsServer():
		FCurrentComponentID += 1
	else:
		FCurrentComponentID -= 1
	return Result


func RegisterComponent(EntityComponent) -> void:
	if EntityComponent.ComponentGroup == [C.ALLGROUP_INDEX]:
		return
	for i in EntityComponent.ComponentGroup:
		while FGroupsInUse.size() <= i:
			FGroupsInUse.append(0)
		# if group is reserved, first component dereserves it
		if FGroupsInUse[i] < 0:
			FGroupsInUse[i] = 0
		FGroupsInUse[i] += 1


func DeregisterComponent(EntityComponent) -> void:
	if EntityComponent.ComponentGroup == [C.ALLGROUP_INDEX]:
		return
	for i in EntityComponent.ComponentGroup:
		assert(FGroupsInUse.size() > i, "TEntity.DeregisterComponent: Some component seems to deregister but never registered or changed its group without notifing the entity.")
		FGroupsInUse[i] -= 1


## Reserves a unused group for further usage. The first component placed in this group will free the reserved
## state. So if killed the group is free for next use.
func ReserveFreeGroup() -> int:
	for i in range(RESERVED_GROUPS - 1, 256):
		while FGroupsInUse.size() <= i:
			FGroupsInUse.append(0)
		if FGroupsInUse[i] == 0:
			# reserve group
			FGroupsInUse[i] = -1
			return i
	# should never happen, except we exaggerate with buffs (256 groups are filled up = ~ 128 Buffs)
	push_error("TEntity.ReserveFreeGroup: Could not find free group!")
	return -1


## Release all content of the groups and unreserves them.
func FreeGroups(Groups: Array) -> void:
	Groups = DSet.Make(Groups)
	Eventbus.Trigger(C.eiBeforeFree, [], Groups)
	Eventbus.Trigger(C.eiFree, [], Groups)
	Blackboard.DeleteValues(Groups)
	for i in Groups:
		if FGroupsInUse.size() > i:
			assert(FGroupsInUse[i] <= 0, "TEntity.FreeGroups: Some components seems to ignore to call to free them. After freeing a group it is still in use.")
			FGroupsInUse[i] = 0


## Adds the groups to be removed by the entity manager.
func RemoveGroups(Groups: Array) -> void:
	GlobalEventbus.Trigger(C.eiRemoveComponentGroup, [ID, DSet.Make(Groups)])


## Registers the entity in the game. Should be called after adding the components.
func Deploy() -> void:
	FGlobalEventbus.Trigger(C.eiNewEntity, [self])
	Eventbus.Trigger(C.eiDeploy, [])


func DeferFree() -> void:
	var game = FGlobalEventbus.Game if FGlobalEventbus != null else null
	if game != null and game.EntityManager != null:
		game.EntityManager.FreeEntity(self)
	else:
		Free()


## Shortcut to read unit properties from eventbus (SetUnitProperty as an Array).
func UnitProperties() -> Array:
	return RParam.AsSet(Eventbus.Read(C.eiUnitProperties, []))


## Shortcut to read unit data from blackboads.
func UnitData(DataType: int):
	return Blackboard.GetIndexedValue(C.eiUnitData, [], DataType)


## Balance(ResourceType) / Balance(ResourceType, Group)
func Balance(ResourceType: int, Group = null):
	if Group == null:
		return Eventbus.Read(C.eiResourceBalance, [ResourceType])
	return Eventbus.ReadHierarchic(C.eiResourceBalance, [ResourceType], Group)


func BalanceInt(ResourceType: int) -> int:
	return RParam.AsInteger(Eventbus.Read(C.eiResourceBalance, [ResourceType]))


func BalanceSingle(ResourceType: int) -> float:
	return RParam.AsSingle(Eventbus.Read(C.eiResourceBalance, [ResourceType]))


## Cap(ResourceType) / Cap(ResourceType, Group)
func Cap(ResourceType: int, Group = null):
	if Group == null:
		return Eventbus.Read(C.eiResourceCap, [ResourceType])
	return Eventbus.ReadHierarchic(C.eiResourceCap, [ResourceType], Group)


func CapSingle(ResourceType: int) -> float:
	return RParam.AsSingle(Cap(ResourceType))


## ResFill(ResourceType) / ResFill(ResourceType, Group)
func ResFill(ResourceType: int, Group = null) -> float:
	if BC.IsIntResource(ResourceType):
		return float(RParam.AsInteger(Balance(ResourceType, Group))) / RParam.AsInteger(Cap(ResourceType, Group))
	return RParam.AsSingle(Balance(ResourceType, Group)) / RParam.AsSingle(Cap(ResourceType, Group))


func TeamID() -> int:
	return RParam.AsInteger(Eventbus.Read(C.eiTeamID, []))


func CommanderID() -> int:
	return RParam.AsInteger(Eventbus.Read(C.eiOwnerCommander, []))


## Returns whether this unit has this property or not.
func HasUnitProperty(UnitProperty: int) -> bool:
	return RParam.AsSet(Eventbus.Read(C.eiUnitProperties, [])).has(UnitProperty)


## Returns whether the main weapon of this unit has this type or not.
func HasDamageType(DamageType: int) -> bool:
	return RParam.AsSet(Eventbus.Read(C.eiDamageType, [], [C.GROUP_MAINWEAPON])).has(DamageType)


## ColorIdentity() / ColorIdentity(Group: TArray<Byte>)
func ColorIdentity(Group = null) -> int:
	if Group == null:
		return RParam.AsInteger(Eventbus.Read(C.eiColorIdentity, []))
	return RParam.AsInteger(Eventbus.Read(C.eiColorIdentity, [], Group))


func ReadCollisionRadius(Group: Array) -> float:
	return RParam.AsSingle(Eventbus.Read(C.eiCollisionRadius, [], Group))


## CardLevel() / CardLevel(Group: Byte) / CardLevel(Group: TArray<Byte>): all plain reads.
func CardLevel(Group = null) -> int:
	if Group == null:
		return RParam.AsInteger(Eventbus.Read(C.eiResourceBalance, [C.reCardLevel]))
	if Group is Array:
		return RParam.AsInteger(Eventbus.Read(C.eiResourceBalance, [C.reCardLevel], Group))
	return RParam.AsInteger(Eventbus.Read(C.eiResourceBalance, [C.reCardLevel], [Group]))


## CardLeague() reads plainly; CardLeague(Group: Byte) and CardLeague(Group: TArray<Byte>) read hierarchically.
func CardLeague(Group = null) -> int:
	if Group == null:
		return RParam.AsInteger(Eventbus.Read(C.eiResourceBalance, [C.reCardLeague]))
	if Group is Array:
		return RParam.AsInteger(Eventbus.ReadHierarchic(C.eiResourceBalance, [C.reCardLeague], Group))
	return RParam.AsInteger(Eventbus.ReadHierarchic(C.eiResourceBalance, [C.reCardLeague], [Group]))
