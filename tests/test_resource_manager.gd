extends "res://tests/test_case.gd"
## TResourceManagerComponent (BaseConflict.EntityComponents.Shared.pas:1804-1969). Expected values follow the
## handler named in each test; the script tests take theirs from the original scripts named there.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []


## Stands in for TGame in the scripts' `Game` global (IsDuo / IsPvP / IsOneLane only).
class FakeGame:
	extends RefCounted
	var duo := false
	var pvp := false
	var one_lane := false

	func IsDuo() -> bool:
		return duo

	func IsPvP() -> bool:
		return pvp

	func IsOneLane() -> bool:
		return one_lane


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()
	TEntity.LastScriptError = ""


func _bus(side: int = C.nsServer) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	return bus


func _entity(side: int = C.nsServer) -> TEntity:
	var e := TEntity.new().Create(_bus(side))
	_free.push_front(e)  # entities before their global bus
	return e


func _keep(e: TEntity) -> TEntity:
	if e != null:
		_free.push_front(e)
	return e


func _balance(e: TEntity, res: int, group: Array = []):
	return e.Eventbus.Read(C.eiResourceBalance, [res], group)


## TEntity.Create adds the component to every entity, in ALLGROUP.
func test_every_entity_has_one() -> void:
	var e := _entity()
	var found: Array = []
	e.Eventbus.Trigger(C.eiEnumerateComponents, [func(comp) -> void: found.append(comp)])
	check_eq(found.size(), 1, "one component")
	check(found[0] is TResourceManagerComponent, "the resource manager")
	check_eq(found[0].ComponentGroup, [C.ALLGROUP_INDEX], "ALLGROUP")


## OnSetResource / OnGetResource: indexed by resource, under the called group; no fallback to the global value.
func test_balance_per_group() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 10.5], [3])
	check_eq(e.Blackboard.GetIndexedValue(C.eiResourceBalance, [3], C.reHealth), 10.5, "stored indexed in group 3")
	check_eq(_balance(e, C.reHealth, [3]), 10.5, "read in group 3")
	check_eq(_balance(e, C.reHealth), null, "nothing in the global group")
	check_eq(e.Blackboard.GetIndexedValue(C.eiResourceBalance, [3], C.reHealth - 1), null, "other resource empty")


## OnTransact, int branch: Max(0, ...), capped only for Amount >= 0.
func test_transact_int() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reCharge, 3])
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 1])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reCharge, 5])
	check_eq(_balance(e, C.reCharge), 3, "capped")
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reCharge, -10])
	check_eq(_balance(e, C.reCharge), 0, "not below 0")
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 5])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reCharge, -1])
	check_eq(_balance(e, C.reCharge), 4, "negative amount is not capped")
	# RES_IGNORE_CAP
	e.Eventbus.Write(C.eiResourceCap, [C.reGadgetCount, 1])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reGadgetCount, 5])
	check_eq(_balance(e, C.reGadgetCount), 5, "gadget count ignores its cap")


## OnTransact, single branch: sums in single precision.
func test_transact_single() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reGold, 10.0])
	e.Eventbus.Write(C.eiResourceBalance, [C.reGold, 2.5])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, 0.1])
	check_eq(_balance(e, C.reGold), RParam.ToSingle(2.5 + RParam.ToSingle(0.1)), "single sum")
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, 100.0])
	check_eq(_balance(e, C.reGold), 10.0, "capped")
	e.Eventbus.Trigger(C.eiResourceSubtraction, [C.reGold, 4.0])
	check_eq(_balance(e, C.reGold), 6.0, "subtraction")


## OnCanTransact / OnCanTransactNegative.
func test_can_transact() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceBalance, [C.reGold, 2.0])
	check_eq(e.Eventbus.Read(C.eiResourceTransaction, [C.reGold, -3.0]), false, "can't go below 0")
	check_eq(e.Eventbus.Read(C.eiResourceTransaction, [C.reGold, -2.0]), true, "down to 0")
	check_eq(e.Eventbus.Read(C.eiResourceTransaction, [C.reGold, 50.0]), true, "inbound always")
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 1])
	check_eq(e.Eventbus.Read(C.eiResourceSubtraction, [C.reCharge, 2]), false, "subtract 2 of 1")
	check_eq(e.Eventbus.Read(C.eiResourceSubtraction, [C.reCharge, 1]), true, "subtract 1 of 1")
	e.Eventbus.Trigger(C.eiResourceSubtraction, [C.reCharge, 1])
	check_eq(_balance(e, C.reCharge), 0, "subtracted")


## OnSetResourceCap re-caps the balance (OnTransact with an empty amount).
func test_lower_cap_caps_balance() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceBalance, [C.reCharge, 5])
	e.Eventbus.Write(C.eiResourceCap, [C.reCharge, 3])
	check_eq(e.Eventbus.Read(C.eiResourceCap, [C.reCharge]), 3, "cap read")
	check_eq(_balance(e, C.reCharge), 3, "balance capped")


