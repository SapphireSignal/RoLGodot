extends RefCounted
## Runtime library of the transpiled scripts (preloaded as `L` by every file in src/content/scripts).
## Holds the hand port of Scripts/HelperScripts/Math.dws and the DWScript built-ins the scripts call.
## See docs/scripts.md for how the transpiler maps names here.

## Math.dws: ALLGROUP = [255]
static var ALLGROUP: Array = [255]
## Math.dws: RVector3ZERO
const RVector3ZERO := Vector3.ZERO

## Resolves the exposed function Game() (BaseConflict.Globals.pas GameResolver). When unset, Game() is the Game of
## the running script's global bus (TEntity.ScriptGame).
static var game_resolver: Callable


# ---- Math.dws: league tables. Index is 1-based ("as long there is no wood league, we skip it") ----

static func s(arr: Array, index: int) -> String:
	return arr[index - 1]


static func i(arr: Array, index: int) -> int:
	return arr[index - 1]


static func ii(arr: Array, index: int, index2: int) -> int:
	return arr[index - 1][index2 - 1]


static func f(arr: Array, index: int) -> float:
	return arr[index - 1]


static func ff(arr: Array, index: int, index2: int) -> float:
	var row: Array = arr[index - 1]
	return row[0] + (row[1] - row[0]) * ((index2 - 1) / 4.0)


# ---- Math.dws: record helpers ----

static func RVector3Add(a: Vector3, b: Vector3) -> Vector3:
	return a + b


static func RVariedSingle_Create(mean: float, variance: float) -> RVariedSingle:
	return RVariedSingle.Create(mean, variance)


# ---- DWScript built-ins ----

## Pascal `div`: integer division truncating toward zero (GDScript int / int does the same).
static func Div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return a / b


## Delphi Round: round half to even (banker's rounding).
static func Round(x: float) -> int:
	var fl := floorf(x)
	var diff := x - fl
	if diff > 0.5:
		return int(fl) + 1
	if diff < 0.5:
		return int(fl)
	return int(fl) + (int(fl) & 1)


static func Trunc(x: float) -> int:
	return int(x)


## System.Math.SameValue(A, B: Single; Epsilon = 0): with Epsilon 0 values within a relative 1E-4
## (SingleResolution = 1E-7 * FuzzFactor 1000, at least 1E-4 absolute) count as the same.
static func SameValue(A: float, B: float, Epsilon: float = 0.0) -> bool:
	if Epsilon == 0:
		Epsilon = maxf(minf(absf(A), absf(B)) * 1E-4, 1E-4)
	if A > B:
		return (A - B) <= Epsilon
	return (B - A) <= Epsilon


## System.Math.CompareValue(A, B: Single; Epsilon = 0): -1 (LessThanValue), 0 (EqualsValue) or 1 (GreaterThanValue).
static func CompareValue(A: float, B: float, Epsilon: float = 0.0) -> int:
	if SameValue(A, B, Epsilon):
		return 0
	if A < B:
		return -1
	return 1


## Random without arguments: a float in [0, 1).
static func Random() -> float:
	return randf()


static func Assigned(value: Variant) -> bool:
	return value != null


static func Assert(condition: bool, message: String = "") -> void:
	if not condition:
		push_error("Script assertion failed" + (": " + message if message else ""))


static func Game() -> Variant:
	if game_resolver.is_valid():
		return game_resolver.call()
	return TEntity.ScriptGame()
