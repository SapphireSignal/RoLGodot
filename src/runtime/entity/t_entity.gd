class_name TEntity
extends TObject
## Port of TEntity (BaseConflict.Entity.pas:323, implementation :507). An entity is its eventbus, blackboard and
## components; everything else lives in components.
## Serialize / Deserialize use TEntityStream (an in-memory stand-in for the network stream); the serializable
## components' own fields are not ported yet.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
## Original script path (lower case, relative to Scripts\) -> generated GDScript, per side.
const SCRIPT_INDEX = preload("res://src/content/scripts/script_index.gd")
## BaseConflict.Constants.pas / BaseConflict.Constants.Cards.pas
const SCRIPT_INHERIT_VAR_NAME = "InheritsFrom"
const SCRIPT_INHERIT_PRECEDING_VAR_NAME = "InheritsFromPreceding"
const FILE_EXTENSION_ENTITY = ".ets"
const PATH_SCRIPT = "\\Scripts\\"

## Port: the last error of the script runner (the original raised an exception), for tests and logs.
static var LastScriptError := ""
## Tests that provoke script errors on purpose set this to keep the log free of expected errors.
static var QuietScriptErrors := false

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
	FCreatedTimestamp = TTimeManager.GetTimeStamp()
	# {$IFDEF SERVER} low(integer) {$ENDIF} {$IFDEF CLIENT} high(integer) {$ENDIF}
	FCurrentComponentID = -2147483648 if IsServer() else 2147483647
	TResourceManagerComponent.new().CreateGroupedAll(self)
	return self


# ---- script runner (BaseConflict.Entity.pas:587-712, Engine/Engine.Script.pas TScript) ------------------------

## CreateFromScript(PatternFileName, GlobalEventbus[, Initializer]): builds an entity with the script's CreateEntity.
## Initializer: Callable(Entity) or an empty Callable (nil).
static func CreateFromScript(PatternFileName: String, GlobalEventbus, Initializer := Callable()) -> TEntity:
	return CreateFromScriptProc(PatternFileName, "CreateEntity", GlobalEventbus, Initializer)


static func CreateMetaFromScript(PatternFileName: String, GlobalEventbus, Initializer := Callable()) -> TEntity:
	return CreateFromScriptProc(PatternFileName, "CreateMeta", GlobalEventbus, Initializer, true)


static func CreateDataFromScript(PatternFileName: String, GlobalEventbus, Initializer := Callable()) -> TEntity:
	return CreateFromScriptProc(PatternFileName, "CreateData", GlobalEventbus, Initializer, true)


## InheritsFrom: the parent chain builds the entity (its ProcName runs fully), then ours runs on it.
## InheritsFromPreceding: ours runs inside the initializer, right after TEntity.Create, before the base script's.
## Neither: this is the base script; it creates the entity and runs the initializer, then ProcName.
## The entity keeps the file name of the script first asked for. Returns null where the original raised.
static func CreateFromScriptProc(PatternFileName: String, ProcName: String, GlobalEventbus, Initializer := Callable(), IsMeta := false, FileNameOverride := "") -> TEntity:
	var FinalScriptFilename := PatternFileName if FileNameOverride == "" else FileNameOverride
	var ScriptFilePath := "scripts\\" + PatternFileName
	if ScriptFilePath.replace("\\", "/").get_file().get_extension() == "":
		ScriptFilePath += FILE_EXTENSION_ENTITY
	var Server: bool = GlobalEventbus == null or GlobalEventbus.ApplicationType == C.nsServer
	var EntityPattern = CompileScriptFromFile(ScriptFilePath, Server)  # RunMain: init global variables of the script
	if EntityPattern == null:
		return null
	_SetScriptGlobals(EntityPattern, GlobalEventbus)
	var Result: TEntity = null
	if SCRIPT_INHERIT_VAR_NAME in EntityPattern:
		Result = CreateFromScriptProc(EntityPattern.get(SCRIPT_INHERIT_VAR_NAME), ProcName, GlobalEventbus, Initializer, IsMeta, FinalScriptFilename)
	elif SCRIPT_INHERIT_PRECEDING_VAR_NAME in EntityPattern:
		var Preceding := func(Entity: TEntity) -> void:
			if Initializer.is_valid():
				Initializer.call(Entity)
			ExecuteFunction(EntityPattern, ProcName, [Entity], GlobalEventbus)
		Result = CreateFromScriptProc(EntityPattern.get(SCRIPT_INHERIT_PRECEDING_VAR_NAME), ProcName, GlobalEventbus, Preceding, IsMeta, FinalScriptFilename)
		if Result != null:
			Result.ScriptFile = FinalScriptFilename
		return Result
	else:
		# only base script file runs initilization methods
		Result = TEntity.new().Create(GlobalEventbus, 0)
		Result.IsAbstract = IsMeta
		if Initializer.is_valid():
			Initializer.call(Result)
	if Result == null:
		return null
	Result.ScriptFile = FinalScriptFilename
	ExecuteFunction(EntityPattern, ProcName, [Result], GlobalEventbus)
	return Result


## Runs ProcName (default 'Apply') of a script with Parameters, or with this entity if there are none.
func ApplyScript(ScriptFileName: String, ProcName := "", Parameters = null) -> void:
	if ProcName == "":
		ProcName = "Apply"
	if not ScriptFileName.is_absolute_path() and not ScriptFileName.begins_with(PATH_SCRIPT):
		ScriptFileName = PATH_SCRIPT + ScriptFileName
	var Script = CompileScriptFromFile(ScriptFileName, IsServer())
	if Script == null:
		return
	_SetScriptGlobals(Script, GlobalEventbus)
	# assigned(Parameters): a dynamic array is nil when empty
	if Parameters != null and not Parameters.is_empty():
		ExecuteFunction(Script, ProcName, Parameters, GlobalEventbus)
	else:
		ExecuteFunction(Script, ProcName, [self], GlobalEventbus)


