class_name TWelaReadyComponent
extends TEntityComponent
## Port of TWelaReadyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:575, implementation :1830).
## Base of the checks that decide whether a wela (weapon / ability) may fire: eiIsReady read in its groups is
## true only if every ready component says so (an empty value counts as true).

const BC = preload("res://src/runtime/base_conflict_constants.gd")


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIsReady", C.eiIsReady, C.epFirst, C.etRead))


func IsReady() -> bool:
	return true


## Determines whether wela is ready or not.
func OnIsReady(PrevValue):
	var Result: bool = RParam.IsEmpty(PrevValue) or RParam.AsBoolean(PrevValue)
	return IsReady() and Result
