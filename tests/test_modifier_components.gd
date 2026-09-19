extends "res://tests/test_case.gd"
## TModifier*Component (BaseConflict.EntityComponents.Shared.Wela.pas:984-1320, :2871, :2910, :3301).
## Values sit on the blackboard: the modified value in group 1, eiWelaModifier / eiWelaDamage in value group 2.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []


class FakeGame:
	extends RefCounted
	var Commanders: Array = []

	func IsShuttingDown() -> bool:
		return false



func after_each() -> void:
	TTimeManager.SetFakeTime(null)
	for o in _free:
		o.Free()
	_free.clear()


func _entity(game = null) -> TEntity:
	var bus := TEventbus.new().Create(null)
	bus.Game = game
	_free.append(bus)
	var e := TEntity.new().Create(bus)
	_free.push_front(e)
	return e


func _bb(e: TEntity, event: int, group: Array, value) -> void:
	e.Blackboard.SetValue(event, group, value)


func test_multiply_cooldown() -> void:
	var e := _entity()
	_bb(e, C.eiCooldown, [1], 333)
	_bb(e, C.eiCooldown, [2], 2000)
	_bb(e, C.eiWelaModifier, [2], 0.5)
	TModifierMultiplyCooldownComponent.new().CreateGrouped(e, [1, 2]).SetValueGroup([2])
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [1]), 166, "333 * 0.5 = 166.5 rounds half to even")
	check_eq(e.Eventbus.Read(C.eiCooldown, [], [2]), 2000, "reads to the value group stay")
	check_eq(e.Eventbus.Read(C.eiCooldown, [], []), null, "no cooldown: stays empty")


func test_damage_type() -> void:
	var e := _entity()
	_bb(e, C.eiDamageType, [], [C.dtMelee, C.dtSiege])
	TModifierDamageTypeComponent.new().Create(e).Add([C.dtRanged]).Remove([C.dtSiege])
	check_eq(e.Eventbus.Read(C.eiDamageType, []), DSet.Make([C.dtMelee, C.dtRanged]), "added and removed")


func test_wela_target_count() -> void:
	var e := _entity()
	_bb(e, C.eiWelaModifier, [1], 2)
	var m: TModifierWelaTargetCountComponent = TModifierWelaTargetCountComponent.new().CreateGrouped(e, [1])
	check_eq(e.Eventbus.Read(C.eiWelaTargetCount, [], [1]), 3, "empty counts as 1, + 2")
	e.Eventbus.Write(C.eiResourceCap, [C.reCharge, 5], [1])
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 3], [1])
	m.ScaleWithResource(C.reCharge)
	check_eq(e.Eventbus.Read(C.eiWelaTargetCount, [], [1]), 7, "1 + 2 * 3 charges")
	_bb(e, C.eiWelaModifier, [1], 0)
	_bb(e, C.eiWelaTargetCount, [1], 4)
	check_eq(e.Eventbus.Read(C.eiWelaTargetCount, [], [1]), 4, "modifier <= 0: unchanged")


func test_armor_type() -> void:
	var e := _entity()
	_bb(e, C.eiArmorType, [], C.atLight)
	var m: TModifierArmorTypeComponent = TModifierArmorTypeComponent.new().Create(e).Increase()
	check_eq(e.Eventbus.Read(C.eiArmorType, []), C.atMedium, "one step up")
	_bb(e, C.eiWelaModifier, [], 5)  # Create: the component's group is empty
	check_eq(e.Eventbus.Read(C.eiArmorType, []), C.atHeavy, "clamped to heavy")
	_bb(e, C.eiArmorType, [], C.atFortified)
	check_eq(e.Eventbus.Read(C.eiArmorType, []), C.atFortified, "fortified is not a normal type")
	m.SetTo(C.atUnarmored)
	check_eq(e.Eventbus.Read(C.eiArmorType, []), C.atUnarmored, "SetTo")
	m.ReadyGroup([3])
	_bb(e, C.eiIsReady, [3], false)
	check_eq(e.Eventbus.Read(C.eiArmorType, []), C.atFortified, "inactive while the ready group is not ready")


