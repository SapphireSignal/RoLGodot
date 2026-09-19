extends "res://tests/test_case.gd"
## The brains (GameServer/BaseConflict.EntityComponents.Server.Brains.pas): think impulses, TBrainComponent's think
## rules, the wela / movement / action / targeting / projectile / commander brains, the auto-brains, and two real
## server SmallMeleeGolems fighting to the death. The game has the real entity manager and server collision manager,
## hard-coded lanes, and a delayed-event queue pumped like TServerGame.Idle.

const C = preload("res://src/runtime/dws/dws_const.gd")
const F = preload("res://tests/component_fakes.gd")

var _bus: TEventbus
var _game_entity: TEntity
var _manager: TEntityManagerComponent


class FakeMap:
	extends RefCounted
	var MapBoundaries := Rect2(-150, -150, 300, 300)
	var Lanes := TLaneManager.new().Create()
	var Pathfinding = null

	func ClampToZone(_Zone: String, Position: Vector2) -> Vector2:
		return Position


class FakeGame:
	extends RefCounted
	var Statistics := TGameStatisticManager.new().Create()
	var Commanders: Array = []
	var Sandbox := false
	var InGameStatus := 2  # BC.gsPlaying
	var Map := FakeMap.new()
	var EntityManager = null
	var ServerEntityManager = null
	var CollisionManager = null
	var DelayedEvents := TIntPriorityQueue.new()

	func IsShuttingDown() -> bool:
		return false

	func IsSandbox() -> bool:
		return Sandbox

	func League() -> int:
		return 1


## Records brain traffic on its entity (ALLGROUP): [name, called-to group, parameters...] in call order.
class BrainProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnThink", C.eiThink, C.epFirst, C.etTrigger))
		e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epFirst, C.etTrigger))
		e.append(XEvent("OnFire", C.eiFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnPreFire", C.eiPreFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnStand", C.eiStand, C.epFirst, C.etTrigger))
		e.append(XEvent("OnMoveTo", C.eiMoveTo, C.epFirst, C.etTrigger))
		e.append(XEvent("OnCancelFire", C.eiCancelFire, C.epFirst, C.etTrigger))
		e.append(XEvent("OnSetMainTarget", C.eiWelaSetMainTarget, C.epFirst, C.etTrigger))
		e.append(XEvent("OnLinkBreak", C.eiLinkBreak, C.epFirst, C.etTrigger))
		e.append(XEvent("OnHitByProjectile", C.eiWelaHitByProjectile, C.epFirst, C.etTrigger))
		e.append(XEvent("OnDieEnd", C.eiDie, C.epLast, C.etTrigger))
		e.append(XEvent("OnDamageDone", C.eiDamageDone, C.epFirst, C.etTrigger))

	func _group() -> Array:
		return TEventbus.CurrentEvent_CalledToGroup.duplicate()

	## The entries of one event.
	func Of(name: String) -> Array:
		var Result: Array = []
		for entry in Log:
			if entry[0] == name:
				Result.append(entry)
		return Result

	func Names() -> Array:
		var Result: Array = []
		for entry in Log:
			Result.append(entry[0])
		return Result

	func OnThink() -> bool:
		Log.append(["Think", _group()])
		return true

	func OnThinkChain() -> bool:
		Log.append(["ThinkChain", _group()])
		return true

	func OnFire(Targets) -> bool:
		Log.append(["Fire", _group(), Desc(Targets)])
		return true

	func OnPreFire(Targets) -> bool:
		Log.append(["PreFire", _group(), Desc(Targets)])
		return true

	func OnStand() -> bool:
		Log.append(["Stand", _group()])
		return true

	func OnMoveTo(Target, Range) -> bool:
		Log.append(["MoveTo", _group(), Desc([Target]), snappedf(Range, 0.0001)])
		return true

	func OnCancelFire() -> bool:
		Log.append(["CancelFire", _group()])
		return true

	func OnSetMainTarget(Target) -> bool:
		Log.append(["SetMainTarget", _group(), Desc([Target])])
		return true

	func OnLinkBreak(Target) -> bool:
		Log.append(["LinkBreak", _group(), Desc([Target])])
		return true

	func OnHitByProjectile(Projectile) -> bool:
		Log.append(["HitByProjectile", _group(), Projectile.ID])
		return true

	func OnDieEnd(KillerID, _KillerCommanderID) -> bool:
		Log.append(["DieEnd", _group(), KillerID])
		return true

	func OnDamageDone(Amount, _DamageType, Target) -> bool:
		Log.append(["DamageDone", _group(), snappedf(Amount, 0.0001), Target.ID, TTimeManager.GetFakeTime()])
		return true

	## Targets as readable values: entity IDs, Vector2 spots, "empty".
	static func Desc(Targets) -> Array:
		var Result: Array = []
		for Target: RTarget in ATarget.FromRParam(Targets):
			if Target.IsEntity():
				Result.append(Target.EntityID)
			elif Target.IsCoordinate():
				Result.append(Target.FTargetCoord)
			else:
				Result.append("empty")
		return Result


## Logs "ThinkChainEnd" into a BrainProbe's Log when eiThinkChain gets to epLast (one handler per event and type per
## class, so the probe needs a second component for it).
class ChainEndProbe:
	extends TEntityComponent
	var Log: Array = []

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnThinkChainEnd", C.eiThinkChain, C.epLast, C.etTrigger))

	func OnThinkChainEnd() -> bool:
		Log.append(["ThinkChainEnd", TEventbus.CurrentEvent_CalledToGroup.duplicate()])
		return true


