class_name TMeshEffectTint
extends TMeshEffectWithTimekeys
## Port of TMeshEffectTint (BaseConflict.EntityComponents.Client.Visuals.pas:554, implementation :6959): blends (or
## adds) a color over the mesh (ColorOverlay.fx), its alpha times the timeline's current value.

const ORDER_VALUE := 5000

var FColor := Color(0, 0, 0, 0)
var FAdditive := false


func Create(Duration = null, Color_ = null):
	super(Duration)
	FColor = RColor(0 if Color_ == null else int(Color_))
	InitShader(PATH_GRAPHICS_SHADER + "ColorOverlay.fx")
	FOrderValue = ORDER_VALUE
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result := super(TMeshEffectTint.new().Create(FTimer.Interval, 0) if Effect == null else Effect)
	Result.FColor = FColor
	Result.FAdditive = FAdditive
	return Result


func Additive():
	FAdditive = true
	return self


func SetUpShader(CurrentShader, Stage: int, PassIndex: int) -> void:
	super(CurrentShader, Stage, PassIndex)
	CurrentShader.SetShaderConstant("co_color", Vector4(FColor.r, FColor.g, FColor.b, FColor.a * CurrentValue()))
	CurrentShader.SetShaderConstant("co_additive", FAdditive)
