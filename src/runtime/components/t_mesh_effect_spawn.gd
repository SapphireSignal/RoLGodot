class_name TMeshEffectSpawn
extends TMeshEffect
## Port of TMeshEffectSpawn (BaseConflict.EntityComponents.Client.Visuals.pas:796, implementation :5421): the spawn
## animation of a new unit or building, a shader per color identity (SpawnShader_<Color>.fx, legendary black its own,
## red uses the white one) over EFFECT_TIMES[color] ms with the offset delay; the mesh is drawn without culling
## meanwhile. Blue draws in BLUE_PASSES own passes (a spinning trail) that hide the mesh's own drawing. Every drop
## gets one (Modifiers\Drop.dws); lane towers and the level 2 nexus use white with a grey fading color.
## As written, InitializeOnMesh sets the timer's interval to EFFECT_TIMES: OverrideEffectTime has no effect.
## Not ported yet: the glow stage (its glow override texture and the "glow" pass constant).

const ORDER_VALUE := 1
const BLUE_PASSES := 20
## by EnumEntityColor: ecColorless, ecBlack, ecGreen, ecRed, ecBlue, ecWhite
const EFFECT_TIMES := [1000, 2500, 2500, 2500, 1500, 2500]
## BaseConflict.Constants.Client.pas GLOW_COLOR_MAP (ARGB) by EnumEntityColor
const GLOW_COLOR_MAP := [0xFF8080A0, 0xFF327AA2, 0xFF80E92B, 0xFFB83E26, 0xFF5BA9FF, 0xFFFEFF98]

var FSpawneffectTexture: Texture2D = null
var FCullmode := "cmCCW"
var FSpawnTimer: TTimer = null
var FFrame := 0
var FOffset := 0
var FZDiff := 0.0
var FHeightFactor := 1.0
var FLegendary := false
var FOverrideColor := Color(0, 0, 0, 0)


func Create(_Param0 = null, _Param1 = null):
	FHeightFactor = 1.0
	FUseGlowOverride = true
	FSpawneffectTexture = TMeshEffectGeneric.LoadEffectTexture(PATH_GRAPHICS_EFFECTS + "Textures\\SpawnMask.png")
	FSpawnTimer = TTimer.new().CreateAndStart(2500)
	super()
	FOrderValue = ORDER_VALUE
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result: TMeshEffect = _NewOfMyClass().CreateEmpty() if Effect == null else Effect
	Result = super(Result)
	Result.FSpawneffectTexture = FSpawneffectTexture
	Result.FSpawnTimer = TTimer.new().CreateAndStart(FSpawnTimer.Interval)
	Result.FLegendary = FLegendary
	Result.FOverrideColor = FOverrideColor
	Result.FFrame = FFrame
	Result.FOffset = FOffset
	Result.FHeightFactor = FHeightFactor
	Result.FCullmode = FCullmode
	Result.FZDiff = FZDiff
	return Result


func Expired() -> bool:
	return super() or FSpawnTimer.Expired


func InitializeOnMesh(Mesh: TMesh) -> void:
	if IsMounted:
		return
	FMesh = Mesh
	FSpawnTimer.Interval = EFFECT_TIMES[FColorIdentity]
	FSpawnTimer.Start()
	FSpawnTimer.Delay(FOffset)
	FCullmode = Mesh.Cullmode
	Mesh.Cullmode = "cmNone"
	super(Mesh)


func FinalizeOnMesh() -> void:
	if not IsMounted:
		return
	FMesh.Cullmode = FCullmode
	super()


func InitOnEntity(Entity) -> void:
	super(Entity)
	var ShaderName := "SpawnShader_White.fx"
	match FColorIdentity:
		C.ecColorless:
			ShaderName = "SpawnShader_Colorless.fx"
		C.ecGreen:
			ShaderName = "SpawnShader_Green.fx"
		C.ecBlack:
			if FLegendary:
				ShaderName = "SpawnShader_Black_Legendary.fx"
				FUseGlowOverride = false
			else:
				ShaderName = "SpawnShader_Black.fx"
		C.ecBlue:
			ShaderName = "SpawnShader_Blue.fx"
			FNeedOwnPass = [TMesh.RS_WORLD, TMesh.RS_GLOW]
			FOwnPasses = BLUE_PASSES
			FOwnPassBlocks = true
	InitShader(PATH_GRAPHICS_SHADER + ShaderName)


func Legendary():
	FLegendary = true
	return self


func OffsetEffectTime(Offset = null):
	FOffset = int(Offset)
	return self


func OverrideColor(Color_ = null):
	FOverrideColor = RColor(int(Color_))
	return self


func OverrideEffectTime(Interval = null):
	FSpawnTimer.Interval = int(Interval)
	return self


func HeightFactor(Factor = null):
	FHeightFactor = RParam.ToSingle(Factor)
	return self


func SetUpShader(CurrentShader, Stage: int, PassIndex: int) -> void:
	if FFrame != GFXD.GetFrameCount():
		FFrame = GFXD.GetFrameCount()
		FZDiff = FSpawnTimer.ZeitDiffProzent(true)
	CurrentShader.SetShaderConstant("glow", 1.0 if Stage == TMesh.RS_GLOW else 0.0)
	CurrentShader.SetShaderConstant("progress", FZDiff)
	var fadingColor := RColor(GLOW_COLOR_MAP[FColorIdentity]) if FOverrideColor.a == 0.0 else FOverrideColor
	CurrentShader.SetShaderConstant("fading_color", Vector3(fadingColor.r, fadingColor.g, fadingColor.b))
	if FColorIdentity in [C.ecGreen, C.ecColorless]:
		# game space, as the shader's blocks work
		CurrentShader.SetShaderConstant("object_position", FMesh.Position - FOwningComponent.FinalModelOffset())
	var model_height := FMesh.BoundingBoxTransformed().end.y * FHeightFactor
	if FColorIdentity == C.ecBlue:
		CurrentShader.SetShaderConstant("model_height", model_height)
		CurrentShader.SetShaderConstant("pass_progress", PassIndex / float(BLUE_PASSES - 1))
	if FColorIdentity != C.ecGreen:
		CurrentShader.SetShaderConstant("model_height", model_height)
	if FColorIdentity == C.ecWhite:
		CurrentShader.SetTexture(TMesh.TS_VARIABLE3, FSpawneffectTexture)
