class_name TMeshComponent
extends TVisualizerComponent
## Port of TMeshComponent (BaseConflict.EntityComponents.Client.Visuals.pas:870, implementation :2807) and the
## conditional textures (TConditionalMeshTexture*, :845, :6551, :6561, :7151). Displays a TMesh at the bind matrix
## of TVisualizerComponent with the final size, plays the animations the entity asks for (eiPlayAnimation) and
## answers sub positions (bones, head, top, ground...) and the bounding sphere.
## Not ported yet: the mesh effects (TMeshEffect*, the effect stack is kept empty), the death decay
## (TUnitDecayManagerComponent: a dying mesh with a death effect only plays its death animation), outline drawing
## (the values reach TMesh, the outline pass is not ported).

const SIZE_FACTOR_3DSMAX = 2.0 / 125.0
## PATH_GRAPHICS_ENVIRONMENT: meshes from here are static (applied once).
const GRAPHICS_ENVIRONMENT := "/graphics/environment/"
## TMeshComponent.Idle BORDER_TEAMCOLORS (ARGB)
const BORDER_TEAMCOLORS = [0xFF404040, 0xFF0036FF, 0xFFFF1818, 0xFF9600FF, 0xFF00FF00, 0xFFFF0000]


## TConditionalMeshTexture: a texture used while Check holds (later entries win).
class TConditionalMeshTexture:
	var TextureType := 0
	var TextureFilename := ""

	func Check(_Component) -> bool:
		return false


class TConditionalMeshTextureTeam extends TConditionalMeshTexture:
	var TargetTeamID := 0

	func Check(Component) -> bool:
		return TMeshComponent.GetDisplayedTeam(Component.Owner, Component.Owner.TeamID()) == TargetTeamID


class TConditionalMeshTextureUnitProperty extends TConditionalMeshTexture:
	var MustHaveAny: Array = []

	func Check(Component) -> bool:
		return DSet.IsSubset(MustHaveAny, Component.Owner.UnitProperties())


class TConditionalMeshTextureResource extends TConditionalMeshTexture:
	const Shared = preload("res://src/runtime/base_conflict_constants.gd")
	var ResourceType := 0
	var Comparator := 0
	var ReferenceValue := 0.0
	var ComponentGroup: Array = []

	func Check(Component) -> bool:
		var Resource = Component.Owner.Balance(ResourceType, ComponentGroup)
		return Resource != null and Shared.ResourceCompare(ResourceType, Resource, Comparator, ReferenceValue)


var FMesh: TMesh = null
var FDeathColorIdentityOverrideActive := false
var FDeathColorIdentityOverride := 0
var FDecaying := false
var FIgnoreScalingForAnimations := false
var FIsEffectMesh := false
var FNoWalkOffset := false
var FConditionalTexturesDirty := false
var FAnimationSpeed := {}
var FSizeNormalization := 1.0
var FModelFileName := ""
var FOutlineColor := Color(0, 0, 0, 0)
var FLastBoundings := [Vector3.ZERO, 0.0]  # RSphere: center, radius
var FHasAttackLoop := false
var FHighlightedThisFrame := false
var FOnlyOutline := false
var FColorHasBeenAdjusted := false
var FUsesGlobalShadingReduction := false
var FShadingReductionFromTerrain := false
var FCastsNoShadows := false
var FEffectStack: Array = []
var FZoneToBoneBinding := {}
var FFollowingDefaultAnimation := {}
var FBoneAdjustments := {}  # lower-case zone -> RMatrixAdjustments
var FOriginalTextures := ["", "", "", ""]  # by EnumMeshTexture
var FConditionalTextures: Array = []
var FAlternatingZoneIndex := 0
var FAlternatingZones := {}


