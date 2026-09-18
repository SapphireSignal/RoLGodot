class_name TUnitPropertyComponent
extends TEntityComponent
## Port of TUnitPropertyComponent (BaseConflict.EntityComponents.Shared.pas:36, implementation :2299).
## Adds a unit property to an entity as long this component is attached to this entity.

var FGiveOwner := false
var FRemove := false
## SetUnitProperty
var FUnitProperties: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnUnitProperties", C.eiUnitProperties, C.epMiddle, C.etRead))


func CreateGrouped(Owner = null, ComponentGroup = [], AttachedProperties = []) -> TEntityComponent:
	super(Owner, ComponentGroup)
	FUnitProperties = DSet.Make(AttachedProperties)  # ByteArrayToSetUnitProperies
	Owner.Eventbus.Trigger(C.eiUnitPropertyChanged, [FUnitProperties.duplicate(), false])
	return self


func Destroy() -> void:
	Owner.Eventbus.Trigger(C.eiUnitPropertyChanged, [FUnitProperties.duplicate(), true])
	super()


## Gives the property the owning commander instead of this unit.
func GivePropertyOwner() -> TUnitPropertyComponent:
	FGiveOwner = true
	return self


## Remove the unit properties instead of adding them.
func Remove() -> TUnitPropertyComponent:
	FRemove = true
	return self


func OnAfterCreate() -> bool:
	var Game = GlobalEventbus().Game
	if FGiveOwner and Game != null:
		var Entity = Game.EntityManager.TryGetOwningCommander(Owner)
		if Entity != null:
			Entity.Eventbus.SubscribeRemote(C.eiUnitProperties, C.etRead, C.epMiddle, self, "GetCommanderUnitProperties", 1)
	return true


## Remote read handler on the owning commander's bus. Port: the original leaves Result unassigned when not
## FGiveOwner, which cannot happen (it only subscribes with FGiveOwner); here that returns RPARAMEMPTY.
func GetCommanderUnitProperties(Previous):
	if FGiveOwner:
		return _Apply(RParam.AsSet(Previous))
	return RParam.RPARAMEMPTY


## Adds the unit properties.
func OnUnitProperties(Previous):
	if not FGiveOwner:
		return _Apply(RParam.AsSet(Previous))
	return Previous


func _Apply(Props: Array) -> Array:
	if FRemove:
		return DSet.Difference(Props, FUnitProperties)
	return DSet.Union(Props, FUnitProperties)
