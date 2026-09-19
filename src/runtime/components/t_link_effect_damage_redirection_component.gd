class_name TLinkEffectDamageRedirectionComponent
extends TGDEntityComponent
## Port of TLinkEffectDamageRedirectionComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:703,
## implementation :2333), server only, a link's continuous effect. On the link's eiAfterCreate it hooks the eiTakeDamage
## read of its source (eiLinkSource[0]; DestinationToSource: eiLinkDest[0]) at epHigher, i.e. before armor. Damage
## without dtIrredirectable, while the destination entity lives, is split: eiWelaModifier of its group (default 1)
## goes to the destination as its own eiTakeDamage read (types + dtIrredirectable + dtRedirected, same inflictor), whose
## answer (the damage dealt there) becomes the read's result; the rest stays as the source's Amount (a var parameter,
## so the armor and health after it see only the rest). Else the result is the Amount unchanged.
## Kept: the result replaces what earlier handlers returned; the hook dies with the link (remote subscription).

var FRedirectFromDestination := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))


func DestinationToSource() -> TLinkEffectDamageRedirectionComponent:
	FRedirectFromDestination = true
	return self


func GetDestination() -> Array:
	if FRedirectFromDestination:
		return ATarget.FromRParam(Eventbus().Read(C.eiLinkSource, []))
	return ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))


func GetSource() -> Array:
	if FRedirectFromDestination:
		return ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
	return ATarget.FromRParam(Eventbus().Read(C.eiLinkSource, []))


## Hook source eiTakeDamage.
func OnAfterCreate() -> bool:
	var Source := GetSource()
	if not ATarget.HasIndex(Source, 0):
		push_error(BuildExceptionMessage("OnAfterCreate: No source found!"))
		return true
	var Entity = Source[0].TryGetTargetEntity(GlobalEventbus().Game)
	if Entity != null:
		Entity.Eventbus.SubscribeRemote(C.eiTakeDamage, C.etRead, C.epHigher, self, "TargetTakeDamage", 3)
	return true


func TargetTakeDamage(Amount, DamageType, InflictorID):
	var RealDamageType := RParam.AsSet(DamageType)
	var Targets := GetDestination()
	if not ATarget.HasIndex(Targets, 0):
		push_error(BuildExceptionMessage("TargetTakeDamage: No destinations set!"))
		return Amount
	var Target: RTarget = Targets[0]
	var Dest = Target.TryGetTargetEntity(GlobalEventbus().Game)
	if not RealDamageType.has(C.dtIrredirectable) and Dest != null:
		var Factor := RParam.AsSingleDefault(Eventbus().Read(C.eiWelaModifier, [], ComponentGroup), 1.0)
		var NewDamageType := DSet.Make(RealDamageType + [C.dtIrredirectable, C.dtRedirected])
		# redirect percentage of damage to destination
		var Result = Dest.Eventbus.Read(C.eiTakeDamage, [RParam.ToSingle(RParam.AsSingle(Amount) * Factor),
			NewDamageType, InflictorID])
		# pass all not redirected damage
		SetVarParam(0, RParam.ToSingle(RParam.AsSingle(Amount) * (1 - Factor)))
		return Result
	return Amount
