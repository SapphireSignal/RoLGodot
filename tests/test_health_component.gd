extends "res://tests/test_case.gd"
## THealthComponent (BaseConflict.EntityComponents.Shared.pas:1003-1188). Expected values follow the Pascal
## method named in each test; the script test takes its numbers from Scripts\Units\Colorless\SmallMeleeGolem.ets.

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

var _free: Array = []
var _buses: Array = []


func after_each() -> void:
	for bus in _buses:
		bus.Game = null
	_buses.clear()
	for o in _free:
		o.Free()
	_free.clear()
	TEntity.LastScriptError = ""


func _bus(side: int = C.nsServer) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	_buses.append(bus)
	return bus


func _entity(bus: TEventbus, id: int = 7) -> TEntity:
	var e := TEntity.new().Create(bus, id)
	_free.push_front(e)
	return e


## A unit as UnitTemplate.dws builds it: health written to the blackboard first, then THealthComponent, then a
## probe. Returns the probe (probe.Owner is the unit).
func _unit(health: float, max_health: float, bus: TEventbus = null, id: int = 7) -> F.Probe:
	var e := _entity(bus if bus != null else _bus(), id)
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reHealth, max_health)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reHealth, health)
	THealthComponent.new().Create(e)
	return F.Probe.new().Create(e)


func _res(e: TEntity, res: int):
	return e.Eventbus.Read(C.eiResourceBalance, [res])


func _cap(e: TEntity, res: int):
	return e.Eventbus.Read(C.eiResourceCap, [res])


func _damage(e: TEntity, amount: float, inflictor: int = 0):
	return e.Eventbus.Read(C.eiTakeDamage, [amount, [C.dtMelee], inflictor])


func _heal(e: TEntity, amount: float, modifier: Array = [], inflictor: int = 0):
	return e.Eventbus.Read(C.eiHeal, [amount, modifier, inflictor])


## Create: alive, overheal cap = MaxHealth * 2. OnWriteResourceCap (server only) keeps it at twice the health cap.
func test_create_and_overheal_cap() -> void:
	var e: TEntity = _unit(100.0, 100.0).Owner
	check_eq(e.Eventbus.Read(C.eiIsAlive, []), true, "alive")
	check_eq(e.Eventbus.Read(C.eiDamageable, []), true, "damageable")
	check_eq(_cap(e, C.reOverheal), 200.0, "overheal cap")
	check_eq(_res(e, C.reOverheal), 0.0, "overheal balance set by the cap write")
	e.Eventbus.Write(C.eiResourceCap, [C.reHealth, 150.0])
	check_eq(_cap(e, C.reOverheal), 300.0, "server: follows the health cap")
	var client: TEntity = _unit(100.0, 100.0, _bus(C.nsClient)).Owner
	client.Eventbus.Write(C.eiResourceCap, [C.reHealth, 150.0])
	check_eq(_cap(client, C.reOverheal), 200.0, "client: no OnWriteResourceCap")


## OnDamage: overheal takes damage first, then health; the result is the damage dealt (+ Previous).
func test_damage() -> void:
	var e: TEntity = _unit(100.0, 100.0).Owner
	check_eq(_damage(e, 30.0), 30.0, "result")
	check_eq(_res(e, C.reHealth), 70.0, "health")
	check(e.HasUnitProperty(C.upInjured), "OnUnitProperies: injured below max")
	e.Eventbus.Write(C.eiResourceBalance, [C.reOverheal, 20.0])
	check_eq(_damage(e, 30.0), 30.0, "result with overheal")
	check_eq(_res(e, C.reOverheal), 0.0, "overheal used up")
	check_eq(_res(e, C.reHealth), 60.0, "rest from health")
	check_eq(_damage(e, 100.0), 60.0, "at most the remaining health")


## Lethal damage: UpdateAlive -> eiKill -> OnKill -> eiDie -> OnDie. A unit at full health when last hit (or never
## hit) dies instantly (eiInstaDie); the server also triggers eiDelayedKillEntity on the global bus.
func test_lethal_damage_insta() -> void:
	var probe := _unit(10.0, 100.0)
	var e: TEntity = probe.Owner
	check_eq(_damage(e, 50.0), 10.0, "min(damage, health)")
	check_eq(probe.Names(), ["Die", "InstaDie", "DelayedKillEntity", "TakeDamage"], "event order")
	check_eq(probe.First("Die"), ["Die", 0, -1], "killer = inflictor 0, no killer entity -> commander -1")
	check_eq(probe.First("DelayedKillEntity"), ["DelayedKillEntity", 7], "own ID")
	check_eq(e.Eventbus.Read(C.eiIsAlive, []), false, "dead")
	check_eq(e.Eventbus.Read(C.eiDamageable, []), false, "not damageable")
	check(e.HasUnitProperty(C.upUnhealable), "OnUnitProperies: dead -> unhealable")
	check_eq(_heal(e, 50.0), 0.0, "cannot be healed")
	probe.Log.clear()
	check_eq(_damage(e, 50.0), 0.0, "no health left")
	check_eq(probe.Names(), ["TakeDamage"], "no second death")


## FInstaDeath := not IsAlive or (CurrentHealth >= MaxHealth) after damage, CurrentHealth >= MaxHealth after heal.
func test_insta_death_flag() -> void:
	var probe := _unit(100.0, 100.0)
	var e: TEntity = probe.Owner
	_damage(e, 30.0)
	_heal(e, 30.0)
	_damage(e, 30.0)
	_damage(e, 100.0)
	check_eq(probe.Names().has("Die"), true, "died")
	check_eq(probe.Names().has("InstaDie"), false, "hit below max health before: no insta death")
	var probe2 := _unit(100.0, 100.0, null, 8)
	_damage(probe2.Owner, 30.0)
	_heal(probe2.Owner, 30.0)
	_damage(probe2.Owner, 200.0)
	check_eq(probe2.Names().has("InstaDie"), true, "healed to full: insta death again")


