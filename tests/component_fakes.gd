extends RefCounted
## Test helpers for component tests: an event probe and a fake TGame with an entity manager.
## Usage: `const F = preload("res://tests/component_fakes.gd")`, then `F.Probe.new().Create(entity)`.

const C = preload("res://src/runtime/dws/dws_const.gd")


## Records the events around a component: Log holds [event name, parameters...] in call order.
class Probe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnDieFirst", C.eiDie, C.epFirst, C.etTrigger))
		e.append(XEvent("OnInstaDie", C.eiInstaDie, C.epLast, C.etTrigger))
		e.append(XEvent("OnOverheal", C.eiOverheal, C.epLast, C.etTrigger))
		e.append(XEvent("OnShame", C.eiYouHaveKilledMeShameOnYou, C.epLast, C.etTrigger))
		e.append(XEvent("OnUnitPropertyChanged", C.eiUnitPropertyChanged, C.epLast, C.etTrigger))
		e.append(XEvent("OnDelayedKillEntity", C.eiDelayedKillEntity, C.epLast, C.etTrigger, C.esGlobal))
		e.append(XEvent("OnTakeDamageLast", C.eiTakeDamage, C.epLast, C.etRead))

	## Names of the logged events, in order.
	func Names() -> Array:
		var names: Array = []
		for entry in Log:
			names.append(entry[0])
		return names

	## The first logged entry of that event, or [] if none.
	func First(name: String) -> Array:
		for entry in Log:
			if entry[0] == name:
				return entry
		return []

	func OnDieFirst(KillerID, KillerCommanderID) -> bool:
		Log.append(["Die", KillerID, KillerCommanderID])
		return true

	func OnInstaDie(KillerID, KillerCommanderID) -> bool:
		Log.append(["InstaDie", KillerID, KillerCommanderID])
		return true

	func OnOverheal(Amount, HealModifier, InflictorID) -> bool:
		Log.append(["Overheal", Amount, HealModifier, InflictorID])
		return true

	func OnShame(VictimID) -> bool:
		Log.append(["Shame", VictimID])
		return true

	func OnUnitPropertyChanged(Props, Removed) -> bool:
		Log.append(["UnitPropertyChanged", Props, Removed])
		return true

	func OnDelayedKillEntity(EntityID) -> bool:
		Log.append(["DelayedKillEntity", EntityID])
		return true

	## Sees the eiTakeDamage Amount after the armor (epMiddle) and health (epLower) handlers.
	func OnTakeDamageLast(Amount, _DamageType, _InflictorID, Previous):
		Log.append(["TakeDamage", Amount])
		return Previous


## Stands in for TGame.EntityManager: Entities by ID, one owning commander for every entity.
class FakeEntityManager:
	extends RefCounted
	var Entities := {}
	var Commander = null

	func TryGetEntityByID(ID: int):
		return Entities.get(ID)

	func TryGetOwningCommander(_Entity):
		return Commander

	func GetOwningCommander(_Entity):
		return Commander


class FakeGame:
	extends RefCounted
	var EntityManager := FakeEntityManager.new()
