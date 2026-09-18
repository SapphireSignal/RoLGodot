class_name DelphiDictionary
extends RefCounted
## Delphi's TDictionary<K, V> with a custom equality comparer (System.Generics.Collections): an open-addressing table
## with linear probing, capacity a power of two, Knuth's backward-shift delete. Ports use it where the original walks
## a dictionary (enumeration follows the slots, i.e. hash order) or removes while walking: removing shifts later
## entries back, so a live walk (NextSlot) can skip one, exactly as the original's `for Key in Dict.Keys`.
## Assumption: the reference snapshot has no RTL; the grow threshold is Berlin's 75% (Delphi 12+ uses 50%). Creation
## with capacity 0: the first Add grows to 4 slots, then the table doubles when Count reaches the threshold.

const EMPTY_HASH := -1
const POSITIVE_MASK := 0x7FFFFFFF

var FHashFunc: Callable  # Key -> int (the comparer's GetHashCode)
var FEqualsFunc: Callable  # (Left, Right) -> bool (the comparer's Equals)
var FHashes: Array[int] = []
var FKeys: Array = []
var FValues: Array = []
var FCount := 0
var FGrowThreshold := 0

var Count: int:
	get:
		return FCount


func Create(HashFunc: Callable, EqualsFunc: Callable) -> DelphiDictionary:
	FHashFunc = HashFunc
	FEqualsFunc = EqualsFunc
	return self


## TDictionary.Hash: positive, never EMPTY_HASH.
func Hash(Key) -> int:
	return POSITIVE_MASK & ((POSITIVE_MASK & int(FHashFunc.call(Key))) + 1)


## The slot of Key, or the complement (-1 - slot) of its insertion point.
func GetBucketIndex(Key, HashCode: int) -> int:
	var L := FHashes.size()
	if L == 0:
		return -1 - 0x7FFFFFFFFFFFFFFF  # not High(NativeInt)
	var Result := HashCode & (L - 1)
	while true:
		var hc := FHashes[Result]
		if hc == EMPTY_HASH:
			return -1 - Result
		if hc == HashCode and FEqualsFunc.call(FKeys[Result], Key):
			return Result
		Result += 1
		if Result >= L:
			Result = 0
	return -1


func Rehash(NewCapPow2: int) -> void:
	if NewCapPow2 == FHashes.size():
		return
	var OldHashes := FHashes
	var OldKeys := FKeys
	var OldValues := FValues
	FHashes = []
	FHashes.resize(NewCapPow2)
	FHashes.fill(EMPTY_HASH)
	FKeys = []
	FKeys.resize(NewCapPow2)
	FValues = []
	FValues.resize(NewCapPow2)
	FGrowThreshold = (NewCapPow2 >> 1) + (NewCapPow2 >> 2)  # 75%
	for i in OldHashes.size():
		if OldHashes[i] != EMPTY_HASH:
			var j := -1 - GetBucketIndex(OldKeys[i], OldHashes[i])
			FHashes[j] = OldHashes[i]
			FKeys[j] = OldKeys[i]
			FValues[j] = OldValues[i]


func Grow() -> void:
	var NewCap := FHashes.size() * 2
	if NewCap == 0:
		NewCap = 4
	Rehash(NewCap)


## Add: a duplicate key is an error (EListError in the original).
func Add(Key, Value) -> void:
	if FCount >= FGrowThreshold:
		Grow()
	var hc := Hash(Key)
	var Index := GetBucketIndex(Key, hc)
	if Index >= 0:
		push_error("DelphiDictionary.Add: Duplicates not allowed")
		return
	Index = -1 - Index
	FHashes[Index] = hc
	FKeys[Index] = Key
	FValues[Index] = Value
	FCount += 1


func ContainsKey(Key) -> bool:
	return GetBucketIndex(Key, Hash(Key)) >= 0


## Items[Key]; a missing key is an error (EListError), null here.
func GetItem(Key):
	var Index := GetBucketIndex(Key, Hash(Key))
	if Index < 0:
		push_error("DelphiDictionary.GetItem: Item not found")
		return null
	return FValues[Index]


func Remove(Key) -> void:
	var Index := GetBucketIndex(Key, Hash(Key))
	if Index < 0:
		return
	var L := FHashes.size()
	FHashes[Index] = EMPTY_HASH
	var Gap := Index
	while true:
		Index += 1
		if Index == L:
			Index = 0
		var hc := FHashes[Index]
		if hc == EMPTY_HASH:
			break
		var Bucket := hc & (L - 1)
		if not _InCircularRange(Gap, Bucket, Index):
			FHashes[Gap] = FHashes[Index]
			FKeys[Gap] = FKeys[Index]
			FValues[Gap] = FValues[Index]
			Gap = Index
			FHashes[Gap] = EMPTY_HASH
	FHashes[Gap] = EMPTY_HASH
	FKeys[Gap] = null
	FValues[Gap] = null
	FCount -= 1


static func _InCircularRange(Bottom: int, Item: int, TopInc: int) -> bool:
	return (Bottom < Item and Item <= TopInc) or (TopInc < Bottom and Item > Bottom) \
		or (TopInc < Bottom and Item <= TopInc)


## TKeyEnumerator.MoveNext: the next used slot after Slot (start with -1), or -1. Walks the live table.
func NextSlot(Slot: int) -> int:
	while Slot < FHashes.size() - 1:
		Slot += 1
		if FHashes[Slot] != EMPTY_HASH:
			return Slot
	return -1


func KeyAt(Slot: int):
	return FKeys[Slot]


func ValueAt(Slot: int):
	return FValues[Slot]


## The keys in enumeration (slot) order, a snapshot.
func Keys() -> Array:
	var Result: Array = []
	var Slot := NextSlot(-1)
	while Slot >= 0:
		Result.append(FKeys[Slot])
		Slot = NextSlot(Slot)
	return Result


func Clear() -> void:
	FHashes = []
	FKeys = []
	FValues = []
	FCount = 0
	FGrowThreshold = 0
