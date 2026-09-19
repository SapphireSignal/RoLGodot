extends "res://tests/test_case.gd"
## The game server on its own thread (TGameThread.StartThread, the original's TGameThread.Execute) with a client in
## the same process, and the per-thread state that makes it safe (TThreadContext, the original's threadvars). Real
## time: FakeTime is one clock for both threads.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const TOKEN = "1"  # CreateTestserverGameInfo's secret key

var _thread: TGameThread = null
var _client: TClientGame = null


func after_each() -> void:
	if _thread != null:
		_thread.StopThread()
	if _client != null:
		_client.Free()
	_client = null
	if _thread != null:
		_thread.Free()
	_thread = null
	super()


func _client_info() -> TGameInformation:
	var info := TGameInformation.new().Create()
	info.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	info.League = BC.TESTSERVER_SENARIO_LEAGUE
	info.Scenario = HScenario.ResolveScenario(info.ScenarioUID, info.League)
	return info


func _client_frame() -> void:
	TThreadContext.Current().GameTimeManager.TickTack()
	_client.GlobalEventbus.Trigger(C.eiIdle, [])
	_client.ReadyWhenLoaded()
	_client.Idle()


## The context: each thread sees its own; Enter / Leave swap the main thread's; the event bus's current event and
## the clock follow it.
func test_thread_context() -> String:
	var main := TThreadContext.Current()
	var other := TThreadContext.new()
	TEventbus.CurrentEvent_EventIdentifier = 7
	TThreadContext.Current().GameTimeManager.ZDiff = 16.0
	var outer := TThreadContext.Enter(other)
	check(TThreadContext.Current() == other, "entered")
	check_eq(TEventbus.CurrentEvent_EventIdentifier, 0, "the other context's event")
	check_eq(TThreadContext.Current().GameTimeManager.ZDiff, 0.0, "the other context's clock")
	TThreadContext.Current().GameTimeManager.ZDiff = 32.0
	TThreadContext.Leave(outer)
	check(TThreadContext.Current() == main, "left")
	check_eq(TEventbus.CurrentEvent_EventIdentifier, 7, "main's event kept")
	check_eq(TThreadContext.Current().GameTimeManager.ZDiff, 16.0, "main's clock kept")
	check_eq(other.GameTimeManager.ZDiff, 32.0, "the other's clock written there")
	TEventbus.CurrentEvent_EventIdentifier = 0
	TThreadContext.Current().GameTimeManager.ZDiff = 0.0
	return take_failure()


## The sandbox server joined by a local client, then on its own thread for ~1.5 s while the main thread runs the
## client: the server computes its frames at the heartbeat on another thread (the client never calls it), the game
## starts once the client is ready, the client keeps getting the game over the network; StopThread ends it.
func test_server_on_its_own_thread() -> String:
	_thread = TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	_client = TClientGame.JoinLocal(_thread, _client_info(), TOKEN)
	check(_client != null, "joined")
	if _client == null:
		return take_failure()
	_thread.DoComputeGame()
	_client_frame()
	var entities_before := _client.EntityManager.DeployedEntityCount
	_thread.StartThread()
	check(_thread.IsThreadRunning(), "running")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		_client_frame()
		OS.delay_msec(8)
	var elapsed := Time.get_ticks_msec() - start
	_thread.StopThread()
	check(not _thread.IsThreadRunning(), "stopped")
	check(_thread.ThreadID != -1 and _thread.ThreadID != OS.get_thread_caller_id(), "frames ran on another thread")
	var expected := elapsed / float(TGameThread.TARGET_FRAMETIME)
	check(_thread.ThreadFrames >= expected * 0.6 and _thread.ThreadFrames <= expected * 1.2,
		"about one frame per heartbeat: %d frames in %d ms" % [_thread.ThreadFrames, elapsed])
	check(_client.IsReady(), "the client is ready")
	# (HasStarted is the end of the warm-up countdown, 10 s later; Start ran when the state became running)
	check_eq(_thread.State, TGameThread.gsRunning, "the server started the game once the client was ready")
	check(_client.EntityManager.DeployedEntityCount >= entities_before, "the client still has the world")
	check(not TThreadContext._by_thread.has(_thread.ThreadID), "the thread's context is unregistered")
	check_eq(TEntity.LastScriptError, "", "no script errors on the main thread")
	check_eq(_thread.FContext.LastScriptError, "", "no script errors on the server thread")
	return take_failure()
