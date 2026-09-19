class_name TThreadContext
extends RefCounted
## The original's threadvars (a game server runs in its own TGameThread): the executing event and its stack
## (BaseConflict.Entity.pas CurrentEvent / Eventstack), the game clock (BaseConflict.Globals.pas GameTimeManager) and
## the per-game NOT_PAYED_RESOURCES (TWelaEffectPayCostComponent class threadvar); the port adds what it keeps in
## statics for the same reasons: the running script's bus stack, the last script error, the event-group version. Game / Map / GlobalEventbus / EntityDataCache already hang on each side's global bus.
##
## The shared code keeps using its static names (TEventbus.CurrentEvent_CalledToGroup, TTimeManager.ZDiff, ...):
## those are static properties that read and write Current(), the calling thread's context. The event bus's own hot
## path uses the context its bus captured at creation (TEventbus.Ctx), which is the same object on that thread.
##
## Threads: the main thread's context is _main_ctx (Enter / Leave swap it, e.g. TGameThread running a server frame on
## the main thread in tests or before its thread starts); a started game thread registers its context in _by_thread
## during a handshake (RegisterThread) before it touches any game code, so the table is only read concurrently.

const C = preload("res://src/runtime/dws/dws_const.gd")

## the port's statics, per thread
var CurrentEvent_EventIdentifier := 0
var CurrentEvent_CalledToGroup: Array = []
var CurrentParameters: Array = []
var GroupsVersion := 0
var ZDiff := 0.0
var LastTickTime := 0.0
var ScriptEventbusStack: Array = []
var LastScriptError := ""
## TWelaEffectPayCostComponent.DEFAULT_NOT_PAYED_RESOURCES = [reLevel, reTier]
var NotPayedResources: Array = [C.reLevel, C.reTier]
## lazy caches (filled per thread instead of locked): TEntityComponent.FComponentSubscriptionPatterns,
## TEntity._component_classes
var SubscriptionPatterns := {}
var ComponentClasses := {}
## TEventbus.Prof, the handler profiler (a development aid), and its call stack of child times
var Prof = null
var ProfChildTime: Array = []

static var _main_id := OS.get_thread_caller_id()
static var _main_ctx: TThreadContext = TThreadContext.new()
static var _by_thread := {}


static func Current() -> TThreadContext:
	var id := OS.get_thread_caller_id()
	if id == _main_id:
		return _main_ctx
	return _by_thread.get(id, _main_ctx)


## Makes Ctx the calling (main) thread's context; returns the one it replaces, for Leave.
static func Enter(Ctx: TThreadContext) -> TThreadContext:
	assert(OS.get_thread_caller_id() == _main_id, "TThreadContext.Enter: only the main thread swaps its context")
	var Previous := _main_ctx
	_main_ctx = Ctx
	return Previous


static func Leave(Previous: TThreadContext) -> void:
	_main_ctx = Previous


## Registers a started thread's context (call from the main thread while that thread waits, see TGameThread).
static func RegisterThread(ThreadID: int, Ctx: TThreadContext) -> void:
	_by_thread[ThreadID] = Ctx


## After the thread has finished.
static func UnregisterThread(ThreadID: int) -> void:
	_by_thread.erase(ThreadID)
