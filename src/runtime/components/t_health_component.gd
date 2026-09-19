class_name THealthComponent
extends TSerializableEntityComponent
## Port of THealthComponent (BaseConflict.EntityComponents.Shared.pas:173, implementation :1003).
## Manages the health of a unit. Health and overheal are the resources reHealth / reOverheal of the entity's
## TResourceManagerComponent; the overheal cap follows the health cap (OVERHEAL_LIMIT_FACTOR).

const OVERHEAL_LIMIT_FACTOR = 2.0

var FIsAlive := false
var FInstaDeath := false
var FKillerCommanderID := 0
var FKillerID := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	if IsServerSide():
		e.append(XEvent("OnDamage", C.eiTakeDamage, C.epLower, C.etRead))
		e.append(XEvent("OnHeal", C.eiHeal, C.epLast, C.etRead))
		e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnKill", C.eiKill, C.epLast, C.etTrigger))
		e.append(XEvent("OnWriteResourceCap", C.eiResourceCap, C.epLast, C.etWrite))
	e.append(XEvent("OnIsAlive", C.eiIsAlive, C.epFirst, C.etRead))
	e.append(XEvent("OnSetIsAlive", C.eiIsAlive, C.epLast, C.etWrite))
	e.append(XEvent("OnDamageable", C.eiDamageable, C.epFirst, C.etRead))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnUnitProperies", C.eiUnitProperties, C.epMiddle, C.etRead))


## The protected fields the server sends (TSerializableEntityComponent).
func NetworkFields() -> Array:
	return ["FIsAlive", "FInstaDeath", "FKillerCommanderID", "FKillerID"]


func Create(Owner = null) -> TEntityComponent:
	super(Owner)
	FIsAlive = true
	FKillerID = -1
	FKillerCommanderID = -1
	FInstaDeath = true
	Eventbus().Write(C.eiResourceCap, [C.reOverheal, RParam.ToSingle(MaxHealth() * OVERHEAL_LIMIT_FACTOR)])
	return self


func CanBeHealed() -> bool:
	return not Owner.UnitProperties().has(C.upUnhealable) and IsAlive()


func CurrentHealth() -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiResourceBalance, [C.reHealth]))


func CurrentOverheal() -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiResourceBalance, [C.reOverheal]))


func IsAlive() -> bool:
	return RParam.AsBoolean(Eventbus().Read(C.eiIsAlive, []))


func IsInvincible() -> bool:
	return Owner.HasUnitProperty(C.upInvincible)


func MaxHealth() -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiResourceCap, [C.reHealth]))


func MaxOverheal() -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiResourceCap, [C.reOverheal]))


## Port: Game.EntityManager.TryGetEntityByID(ID, out Entity), the entity or null. The original has no nil check
## on Game; here a bus without Game (tests, no game loop yet) finds nothing.
func _TryGetEntityByID(ID: int):
	var Game = GlobalEventbus().Game
	if Game == null:
		return null
	return Game.EntityManager.TryGetEntityByID(ID)


## Returns true if alive.
func OnDamageable():
	return IsAlive() and not IsInvincible()


## Sets the unit to dead.
func OnDie(KillerID, KillerCommanderID) -> bool:
	if not IsAlive():
		return false
	FKillerID = RParam.AsInteger(KillerID)
	FKillerCommanderID = RParam.AsInteger(KillerCommanderID)
	var Killer = _TryGetEntityByID(RParam.AsInteger(KillerID))
	if Killer != null:
		Killer.Eventbus.Trigger(C.eiYouHaveKilledMeShameOnYou, [FOwner.ID])
	Eventbus().Write(C.eiIsAlive, [false])
	if FInstaDeath:
		Eventbus().Trigger(C.eiInstaDie, [KillerID, KillerCommanderID])
	if IsServerSide():
		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [FOwner.ID])
	return true


## Return alivestate.
func OnIsAlive():
	return FIsAlive


## Set alivestate.
func OnSetIsAlive(IsAlive) -> bool:
	FIsAlive = RParam.AsBoolean(IsAlive)
	if not FIsAlive:
		Eventbus().Write(C.eiResourceBalance, [C.reHealth, 0.0])
	return true


