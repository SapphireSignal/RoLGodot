class_name TMeshEffectMetal
extends TMeshEffectGeneric
## Port of TMeshEffectMetal (BaseConflict.EntityComponents.Client.Visuals.pas:706, implementation :5615): reflects a
## sphere-mapped environment texture (tsVariable2, per color identity or ShowAsColor) on the metal parts, weighted by
## the material's specular intensity and tinting (MetalShader.fx). The snapshot has only Metal_White, _Blue and
## _Generic: green, black and red units get no texture (the original logs a warning, as the port does).

const ORDER_VALUE := 10000

var FColorOverride := C.ecColorless


func Create(_Param0 = null, _Param1 = null):
	super("MetalShader.fx", "")
	FOrderValue = ORDER_VALUE
	FTextureSlot = TMesh.TS_VARIABLE2
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result := super(TMeshEffectMetal.new().Create() if Effect == null else Effect)
	Result.FColorOverride = FColorOverride
	return Result


func InitOnEntity(Entity) -> void:
	super(Entity)
	var Color_ := FColorOverride if FColorOverride != C.ecColorless else FColorIdentity
	var MetalTexture := "Metal\\Metal_Generic.png"
	match Color_:
		C.ecWhite:
			MetalTexture = "Metal\\Metal_White.png"
		C.ecGreen:
			MetalTexture = "Metal\\Metal_Green.png"
		C.ecBlack:
			MetalTexture = "Metal\\Metal_Black.png"
		C.ecBlue:
			MetalTexture = "Metal\\Metal_Blue.png"
		C.ecRed:
			MetalTexture = "Metal\\Metal_Red.png"
	SetTexture(PATH_GRAPHICS_EFFECTS + MetalTexture)


func ShowAsColor(ColorOverride = null):
	FColorOverride = int(ColorOverride)
	return self
