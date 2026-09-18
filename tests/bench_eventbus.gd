extends SceneTree
## Micro-benchmark of the event bus hot path (not a test: run it by hand like tests/profile_sandbox.gd).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const N = 100000


func _init() -> void:
	TTimeManager.FakeTime = 1000.0
	var thread := TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var commander: TEntity = thread.InternalGame.Commanders[3]
	var bus: TEventbus = commander.Eventbus
	var bb: TBlackboard = commander.Blackboard
	for ei in [C.eiThink, C.eiThinkChain]:
		print("event %d: trigger handlers %d" % [ei, bus.FEventhandler[ei * 3 + C.etTrigger].Subscribers.size()])
	var e := [C.eiExiled, C.eiIsAlive, C.eiResourceBalance]
	for ei in e:
		print("event %d: read handlers %d" % [ei, bus.FEventhandler[ei * 3 + C.etRead].Subscribers.size() if bus.FEventhandler.has(ei * 3 + C.etRead) else 0])
	_bench("empty loop", func(): pass)
	_bench("bus.Read(eiExiled)", func(): bus.Read(C.eiExiled, []))
	_bench("bus.Read(eiIsAlive)", func(): bus.Read(C.eiIsAlive, []))
	_bench("bus.Read(eiExiled, [], [20])", func(): bus.Read(C.eiExiled, [], [20]))
	_bench("bb.GetValue(eiExiled, [])", func(): bb.GetValue(C.eiExiled, []))
	_bench("DSet.Make([])", func(): DSet.Make([]))
	_bench("DSet.Make([20])", func(): DSet.Make([20]))
	_bench("bus.StartEvent+EndEvent", func():
		bus.StartEvent(C.eiExiled, [], [])
		bus.EndEvent(0, [], []))
	_bench("BC.EventIdentifierToNetworkSend(eiThink)", func(): BC.EventIdentifierToNetworkSend(C.eiThink))
	_bench("FEventhandler.get", func(): bus.FEventhandler.get(C.eiExiled * 3 + C.etRead))
	_bench("RParam.AsBoolean(null)", func(): RParam.AsBoolean(null))
	var t := TTimer.new().CreateAndStart(250)
	_bench("TTimer.Expired", func(): t.Expired)
	_bench("bus.Trigger(eiThink, [], [20])", func(): bus.Trigger(C.eiThink, [], [20]))
	_bench("bus.Trigger(eiThink, [], [250]) (no match)", func(): bus.Trigger(C.eiThink, [], [250]))
	thread.Free()
	TTimeManager.FakeTime = null
	TCardInfoManager._Instance = null
	TScenarioInfoManager._Instance = null
	TEntityComponent.FComponentSubscriptionPatterns = {}
	quit(0)


func _bench(label: String, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in N:
		f.call()
	print("%-40s %6.2f us" % [label, float(Time.get_ticks_usec() - t0) / N])