## GetDisplayedTeam (BaseConflict.Constants.Client.pas:570): with fixed team colors the own team shows as team 1,
## every other as team 2. Needs the client game's commander manager (not ported yet: the team shows as it is).
static func GetDisplayedTeam(Entity, TeamID: int) -> int:
	var game = Entity.GlobalEventbus.Game if Entity != null and Entity.GlobalEventbus != null else null
	if game != null and game.get("CommanderManager") != null and TOptionManager.GetBooleanOption(C.coGameplayFixedTeamColors) \
			and TeamID != 0:
		return 1 if game.CommanderManager.ActiveCommanderTeamID == TeamID else 2
	return TeamID


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDrawOutline", C.eiDrawOutline, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnAfterDeserialization", C.eiAfterCreate, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnChangeCommander", C.eiChangeCommander, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnColorAdjustment", C.eiColorAdjustment, C.epLast, C.etTrigger))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnPlayAnimation", C.eiPlayAnimation, C.epLast, C.etTrigger))
	e.append(XEvent("OnSubPositionByString", C.eiSubPositionByString, C.epFirst, C.etRead))
	e.append(XEvent("OnUnitPropertyChanged", C.eiUnitPropertyChanged, C.epLast, C.etTrigger))
	e.append(XEvent("OnBoundings", C.eiBoundings, C.epFirst, C.etRead))
	e.append(XEvent("OnClientOption", C.eiClientOption, C.epLast, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnSetResource", C.eiResourceBalance, C.epLast, C.etWrite))
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))


func Create(Owner = null, Meshpath = "") -> TEntityComponent:
	return CreateGrouped(Owner, [], Meshpath)


func CreateGrouped(Owner = null, Group = [], Meshpath = "") -> TEntityComponent:
	super(Owner, Group)
	FModelFileName = Meshpath
	LoadMesh()
	return self


func Destroy() -> void:
	FEffectStack.clear()
	FConditionalTextures.clear()
	if not FDecaying and FMesh != null:
		TMesh.Release(FMesh)
	FMesh = null
	super()


func LoadMesh() -> void:
	if FModelFileName == "":
		return
	var Meshpath := TMesh.ResolveDescriptor(FModelFileName)
	if Meshpath.contains(GRAPHICS_ENVIRONMENT):
		FIsStatic = true
	FMesh = TMesh.CreateFromFile(FModelFileName)
	if FMesh == null:
		# the original raises: the entity is not created
		push_error("TMeshComponent: failed to load mesh '%s'" % FModelFileName)
		return
	FMesh.DrivenByController = true
	GFXD.AddToScene(FMesh)
	FOriginalTextures = [FMesh.DiffuseTexture, FMesh.NormalTexture, FMesh.MaterialTexture, FMesh.GlowTexture]
	FSizeNormalization = 1.0
	FMesh.SetScale(FSizeNormalization)
	FMesh.ShadingReductionOverride = TOptionManager.GetSingleOption(C.coEngineGlobalShadingReduction)
	FMesh.ApplyMaterial()
	if FMesh.AnimationController.HasAnimation(C.ANIMATION_STAND):
		FMesh.AnimationController.DefaultAnimation = C.ANIMATION_STAND


func Apply() -> void:
	super()
	if FMesh != null:
		FMesh.ScaleVector = FinalSize()
		FMesh.Position = FBindMatrix.origin
		FMesh.SetFront(FBindMatrix.basis.z)
		FMesh.SetUp(FBindMatrix.basis.y)
		FMesh.ComputeTransformationMatrix()


func FinalSize() -> Vector3:
	return FSizeNormalization * super()


func Idle() -> void:
	super()
	if FMesh == null:
		return
	if FConditionalTexturesDirty:
		CheckConditionalTextures()
	var material_before := [FMesh.ColorAdjustment, FMesh.AbsoluteHSV, FMesh.ShadingReduction]
	FMesh.Outline = FHighlightedThisFrame
	if FOutlineColor.a == 0.0:
		var TeamID := clampi(Owner.TeamID(), 0, BORDER_TEAMCOLORS.size() - 1)
		FMesh.OutlineColor = Color.hex(_argb_to_rgba(BORDER_TEAMCOLORS[TeamID]))
	else:
		FMesh.OutlineColor = FOutlineColor
	FMesh.OnlyOutline = FHighlightedThisFrame and FOnlyOutline
	FHighlightedThisFrame = false
	if not FColorHasBeenAdjusted:
		FMesh.ColorAdjustment = Vector3.ZERO
		FMesh.AbsoluteHSV = Vector3.ZERO
	FMesh.SetVisible(IsVisible())
	FMesh.CastsNoShadow = FCastsNoShadows
	var ClientMap = _client_map()
	if ClientMap != null and FShadingReductionFromTerrain and ClientMap.Terrain != null:
		FMesh.ShadingReduction = ClientMap.Terrain.ShadingReduction
	if material_before != [FMesh.ColorAdjustment, FMesh.AbsoluteHSV, FMesh.ShadingReduction]:
		FMesh.ApplyMaterial()


