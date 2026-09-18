class_name TRemoteSubscription
extends TObject
## Port of TRemoteSubscription (BaseConflict.Entity.pas:123, implementation :2672): a component subscribed on
## another eventbus. Whichever of the two is freed first tells the other side; both must be freed eventually.

var FTargetEventbus = null  # TEventbus
var FTargetComponent = null  # TEntityComponent
var FComponentFreed := false
var FEventbusFreed := false
var FEvent := 0
var FEventType := 0
var FEventPriotity := 0
var FRefCounter := 0


func Create(TargetComponent = null, TargetEventbus = null, Event: int = 0, EventType: int = 0, EventPriority: int = 0) -> TRemoteSubscription:
	FComponentFreed = false
	FEventbusFreed = false
	FTargetEventbus = TargetEventbus
	FTargetComponent = TargetComponent
	FEvent = Event
	FEventPriotity = EventPriority
	FEventType = EventType
	FRefCounter = 2
	return self


func DecRefCounter() -> void:
	FRefCounter -= 1
	# eventbus and component are freed, free me too ;)
	if FRefCounter <= 0:
		Free()


func Destroy() -> void:
	if not FComponentFreed:
		push_error("TRemoteSubscription.Destroy: Component(%s) has not been freed!" % FTargetComponent.ClassName())
	if not FEventbusFreed:
		push_error("TRemoteSubscription.Destroy: Eventbus has not been freed!")
	FTargetEventbus = null
	FTargetComponent = null
	super()


func FreeComponent() -> void:
	assert(FComponentFreed == false)
	FComponentFreed = true
	# if TargetEventbus exist, unsubscribe!
	if not FEventbusFreed:
		FTargetEventbus.Unsubscribe(FEvent, FEventType, FEventPriotity, FTargetComponent)
	# delete manually to prevent auto unsubscribe on eventbus
	FTargetComponent.DeleteSubscribedEvent(FTargetComponent.LookUpSubscribedEvent(FTargetEventbus, FEvent, FEventType))
	DecRefCounter()


func FreeEventbus() -> void:
	assert(FEventbusFreed == false)
	FEventbusFreed = true
	DecRefCounter()