## Answers eiEnumerateNexus like the nexus entities do.
class NexusMarker:
	extends TEntityComponent

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnEnumerateNexus", C.eiEnumerateNexus, C.epMiddle, C.etRead, C.esGlobal))

	func OnEnumerateNexus(Previous):
		var List: Array = Previous if Previous is Array else []
		List.append(Owner)
		return List


## A targeting wela stand-in: eiWelaUpdateTargets adds Candidates not in the list yet (up to eiWelaTargetCount,
## default 1), eiWelaValidateTarget answers whether the target is in Valid.
class FakeTargeting:
	extends TEntityComponent
	var Candidates: Array = []  # of RTarget
	var Valid: Array = []  # of entity IDs

	func _DeclareEvents(e: Array) -> void:
		super(e)
		e.append(XEvent("OnUpdate", C.eiWelaUpdateTargets, C.epMiddle, C.etTrigger))
		e.append(XEvent("OnValidate", C.eiWelaValidateTarget, C.epFirst, C.etRead))

	func OnUpdate(Targets) -> bool:
		var Max := maxi(1, RParam.AsIntegerDefault(Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup), 1))
		for Candidate: RTarget in Candidates:
			if Targets.size() >= Max:
				break
			var Known := false
			for Target: RTarget in Targets:
				Known = Known or Target.Equal(Candidate)
			if not Known:
				Targets.append(Candidate)
		return true

	func OnValidate(Target):
		return Target is RTarget and Valid.has(Target.EntityID)


func _setup() -> void:
	TTimeManager.SetFakeTime(1000.0)
	_bus = TEventbus.new().Create(null)
	_bus.ApplicationType = C.nsServer
	_bus.Game = FakeGame.new()
	_game_entity = TEntity.new().Create(_bus, 1)
	_manager = TServerEntityManagerComponent.new().Create(_game_entity)
	_bus.Game.EntityManager = _manager
	_bus.Game.ServerEntityManager = _manager
	_bus.Game.CollisionManager = TServerCollisionManagerComponent.new().Create(_game_entity)


func after_each() -> void:
	TTimeManager.SetFakeTime(null)
	if _game_entity != null:
		_bus.Game.CollisionManager = null
		_bus.Game.ServerEntityManager = null
		_bus.Game.DelayedEvents.Clear()
		_game_entity.Free()  # frees the managers and every deployed entity
		_bus.Game = null
		_bus.Free()
	_bus = null
	_game_entity = null
	_manager = null
	TEntity.LastScriptError = ""
	super()


func _unit(team: int, pos: Vector2, props: Array = []) -> TEntity:
	var e := TEntity.new().Create(_bus, _manager.GenerateUniqueID())
	e.Blackboard.SetValue(C.eiTeamID, [], team)
	e.Blackboard.SetValue(C.eiUnitProperties, [], props)
	e.Position = pos
	e.CollisionRadius = 0.5
	TCollisionComponent.new().Create(e)
	e.Deploy()
	return e


func _probe(e: TEntity) -> BrainProbe:
	var probe: BrainProbe = BrainProbe.new().CreateGroupedAll(e)
	var chain_end: ChainEndProbe = ChainEndProbe.new().CreateGroupedAll(e)
	chain_end.Log = probe.Log  # shared
	return probe


## One server frame at time t: due delayed events, then the global eiIdle (TServerGame.Idle), then the manager.
func _frame(t: float) -> void:
	TTimeManager.SetFakeTime(t)
	TDelayedEventHandler.ProcessDueEvents(_bus.Game.DelayedEvents)
	_bus.Trigger(C.eiIdle)
	_manager.Idle()


func _think(e: TEntity, group: Array = []) -> void:
	e.Eventbus.Trigger(C.eiThink, [], group)
	e.Eventbus.Trigger(C.eiThinkChain, [], group)


## TThinkImpulseTimerComponent: thinks at the first eiIdle 250 ms after creation / the last thought, at the next
## eiIdle after eiMoveTargetReached, never while exiled or dead.
func test_think_impulse_timer() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	TThinkImpulseTimerComponent.new().CreateGrouped(e, [3])
	var probe := _probe(e)
	_frame(1249.0)
	check_eq(probe.Log, [], "not before 250 ms")
	_frame(1250.0)
	check_eq(probe.Names(), ["Think", "ThinkChain", "ThinkChainEnd"], "thinks at 250 ms")
	check_eq(probe.Log[0][1], [3], "in its group")
	probe.Log.clear()
	_frame(1400.0)
	check_eq(probe.Log, [], "timer restarted")
	e.Eventbus.Trigger(C.eiMoveTargetReached)
	_frame(1401.0)
	check_eq(probe.Of("Think").size(), 1, "move target reached: thinks at the next idle")
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiExiled, [], true)
	_frame(2000.0)
	check_eq(probe.Log, [], "exiled: no thinking")
	e.Blackboard.SetValue(C.eiExiled, [], false)
	e.Blackboard.SetValue(C.eiIsAlive, [], false)
	_frame(2000.0)
	check_eq(probe.Log, [], "dead: no thinking")
	e.Blackboard.SetValue(C.eiIsAlive, [], true)
	_frame(2000.0)
	check_eq(probe.Of("Think").size(), 1, "alive again")


