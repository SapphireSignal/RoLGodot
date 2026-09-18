class_name TDelayedEventHandler
extends TObject
## Port of TDelayedEventHandler (GameServer/BaseConflict.Classes.Server.pas:93, implementation :348): a callback the
## server's game loop runs once its timestamp is reached.
## Port notes: the original queued itself in the ServerGame global's DelayedEvents (a TIntPriorityQueue keyed by
## GameTimeManager.GetTimestamp + TimeToEvent); here RegisterEvent takes that queue (callers pass
## GlobalEventbus().Game.DelayedEvents). The per-game clock is TTimeManager until phase 3. ProcessDueEvents is the
## loop of TServerGame.Idle (BaseConflict.Game.Server.pas:830) that runs the due callbacks.

var FInQueue: TIntPriorityQueue = null
var FCallback := Callable()


func Create(Callback = null) -> TObject:
	FCallback = Callback if Callback is Callable else Callable()
	return self


func Destroy() -> void:
	UnregisterEvent()
	FCallback = Callable()
	super()


func Callback() -> void:
	if FCallback.is_valid():
		FCallback.call()
	FInQueue = null


func IsWaiting() -> bool:
	return FInQueue != null


func RegisterEvent(TimeToEvent: int, Queue: TIntPriorityQueue) -> void:
	assert(not IsWaiting(), "TDelayedEventHandler.RegisterEvent: Tried to register same event twice!")
	FInQueue = Queue
	Queue.Insert(self, TTimeManager.GetTimeStamp() + TimeToEvent)


func UnregisterEvent() -> void:
	if IsWaiting():
		FInQueue.Remove(self)
		FInQueue = null


## TServerGame.Idle: runs every handler whose timestamp has been reached, earliest first.
static func ProcessDueEvents(Queue: TIntPriorityQueue) -> void:
	while not Queue.IsEmpty() and Queue.PeekPriority() <= TTimeManager.GetTimeStamp():
		var DelayedEvent: TDelayedEventHandler = Queue.ExtractMin()
		DelayedEvent.Callback()
