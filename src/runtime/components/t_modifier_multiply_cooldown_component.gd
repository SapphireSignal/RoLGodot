class_name TModifierMultiplyCooldownComponent
extends TModifierComponent
## Port of TModifierMultiplyCooldownComponent (BaseConflict.EntityComponents.Shared.Wela.pas:124, implementation
## :1009). Multiplies every eiCooldown of its groups by eiWelaModifier of ValueGroup, except reads to ValueGroup.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnCooldown", C.eiCooldown, C.epMiddle, C.etRead))


func OnCooldown(Previous):
	# modify cooldown if there is a cooldown value and the read doesn't come from our value group
	if not RParam.IsEmpty(Previous) and not DSet.Intersects(TEventbus.GetCurrentEvent_CalledToGroup(), FValueGroup):
		# the original asserts a value for eiWelaModifier in ValueGroup (debug builds only)
		var Factor = Eventbus().Read(C.eiWelaModifier, [], FValueGroup)
		return L.Round(RParam.AsInteger(Previous) * RParam.AsSingleDefault(Factor, 1.0))
	return Previous