## Once (first idle, then freed; WaitOneFrame; TriggerOnAfterCreate), Now, GameTick, Immediate, Fire, the cooldown
## timer and the block.
func test_think_impulses() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var probe := _probe(e)
	var once: TThinkImpulseOnceComponent = TThinkImpulseOnceComponent.new().CreateGrouped(e, [1]).WaitOneFrame()
	_frame(1000.0)
	check_eq(probe.Log, [], "WaitOneFrame skips the first idle")
	_frame(1000.0)
	check_eq(probe.Names(), ["Think", "ThinkChain", "ThinkChainEnd"], "once at the second idle")
	check(once.Owner == null, "and freed")
	probe.Log.clear()
	_frame(1000.0)
	check_eq(probe.Log, [], "only once")
	var on_create: TThinkImpulseOnceComponent = TThinkImpulseOnceComponent.new().CreateGrouped(e, [2]).TriggerOnAfterCreate()
	_frame(1000.0)
	check_eq(probe.Log, [], "TriggerOnAfterCreate ignores idles")
	e.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe.Of("Think"), [["Think", [2]]], "thinks at eiAfterCreate")
	check(on_create.Owner == null, "and is freed")
	probe.Log.clear()

	TThinkImpulseNowComponent.new().CreateGrouped(e, [4])
	check_eq(probe.Of("Think"), [["Think", [4]]], "Now thinks in its constructor")
	probe.Log.clear()
	var tick := TThinkImpulseGameTickComponent.new().CreateGrouped(e, [5])
	_bus.Trigger(C.eiGameTick)
	check_eq(probe.Of("Think"), [["Think", [5]]], "GameTick thinks at every eiGameTick")
	tick.Free()
	probe.Log.clear()
	var immediate := TThinkImpulseImmediateComponent.new().CreateGrouped(e, [6])
	_frame(1000.0)
	_frame(1000.0)
	check_eq(probe.Of("Think"), [["Think", [6]], ["Think", [6]]], "Immediate thinks every idle")
	immediate.Free()
	probe.Log.clear()
	TThinkImpulseFireComponent.new().CreateGrouped(e, [7]).TargetGroup([8])
	e.Eventbus.Trigger(C.eiFire, [[]], [9])
	check_eq(probe.Of("Think"), [], "an eiFire in another group does not reach it")
	e.Eventbus.Trigger(C.eiFire, [[]], [7])
	check_eq(probe.Of("Think"), [["Think", [8]]], "Fire thinks in its target group at an eiFire in its own")
	probe.Log.clear()

	e.Blackboard.SetValue(C.eiCooldown, [10], 1000)
	TThinkImpulseTimerCooldownComponent.new().CreateGrouped(e, [10]).Once()
	_frame(1999.0)
	check_eq(probe.Of("Think").filter(func(x): return x[1] == [10]), [], "cooldown not over")
	_frame(2000.0)
	check_eq(probe.Of("Think").filter(func(x): return x[1] == [10]).size(), 1, "thinks after eiCooldown")
	_frame(3000.0)
	check_eq(probe.Of("Think").filter(func(x): return x[1] == [10]).size(), 1, "Once: only the first time")

	var blocked := _unit(1, Vector2.ZERO)
	TThinkBlockComponent.new().Create(blocked)
	var blocked_probe := _probe(blocked)
	_think(blocked)
	check_eq(blocked_probe.Log, [], "the block stops (groupless) eiThink and eiThinkChain before everyone after it")


## TBrainComponent: CanThink (stun, eiWelaActive, ThinksLocal), the chain stops at a consuming brain, passive brains
## think their chain in eiThink.
func test_think_rules() -> void:
	_setup()
	var e := _unit(1, Vector2(3, 4))
	var probe := _probe(e)
	var selftarget: TBrainWelaSelftargetComponent = TBrainWelaSelftargetComponent.new().CreateGrouped(e, [1])
	_think(e, [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [e.ID]]], "selftarget fires at the owner")
	check_eq(probe.Of("ThinkChainEnd").size(), 1, "and lets the chain go on")
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upStunned])
	_think(e, [1])
	check_eq(probe.Of("Fire"), [], "stunned: no thinking")
	selftarget.ThinksPassively()
	_think(e, [1])
	check_eq(probe.Of("Fire").size(), 1, "passive brains think while stunned (in eiThink)")
	e.Blackboard.SetValue(C.eiUnitProperties, [], [])
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiWelaActive, [1], false)
	_think(e, [1])
	check_eq(probe.Of("Fire"), [], "eiWelaActive false: no thinking")
	e.Blackboard.SetValue(C.eiWelaActive, [1], true)
	selftarget.FPassiveThinking = false
	selftarget.ThinksLocal()
	_think(e, [])
	check_eq(probe.Of("Fire"), [], "ThinksLocal: a groupless impulse is not local to group 1")
	_think(e, [1])
	check_eq(probe.Of("Fire").size(), 1, "a group 1 impulse is")
	probe.Log.clear()
	selftarget.FThinkLocal = false

	selftarget.Blocking()
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain", "Stand", "PreFire"], "blocking: stand, eiPreFire, chain consumed")
	probe.Log.clear()
	selftarget.FFireEvent = C.eiFire
	selftarget.FBlocking = false
	TWelaTargetConstraintUnitPropertyComponent.new().CreateGrouped(e, [1]).MustNotHave([C.upInvisible])
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upInvisible])
	_think(e, [1])
	check_eq(probe.Of("Fire"), [], "an invalid owner is not fired at")