func _wela_damage(modifier: float) -> Array:
	var e := _entity()
	_bb(e, C.eiWelaDamage, [1], 10.0)
	_bb(e, C.eiWelaModifier, [2], modifier)
	var m: TModifierWelaDamageComponent = TModifierWelaDamageComponent.new().CreateGrouped(e, [1]).SetValueGroup([2])
	return [e, m]


func _damage(e: TEntity):
	return e.Eventbus.Read(C.eiWelaDamage, [], [1])


func test_wela_damage() -> void:
	var r := _wela_damage(3.0)
	check_eq(_damage(r[0]), 13.0, "adds by default")
	r[1].Negate()
	check_eq(_damage(r[0]), 7.0, "Negate")
	r = _wela_damage(3.0)
	r[1].Multiply()
	check_eq(_damage(r[0]), 30.0, "Multiply")
	r = _wela_damage(4.0)
	r[1].Divide()
	check_eq(_damage(r[0]), 2.5, "Divide")
	r = _wela_damage(3.0)
	r[1].FactorForUnitProperty([C.upUnit], 2.0)
	check_eq(_damage(r[0]), 13.0, "owner lacks the property")
	_bb(r[0], C.eiUnitProperties, [], DSet.Make([C.upUnit, C.upGround]))
	check_eq(_damage(r[0]), 16.0, "factor 3 * 2 for the property")


func test_wela_damage_scales_with_resource() -> void:
	var r := _wela_damage(3.0)
	var e: TEntity = r[0]
	e.Eventbus.Write(C.eiResourceCap, [C.reGold, 10.0])
	e.Eventbus.Write(C.eiResourceBalance, [C.reGold, 2.5])
	r[1].Multiply().ScaleWithResource(C.reGold).ResourceOffset(0.5)
	check_eq(_damage(e), 90.0, "10 * 3 * (2.5 + 0.5)")
	r[1].MaximumResourceScaleFactor(2.0)
	check_eq(_damage(e), 60.0, "resource factor capped at 2")


func test_resource_cap() -> void:
	var game := FakeGame.new()
	var e := _entity(game)
	e.Eventbus.Write(C.eiResourceCap, [C.reHealth, 100.0])
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 100.0])
	_bb(e, C.eiWelaDamage, [1], 50.0)
	var m: TModifierResourceComponent = TModifierResourceComponent.new().CreateGrouped(e, [1]).Resource(C.reHealth).ApplyNow()
	check_eq(e.Cap(C.reHealth), 150.0, "cap raised")
	check_eq(e.Balance(C.reHealth), 150.0, "new space filled")
	e.Eventbus.Trigger(C.eiBeforeFree, [], [], m.UniqueID)
	e.Eventbus.Trigger(C.eiFree, [], [], m.UniqueID)
	check_eq(e.Cap(C.reHealth), 100.0, "taken back when freed")


func test_resource_cap_keeps_one() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reHealth, 100.0])
	_bb(e, C.eiWelaDamage, [1], -500.0)
	TModifierResourceComponent.new().CreateGrouped(e, [1]).Resource(C.reHealth).ApplyNow()
	check_eq(e.Cap(C.reHealth), 1.0, "at least 1 left")


func test_resource_int_add_modifier() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reMana, 10])
	_bb(e, C.eiWelaDamage, [1], 2.0)
	_bb(e, C.eiWelaModifier, [1], 0.5)
	var before = e.Balance(C.reMana)
	TModifierResourceComponent.new().CreateGrouped(e, [1]).Resource(C.reMana).AddModifier().DontFillCap().ApplyNow()
	check_eq(e.Cap(C.reMana), 12, "2 + 0.5 = 2.5 rounds half to even")
	check_eq(e.Balance(C.reMana), before, "DontFillCap: no balance added")


func _range(modifier: float) -> Array:
	var e := _entity()
	_bb(e, C.eiWelaRange, [1], 4.0)
	_bb(e, C.eiWelaModifier, [2], modifier)
	var m: TModifierWelaRangeComponent = TModifierWelaRangeComponent.new().CreateGrouped(e, [1]).SetValueGroup([2])
	return [e, m]