static func _argb_to_rgba(argb: int) -> int:
	return ((argb & 0xFFFFFF) << 8) | ((argb >> 24) & 0xFF)


## The client game's map (BaseConflict.Globals.Client ClientMap), if there is one.
func _client_map():
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	return game.get("ClientMap") if game != null else null


func CheckConditionalTextures() -> void:
	if FMesh != null:
		var textures: Array = FOriginalTextures.duplicate()
		for Conditional: TConditionalMeshTexture in FConditionalTextures:
			if Conditional.Check(self):
				textures[Conditional.TextureType] = Conditional.TextureFilename
		if textures != [FMesh.DiffuseTexture, FMesh.NormalTexture, FMesh.MaterialTexture, FMesh.GlowTexture]:
			FMesh.DiffuseTexture = textures[C.mtDiffuse]
			FMesh.NormalTexture = textures[C.mtNormal]
			FMesh.MaterialTexture = textures[C.mtMaterial]
			FMesh.GlowTexture = textures[C.mtGlow]
			FMesh.ApplyMaterial()
	FConditionalTexturesDirty = false


func ConditionalTexturesDirty() -> void:
	FConditionalTexturesDirty = true


# ---- event handlers ---------------------------------------------------------------------------------------------

func OnAfterDeserialization() -> bool:
	Apply()
	ConditionalTexturesDirty()
	return true


func OnBoundings(Previous):
	if Previous == null and not FIsEffectMesh:
		if FMesh != null:
			FLastBoundings = FMesh.BoundingSphereTransformed()
		return FLastBoundings
	return Previous


func OnChangeCommander(_Index) -> bool:
	ConditionalTexturesDirty()
	return true


func OnClientOption(ChangedOption) -> bool:
	if FMesh != null:
		match RParam.AsEnumType(ChangedOption):
			C.coEngineGlobalShadingReduction:
				FMesh.ShadingReductionOverride = TOptionManager.GetSingleOption(C.coEngineGlobalShadingReduction)
				FMesh.ApplyMaterial()
			C.coGameplayFixedTeamColors:
				ConditionalTexturesDirty()
	return true


## [ScriptExcludeMember] Recolorize the mesh (the absolute flags are one flag per channel in the original; the port's
## shader takes one absolute switch).
func OnColorAdjustment(ColorAdjustment, _absH, _absS, _absV) -> bool:
	if FMesh != null:
		FColorHasBeenAdjusted = true
		FMesh.ColorAdjustment = RParam.AsVector3(ColorAdjustment)
		FMesh.AbsoluteHSV = RParam.AsVector3(ColorAdjustment)
		FMesh.ApplyMaterial()
	return true


func OnDie(_KillerID, _KillerCommanderID) -> bool:
	if FIsEffectMesh or FMesh == null:
		return true
	if FMesh.AnimationController.HasAnimation(C.ANIMATION_DEATH):
		FMesh.AnimationController.Play(C.ANIMATION_DEATH)
	else:
		FMesh.AnimationController.Pause()
	# not ported yet: with udHasDeathEffect the mesh goes to ClientGame.DecayManager (TUnitDecayManagerComponent)
	return true


func OnDrawOutline(Color_, OnlyOutline) -> bool:
	if FIsEffectMesh:
		return true
	FHighlightedThisFrame = true
	FOutlineColor = Color_ if Color_ is Color else Color(0, 0, 0, 0)
	FOnlyOutline = RParam.AsBoolean(OnlyOutline)
	return true


func OnFire(_Targets) -> bool:
	FAlternatingZoneIndex = FAlternatingZoneIndex + 1
	return true


