class_name TVisualizerComponent
extends TGDEntityComponent
## Port of TVisualizerComponent (BaseConflict.EntityComponents.Client.Visuals.pas:257, implementation :2400), the
## master class of unit displays like meshes, and RMatrixAdjustments (:249, :6273). Every frame (global eiIdle) it
## computes the bind matrix (game space, RMatrix as Transform3D: see RMatrix) from the entity's display position,
## front and up (or a bound zone of another component, or a fixed orientation), the size from eiSize / eiModelSize /
## a scale event / a resource, and hands both to its subclass (Apply). Static ones (environment meshes) apply once.

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const GAMEPLAY_SCALE_EVENTS = [C.eiWelaRange, C.eiWelaAreaOfEffect]


## RMatrixAdjustments: swaps, inversions, offset and rotation applied to a bind or bone matrix.
class RMatrixAdjustments:
	var BindInvertX := false
	var BindInvertY := false
	var BindInvertZ := false
	var BindSwapXY := false
	var BindSwapXZ := false
	var BindSwapYZ := false
	var Offset := Vector3.ZERO
	var Rotation := Vector3.ZERO

	func Apply(a: Transform3D) -> Transform3D:
		var result := a
		if BindSwapXY:
			result = RMatrix.SwapColumns(result, 0, 1)
		if BindSwapXZ:
			result = RMatrix.SwapColumns(result, 2, 0)
		if BindSwapYZ:
			result = RMatrix.SwapColumns(result, 1, 2)
		if BindInvertX:
			result.basis.x = -result.basis.x
		if BindInvertY:
			result.basis.y = -result.basis.y
		if BindInvertZ:
			result.basis.z = -result.basis.z
		if Offset != Vector3.ZERO:
			result = result * RMatrix.CreateTranslation(Offset)
		if Rotation != Vector3.ZERO:
			result = result * RMatrix.CreateRotationPitchYawRoll(Rotation)
		return result

	func Copy() -> RMatrixAdjustments:
		var c := RMatrixAdjustments.new()
		c.BindInvertX = BindInvertX
		c.BindInvertY = BindInvertY
		c.BindInvertZ = BindInvertZ
		c.BindSwapXY = BindSwapXY
		c.BindSwapXZ = BindSwapXZ
		c.BindSwapYZ = BindSwapYZ
		c.Offset = Offset
		c.Rotation = Rotation
		return c


var FBoundZone := ""
var FBindGroup: Array = []
var FBindMatrix := Transform3D.IDENTITY
var FSize := Vector3.ONE
var FFixedTeamID := -1
var FOveriddenResourceCap := 0.0
var FModelsize := 1.0
var FMinScaleEvent := 0.0
var FMaxScaleEvent := 1000.0
var FFixedHeight := 0.0
var FResourceScaleFactorMin := 0.0
var FResourceScaleFactorMax := 0.0
var FScaleWithResource: int = C.reNone
var FScaleEvent := 0
var FBindMatrixAdjustments := RMatrixAdjustments.new()
var FFixedOrientation := false
var FScaleWithEvent := false
var FIgnoreSize := false
var FIgnoreModelSize := false
var FHasFixedHeight := false
var FBindDebug := false
var FIsStatic := false
var FFirstStaticApplyDone := false
var FIsPiece := false
var FVisibleWithWelaReady := false
var FVisibleWithOption := false
var FVisibilityOption := 0
var FWelaReadyGroup: Array = []
var FVisibleWithResource: int = C.reNone
var FVisibleWithUnitPropertyMustHave: Array = []
var FVisibleWithUnitPropertyMustNotHave: Array = []
var FOffset := Vector3.ZERO
var FRotationOffset := Vector3.ZERO
var FFixedFront := Vector3.ZERO
var FFixedUp := Vector3.ZERO
var FDefaultFront := Vector3(-1, 0, 0)
var FDefaultUp := Vector3(0, 1, 0)
var FFixedOffset := Vector3.ZERO


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnModelSize", C.eiModelSize, C.epLast, C.etWrite))
	e.append(XEvent("OnIdle", C.eiIdle, C.epLower, C.etTrigger, C.esGlobal))


