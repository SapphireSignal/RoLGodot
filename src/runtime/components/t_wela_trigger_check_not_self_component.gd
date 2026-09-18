class_name TWelaTriggerCheckNotSelfComponent
extends TWelaTriggerCheckTakeDamageComponent
## Port of TWelaTriggerCheckNotSelfComponent (BaseConflict.EntityComponents.Shared.Wela.pas:540, implementation
## :3196). Ignores damage the unit dealt to itself.


func IsValid(_Amount: float, _DamageType: Array, InflictorID: int) -> bool:
	return Owner.ID != InflictorID
