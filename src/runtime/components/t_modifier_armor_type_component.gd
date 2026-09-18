class_name TModifierArmorTypeComponent
extends TModifierComponent
## Port of TModifierArmorTypeComponent (BaseConflict.EntityComponents.Shared.Wela.pas:134, implementation :1240).
## While active, sets eiArmorType to a fixed type (SetTo) or moves a normal armor type (unarmored .. heavy) up or
## down by eiWelaModifier of its own group (default 1) steps, clamped to that range. Fortified stays as it is.

var FChangeClassIndex := 0
var FSetArmorType := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnArmorType", C.eiArmorType, C.epMiddle, C.etRead))


func OnArmorType(Previous):
	if not IsActive():
		return Previous
	var CurrentArmorType: int
	if FSetArmorType:
		CurrentArmorType = FChangeClassIndex
	else:
		CurrentArmorType = RParam.AsEnumType(Previous)
		var ChangeBy: int = FChangeClassIndex * RParam.AsIntegerDefault(Eventbus().Read(C.eiWelaModifier, [], ComponentGroup), 1)
		if BC.IsNormalArmorType(CurrentArmorType):
			CurrentArmorType = mini(C.atHeavy, maxi(C.atUnarmored, CurrentArmorType + ChangeBy))
	return CurrentArmorType


func Increase() -> TModifierArmorTypeComponent:
	FChangeClassIndex = 1
	return self


func Decrease() -> TModifierArmorTypeComponent:
	FChangeClassIndex = -1
	return self


func SetTo(ArmorType: int) -> TModifierArmorTypeComponent:
	FSetArmorType = true
	FChangeClassIndex = ArmorType
	return self