## OnResourceCapTransaction: raises the cap and fills the new space unless Empty.
func test_cap_transaction() -> void:
	var e := _entity()
	e.Eventbus.Write(C.eiResourceCap, [C.reHealth, 10.0], [2])
	e.Eventbus.Write(C.eiResourceBalance, [C.reHealth, 4.0], [2])
	e.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reHealth, 5.0, false], [2])
	check_eq(e.Eventbus.Read(C.eiResourceCap, [C.reHealth], [2]), 15.0, "cap raised")
	check_eq(_balance(e, C.reHealth, [2]), 9.0, "filled")
	e.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reHealth, 5.0, true], [2])
	check_eq(e.Eventbus.Read(C.eiResourceCap, [C.reHealth], [2]), 20.0, "cap raised again")
	check_eq(_balance(e, C.reHealth, [2]), 9.0, "Empty: not filled")
	e.Eventbus.Trigger(C.eiResourceCapTransaction, [C.reHealth, -12.0, false], [2])
	check_eq(e.Eventbus.Read(C.eiResourceCap, [C.reHealth], [2]), 8.0, "cap lowered")
	check_eq(_balance(e, C.reHealth, [2]), 8.0, "lowered cap re-caps the balance")


## OnAfterCreate saves the global-group balances, OnResetResource writes them back.
func test_reset_resource() -> void:
	var e := _entity()
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCharge, 2)
	e.Eventbus.Trigger(C.eiAfterCreate, [])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reCharge, 1])
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reMana, 7])
	check_eq(_balance(e, C.reCharge), 3, "changed")
	e.Eventbus.Trigger(C.eiResourceReset, [C.reCharge])
	check_eq(_balance(e, C.reCharge), 2, "reset to the initial value")
	e.Eventbus.Trigger(C.eiResourceReset, [C.reMana])
	check_eq(_balance(e, C.reMana), 7, "no initial value: unchanged")


## OnSetResourceCost / OnGetResourceCost: an AResourceCost, or empty.
func test_cost() -> void:
	var e := _entity()
	check_eq(e.Eventbus.Read(C.eiResourceCost, [], [1]), null, "no cost: empty")
	e.Eventbus.Write(C.eiResourceCost, [C.reWood, 50.0], [1])
	e.Eventbus.Write(C.eiResourceCost, [C.reGold, 100.0], [1])
	var cost: Array = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, [], [1]))
	check_eq(RResourceCost.Count(cost), 2, "two entries")
	check_eq(RResourceCost.GetValue(cost, C.reGold), 100.0, "gold")
	check_eq(RResourceCost.TryGetValue(cost, C.reWood), [true, 50.0], "wood")
	check_eq(RResourceCost.TryGetValue(cost, C.reCharge), [false, null], "no charge")


## Card initializer (BaseConflict.Classes.Shared.pas:510) on Units\Neutral\NexusLevel1.ets, InheritsFrom Nexus.ets.
## League 2 (f/i index League - 1): Nexus reWelaCharge i([8, 16, ...]) = 16, NexusLevel1 reHealth f([2500.0, 3250.0, ...]).
func test_card_league_nexus() -> void:
	var bus := _bus()
	var game := FakeGame.new()
	bus.Game = game
	var init := func(Entity: TEntity) -> void:
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, 1)
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, 2)
	var e := _keep(TEntity.CreateDataFromScript("Units\\Neutral\\NexusLevel1", bus, init))
	check(e != null, "entity created: " + TEntity.LastScriptError)
	if e != null:
		check_eq(e.CardLeague(), 2, "CardLeague")
		check_eq(e.CardLevel(), 1, "CardLevel")
		check_eq(e.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reWelaCharge), 16, "Nexus charge cap")
		check_eq(e.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reHealth), 3250.0, "NexusLevel1 health cap")
		check_eq(e.Blackboard.GetIndexedValue(C.eiResourceBalance, [], C.reHealth), 3250.0, "NexusLevel1 health")
	# 2v2 PvP (not one lane): Nexus keeps the "Rest" charges, NexusLevel1 doubles the health
	game.duo = true
	game.pvp = true
	var duo := _keep(TEntity.CreateDataFromScript("Units\\Neutral\\NexusLevel1", bus, init))
	check(duo != null, "duo entity created: " + TEntity.LastScriptError)
	if duo != null:
		check_eq(duo.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reWelaCharge), 16, "duo charge cap")
		check_eq(duo.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reHealth), 6500.0, "duo health cap")
	check_eq(TEntity.LastScriptError, "", "no script error")
	bus.Game = null


## Units\Black\VoidSkeletonDrop.ets on the client: DropTemplate InitDropData -> CardTemplate InitCardData, tier 1,
## league 4, level 2: cost 100.0 gold, tier 1, 1 charge; charges i([1, 2, 3, 4, 5], 4) = 4;
## cooldown ii(..., 4, 2) = 27250.
func test_card_league_drop_client() -> void:
	var init := func(Entity: TEntity) -> void:
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLevel, 2)
		Entity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardLeague, 4)
	var e := _keep(TEntity.CreateDataFromScript("Units\\Black\\VoidSkeletonDrop", _bus(C.nsClient), init))
	check(e != null, "entity created: " + TEntity.LastScriptError)
	if e == null:
		return
	check_eq(e.IsServer(), false, "client entity")
	check_eq(e.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reCharge), 4, "charge cap")
	check_eq(_balance(e, C.reCharge), 4, "charges")
	check_eq(e.Blackboard.GetValue(C.eiCooldown, []), 27250, "charge cooldown")
	var cost: Array = RParam.AsArray(e.Eventbus.Read(C.eiResourceCost, []))
	check_eq(RResourceCost.GetValue(cost, C.reGold), 100.0, "gold cost")
	check_eq(RResourceCost.GetValue(cost, C.reTier), 1, "tier")
	check_eq(RResourceCost.GetValue(cost, C.reCharge), 1, "charge cost")
	check_eq(TEntity.LastScriptError, "", "no script error")
