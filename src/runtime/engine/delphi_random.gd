class_name DelphiRandom
extends RefCounted
## Delphi's System.Random (the Win32 RTL the original was built with): a global linear congruential generator.
## Each call first steps RandSeed := RandSeed * $08088405 + 1 (32-bit wrap), then uses the new seed as unsigned:
##   Random          = UInt32(RandSeed) * 2^-32              (0 <= x < 1)
##   Random(Range)   = (UInt32(RandSeed) * Range) shr 32      (0 <= x < Range)
## The original reseeds it to replay rolls (Engine.Vegetation.pas: RandSeed := FRandSeed), so ports of such code
## use this instead of Godot's RNG. Engine.Math's varied values (RVariedSingle.Random etc.) are here as well.

## System.RandSeed, an Int32.
static var RandSeed: int = 0


static func _step() -> int:
	var next := (RandSeed * 0x08088405 + 1) & 0xFFFFFFFF
	RandSeed = next - 0x100000000 if next >= 0x80000000 else next
	return next


## System.Random: a float in [0, 1).
static func Random() -> float:
	return _step() / 4294967296.0


## System.Random(Range): an int in [0, Range).
static func RandomRange(range_value: int) -> int:
	return (_step() * range_value) >> 32


## RVariedSingle.Random: Mean + (Random * 2 - 1) * Variance. `varied` = {Mean: float, Variance: float}.
static func VariedSingle(varied: Dictionary) -> float:
	return float(varied.Mean) + (Random() * 2.0 - 1.0) * float(varied.Variance)


## RVariedVector2.GetRandomVector with FRadialVaried false (callers force it, like the original's vegetation):
## one roll per axis, x then y. `varied` = {Mean: [x, y], Variance: [x, y]}.
static func VariedVector2(varied: Dictionary) -> Vector2:
	var mean: Array = varied.Mean
	var variance: Array = varied.Variance
	var x := float(mean[0]) + (Random() * 2.0 - 1.0) * float(variance[0])
	var y := float(mean[1]) + (Random() * 2.0 - 1.0) * float(variance[1])
	return Vector2(x, y)


## RVariedVector3.GetRandomVector with FRadialVaried false: one roll per axis, x, y, z (also for zero variance).
static func VariedVector3(varied: Dictionary) -> Vector3:
	var mean: Array = varied.Mean
	var variance: Array = varied.Variance
	var x := float(mean[0]) + (Random() * 2.0 - 1.0) * float(variance[0])
	var y := float(mean[1]) + (Random() * 2.0 - 1.0) * float(variance[1])
	var z := float(mean[2]) + (Random() * 2.0 - 1.0) * float(variance[2])
	return Vector3(x, y, z)
