class_name TPriorityQueue
extends RefCounted
## Port of TPriorityQueue<T : class> (Engine\Engine.Helferlein.DataStructures.pas:416, base TPriorityQueue<T, U>
## :369, implementation :979): a sorted array, highest priority first, so ExtractMin takes the last item.
## Priorities are singles compared with CompareValue, so priorities within a relative 1E-4 count as equal; an
## item inserted among equal priorities comes out before them (last in, first out). TIntPriorityQueue compares
## exactly. The Order property (poDescending) is never used by the game: ascending only.

const L = preload("res://src/runtime/dws/dws_lib.gd")

var FItems: Array = []  # [Item, Priority] pairs


var Count: int:
	get:
		return FItems.size()


func Compare(a, b) -> int:
	return L.CompareValue(a, b)


## Inserts a new item to the queue. Priority is fetched once at insertion.
func Insert(Data, Priority) -> void:
	var i := FItems.size() - 1
	# shift every item the new one is greater than (GreaterThanValue) one up
	while i >= 0 and Compare(Priority, FItems[i][1]) == 1:
		i -= 1
	FItems.insert(i + 1, [Data, Priority])


## Returns the first item in relation to order and removes it from the queue.
func ExtractMin():
	assert(FItems.size() > 0, "TPriorityQueue.ExtractMin: Called with Count = 0!")
	return FItems.pop_back()[0]


func Peek():
	assert(FItems.size() > 0, "TPriorityQueue.Peek: Called with Count = 0!")
	return FItems[-1][0]


func PeekPriority():
	assert(FItems.size() > 0, "TPriorityQueue.PeekPriority: Called with Count = 0!")
	return FItems[-1][1]


func Contains(Item) -> bool:
	for Entry: Array in FItems:
		if Entry[0] == Item:
			return true
	return false


## Removes the first entry of the item (lowest index = highest priority).
func Remove(Item) -> void:
	for i in FItems.size():
		if FItems[i][0] == Item:
			FItems.remove_at(i)
			return


## Changes the priority of an item: remove and insert again.
func DecreaseKey(Item, NewPriority) -> void:
	Remove(Item)
	Insert(Item, NewPriority)


func Clear() -> void:
	FItems.clear()


func IsEmpty() -> bool:
	return FItems.is_empty()
