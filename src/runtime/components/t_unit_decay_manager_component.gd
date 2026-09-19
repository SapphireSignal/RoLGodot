class_name TUnitDecayManagerComponent
extends TGDEntityComponent
## Port of TUnitDecayManagerComponent (BaseConflict.EntityComponents.Client.pas:595, implementation :3070), on the
## client game's entity (TClientGame.DecayManager): the procedural death effect of units. A dying unit's mesh
## component (TMeshComponent.OnDie, units and buildings with udHasDeathEffect) hands its mesh over; the mesh keeps
## playing its death animation and draws with only the death shader for 500 ms (black: DeathShader_Black.fx, which
## darkens it; every other color: DeathShader.fx, which blows it apart glowing in the color's GLOW_COLOR_MAP color),
## then it is freed. Fur is not ported (the original sets FurIterations to 0 here).

const PATH_GRAPHICS_SHADER := "Graphics\\Effects\\Shader\\"
## BaseConflict.Constants.Client.pas GLOW_COLOR_MAP (ARGB) by EnumEntityColor
const GLOW_COLOR_MAP := [0xFF8080A0, 0xFF327AA2, 0xFF80E92B, 0xFFB83E26, 0xFF5BA9FF, 0xFFFEFF98]
const DECAY_TIME := 500


## TDecayingUnit: a handed over mesh (Mesh in the original: a Godot class name) and its decay timer.
class TDecayingUnit:
	var DecayingMesh: TMesh = null
	var DecayTimer: TTimer = TTimer.new().CreateAndStart(DECAY_TIME)

	func Destroy() -> void:
		if DecayingMesh != null and is_instance_valid(DecayingMesh):
			TMesh.Release(DecayingMesh)
		DecayingMesh = null


var FDecayingUnits: Array[TDecayingUnit] = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func Create(Owner = null) -> TEntityComponent:
	super(Owner)
	return self


func Destroy() -> void:
	for DecayingUnit: TDecayingUnit in FDecayingUnits:
		DecayingUnit.Destroy()
	FDecayingUnits.clear()
	super()


## RColor.RGB of an ARGB cardinal.
static func _rgb(argb: int) -> Vector3:
	return Vector3(((argb >> 16) & 0xFF) / 255.0, ((argb >> 8) & 0xFF) / 255.0, (argb & 0xFF) / 255.0)


## Takes over a dying unit's mesh: only the death shader of its color identity draws it until it is freed.
func AddMesh(Mesh_: TMesh, ColorIdentity: int) -> void:
	var DecayingUnit := TDecayingUnit.new()
	DecayingUnit.DecayingMesh = Mesh_
	var GlowColor := _rgb(GLOW_COLOR_MAP[ColorIdentity])
	Mesh_.CustomShader.clear()
	match ColorIdentity:
		C.ecBlack:
			Mesh_.CustomShader.append(TMesh.RMeshShader.new(PATH_GRAPHICS_SHADER + "DeathShader_Black.fx",
				func(CurrentShader, _Stage, _PassIndex):
					CurrentShader.SetShaderConstant("dsb_progress", DecayingUnit.DecayTimer.ZeitDiffProzent(true))))
		_:
			Mesh_.CustomShader.append(TMesh.RMeshShader.new(PATH_GRAPHICS_SHADER + "DeathShader.fx",
				func(CurrentShader, _Stage, _PassIndex):
					CurrentShader.SetShaderConstant("explosion_progress", DecayingUnit.DecayTimer.ZeitDiffProzent(true))
					CurrentShader.SetShaderConstant("explosion_color", GlowColor)))
	Mesh_.ApplyMaterial()
	FDecayingUnits.append(DecayingUnit)


## Frees the meshes that have decayed.
func OnIdle() -> bool:
	for i in range(FDecayingUnits.size() - 1, -1, -1):
		if FDecayingUnits[i].DecayTimer.Expired:
			FDecayingUnits[i].Destroy()
			FDecayingUnits.remove_at(i)
	return true


func DecayingCount() -> int:
	return FDecayingUnits.size()