## Runs ProcName (default 'Apply') with this entity; it returns the component groups it created (array of integer).
func ApplyScriptReturnGroups(ScriptFileName: String, ProcName := "") -> Array:
	var finalProcName := "Apply" if ProcName == "" else ProcName
	var Script = CompileScriptFromFile("scripts\\" + ScriptFileName, IsServer())
	if Script == null:
		return []
	_SetScriptGlobals(Script, GlobalEventbus)
	var ReturnValue = ExecuteFunction(Script, finalProcName, [self], GlobalEventbus)
	if not ReturnValue is Array:
		return []
	# integer -> Byte (truncates like the original's assignment), then ByteArrayToComponentGroup
	return DSet.Make(ReturnValue.map(func(i): return int(i) & 0xFF))


## Port of TScriptmanager.CompileScriptFromFile + TScript.RunMain: the generated script of one side for an original
## path (any case, either slash, relative to or inside the Scripts folder), instantiated (= globals initialised).
## Fails like the original on a missing file and on a file the original could not compile.
static func CompileScriptFromFile(FileName: String, Server: bool) -> Object:
	var Key := "\\" + FileName.replace("/", "\\").to_lower()
	# Windows takes doubled separators as one: '\Scripts\' + '\Environment\Bridge11.ets' (TClientMap decorations)
	while Key.contains("\\\\"):
		Key = Key.replace("\\\\", "\\")
	var At := Key.rfind("\\scripts\\")
	Key = Key.substr(At + 9) if At >= 0 else Key.substr(1)
	var Index: Dictionary = SCRIPT_INDEX.SERVER if Server else SCRIPT_INDEX.CLIENT
	if not Index.has(Key):
		_ScriptError("TScriptmanager.CompileScriptFromFile: Can't find scriptfile \"%s\"." % FileName)
		return null
	var Source: GDScript = load(Index[Key])
	var Constants := Source.get_script_constant_map()
	if Constants.has("ORIGINAL_COMPILE_ERROR"):
		_ScriptError("Error while compiling scriptfile (%s): %s" % [FileName, Constants["ORIGINAL_COMPILE_ERROR"]])
		return null
	return Source.new()


## Port of TScript.ExecuteFunction: the parameter count must match the routine's exactly.
## GlobalEventbus: the side the script runs for; while it runs, the exposed Game() (L.Game) returns its Game.
static func ExecuteFunction(Script: Object, Name: String, Parameters: Array, GlobalEventbus = null) -> Variant:
	if not Script.has_method(Name):
		_ScriptError("TScript.ExecuteFunction: Unknown function \"%s\"." % Name)
		return null
	if Script.get_method_argument_count(Name) != Parameters.size():
		_ScriptError("TScript.ExecuteFunction: Parametercount doesn't match.")
		return null
	_ScriptEventbusStack.push_back(GlobalEventbus)
	var Result = Script.callv(Name, Parameters)
	_ScriptEventbusStack.pop_back()
	return Result


## The global buses of the scripts running now, innermost last.
static var _ScriptEventbusStack: Array = []


## BaseConflict.Globals.Game, a threadvar in the original (one game per server thread): the Game of the global
## bus of the innermost running script.
static func ScriptGame():
	if _ScriptEventbusStack.is_empty() or _ScriptEventbusStack.back() == null:
		return null
	return _ScriptEventbusStack.back().Game


## SetGlobalVariableValueIfExist for 'GlobalEventbus' and 'Game' (the Game of the bus's side).
static func _SetScriptGlobals(Script: Object, GlobalEventbus) -> void:
	if "GlobalEventbus" in Script:
		Script.set("GlobalEventbus", GlobalEventbus)
	if "Game" in Script:
		Script.set("Game", GlobalEventbus.Game if GlobalEventbus != null else null)


static func _ScriptError(Message: String) -> void:
	LastScriptError = Message
	if not QuietScriptErrors:
		push_error(Message)


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


## TEntity.Serialize (:801): ID, script, skin, UID and the blackboard, then eiSerialize for the serializable
## components (their RTTI field serialization is not ported yet: no component writes anything).
func Serialize(Stream: TEntityStream) -> void:
	Stream.Write(FID)
	Stream.Write(FScriptFile)
	Stream.Write(FSkinID)
	Stream.Write(FUID)
	Blackboard.SaveToStream(Stream)
	Eventbus.Trigger(C.eiSerialize, [Stream])


## TEntity.Deserialize (:733): the client builds the entity from its script with the server's blackboard already in
## place (so the creating components see the server's values), then loads the blackboard again over what the script
## set. The stream stands after the ID (TClientNetworkComponent.DeserializeEntity reads it first). Serialized
## components (the rest of the stream) are not ported yet.
static func Deserialize(EntityID: int, Stream: TEntityStream, GlobalEventbus) -> TEntity:
	var ScriptFile_: String = Stream.Read()
	var SkinID_: String = Stream.Read()
	var UID_: String = Stream.Read()
	var BlackboardStreamPosition := Stream.Position
	var Result := CreateFromScript(ScriptFile_, GlobalEventbus, func(Entity: TEntity) -> void:
		Entity.SkinID = SkinID_
		# init all values set by the server to the entity, so all components have access to them
		Entity.Blackboard.LoadFromStream(Stream))
	if Result == null:
		return null
	# now override all values already overwritten by the server, but set by the creation script
	Stream.Position = BlackboardStreamPosition
	Result.Blackboard.LoadFromStream(Stream)
	Result.FID = EntityID
	Result.UID = UID_
	return Result


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