func Create(Owner = null) -> TEntityComponent:
	return CreateGrouped(Owner, [])


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FBindMatrix = Transform3D.IDENTITY
	FSize = Vector3.ONE
	FModelsize = RParam.AsSingleDefault(Eventbus().Read(C.eiModelSize, [], ComponentGroup), 1.0)
	FMaxScaleEvent = 1000.0
	FDefaultFront = Vector3(-1, 0, 0)
	FDefaultUp = Vector3(0, 1, 0)
	FFixedTeamID = -1
	return self


## Apply position, front, size etc data to visual representation.
func Apply() -> void:
	if IsBoundToBone():
		var mat = Eventbus().Read(C.eiSubPositionByString, [FBoundZone], FBindGroup)
		if mat != null:
			FBindMatrix = mat
		else:
			FBindMatrix = Transform3D.IDENTITY
			if FIsPiece:
				FBindMatrix.origin = RParam.AsVector3(Eventbus().ReadHierarchic(C.eiDisplayPosition, [], ComponentGroup))
			else:
				FBindMatrix.origin = Owner.DisplayPosition
		if FFixedOrientation:
			FBindMatrix.basis.z = FFixedFront
			FBindMatrix.basis.y = FFixedUp
			FBindMatrix.basis.x = FFixedFront.cross(FFixedUp).normalized()
		elif FIsPiece:
			FBindMatrix.basis.z = RParam.AsVector3Default(Eventbus().ReadHierarchic(C.eiDisplayFront, [], ComponentGroup), FDefaultFront)
			FBindMatrix.basis.y = RParam.AsVector3Default(Eventbus().ReadHierarchic(C.eiDisplayUp, [], ComponentGroup), FDefaultUp)
	else:
		FBindMatrix = Transform3D.IDENTITY
		if FIsPiece:
			FBindMatrix.origin = RParam.AsVector3(Eventbus().ReadHierarchic(C.eiDisplayPosition, [], ComponentGroup))
		else:
			FBindMatrix.origin = Owner.DisplayPosition
		if FFixedOrientation:
			FBindMatrix.basis.z = FFixedFront
			FBindMatrix.basis.y = FFixedUp
		else:
			if FIsPiece:
				FBindMatrix.basis.z = RParam.AsVector3Default(Eventbus().ReadHierarchic(C.eiDisplayFront, [], ComponentGroup), FDefaultFront)
			else:
				FBindMatrix.basis.z = Owner.DisplayFront
			if FIsPiece:
				FBindMatrix.basis.y = RParam.AsVector3Default(Eventbus().ReadHierarchic(C.eiDisplayUp, [], ComponentGroup), FDefaultUp)
			else:
				FBindMatrix.basis.y = Owner.DisplayUp
		FBindMatrix.basis.x = FBindMatrix.basis.z.cross(FBindMatrix.basis.y).normalized()
	FBindMatrix = FBindMatrixAdjustments.Apply(FBindMatrix)
	FBindMatrix = FBindMatrix * RMatrix.CreateRotationPitchYawRoll(FRotationOffset) * RMatrix.CreateTranslation(FinalModelOffset())
	if FHasFixedHeight:
		FBindMatrix.origin.y = FFixedHeight


func Update() -> void:
	FSize = RParam.AsVector3Default(Eventbus().Read(C.eiSize, [], []), Vector3.ONE) \
		* RParam.AsVector3Default(Eventbus().Read(C.eiSize, [], ComponentGroup), Vector3.ONE)


func FinalModelOffset() -> Vector3:
	return FOffset * FModelsize * FSize + FFixedOffset


func FinalSize() -> Vector3:
	var EventSize := 1.0
	if FScaleWithEvent:
		if FScaleEvent == C.eiCollisionRadius:
			EventSize = Owner.CollisionRadius
		else:
			EventSize = RParam.AsSingle(Eventbus().ReadHierarchic(FScaleEvent, [], ComponentGroup))
	var Result := Vector3.ONE * maxf(FMinScaleEvent, minf(FMaxScaleEvent, EventSize))
	if FScaleWithResource != C.reNone:
		var percentage := BC.ResourcePercentage(FScaleWithResource, Owner.Balance(FScaleWithResource, ComponentGroup),
			ResourceOverride(FScaleWithResource, Owner.Cap(FScaleWithResource, ComponentGroup), FOveriddenResourceCap))
		Result = Result * (FResourceScaleFactorMin + (FResourceScaleFactorMax - FResourceScaleFactorMin) * percentage)
	if not FScaleWithEvent or not GAMEPLAY_SCALE_EVENTS.has(FScaleEvent):
		if not FIgnoreModelSize:
			Result = Result * FModelsize
		if not FIgnoreSize:
			Result = Result * FSize
	return Result