## Tags the unit with certain properties.
func OnUnitProperies(Previous):
	var Props: Array = RParam.AsSet(Previous)
	if CurrentHealth() < MaxHealth():
		Props = DSet.Union(Props, [C.upInjured])
	if not IsAlive():
		Props = DSet.Union(Props, [C.upUnhealable])
	return DSet.Make(Props)


func ResolveKiller(ID: int) -> void:
	FKillerID = ID
	# if is projectile try to resolve to owner
	var Entity = _TryGetEntityByID(ID)
	if Entity != null:
		if RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upProjectile):
			ID = RParam.AsInteger(Entity.Eventbus.Read(C.eiCreator, []))
			# if creator hasn't be set or is already dead, use projectile untouched as killer
			if _TryGetEntityByID(ID) != null:
				FKillerID = ID


func UpdateAlive() -> void:
	if IsAlive() and CurrentHealth() < 1:
		Eventbus().Trigger(C.eiKill, [FKillerID, FKillerCommanderID])


# {$IFDEF SERVER} handlers, subscribed on the server side only (see _DeclareEvents).

## Take some damage.
func OnDamage(Amount, _DamageType, InflictorID, Previous):
	if IsInvincible():
		return 0.0
	# save last damage inflictor, to determine killer later
	ResolveKiller(RParam.AsInteger(InflictorID))
	var Killer = _TryGetEntityByID(FKillerID)
	if Killer != null:
		FKillerCommanderID = RParam.AsInteger(Killer.Eventbus.Read(C.eiOwnerCommander, []))
	# now apply damage
	var Damage := RParam.AsSingle(Amount)
	var OverhealDamage := minf(Damage, CurrentOverheal())
	Damage = minf(RParam.ToSingle(Damage - OverhealDamage), CurrentHealth())
	if OverhealDamage > 0:
		Eventbus().Trigger(C.eiResourceTransaction, [C.reOverheal, -OverhealDamage])
	if Damage > 0:
		Eventbus().Trigger(C.eiResourceTransaction, [C.reHealth, -Damage])
	var Result := RParam.ToSingle(RParam.ToSingle(Damage + OverhealDamage) + RParam.AsSingle(Previous))
	# check if the damage killed us
	UpdateAlive()
	FInstaDeath = not IsAlive() or CurrentHealth() >= MaxHealth()
	return Result


## Receive some heal.
func OnHeal(Amount, HealModifier, InflictorID):
	if not CanBeHealed():
		return 0.0
	var HealedAmount := minf(RParam.AsSingle(Amount), RParam.ToSingle(MaxHealth() - CurrentHealth()))
	if HealedAmount > 0:
		Eventbus().Trigger(C.eiResourceTransaction, [C.reHealth, HealedAmount])
	var Overheal := 0.0
	if RParam.AsSet(HealModifier).has(C.dtOverheal):
		Overheal = minf(RParam.ToSingle(RParam.AsSingle(Amount) - HealedAmount), RParam.ToSingle(MaxOverheal() - CurrentOverheal()))
		if Overheal > 0:
			Eventbus().Trigger(C.eiResourceTransaction, [C.reOverheal, Overheal])
			Eventbus().Trigger(C.eiOverheal, [Overheal, HealModifier, InflictorID])
	var Result := RParam.ToSingle(HealedAmount + Overheal)
	FInstaDeath = CurrentHealth() >= MaxHealth()
	return Result


## Send killevents until unit is dead, when Health is 0.
func OnIdle() -> bool:
	UpdateAlive()
	return true


## Kills the unit instantly.
func OnKill(KillerID, KillerCommanderID) -> bool:
	ResolveKiller(RParam.AsInteger(KillerID))
	FKillerCommanderID = RParam.AsInteger(KillerCommanderID)
	Eventbus().Trigger(C.eiDie, [FKillerID, FKillerCommanderID])
	return true


## Adjusts dynamic caps like overheal.
func OnWriteResourceCap(ResourceID, Amount) -> bool:
	if RParam.AsInteger(ResourceID) == C.reHealth:
		Eventbus().Write(C.eiResourceCap, [C.reOverheal, RParam.ToSingle(RParam.AsSingle(Amount) * OVERHEAL_LIMIT_FACTOR)])
	return true
