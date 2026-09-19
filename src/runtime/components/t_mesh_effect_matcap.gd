class_name TMeshEffectMatcap
extends TMeshEffectGeneric
## Port of TMeshEffectMatcap (BaseConflict.EntityComponents.Client.Visuals.pas:719, implementation :5660): reflects a
## "material capture" texture (tsVariable2) by the screen direction of the normal (MatcapShader.fx), weighted by the
## material's specular intensity and tinting; the nexus and lane tower crystals use MatcapCrystal<team>.png. Without
## a texture: MatcapDefault.png.

const ORDER_VALUE := 9993


func Create(_Param0 = null, _Param1 = null):
	super("MatcapShader.fx", "")
	FTextureSlot = TMesh.TS_VARIABLE2
	FOrderValue = ORDER_VALUE
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	return super(TMeshEffectMatcap.new().Create() if Effect == null else Effect)


func InitOnEntity(Entity) -> void:
	super(Entity)
	if FEffectTexture == null and FTextureName == "":
		SetTexture(PATH_GRAPHICS_EFFECTS + "Textures\\MatcapDefault.png")