## TBrainWelaSavedTargetComponent, TBrainWelaSelftargetGroundComponent, TBrainWelaTargetlessComponent.
func test_wela_brains() -> void:
	_setup()
	var e := _unit(1, Vector2(3, 4))
	var other := _unit(2, Vector2(5, 5))
	var probe := _probe(e)
	e.Blackboard.SetValue(C.eiWelaSavedTargets, [2], [RTarget.Create(e), RTarget.Create(other)])
	var saved: TBrainWelaSavedTargetComponent = TBrainWelaSavedTargetComponent.new().CreateGrouped(e, [1]).SaveGroup([2])
	_think(e, [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [e.ID, other.ID]]], "fires at the saved targets of the save group")
	probe.Log.clear()
	saved.FireAtIndex(1)
	_think(e, [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [other.ID]]], "FireAtIndex: only that target")
	probe.Log.clear()
	saved.FireAtIndex(5)
	_think(e, [1])
	check_eq(probe.Of("Fire"), [], "missing index: nothing")
	saved.Free()

	TBrainWelaSelftargetGroundComponent.new().CreateGrouped(e, [3])
	_think(e, [3])
	check_eq(probe.Of("Fire"), [["Fire", [3], [Vector2(3, 4)]]], "ground at the owner's feet")
	probe.Log.clear()
	TBrainWelaTargetlessComponent.new().CreateGrouped(e, [4]).Blocking()
	_think(e, [4])
	check_eq(probe.Names(), ["Think", "ThinkChain", "Stand", "PreFire"], "targetless, blocking")
	check_eq(probe.Of("PreFire")[0][2], ["empty"], "at one empty target")
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiIsReady, [4], false)
	_think(e, [4])
	check_eq(probe.Of("PreFire"), [], "not ready: nothing")


## TBrainActionComponent: eiPreFire fires at once without an action point, else after it (delayed event), locking
## the chain for max(1, action point, action duration); exile cancels the pending shot.
func test_action_brain() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var other := _unit(2, Vector2(1, 0))
	TBrainActionComponent.new().CreateGroupedAll(e)
	var probe := _probe(e)
	e.Eventbus.Trigger(C.eiPreFire, [[RTarget.Create(other)]], [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [other.ID]]], "no action point: fires at once")
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(probe.Of("ThinkChainEnd").size(), 0, "locked for 1 ms")
	_frame(1001.0)
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(probe.Of("ThinkChainEnd").size(), 1, "unlocked after 1 ms")

	e.Blackboard.SetValue(C.eiWelaActionpoint, [2], 300)
	e.Blackboard.SetValue(C.eiWelaActionduration, [2], 500)
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiPreFire, [[RTarget.Create(other)]], [2])
	check_eq(probe.Of("Fire"), [], "action point 300: not yet")
	_frame(1300.0)
	check_eq(probe.Of("Fire"), [], "not before 300 ms")
	_frame(1301.0)
	check_eq(probe.Of("Fire"), [["Fire", [2], [other.ID]]], "fires at the action point")
	e.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(probe.Of("ThinkChainEnd").size(), 0, "chain locked for the action duration")
	_frame(1501.0)
	e.Eventbus.Trigger(C.eiThinkChain, [], [1])
	check_eq(probe.Of("ThinkChainEnd").size(), 1, "free after 500 ms")

	probe.Log.clear()
	e.Eventbus.Trigger(C.eiPreFire, [[RTarget.Create(other)]], [2])
	e.Eventbus.Write(C.eiExiled, [true])
	check_eq(probe.Of("CancelFire"), [["CancelFire", [2]]], "exile cancels")
	_frame(3000.0)
	check_eq(probe.Of("Fire"), [], "and the shot never comes")
	e.Eventbus.Write(C.eiExiled, [false])
	e.Eventbus.Trigger(C.eiPreFire, [[RTarget.Create(other)]], [2])
	e.Blackboard.SetValue(C.eiIsReady, [2], false)
	_frame(3301.0)
	check_eq(probe.Of("Fire"), [], "not ready at the action point")
	check_eq(probe.Of("CancelFire").size(), 2, "cancels instead")


## TBrainTargetingWelaComponent + TBrainWelaFightComponent with a fake targeting, and TBrainWelaLinkComponent.
func test_fight_and_link_brains() -> void:
	_setup()
	var e := _unit(1, Vector2.ZERO)
	var a := _unit(2, Vector2(1, 0))
	var b := _unit(2, Vector2(2, 0))
	var probe := _probe(e)
	var targeting: FakeTargeting = FakeTargeting.new().CreateGrouped(e, [1])
	targeting.Candidates = [RTarget.Create(a)]
	targeting.Valid = [a.ID]
	var fight: TBrainWelaFightComponent = TBrainWelaFightComponent.new().CreateGrouped(e, [1])
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain", "SetMainTarget", "Fire", "ThinkChainEnd"],
		"not preemptive: main target, fire, the chain goes on")
	check_eq(probe.Of("Fire")[0][2], [a.ID], "at the found target")
	var current = e.Eventbus.Read(C.eiGetCurrentTargets, [], [1])
	check_eq(BrainProbe.Desc(current), [a.ID], "eiGetCurrentTargets")
	probe.Log.clear()
	fight.Preemptive()
	e.Blackboard.SetValue(C.eiIsReady, [1], false)
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain", "Stand"], "preemptive, not ready: stands, chain consumed")
	probe.Log.clear()
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain"], "already active: no second stand")
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiIsReady, [1], true)
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain", "SetMainTarget", "PreFire"], "ready: eiPreFire")
	probe.Log.clear()
	targeting.Valid = []
	targeting.Candidates = []
	_think(e, [1])
	check_eq(probe.Names(), ["Think", "ThinkChain", "SetMainTarget", "ThinkChainEnd"],
		"target invalid: dropped (empty main target), the chain goes on")
	check_eq(probe.Of("SetMainTarget")[0][2], ["empty"], "empty main target")
	fight.Free()
	targeting.Free()
	probe.Log.clear()

	var link_targeting: FakeTargeting = FakeTargeting.new().CreateGrouped(e, [2])
	var link: TBrainWelaLinkComponent = TBrainWelaLinkComponent.new().CreateGrouped(e, [2])
	link_targeting.Candidates = [RTarget.Create(a)]
	link_targeting.Valid = [a.ID, b.ID]
	_think(e, [2])
	check_eq(probe.Of("Fire"), [["Fire", [2], [a.ID]]], "link: builds at once (timer starts expired)")
	probe.Log.clear()
	_think(e, [2])
	check_eq(probe.Of("Fire"), [], "next link only after 250 ms")
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiWelaChangeTarget, [RTarget.Create(b)], [2])
	check_eq(probe.Names(), ["LinkBreak", "SetMainTarget", "Fire", "SetMainTarget"],
		"change target: break the old (list empty: empty main target), link the new, main target")
	check_eq(probe.Of("LinkBreak")[0][2], [a.ID], "breaks a")
	check_eq(probe.Of("Fire")[0][2], [b.ID], "links b")
	check_eq(BrainProbe.Desc(e.Eventbus.Read(C.eiGetCurrentTargets, [], [2])), [b.ID], "b is the target")
	probe.Log.clear()
	e.Eventbus.Trigger(C.eiWelaStop, [], [2])
	check_eq(probe.Names(), ["LinkBreak", "SetMainTarget"], "eiWelaStop breaks every link")
	link.Free()