## ResourceOverride (BaseConflict.Types.Shared.pas:174)
static func ResourceOverride(ResourceType: int, Resource, OverrideValue: float):
	if OverrideValue <= 0:
		return Resource
	if BC.IsIntResource(ResourceType):
		return int(roundf(OverrideValue))
	return RParam.ToSingle(OverrideValue)


## Called every frame; static visualizers apply once.
func Idle() -> void:
	if not FIsStatic or not FFirstStaticApplyDone:
		Update()
		Apply()
		FFirstStaticApplyDone = true


func SetModelSize(ModelSize: float) -> void:
	if ModelSize > 0:
		FModelsize = ModelSize


func IsVisible() -> bool:
	var Result := RParam.AsBooleanDefaultTrue(Eventbus().ReadHierarchic(C.eiVisible, [], ComponentGroup)) \
		and not RParam.AsBoolean(Eventbus().Read(C.eiExiled, []))
	if FVisibleWithWelaReady:
		Result = Result and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FWelaReadyGroup))
	if FVisibleWithResource != C.reNone:
		Result = Result and RParam.AsInteger(Owner.Balance(FVisibleWithResource, ComponentGroup)) \
			== RParam.AsInteger(Owner.Cap(FVisibleWithResource, ComponentGroup))
	if FVisibleWithOption:
		Result = Result and TOptionManager.GetBooleanOption(FVisibilityOption)
	if not FVisibleWithUnitPropertyMustHave.is_empty():
		Result = Result and DSet.IsSubset(FVisibleWithUnitPropertyMustHave, Owner.UnitProperties())
	if not FVisibleWithUnitPropertyMustNotHave.is_empty():
		Result = Result and not DSet.Intersects(FVisibleWithUnitPropertyMustNotHave, Owner.UnitProperties())
	return Result


func IsBoundToBone() -> bool:
	return FBoundZone != ""


func OnIdle() -> bool:
	Idle()
	return true


func OnModelSize(Size) -> bool:
	SetModelSize(RParam.AsSingle(Size))
	return true


# ---- fluent setters (script API) ----------------------------------------------------------------------------

func SetModelOffset(OffsetX = null, OffsetY = null, OffsetZ = null) -> TVisualizerComponent:
	if OffsetX is Vector3:
		FOffset = OffsetX
	else:
		FOffset = Vector3(OffsetX, OffsetY, OffsetZ)
	return self


func SetModelRotationOffset(Offset = null) -> TVisualizerComponent:
	FRotationOffset = Offset
	return self


func BindToSubPosition(ZoneName = null) -> TVisualizerComponent:
	FBoundZone = ZoneName
	FBindGroup = ComponentGroup
	return self


func BindToSubPositionGroup(ZoneName = null, TargetGroup = null) -> TVisualizerComponent:
	FBoundZone = ZoneName
	FBindGroup = DSet.Make(TargetGroup)
	return self


func InvertXBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindInvertX = true
	return self


func InvertYBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindInvertY = true
	return self


func InvertZBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindInvertZ = true
	return self


func SwapXYBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindSwapXY = true
	return self


func SwapXZBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindSwapXZ = true
	return self


func SwapYZBindMatrix() -> TVisualizerComponent:
	FBindMatrixAdjustments.BindSwapYZ = true
	return self


## Draws the bind matrix in the original (LinePool); the port has no debug line pool yet.
func DebugBindMatrix() -> TVisualizerComponent:
	FBindDebug = true
	return self


func ScaleWith(Event = null) -> TVisualizerComponent:
	FScaleEvent = Event
	FScaleWithEvent = true
	return self


func ScaleWithResource(Resource = null, ScaleFactorMin = null, ScaleFactorMax = null) -> TVisualizerComponent:
	FScaleWithResource = Resource
	FResourceScaleFactorMin = RParam.ToSingle(ScaleFactorMin)
	FResourceScaleFactorMax = RParam.ToSingle(ScaleFactorMax)
	return self