func _read_range(e: TEntity):
	return e.Eventbus.Read(C.eiWelaRange, [], [1])


func test_wela_range() -> void:
	var r := _range(1.5)
	check_eq(_read_range(r[0]), 6.0, "multiplies")
	r[1].AddModifier()
	check_eq(_read_range(r[0]), 5.5, "AddModifier")
	r = _range(0.1)
	check_eq(_read_range(r[0]), 1.0, "at least 1")


func test_wela_range_scale_with_time() -> void:
	TTimeManager.SetFakeTime(0.0)
	var r := _range(2.0)
	var e: TEntity = r[0]
	_bb(e, C.eiCooldown, [2], 1000)
	r[1].ScaleWithTime().ActivateOnStand().DeactivateOnMoveTo()
	TTimeManager.SetFakeTime(500.0)
	check_eq(_read_range(e), 4.0, "4 * 2 * 0.5")
	TTimeManager.SetFakeTime(5000.0)
	check_eq(_read_range(e), 8.0, "progress clamped to 1")
	e.Eventbus.Trigger(C.eiMoveTo, [null, 0.0])
	TTimeManager.SetFakeTime(6000.0)
	check_eq(_read_range(e), 1.0, "paused at 0 after MoveTo, then at least 1")
	e.Eventbus.Trigger(C.eiStand, [])
	TTimeManager.SetFakeTime(6250.0)
	check_eq(_read_range(e), 2.0, "restarted on Stand: 4 * 2 * 0.25")


func test_wela_range_scale_with_stage() -> void:
	var game := FakeGame.new()
	var e := _entity(game)
	var commander := TEntity.new().Create(e.GlobalEventbus)
	_free.push_front(commander)
	commander.Eventbus.Write(C.eiResourceCap, [C.reTier, 5])
	commander.Eventbus.Write(C.eiResourceBalance, [C.reTier, 3])
	game.Commanders = [commander]
	_bb(e, C.eiWelaRange, [1], 4.0)
	_bb(e, C.eiWelaModifier, [2], 0.5)
	TModifierWelaRangeComponent.new().CreateGrouped(e, [1]).SetValueGroup([2]).ScaleWithStage()
	check_eq(_read_range(e), 6.0, "server: 4 * 0.5 * tier 3 of the first commander")


func test_cost() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 100.0], [1])
	e.Eventbus.Write(C.eiResourceCost, [C.reCharge, 2], [3])
	_bb(e, C.eiWelaModifier, [2], 10.0)
	var m: TModifierCostComponent = TModifierCostComponent.new().CreateGrouped(e, [1]).SetValueGroup([2])
	var cost: Array = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [1]))
	check_eq(RResourceCost.GetValue(cost, C.reGold), 110.0, "offset added")
	cost = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [3]))
	check_eq(RResourceCost.GetValue(cost, C.reCharge), 2, "not our group: unchanged")
	e.Eventbus.Write(C.eiResourceCap, [C.reCharge, 5], [1])
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 2], [1])
	m.ScaleWithResource(C.reCharge)
	cost = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [1]))
	check_eq(RResourceCost.GetValue(cost, C.reGold), 120.0, "offset 10 * 2 charges")


## Real script: Modifiers\BlessingHealth on the server SmallMeleeGolem (68 health) raises the health cap by
## 0.3 x 68 + 50 = 70.4 (TModifierResourceComponent, ScaleWithResource(reHealth).UseResourceCap.AddModifier).
func test_real_blessing_health() -> void:
	var bus := TEventbus.new().Create(null)
	_free.append(bus)
	var e := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", bus)
	check(e != null, "created: " + TEntity.GetLastScriptError())
	if e == null:
		return
	_free.push_front(e)
	e.ApplyScript("Modifiers\\BlessingHealth.dws", "Apply", [e])
	check(absf(RParam.AsSingle(e.Cap(C.reHealth)) - 138.4) < 0.001, "cap 68 + 70.4, got %s" % e.Cap(C.reHealth))
	check(absf(RParam.AsSingle(e.Balance(C.reHealth)) - 138.4) < 0.001, "new space filled")
	check(e.HasUnitProperty(C.upBlessedHealth), "unit property from the script")