## TBrainFollowLaneComponent, TBrainApproachComponent, TBrainWaitComponent, TBrainOverwatchComponent,
## TBrainFleeComponent.
func test_movement_brains() -> void:
	_setup()
	var e := _unit(1, Vector2(0, 10))
	var probe := _probe(e)
	var lane: TBrainFollowLaneComponent = TBrainFollowLaneComponent.new().Create(e)
	_think(e)
	check_eq(probe.Of("MoveTo"), [], "no enemy nexus: stands still")
	var nexus := _unit(2, Vector2(0, 100))
	NexusMarker.new().Create(nexus)
	e.Eventbus.Trigger(C.eiAfterCreate)
	check(e.Eventbus.Read(C.eiGetLane, []) != null, "bound to a lane at eiAfterCreate")
	_think(e)
	check_eq(probe.Of("MoveTo"), [["MoveTo", [], [nexus.ID], 0.5]], "walks to the enemy nexus, range = own radius")
	probe.Log.clear()
	_think(e)
	check_eq(probe.Of("MoveTo"), [], "already moving")
	e.Eventbus.Trigger(C.eiMoveTargetReached)
	e.Blackboard.SetValue(C.eiUnitProperties, [], [C.upRooted])
	_think(e)
	check_eq(probe.Of("MoveTo"), [], "rooted: cannot move")
	e.Blackboard.SetValue(C.eiUnitProperties, [], [])
	lane.Free()
	probe.Log.clear()

	var enemy := _unit(2, Vector2(0, 15))
	var targeting: FakeTargeting = FakeTargeting.new().CreateGrouped(e, [0])
	targeting.Candidates = [RTarget.Create(enemy)]
	e.Blackboard.SetValue(C.eiWelaRange, [0], 1.0)
	var approach := TBrainApproachComponent.new().CreateGrouped(e, [0])
	_think(e, [0])
	# range = 1 + 0.5 + 0.5 - 0.1 = 1.9 < 5
	check_eq(probe.Of("MoveTo"), [["MoveTo", [], [enemy.ID], snappedf(1.9, 0.0001)]], "approaches to weapon range")
	check_eq(probe.Of("ThinkChainEnd").size(), 0, "and consumes the chain")
	probe.Log.clear()
	enemy.Position = Vector2(0, 11.5)
	_think(e, [0])
	check_eq(probe.Names(), ["Think", "ThinkChain", "Stand"], "in range: stands")
	probe.Log.clear()
	targeting.Candidates = []
	_think(e, [0])
	check_eq(probe.Names(), ["Think", "ThinkChain", "ThinkChainEnd"], "nothing to approach: the chain goes on")
	approach.Free()
	targeting.Candidates = [RTarget.Create(enemy)]
	var wait := TBrainWaitComponent.new().CreateGrouped(e, [0])
	probe.Log.clear()
	_think(e, [0])
	check_eq(probe.Names(), ["Think", "ThinkChain"], "wait: a target consumes the chain (not moving: no stand)")
	wait.Free()
	targeting.Free()

	var guard := _unit(1, Vector2(20, 20))
	guard.Front = Vector2(1, 0)
	var guard_probe := _probe(guard)
	TBrainOverwatchComponent.new().Create(guard)
	guard.Eventbus.Trigger(C.eiAfterCreate)
	guard.Position = Vector2(20.5, 20)
	_think(guard)
	check_eq(guard_probe.Of("MoveTo"), [], "overwatch: within 1.0, stays")
	guard.Position = Vector2(22, 20)
	guard.Front = Vector2(0, 1)
	_think(guard)
	check_eq(guard_probe.Of("MoveTo"), [["MoveTo", [], [Vector2(20, 20)], 0.0]], "away: back to the post")
	guard.Position = Vector2(20, 20)
	guard.Eventbus.Trigger(C.eiMoveTargetReached)
	check_eq(guard.Front, Vector2(1, 0), "back on post: old front")

	var runner := _unit(1, Vector2(40, 40))
	var runner_probe := _probe(runner)
	TBrainFleeComponent.new().Create(runner).Range(5.0)
	runner.Eventbus.Trigger(C.eiAfterCreate)
	runner.Position = Vector2(44, 40)
	_think(runner)
	check_eq(runner_probe.Of("ThinkChainEnd").size(), 1, "flee: within range, the chain goes on")
	runner.Position = Vector2(45, 40)
	_think(runner)
	check_eq(runner_probe.Of("MoveTo"), [["MoveTo", [], [Vector2(40, 40)], 0.0]], "out of range: runs back")
	check_eq(runner_probe.Of("ThinkChainEnd").size(), 1, "consuming the chain")
	_think(runner)
	check_eq(runner_probe.Of("ThinkChainEnd").size(), 1, "also while running back")


