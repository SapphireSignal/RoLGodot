class_name TMeshEffect
extends TObject
## Port of TMeshEffect (BaseConflict.EntityComponents.Client.Visuals.pas:472, implementation :5210): a change of how
## a mesh is drawn, as a custom shader (a set of blocks over the standard shader, TShader) inserted into the mesh's
## CustomShader list by its order value (smallest drawn first = outermost block), with a SetUp that sets its shader
## constants every drawn frame. TMeshComponent keeps the effects in a stack; only one effect of a class is mounted
## at a time (their blocks would clash). Read docs/assets.md ("Mesh effects").
##
## Port: Create takes two optional parameters in every class of the family (GDScript overrides can't drop
## parameters). The original's default order value is the class's RTTI address (abs(ClassInfo)), which no port can
## reproduce; classes without an ORDER_VALUE get a stable large number instead (only TMeshEffectSoulExtract, unused).

const C = preload("res://src/runtime/dws/dws_const.gd")
const PATH_GRAPHICS_EFFECTS :="\\Graphics\\Effects\\"
const PATH_GRAPHICS_EFFECTS_TEXTURES := "\\Graphics\\Effects\\Textures\\"
const PATH_GRAPHICS_SHADER := "\\Graphics\\Effects\\Shader\\"

var FOwningEntity = null
var FOwningComponent = null  # TMeshComponent
var FMesh: TMesh = null
var FCustomShader := ""
var FOriginalGlowTexture := ""
var FHasShaderSetup := false
var FManaged := false
var FColorIdentityOverride := false
var FBlendMode := TMesh.BLEND_LINEAR
var FNeedOwnPass: Array = []
var FOwnPasses := 0
var FGlowOverride := false
var FUseGlowOverride := false
var FGlowTextureOverride := false
var FOwnPassBlocks := false
var FIsMounted := false
var FColorIdentity := 0
## smallest value gets rendered first
var FOrderValue := 0

## If any effect is important it will be applied alone. If multiple the first is taken.
var Managed: bool:
	get:
		return FManaged
	set(value):
		FManaged = value
var OrderValue: int:
	get:
		return FOrderValue
var NeedOwnPass: Array:
	get:
		return FNeedOwnPass
var IsMounted: bool:
	get:
		return FIsMounted
var ColorIdentity: int:
	get:
		return FColorIdentity


## RColor.Create(Cardinal): an ARGB cardinal ($AARRGGBB) as a Color.
static func RColor(argb: int) -> Color:
	return Color.hex(((argb & 0xFFFFFF) << 8) | ((argb >> 24) & 0xFF))


func Create(_Param0 = null, _Param1 = null):
	FOrderValue = ClassName().hash() & 0x3FFFFFFF
	return self


## CreateEmpty: the object without the constructor's work (Clone fills it).
func CreateEmpty():
	return self


## A new, empty object of this effect's class (Clone(nil) of the subclasses).
func _NewOfMyClass() -> TMeshEffect:
	return (get_script() as Script).new()


## Clone: copies the base fields into Effect (the subclass made it).
func Clone(Effect: TMeshEffect) -> TMeshEffect:
	assert(Effect != null, "TMeshEffect.Clone: Base class got no initialized cloning class!")
	var Result := Effect
	Result.FOwningEntity = FOwningEntity
	Result.FMesh = FMesh
	Result.FCustomShader = FCustomShader
	Result.FHasShaderSetup = FHasShaderSetup
	Result.FColorIdentity = FColorIdentity
	Result.FUseGlowOverride = FUseGlowOverride
	Result.FNeedOwnPass = FNeedOwnPass.duplicate()
	Result.FOwnPasses = FOwnPasses
	Result.FOwnPassBlocks = FOwnPassBlocks
	Result.FGlowTextureOverride = FGlowTextureOverride
	Result.FBlendMode = FBlendMode
	Result.FOrderValue = FOrderValue
	Result.FColorIdentityOverride = FColorIdentityOverride
	return Result


## Only for own passes.
func Additive():
	FBlendMode = TMesh.BLEND_ADDITIVE
	return self


func OverrideGlowTexture():
	FGlowTextureOverride = true
	return self


func OverrideColorIdentity(ColorIdentity_ = null):
	FColorIdentityOverride = true
	FColorIdentity = int(ColorIdentity_)
	return self


func Reset() -> void:
	pass


## Gives the effect to every mesh of the entity: this object to the first, clones to the others.
func AssignToEntity(Entity = null) -> void:
	InitOnEntity(Entity)
	var found := [false]
	var effect := self
	Entity.Eventbus.Trigger(C.eiEnumerateComponents, [func(Component) -> void:
		if Component is TMeshComponent:
			if found[0]:
				Component.AddMeshEffect(effect.Clone(null))
			else:
				Component.AddMeshEffect(effect)
			found[0] = true])


func InitShader(ShaderName: String) -> void:
	if ShaderName == "":
		return
	FHasShaderSetup = true
	FCustomShader = ShaderName


func Expired() -> bool:
	return false


func InitializeOnMesh(Mesh: TMesh) -> void:
	if IsMounted:
		return
	FMesh = Mesh
	# build mesh shader description
	var Desc := TMesh.RMeshShader.new(FCustomShader, SetUpShader if FHasShaderSetup else Callable(),
		FNeedOwnPass.duplicate(), FOwnPasses, FOwnPassBlocks, FBlendMode, self)
	# insert shader at the right position regarding its order value
	var Inserted := false
	for i in FMesh.CustomShader.size():
		if FMesh.CustomShader[i].Tag.OrderValue > OrderValue:
			Inserted = true
			FMesh.CustomShader.insert(i, Desc)
			break
	if not Inserted:
		FMesh.CustomShader.append(Desc)
	# global overrides
	if FUseGlowOverride and (FMesh.GlowTexture == "" or FGlowTextureOverride):
		FGlowOverride = true
		var DefaultGlowTexture := "WhiteGlow.tga"
		match FColorIdentity:
			C.ecGreen:
				DefaultGlowTexture = "GreenGlow.tga"
			C.ecBlack:
				DefaultGlowTexture = "BlackGlow.tga"
			C.ecBlue:
				DefaultGlowTexture = "BlueGlow.tga"
			C.ecColorless:
				DefaultGlowTexture = "ColorlessGlow.tga"
		FOriginalGlowTexture = FMesh.GlowTexture
		FMesh.GlowTexture = PATH_GRAPHICS_EFFECTS_TEXTURES + DefaultGlowTexture
	FIsMounted = true
	FMesh.ApplyMaterial()


func FinalizeOnMesh() -> void:
	if not IsMounted:
		return
	if FGlowOverride:
		FMesh.GlowTexture = FOriginalGlowTexture
	for i in range(FMesh.CustomShader.size() - 1, -1, -1):
		if FMesh.CustomShader[i].Tag == self:
			FMesh.CustomShader.remove_at(i)
	FIsMounted = false
	FMesh.ApplyMaterial()


func InitOnEntity(Entity) -> void:
	FOwningEntity = Entity
	if not FColorIdentityOverride:
		FColorIdentity = RParam.AsEnumType(Entity.Eventbus.Read(C.eiColorIdentity, []))


## SetUp of the effect's custom shader: CurrentShader is a TMesh.ShaderBinding, Stage a render stage (TMesh.RS_*).
func SetUpShader(_CurrentShader, _Stage: int, _PassIndex: int) -> void:
	pass