func OnUnitPropertyChanged(ChangedUnitProperties, Removed) -> bool:
	ConditionalTexturesDirty()
	if FMesh != null:
		if DSet.Intersects([C.upFrozen, C.upBanished, C.upPetrified], RParam.AsSet(ChangedUnitProperties)):
			if RParam.AsBoolean(Removed):
				FMesh.AnimationController.Resume()
			else:
				FMesh.AnimationController.Pause()
	return true


func OnSetResource(_ResourceID, _Amount) -> bool:
	ConditionalTexturesDirty()
	return true


## A zone's matrix (game space): a bone of the mesh (after BindZoneToBone and the bone adjustments), else head /
## top / ground / pivot / bottom from the mesh's box, else the center of its bounding sphere.
func OnSubPositionByString(Name_, PrevValue):
	if PrevValue != null or not IsVisible():
		return PrevValue
	# hack to prevent meshes added to entity dynamically from answering position requests
	var called: Array = TEventbus.CurrentEvent_CalledToGroup
	if (not called.is_empty() and not DSet.Intersects(called, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])) or FMesh == null:
		return PrevValue
	var ZoneName := RParam.AsString(Name_).to_lower()
	var AlternatingZoneCount: int = FAlternatingZones.get(ZoneName, 0)
	if AlternatingZoneCount > 1:
		ZoneName = ZoneName + str(FAlternatingZoneIndex % AlternatingZoneCount)
	# translate predefined zones to bones
	var BoneName: String = FZoneToBoneBinding.get(ZoneName, ZoneName)
	var Pos = FMesh.TryGetBonePosition(BoneName)
	if Pos != null:
		var BoneMatrix: Transform3D = Pos
		if FBoneAdjustments.has(ZoneName):
			BoneMatrix = FBoneAdjustments[ZoneName].Apply(BoneMatrix)
		return BoneMatrix
	var BoneMatrix := Transform3D.IDENTITY
	BoneMatrix.basis = Basis(FMesh.Left(), FMesh.Up, FMesh.Front)
	var Position := Vector3.ZERO
	if ZoneName == C.BIND_ZONE_HEAD:
		Position = Vector3(FMesh.Position.x, FMesh.BoundingBoxTransformed().end.y * 0.8, FMesh.Position.z)
	elif ZoneName == C.BIND_ZONE_TOP:
		Position = Vector3(FMesh.Position.x, FMesh.BoundingBoxTransformed().end.y, FMesh.Position.z)
	elif ZoneName == C.BIND_ZONE_GROUND:
		Position = Vector3(FMesh.Position.x, C.GROUND_EPSILON, FMesh.Position.z)
	elif ZoneName == C.BIND_ZONE_PIVOT or ZoneName == C.BIND_ZONE_BOTTOM:
		Position = FMesh.Position
	else:
		# center as default
		Position = FMesh.BoundingSphereTransformed()[0]
		if Position.y < 0:
			Position = Position * Vector3(1, -1, 1)
	Position = Position - (BoneMatrix * FinalModelOffset())
	if ZoneName == C.BIND_ZONE_GROUND:
		Position.y = C.GROUND_EPSILON
	BoneMatrix.origin = Position
	if FBoneAdjustments.has(ZoneName):
		BoneMatrix = FBoneAdjustments[ZoneName].Apply(BoneMatrix)
	return BoneMatrix