## TBrainProjectileComponent: flies to its saved target, fires and dies; instant, not homing, dead target,
## reflection back to its creator.
func test_projectile_brain() -> void:
	_setup()
	var creator := _unit(1, Vector2.ZERO)
	var target := _unit(2, Vector2(5, 0))
	var target_probe := _probe(target)
	var kills: F.Probe = F.Probe.new().Create(_game_entity)
	var p := _unit(1, Vector2.ZERO)
	var probe := _probe(p)
	p.Blackboard.SetValue(C.eiWelaSavedTargets, [], [RTarget.Create(target)])
	p.Blackboard.SetValue(C.eiCreator, [], creator.ID)
	TBrainProjectileComponent.new().Create(p)
	p.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe.Of("MoveTo"), [["MoveTo", [], [target.ID], 0.0]], "flies to its target")
	p.Eventbus.Trigger(C.eiMoveTargetReached)
	check_eq(probe.Of("Fire"), [["Fire", [], [target.ID]]], "fires on arrival")
	check_eq(target_probe.Of("HitByProjectile"), [["HitByProjectile", [], p.ID]], "the target learns it was hit")
	check_eq(kills.Log, [["DelayedKillEntity", p.ID]], "and dies (global eiDelayedKillEntity)")

	var p2 := _unit(1, Vector2.ZERO)
	var probe2 := _probe(p2)
	p2.Blackboard.SetValue(C.eiWelaSavedTargets, [], [RTarget.Create(target)])
	TBrainProjectileComponent.new().Create(p2).SetNotFollowingTarget()
	p2.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe2.Of("MoveTo"), [["MoveTo", [], [Vector2(5, 0)], 0.0]], "not homing: to the spot")
	check_eq(BrainProbe.Desc(p2.Blackboard.GetValue(C.eiWelaSavedTargets, [])), [Vector2(5, 0)], "saved as ground")

	var p3 := _unit(1, Vector2.ZERO)
	var probe3 := _probe(p3)
	p3.Blackboard.SetValue(C.eiWelaSavedTargets, [], [RTarget.Create(target)])
	TBrainProjectileComponent.new().Create(p3).SetInstant()
	p3.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe3.Names().filter(func(x): return x == "Fire" or x == "MoveTo"), ["Fire"], "instant: fires, no flight")

	var p4 := _unit(1, Vector2.ZERO)
	var probe4 := _probe(p4)
	p4.Blackboard.SetValue(C.eiWelaSavedTargets, [], [RTarget.Create(9999)])
	TBrainProjectileComponent.new().Create(p4)
	p4.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe4.Of("MoveTo"), [], "dead target: never flies")

	target.Blackboard.SetValue(C.eiUnitProperties, [], [C.upProjectileReflector])
	var p5 := _unit(1, Vector2.ZERO)
	var probe5 := _probe(p5)
	p5.Blackboard.SetValue(C.eiWelaSavedTargets, [], [RTarget.Create(target)])
	p5.Blackboard.SetValue(C.eiCreator, [], creator.ID)
	TBrainProjectileComponent.new().Create(p5)
	p5.Eventbus.Trigger(C.eiAfterCreate)
	p5.Eventbus.Trigger(C.eiMoveTargetReached)
	check_eq(p5.TeamID(), 2, "reflected: now in the reflector's team")
	check_eq(BrainProbe.Desc(p5.Blackboard.GetValue(C.eiWelaSavedTargets, [])), [creator.ID], "aimed at its creator")
	probe5.Log.clear()
	_frame(1000.0)
	check_eq(probe5.Of("MoveTo"), [["MoveTo", [], [creator.ID], 0.0]], "and flies back at the next frame")