func OverrideResourceCap(NewCap = null) -> TVisualizerComponent:
	FOveriddenResourceCap = RParam.ToSingle(NewCap)
	return self


func MaxScale(Maximum = null) -> TVisualizerComponent:
	FMaxScaleEvent = RParam.ToSingle(Maximum)
	return self


func ScaleRange(Minimum = null, Maximum = null) -> TVisualizerComponent:
	FMinScaleEvent = RParam.ToSingle(Minimum)
	FMaxScaleEvent = RParam.ToSingle(Maximum)
	return self


func IgnoreSize() -> TVisualizerComponent:
	FIgnoreSize = true
	return self


func IgnoreModelSize() -> TVisualizerComponent:
	FIgnoreModelSize = true
	return self


## Set a model offset of y = GROUND_EPSILON.
func IsDecal() -> TVisualizerComponent:
	SetModelOffset(Vector3(0, 1, 0) * C.GROUND_EPSILON)
	return self


func IsPiece() -> TVisualizerComponent:
	FIsPiece = true
	return self


func FixedHeight(Height = null) -> TVisualizerComponent:
	FHasFixedHeight = true
	FFixedHeight = RParam.ToSingle(Height)
	return self


func FixedHeightGround() -> TVisualizerComponent:
	FHasFixedHeight = true
	FFixedHeight = C.GROUND_EPSILON
	return self


func FixedOffsetGround() -> TVisualizerComponent:
	FFixedOffset.y = C.GROUND_EPSILON
	return self


func FixedOrientationDefault() -> TVisualizerComponent:
	FFixedOrientation = true
	FFixedFront = Vector3(0, 0, 1)
	FFixedUp = Vector3(0, 1, 0)
	return self


func FixedOrientation(FrontX = null, FrontY = null, FrontZ = null) -> TVisualizerComponent:
	FFixedOrientation = true
	FFixedFront = Vector3(FrontX, FrontY, FrontZ).normalized()
	FFixedUp = Vector3(0, 1, 0)
	return self


func FixedOrientationUp(UpX = null, UpY = null, UpZ = null) -> TVisualizerComponent:
	FFixedOrientation = true
	FFixedUp = Vector3(UpX, UpY, UpZ).normalized()
	return self


func FixedOrientationAngle(FrontX = null, FrontY = null, FrontZ = null) -> TVisualizerComponent:
	FFixedOrientation = true
	var angles := Vector3(FrontX, FrontY, FrontZ)
	FFixedFront = RMatrix.RotatePitchYawRoll(Vector3(0, 0, 1), angles)
	FFixedUp = RMatrix.RotatePitchYawRoll(Vector3(0, 1, 0), angles)
	return self


func DefaultOrientation(FrontX = null, FrontY = null, FrontZ = null) -> TVisualizerComponent:
	FDefaultFront = Vector3(FrontX, FrontY, FrontZ)
	return self


func DefaultOrientationUp(UpX = null, UpY = null, UpZ = null) -> TVisualizerComponent:
	FDefaultUp = Vector3(UpX, UpY, UpZ)
	return self


func ShowAsTeam(FixTeamID = null) -> TVisualizerComponent:
	FFixedTeamID = FixTeamID
	return self


func VisibleWithOption(Option = null) -> TVisualizerComponent:
	FVisibilityOption = Option
	FVisibleWithOption = true
	return self


func VisibleWithWelaReady() -> TVisualizerComponent:
	FVisibleWithWelaReady = true
	FWelaReadyGroup = ComponentGroup
	return self


func VisibleWithWelaReadyGrouped(Group = null) -> TVisualizerComponent:
	FVisibleWithWelaReady = true
	FWelaReadyGroup = DSet.Make(Group)
	return self


func VisibleWithResource(ResourceID = null) -> TVisualizerComponent:
	FVisibleWithResource = ResourceID
	return self


func VisibleWithUnitPropertyMustHave(Properties = null) -> TVisualizerComponent:
	FVisibleWithUnitPropertyMustHave = DSet.Make(Properties)
	return self


func VisibleWithUnitPropertyMustNotHave(Properties = null) -> TVisualizerComponent:
	FVisibleWithUnitPropertyMustNotHave = DSet.Make(Properties)
	return self