func OnPlayAnimation(AnimationName, AnimationPlayMode, Length) -> bool:
	if FMesh == null:
		return true
	var Controller := FMesh.AnimationController
	var AnimName := RParam.AsString(AnimationName)
	var Blend := AnimName == C.ANIMATION_WALK
	if not Controller.HasAnimation(AnimName):
		return true
	var AnimationOffset := 0
	var AnimationLength := RParam.AsInteger(Length)
	if AnimationLength <= 0:
		AnimationLength = Controller.GetAnimationInfoExtendedForItem(AnimName).Length
	var SpeedFactor: float = FAnimationSpeed.get(AnimName, 1.0)
	# special code for walkanimation
	if AnimName == C.ANIMATION_WALK:
		if not FIgnoreScalingForAnimations:
			var Speed := 1.0 / RParam.AsSingle(Eventbus().Read(C.eiSpeed, []))
			var Scale := FMesh.GetScale()
			AnimationLength = roundi(Speed * AnimationLength * Scale / FSizeNormalization * SIZE_FACTOR_3DSMAX * SpeedFactor * 0.077 * 2.5)
		else:
			AnimationLength = roundi(AnimationLength * maxf(absf(FSize.x), maxf(absf(FSize.y), absf(FSize.z))) * SpeedFactor)
		# test for randomness in walk cycle to have same units look more different
		if not FNoWalkOffset:
			AnimationOffset = roundi(AnimationLength * randf() * 0.7)
	else:
		AnimationLength = roundi(AnimationLength * SpeedFactor)
	var FollowingDefault: String = FFollowingDefaultAnimation.get(AnimName, "")
	if FollowingDefault != "" and Controller.HasAnimation(FollowingDefault):
		Controller.DefaultAnimation = FollowingDefault
	elif AnimName == C.ANIMATION_ATTACK and FHasAttackLoop and Controller.HasAnimation(C.ANIMATION_ATTACK_LOOP):
		Controller.DefaultAnimation = C.ANIMATION_ATTACK_LOOP
	elif AnimName == C.ANIMATION_ATTACK and RParam.AsBoolean(Eventbus().Read(C.eiIsMoving, [])):
		Controller.DefaultAnimation = C.ANIMATION_WALK
	elif Controller.HasAnimation(C.ANIMATION_STAND):
		Controller.DefaultAnimation = C.ANIMATION_STAND
	Controller.Play(AnimName, RParam.AsEnumType(AnimationPlayMode), AnimationLength, Blend, AnimationOffset)
	return true


# ---- fluent setters (script API) ----------------------------------------------------------------------------

func CastsNoShadows() -> TMeshComponent:
	FCastsNoShadows = true
	return self


func ShadingReductionFromTerrain() -> TMeshComponent:
	FShadingReductionFromTerrain = true
	return self


func ApplyAutoSizeNormalization() -> TMeshComponent:
	if FMesh != null:
		var half := FMesh.GetUntransformedBoundingBox().size / 2.0
		FSizeNormalization = 1.0 / (maxf(absf(half.x), absf(half.z)) * 2.0)
	return self


func ApplyLegacySizeFactor() -> TMeshComponent:
	FSizeNormalization = SIZE_FACTOR_3DSMAX
	if FMesh != null:
		FMesh.SetScale(FSizeNormalization)
	return self


func HasAttackLoop() -> TMeshComponent:
	FHasAttackLoop = true
	return self


func NoWalkOffset() -> TMeshComponent:
	FNoWalkOffset = true
	return self


func AlternatingZone(ZoneName = null, ZoneCount = null) -> TMeshComponent:
	FAlternatingZones[String(ZoneName).to_lower()] = ZoneCount
	return self


func IgnoreScalingForAnimations() -> TMeshComponent:
	FIgnoreScalingForAnimations = true
	return self


func IsEffectMesh() -> TMeshComponent:
	FIsEffectMesh = true
	return self


func IsDecal() -> TVisualizerComponent:
	super()
	SetModelOffset(Vector3(0, 1, 0) * (C.GROUND_EPSILON / 10.0))
	return self


func SetAnimationSpeed(AnimationName = null, AnimationSpeed = null) -> TMeshComponent:
	FAnimationSpeed[AnimationName] = RParam.ToSingle(AnimationSpeed)
	return self


func CreateNewAnimationFrom(SourceAnimation = null, NewAnimationName = null, Startframe = null, Endframe = null) -> TMeshComponent:
	if FMesh == null:
		push_error("TMeshComponent.CreateNewAnimationFrom: no mesh")
		return self
	FMesh.CreateNewAnimation(NewAnimationName, SourceAnimation, Startframe, Endframe)
	var Controller := FMesh.AnimationController
	if NewAnimationName == C.ANIMATION_STAND and Controller.DefaultAnimation == "" and Controller.HasAnimation(C.ANIMATION_STAND):
		Controller.DefaultAnimation = C.ANIMATION_STAND
	return self


## For "FBX import": animation clips cut out of the file's take (FBX_DEFAULT_ANIMATIONTRACK).
func CreateNewAnimation(AnimationName = null, Startframe = null, Endframe = null) -> TMeshComponent:
	return CreateNewAnimationFrom(TMesh.FBX_DEFAULT_ANIMATIONTRACK, AnimationName, Startframe, Endframe)