## The auto-brains.
func test_auto_brains() -> void:
	_setup()
	var e := _unit(1, Vector2(1, 2))
	var enemy := _unit(2, Vector2(3, 3))
	var probe := _probe(e)

	TAutoBrainOnDeathComponent.new().CreateGrouped(e, [1]).FireAtGround()
	TAutoBrainOnDeathComponent.new().CreateGrouped(e, [2]).FireAtKiller()
	e.Eventbus.Trigger(C.eiDie, [enemy.ID, -1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [Vector2(1, 2)]], ["Fire", [2], [enemy.ID]]],
		"on death: at the ground; FireAtKiller at the killer")
	probe.Log.clear()

	var guard := _unit(1, Vector2.ZERO)
	var guard_probe := _probe(guard)
	TAutoBrainPreventDeathComponent.new().CreateGrouped(guard, [3])
	guard.Eventbus.Trigger(C.eiDie, [enemy.ID, -1])
	check_eq(guard_probe.Of("Fire"), [["Fire", [3], [guard.ID]]], "prevent death fires at the owner")
	check_eq(guard_probe.Of("DieEnd"), [], "and stops eiDie")
	guard.Blackboard.SetValue(C.eiIsReady, [3], false)
	guard.Eventbus.Trigger(C.eiDie, [enemy.ID, -1])
	check_eq(guard_probe.Of("DieEnd").size(), 1, "not ready: the unit dies")

	TAutoBrainBuffComponent.new().CreateGrouped(e, [4], [C.btNegative])
	check_eq(e.Eventbus.Read(C.eiBuffed, []), [C.btNegative], "eiBuffed lists its buff type")
	e.Eventbus.Trigger(C.eiRemoveBuffs, [DSet.Make([C.btNegative, C.btPositive]), []])
	check_eq(probe.Of("Fire"), [["Fire", [4], [e.ID]]], "whitelisted: fires to remove the buff")
	e.Eventbus.Trigger(C.eiRemoveBuffs, [[C.btNegative], [C.btNegative]])
	check_eq(probe.Of("Fire").size(), 1, "blacklisted: nothing")
	probe.Log.clear()

	TAutoBrainOnGameEventComponent.new().CreateGrouped(e, [5]).SetEvent("Tech2")
	_bus.Trigger(C.eiGameEvent, ["tech2"])
	_bus.Trigger(C.eiGameEvent, ["tech3"])
	check_eq(probe.Of("Fire"), [["Fire", [5], [e.ID]]], "game event, any case")
	probe.Log.clear()

	TAutoBrainOnCreateComponent.new().CreateGrouped(e, [6]).FireAtSelf()
	TAutoBrainOnCreateComponent.new().CreateGrouped(e, [7]).OnlyBeforeGameStart()
	e.Eventbus.Trigger(C.eiAfterCreate)
	check_eq(probe.Of("Fire"), [["Fire", [6], [e.ID]]], "on create; OnlyBeforeGameStart: the game has started")
	probe.Log.clear()

	var free_brain2 := TAutoBrainOnFreeComponent.new().CreateGrouped(e, [9])
	e.Eventbus.Trigger(C.eiBeforeFree, [], [9])
	check_eq(probe.Of("Fire"), [["Fire", [9], [e.ID]]], "freeing its group fires")
	free_brain2.Free()
	probe.Log.clear()

	TAutoBrainOnUnitPropertyComponent.new().CreateGrouped(e, [10]).TriggerOn([C.upStunned]).MustNotHave([C.upFrozen])
	e.Eventbus.Trigger(C.eiUnitPropertyChanged, [[C.upStunned], false])
	e.Eventbus.Trigger(C.eiUnitPropertyChanged, [[C.upStunned], true])
	e.Eventbus.Trigger(C.eiUnitPropertyChanged, [[C.upStunned, C.upFrozen], false])
	check_eq(probe.Of("Fire"), [["Fire", [10], [e.ID]]], "unit property added, not removed, not with MustNotHave")
	probe.Log.clear()

	var healer = TAutoBrainOnHealedComponent.new().CreateGrouped(e, [11]).TimesForEach(10)
	e.Eventbus.Read(C.eiHeal, [25.0, 1.0, enemy.ID])
	check_eq(probe.Of("Fire").size(), 2, "healed 25, every 10: twice")
	healer.Free()
	probe.Log.clear()

	e.Blackboard.SetIndexedValue(C.eiResourceCap, [], C.reGold, 100.0)
	e.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reGold, 97.0)
	TAutoBrainOnResourceComponent.new().CreateGrouped(e, [12]).TriggerOn([C.reGold]).TimesForEach()
	e.Eventbus.Trigger(C.eiResourceTransaction, [C.reGold, 5.0])
	check_eq(probe.Of("Fire").size(), 3, "5 gold (a single resource), 3 fit under the cap: three times")
	probe.Log.clear()

	var deal: TAutoBrainOnDealDamageComponent = TAutoBrainOnDealDamageComponent.new().CreateGrouped(e, [13]) \
		.WriteAmountTo(C.eiWelaDamage).AddAmountAtWrite().RedirectToSelf()
	e.Blackboard.SetValue(C.eiWelaModifier, [13], 0.5)
	e.Blackboard.SetValue(C.eiWelaDamage, [13], 1.0)
	e.Eventbus.Trigger(C.eiDamageDone, [10.0, [C.dtMelee], enemy])
	check_eq(e.Blackboard.GetValue(C.eiWelaDamage, [13]), 6.0, "writes 10 × 0.5 + 1")
	check_eq(probe.Of("Fire"), [["Fire", [13], [e.ID]]], "and fires at itself")
	deal.Free()
	probe.Log.clear()

	var hurt := _unit(1, Vector2.ZERO)
	var hurt_probe: F.Probe = F.Probe.new().Create(hurt)
	TAutoBrainOnTakeDamageComponent.new().CreateGrouped(hurt, [14]).ModifiesAmount().FireTargetsInGroup([14])
	hurt.Blackboard.SetValue(C.eiWelaModifier, [14], 0.25)
	var hurt_brain_probe := _probe(hurt)
	hurt.Eventbus.Read(C.eiTakeDamage, [8.0, [C.dtMelee], enemy.ID])
	check_eq(hurt_probe.First("TakeDamage"), ["TakeDamage", 2.0], "ModifiesAmount: later handlers see 8 × 0.25")
	check_eq(hurt_brain_probe.Of("Fire"), [["Fire", [14], [enemy.ID]]], "fires at the inflictor")
	var shot := _unit(2, Vector2.ZERO, [C.upProjectile])
	shot.Blackboard.SetValue(C.eiCreator, [], enemy.ID)
	hurt.Eventbus.Read(C.eiTakeDamage, [8.0, [C.dtMelee], shot.ID])
	check_eq(hurt_brain_probe.Of("Fire")[1][2], [enemy.ID], "a projectile resolves to its creator")

	TAutoBrainUnitSpawnComponent.new().CreateGrouped(e, [15])
	var newcomer := _unit(2, Vector2.ZERO)
	check_eq(probe.Of("Fire"), [["Fire", [15], [newcomer.ID]]], "unit spawn: fires at every new entity")
	probe.Log.clear()
	TAutoBrainWelaTargetProducedUnitComponent.new().CreateGrouped(e, [16]).FireOnlyAtUnitsInOwnGroup()
	e.Eventbus.Trigger(C.eiWelaUnitProduced, [newcomer.ID], [17])
	e.Eventbus.Trigger(C.eiWelaUnitProduced, [newcomer.ID], [16])
	check_eq(probe.Of("Fire"), [["Fire", [16], [newcomer.ID]]], "produced unit: own group only")
	probe.Log.clear()
	TAutoBrainOnWelaShotProjectileComponent.new().CreateGrouped(e, [18])
	TAutoBrainOnWelaHitByProjectileComponent.new().CreateGrouped(e, [19])
	e.Eventbus.Trigger(C.eiWelaShotProjectile, [shot])
	e.Eventbus.Trigger(C.eiWelaHitByProjectile, [shot])
	check_eq(probe.Of("Fire").filter(func(x): return x[1] != []),
		[["Fire", [18], [shot.ID]], ["Fire", [19], [shot.ID]]], "shot / hit by projectile")
	probe.Log.clear()
	e.Blackboard.SetValue(C.eiWelaRange, [20], 3.0)
	TAutoBrainOnCommanderAbilityUsedComponent.new().CreateGrouped(e, [20]).ConstraintOnSameTeamID() \
		.ConstraintOnInWelaRange()
	_bus.Trigger(C.eiCommanderAbilityUsed, [2, [RTarget.Create(Vector2(1, 3))]])
	_bus.Trigger(C.eiCommanderAbilityUsed, [1, [RTarget.Create(Vector2(1, 9))]])
	_bus.Trigger(C.eiCommanderAbilityUsed, [1, [RTarget.Create(Vector2(1, 3))]])
	check_eq(probe.Of("Fire"), [["Fire", [20], [Vector2(1, 3)]]], "ability used: own team, in range")


