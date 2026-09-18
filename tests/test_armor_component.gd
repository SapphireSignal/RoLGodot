extends "res://tests/test_case.gd"
## TArmorComponent.OnDamage (BaseConflict.EntityComponents.Shared.pas:2043). The component changes the `var`
## Amount of eiTakeDamage; a probe at epLast sees what the handlers after it get.

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

var _free: Array = []


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()


## An entity with the given armor type (null = none written), a TArmorComponent and a probe.
func _armored(armor) -> F.Probe:
	var bus := TEventbus.new().Create(null)
	_free.append(bus)
	var e := TEntity.new().Create(bus)
	_free.push_front(e)
	if armor != null:
		e.Blackboard.SetValue(C.eiArmorType, [], armor)
	TArmorComponent.new().Create(e)
	return F.Probe.new().Create(e)


## Reads eiTakeDamage and returns [Amount the probe saw, read result].
func _damage(probe: F.Probe, amount: float, types: Array) -> Array:
	probe.Log.clear()
	var result = probe.Owner.Eventbus.Read(C.eiTakeDamage, [amount, types, 0])
	return [probe.First("TakeDamage")[1], result]


func test_factors() -> void:
	check_eq(_damage(_armored(C.atUnarmored), 100.0, [])[0], 100.0, "unarmored: factor 1")
	check_eq(_damage(_armored(C.atLight), 100.0, [])[0], 85.0, "light: 0.85")
	check_eq(_damage(_armored(C.atMedium), 100.0, [C.dtMelee])[0], 80.0, "medium: 0.8")
	check_eq(_damage(_armored(C.atMedium), 100.0, [C.dtRanged])[0], 70.0, "medium vs ranged: 0.7")
	check_eq(_damage(_armored(C.atHeavy), 100.0, [])[0], 65.0, "heavy: 0.7 * 100 - 5")
	check_eq(_damage(_armored(C.atFortified), 10.0, [])[0], 10.0, "fortified: no change")
	check_eq(_damage(_armored(C.atFortified), 10.0, [C.dtSiege])[0], 40.0, "fortified vs siege: 4x")


## No eiArmorType: the empty RParam reads as ord 0 = atUnarmored (factor 1, still at least 1).
func test_no_armor_type_is_unarmored() -> void:
	check_eq(_damage(_armored(null), 50.0, [])[0], 50.0, "unchanged")


## Every shot deals 1 damage at least; Amount <= 1 and dtIgnoreArmor are left alone.
func test_minimum_and_skips() -> void:
	check_eq(_damage(_armored(C.atHeavy), 6.0, [])[0], 1.0, "0.7 * 6 - 5 < 1 -> 1")
	check_eq(_damage(_armored(C.atHeavy), 1.0, [])[0], 1.0, "Amount 1.0 not > 1.0: untouched")
	check_eq(_damage(_armored(C.atHeavy), 0.5, [])[0], 0.5, "Amount 0.5 untouched (no minimum)")
	check_eq(_damage(_armored(C.atHeavy), 100.0, [C.dtIgnoreArmor])[0], 100.0, "dtIgnoreArmor")


## Result := Previous: the armor adds nothing to the read result.
func test_result_is_previous() -> void:
	var probe := _armored(C.atHeavy)
	check_eq(_damage(probe, 100.0, [])[1], null, "no result without a health component")