## IsInvincible: OnDamage returns 0.0 and takes nothing; not damageable.
func test_invincible() -> void:
	var e: TEntity = _unit(100.0, 100.0).Owner
	TUnitPropertyComponent.new().CreateGrouped(e, [], [C.upInvincible])
	check_eq(_damage(e, 30.0), 0.0, "no damage")
	check_eq(_res(e, C.reHealth), 100.0, "health untouched")
	check_eq(e.Eventbus.Read(C.eiDamageable, []), false, "not damageable")


## OnHeal: up to max health; with dtOverheal the rest goes to overheal up to its cap (eiOverheal is triggered).
func test_heal() -> void:
	var probe := _unit(50.0, 100.0)
	var e: TEntity = probe.Owner
	check_eq(_heal(e, 30.0), 30.0, "healed")
	check_eq(_res(e, C.reHealth), 80.0, "health")
	check_eq(_heal(e, 80.0), 20.0, "up to max")
	check_eq(_res(e, C.reOverheal), 0.0, "no overheal without dtOverheal")
	check_eq(_heal(e, 50.0, [C.dtOverheal], 9), 50.0, "all into overheal")
	check_eq(_res(e, C.reOverheal), 50.0, "overheal")
	check_eq(probe.First("Overheal"), ["Overheal", 50.0, [C.dtOverheal], 9], "eiOverheal")
	check_eq(_heal(e, 300.0, [C.dtOverheal]), 150.0, "overheal up to its cap")
	check_eq(_res(e, C.reOverheal), 200.0, "at cap")
	TUnitPropertyComponent.new().CreateGrouped(e, [], [C.upUnhealable])
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 10.0])
	check_eq(_heal(e, 30.0), 0.0, "unhealable")


## OnIdle (server, global bus): a unit below 1 health dies on the next idle.
func test_idle_kills() -> void:
	var probe := _unit(100.0, 100.0)
	var e: TEntity = probe.Owner
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 0.5])
	check_eq(probe.Names(), [], "nothing yet")
	e.GlobalEventbus.Trigger(C.eiIdle, [])
	check_eq(probe.First("Die"), ["Die", -1, -1], "killed by nobody")
	check_eq(e.Eventbus.Read(C.eiIsAlive, []), false, "dead")


## Client: no damage/heal/kill handlers, but eiDie still sets the unit dead (no eiDelayedKillEntity).
func test_client_side() -> void:
	var probe := _unit(100.0, 100.0, _bus(C.nsClient))
	var e: TEntity = probe.Owner
	check_eq(_damage(e, 30.0), null, "no OnDamage on the client")
	check_eq(_res(e, C.reHealth), 100.0, "health untouched")
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiDie, [3, 4])
	check_eq(probe.Names(), ["Die", "InstaDie"], "died")
	check_eq(e.Eventbus.Read(C.eiIsAlive, []), false, "dead")
	check_eq(_res(e, C.reHealth), 0.0, "OnSetIsAlive zeroes health")
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiDie, [3, 4])
	check_eq(probe.Names(), ["Die"], "OnDie returns False when already dead: nothing after it")


## ResolveKiller: a projectile inflictor resolves to its creator if that still exists; the killer's
## eiOwnerCommander becomes the killer commander; the killer gets eiYouHaveKilledMeShameOnYou.
func test_killer_resolution() -> void:
	var bus := _bus()
	var game := F.FakeGame.new()
	bus.Game = game
	var creator := _entity(bus, 20)
	creator.Blackboard.SetValue(C.eiOwnerCommander, [], 3)
	var creator_probe: F.Probe = F.Probe.new().Create(creator)
	var projectile := _entity(bus, 30)
	projectile.Blackboard.SetValue(C.eiUnitProperties, [], [C.upProjectile])
	projectile.Blackboard.SetValue(C.eiCreator, [], 20)
	var orphan := _entity(bus, 31)
	orphan.Blackboard.SetValue(C.eiUnitProperties, [], [C.upProjectile])
	orphan.Blackboard.SetValue(C.eiCreator, [], 99)
	for x in [creator, projectile, orphan]:
		game.EntityManager.Entities[x.ID] = x
	var victim := _unit(10.0, 100.0, bus, 10)
	_damage(victim.Owner, 50.0, 30)
	check_eq(victim.First("Die"), ["Die", 20, 3], "creator and its commander")
	check_eq(creator_probe.First("Shame"), ["Shame", 10], "creator told")
	var victim2 := _unit(10.0, 100.0, bus, 11)
	_damage(victim2.Owner, 50.0, 31)
	check_eq(victim2.First("Die"), ["Die", 31, 0], "creator gone: the projectile itself")


## Real script: SmallMeleeGolem (68 health, atLight) built by UnitTemplate.dws on the server side.
func test_small_melee_golem() -> void:
	var e := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus())
	check(e != null, "created: " + TEntity.LastScriptError)
	if e == null:
		return
	_free.push_front(e)
	check_eq(_cap(e, C.reOverheal), 136.0, "overheal cap 2 x 68")
	check_eq(_damage(e, 20.0), 17.0, "light armor: 0.85 x 20")
	check_eq(_res(e, C.reHealth), 51.0, "68 - 17")
