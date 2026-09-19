class_name TMeshEffectGeneric
extends TMeshEffect
## Port of TMeshEffectGeneric (BaseConflict.EntityComponents.Client.Visuals.pas:511, implementation :5366): an effect
## with a shader and a texture bound to a slot (default tsVariable3). A texture name with %d is formatted with the
## entity's displayed team when drawn (and reloaded when that changes).

var FLastDisplayedTeamID := -1
var FTextureSlot := TMesh.TS_VARIABLE3
var FTextureName := ""
var FEffectTexture: Texture2D = null

## Paths already warned about (the original retries every drawn frame; the port warns once).
static var _missing := {}


## TTexture.CreateTextureFromFile(AbsolutePath(Filename)): a game path ("\Graphics\Effects\...") -> the imported
## texture; null (and a warning) when it does not exist.
static func LoadEffectTexture(Filename: String) -> Texture2D:
	var path := TClientMap.ResolveGamePath(Filename)
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			push_warning("TMeshEffect: can't find texture %s (%s)" % [Filename, path])
		return null
	return load(path) as Texture2D


func Create(ShaderName = null, TextureFilename = null):
	FLastDisplayedTeamID = -1
	FTextureSlot = TMesh.TS_VARIABLE3
	InitShader("" if ShaderName == null else ShaderName)
	if TextureFilename != null and TextureFilename != "":
		FEffectTexture = LoadEffectTexture(TextureFilename)
	super()
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result: TMeshEffect = _NewOfMyClass().CreateEmpty() if Effect == null else Effect
	Result = super(Result)
	Result.FLastDisplayedTeamID = FLastDisplayedTeamID
	Result.FTextureName = FTextureName
	Result.FTextureSlot = FTextureSlot
	if FEffectTexture != null:
		Result.FEffectTexture = FEffectTexture
	return Result


func SetTexture(TextureFilename = null):
	if TextureFilename != null and TextureFilename != "":
		if String(TextureFilename).contains("%d"):
			FTextureName = TextureFilename
		else:
			FEffectTexture = LoadEffectTexture(TextureFilename)
	return self


func SetUpShader(CurrentShader, _Stage: int, _PassIndex: int) -> void:
	var DisplayedTeam := TMeshComponent.GetDisplayedTeam(FOwningEntity, FOwningEntity.TeamID())
	if (FEffectTexture == null or FLastDisplayedTeamID != DisplayedTeam) and FTextureName != "":
		FLastDisplayedTeamID = DisplayedTeam
		FEffectTexture = LoadEffectTexture(FTextureName % DisplayedTeam)
	if FEffectTexture != null:
		CurrentShader.SetTexture(FTextureSlot, FEffectTexture)
