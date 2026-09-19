extends "res://tests/test_case.gd"
## TCommanderIncome*Component (BaseConflict.EntityComponents.Shared.pas:2490-2590). eiIncome is a global read
## with [CommanderID]; every income component of that commander adjusts the RIncome in priority order:
## Default (epFirst) adds the base gold, Loan (epMiddle) multiplies it, Overflow (epLast) turns gold over the cap
## into wood.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []
var _buses: Array = []


func after_each() -> void:
	for bus in _buses:
		bus.Game = null
	_buses.clear()
	for o in _free:
		o.Free()
	_free.clear()
	TTimeManager.SetFakeTime(null)
	TEntity.SetLastScriptError("")


func _bus(side: int = C.nsServer) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	_buses.append(bus)
	return bus


## A commander entity (eiOwnerCommander = its ID) with gold balance / cap.
func _commander(bus: TEventbus, id: int, gold: float, cap: float) -> TEntity:
	var e := TEntity.new().Create(bus, id)
	_free.push_front(e)
	e.Blackboard.SetValue(C.eiOwnerCommander, [], id)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reGold, gold)
	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reGold, cap)
	return e


## The group-1 default income setup of CommanderTemplate.ets.
func _default_income(e: TEntity, rate: float, per_upgrade: float, upgrades: int) -> void:
	e.Blackboard.SetIndexedValue(C.eiResourceCost, [1], C.reGold, rate)
	e.Blackboard.SetValue(C.eiWelaDamage, [1], per_upgrade)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reIncomeUpgrade, upgrades)
	TCommanderIncomeDefaultComponent.new().CreateGrouped(e, [1])


func _income(bus: TEventbus, commander_id: int) -> RIncome:
	var r = bus.Read(C.eiIncome, [commander_id])
	check(r is RIncome, "eiIncome is an RIncome")
	return r if r is RIncome else RIncome.new()


func test_default_income() -> void:
	var bus := _bus()
	var e := _commander(bus, 7, 0.0, 1000.0)
	_default_income(e, 10.0, 2.5, 3)
	var inc := _income(bus, 7)
	check_eq(inc.Gold, 17.5, "10 + 2.5 * 3")
	check_eq(inc.Wood, 0.0, "no wood")


## Another commander's read is passed through (Result := Previous, the empty RParam).
func test_other_commander_untouched() -> void:
	var bus := _bus()
	var e := _commander(bus, 7, 0.0, 1000.0)
	_default_income(e, 10.0, 0.0, 0)
	check_eq(bus.Read(C.eiIncome, [8]), null, "commander 8 has no income components")


## Overflow (epLast) sees the default income (epFirst) even though it was created first.
func test_overflow_turns_gold_over_cap_into_wood() -> void:
	var bus := _bus()
	var e := _commander(bus, 7, 95.0, 100.0)
	TCommanderIncomeOverflowComponent.new().CreateGrouped(e, [])
	_default_income(e, 12.0, 0.0, 0)
	var inc := _income(bus, 7)
	check_eq(inc.Gold, 5.0, "up to the cap")
	check_eq(inc.Wood, 7.0, "the rest")


## A balance over the cap counts as the cap: Min(GoldCap, Balance).
func test_overflow_balance_over_cap() -> void:
	var bus := _bus()
	var e := _commander(bus, 7, 150.0, 100.0)
	TCommanderIncomeOverflowComponent.new().CreateGrouped(e, [])
	_default_income(e, 12.0, 0.0, 0)
	var inc := _income(bus, 7)
	check_eq(inc.Gold, 0.0, "full")
	check_eq(inc.Wood, 12.0, "all to wood")


func test_overflow_under_cap_unchanged() -> void:
	var bus := _bus()
	var e := _commander(bus, 7, 10.0, 100.0)
	TCommanderIncomeOverflowComponent.new().CreateGrouped(e, [])
	_default_income(e, 12.0, 0.0, 0)
	var inc := _income(bus, 7)
	check_eq(inc.Gold, 12.0, "all gold")
	check_eq(inc.Wood, 0.0, "no wood")


## EchoesOfTheFuture: Factor 2 for Duration, then Duration * 2 / 2 without gold, then normal again.
func test_loan() -> void:
	TTimeManager.SetFakeTime(0.0)
	var bus := _bus()
	var e := _commander(bus, 7, 0.0, 1000.0)
	_default_income(e, 10.0, 0.0, 0)
	TCommanderIncomeLoanComponent.new().CreateGrouped(e, [9]).Factor(2.0).Duration(1000)
	check_eq(_income(bus, 7).Gold, 20.0, "doubled")
	TTimeManager.SetFakeTime(999.0)
	check_eq(_income(bus, 7).Gold, 20.0, "still doubled")
	TTimeManager.SetFakeTime(1000.0)
	check_eq(_income(bus, 7).Gold, 20.0, "expired read still doubles, then restarts for 1000 * 2 / 2")
	TTimeManager.SetFakeTime(1500.0)
	check_eq(_income(bus, 7).Gold, 0.0, "paying back")
	TTimeManager.SetFakeTime(2000.0)
	check_eq(_income(bus, 7).Gold, 10.0, "paid back: normal income")
	TTimeManager.SetFakeTime(5000.0)
	check_eq(_income(bus, 7).Gold, 10.0, "stays normal")


## Real script: the server CommanderTemplate.ets with a fake Game carrying the settings it reads, at the
## TGame defaults (BaseConflict.Game.pas:224; single / integer as declared there).
class TemplateGame:
	extends RefCounted
	var StartingGold := 300.0
	var GoldCap := 400.0
	var StartingWood := 1600.0
	var IncomeUpgradeCap := 10
	var StartingTier := 1
	var GadgetCountCap := 5
	var CharmCountCap := 3
	var StartingIncomeRate := 10.0
	var IncomeRatePerIncomeUpgrade := 2.0
	var StartingIncomeUpgradeCost := 1500.0
	var IncomeUpgradeCostPerIncomeUpgrade := 250.0
	var GoldCapPerTier := 100.0


func test_commander_template() -> void:
	var bus := _bus()
	bus.Game = TemplateGame.new()
	var e := TEntity.CreateFromScript("Commander\\CommanderTemplate", bus, func(x): x.Blackboard.SetValue(C.eiOwnerCommander, [], x.ID))
	check(e != null, "created: " + TEntity.GetLastScriptError())
	if e == null:
		return
	_free.push_front(e)
	var inc := _income(bus, e.ID)
	check_eq(inc.Gold, 10.0, "starting income 10, balance 300 of 400")
	check_eq(inc.Wood, 0.0, "no overflow")
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reIncomeUpgrade, 2)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reGold, 395.0)
	inc = _income(bus, e.ID)
	check_eq(inc.Gold, 5.0, "10 + 2 * 2 = 14, only 5 fit under the cap")
	check_eq(inc.Wood, 9.0, "overflow")