func SetFollowingDefaultAnimation(AnimationName = null, FollowingDefaultAnimationName = null) -> TMeshComponent:
	FFollowingDefaultAnimation[AnimationName] = FollowingDefaultAnimationName
	return self


func BindZoneToBone(ZoneName = null, BoneName = null) -> TMeshComponent:
	FZoneToBoneBinding[String(ZoneName).to_lower()] = String(BoneName).to_lower()
	return self


func GetBoneAdjustments(BoneName: String) -> TVisualizerComponent.RMatrixAdjustments:
	var found = FBoneAdjustments.get(BoneName.to_lower())
	return found.Copy() if found != null else TVisualizerComponent.RMatrixAdjustments.new()


func SetBoneAdjustments(BoneName: String, Value: TVisualizerComponent.RMatrixAdjustments) -> void:
	FBoneAdjustments[BoneName.to_lower()] = Value


func BoneInvertX(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindInvertX = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneInvertY(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindInvertY = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneInvertZ(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindInvertZ = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneOffset(BoneName = null, OffsetX = null, OffsetY = null, OffsetZ = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.Offset = Vector3(OffsetX, OffsetY, OffsetZ)
	SetBoneAdjustments(BoneName, a)
	return self


func BoneRotation(BoneName = null, RotationX = null, RotationY = null, RotationZ = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.Rotation = Vector3(RotationX, RotationY, RotationZ)
	SetBoneAdjustments(BoneName, a)
	return self


func BoneSwapXY(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindSwapXY = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneSwapXZ(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindSwapXZ = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneSwapYZ(BoneName = null) -> TMeshComponent:
	var a := GetBoneAdjustments(BoneName)
	a.BindSwapYZ = true
	SetBoneAdjustments(BoneName, a)
	return self


func BoneSwizzleXZY(BoneName = null) -> TMeshComponent:
	return BoneSwapYZ(BoneName)


func BoneSwizzleYXZ(BoneName = null) -> TMeshComponent:
	return BoneSwapXY(BoneName)


func BoneSwizzleYZX(BoneName = null) -> TMeshComponent:
	BoneSwapXZ(BoneName)
	return BoneSwapYZ(BoneName)


func BoneSwizzleZXY(BoneName = null) -> TMeshComponent:
	BoneSwapXY(BoneName)
	return BoneSwapYZ(BoneName)


func BoneSwizzleZYX(BoneName = null) -> TMeshComponent:
	return BoneSwapXZ(BoneName)


func BindTextureToResource(TextureType = null, TextureFilename = null, ResourceType = null, Comparator = null, ReferenceValue = null, TargetGroup = null) -> TMeshComponent:
	var Conditional := TConditionalMeshTextureResource.new()
	Conditional.TextureType = TextureType
	Conditional.TextureFilename = TextureFilename
	Conditional.ResourceType = ResourceType
	Conditional.Comparator = Comparator
	Conditional.ReferenceValue = RParam.ToSingle(ReferenceValue)
	Conditional.ComponentGroup = DSet.Make(TargetGroup)
	FConditionalTextures.append(Conditional)
	return self


func BindTextureToTeam(TextureType = null, TextureFilename = null, TeamID = null) -> TMeshComponent:
	var Conditional := TConditionalMeshTextureTeam.new()
	Conditional.TextureType = TextureType
	Conditional.TextureFilename = TextureFilename
	Conditional.TargetTeamID = TeamID
	FConditionalTextures.append(Conditional)
	return self


func BindTextureToUnitProperty(TextureType = null, TextureFilename = null, MustHave = null) -> TMeshComponent:
	var Conditional := TConditionalMeshTextureUnitProperty.new()
	Conditional.TextureType = TextureType
	Conditional.TextureFilename = TextureFilename
	Conditional.MustHaveAny = DSet.Make(MustHave)
	FConditionalTextures.append(Conditional)
	return self


func DeathColorIdentityOverride(ColorIdentity = null) -> TMeshComponent:
	FDeathColorIdentityOverrideActive = true
	FDeathColorIdentityOverride = ColorIdentity
	return self