## TBrainWelaCommanderComponent: eiCanUseAbility / eiUseAbility.
func test_commander_brain() -> void:
	_setup()
	var commander := _unit(1, Vector2.ZERO)
	var unit := _unit(1, Vector2(2, 2))
	var probe := _probe(commander)
	var brain: TBrainWelaCommanderComponent = TBrainWelaCommanderComponent.new().CreateGrouped(commander, [1])
	var targets := [RCommanderAbilityTarget.Create(unit), RCommanderAbilityTarget.Create(Vector2(1, 1))]
	check_eq(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [1]), true, "ready, valid")
	commander.Blackboard.SetValue(C.eiAbilityTargetCount, [1], 3)
	check_eq(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [1]), false, "too few targets")
	commander.Blackboard.SetValue(C.eiAbilityTargetCount, [1], 2)
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [unit.ID, Vector2(1, 1)]]], "fires at the targets")
	probe.Log.clear()
	commander.Blackboard.SetValue(C.eiIsReady, [1], false)
	check_eq(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [1]), false, "not ready")
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [1])
	check_eq(probe.Of("Fire"), [], "no fire")
	_bus.Game.Sandbox = true
	check_eq(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [1]), true, "the sandbox ignores readiness")
	_bus.Game.Sandbox = false
	commander.Blackboard.SetValue(C.eiIsReady, [1], true)
	brain.OverrideTargetToOwner()
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [1])
	check_eq(probe.Of("Fire"), [["Fire", [1], [commander.ID]]], "OverrideTargetToOwner")


## Two real server SmallMeleeGolems 2.0 apart (radial reach 2.1): 68 health, 10 melee damage vs light armor = 8.5
## a hit, cooldown 1700 (ready 1167 after the shot at the action point 533), action duration 1133. Both think every
## 250 ms from creation: first shots at 250 + 533 = 783 ms, then ready at 1950, next think at 2000: a hit every
## 1750 ms. The 8th hit (at 783 + 7 × 1750 = 13033 ms) kills: both strike in the same frame, and the second shot
## of that frame comes from a unit already dead (the server entity manager removes it one frame later), so both
## fall together.
func test_real_golems_fight_to_the_death() -> void:
	_setup()
	var golems: Array = []
	var probes: Array = []
	for i in 2:
		var team: int = i + 1
		var pos := Vector2(0, 10) if i == 0 else Vector2(2.0, 10)
		var init := func(x):
			x.ID = _manager.GenerateUniqueID()
			x.Blackboard.SetValue(C.eiTeamID, [], team)
			x.Position = pos
		var g := TEntity.CreateFromScript("Units\\Colorless\\SmallMeleeGolem", _bus, init)
		check(g != null, "created: " + TEntity.LastScriptError)
		if g == null:
			return
		g.Deploy()
		g.Eventbus.Trigger(C.eiAfterCreate)
		golems.append(g)
		probes.append(_probe(g))
	var t := 1000.0
	var dead: Array = [false, false]
	while t < 20000.0 and not (dead[0] or dead[1]):
		t += 1.0
		_frame(t)
		for i in 2:
			dead[i] = golems[i].Eventbus.Read(C.eiIsAlive, []) == false
	for i in 2:
		var hits: Array = probes[i].Of("DamageDone")
		var times: Array = hits.map(func(x): return x[4] - 1000.0)
		check_eq(times, [783.0, 2533.0, 4283.0, 6033.0, 7783.0, 9533.0, 11283.0, 13033.0],
			"golem %d hits every 1750 ms from 783 ms" % i)
		check_eq(hits.map(func(x): return x[2]), [8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5], "8.5 a hit")
		check_eq(hits.map(func(x): return x[3]), _ids(golems[1 - i].ID, 8), "at the other golem")
		check(dead[i], "golem %d is dead" % i)
		check_eq(golems[i].BalanceSingle(C.reHealth), 0.0, "no health left")
	check_eq(t, 14033.0, "both fall at 13033 ms")


func _ids(id: int, n: int) -> Array:
	var Result: Array = []
	for i in n:
		Result.append(id)
	return Result
