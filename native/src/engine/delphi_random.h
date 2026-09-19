#pragma once

// Delphi's System.Random (the Win32 RTL the original was built with): a global linear congruential generator.
// Each call first steps RandSeed := RandSeed * $08088405 + 1 (32-bit wrap), then uses the new seed as unsigned:
//   Random          = UInt32(RandSeed) * 2^-32              (0 <= x < 1)
//   Random(Range)   = (UInt32(RandSeed) * Range) shr 32      (0 <= x < Range)
// The original reseeds it to replay rolls (Engine.Vegetation.pas: RandSeed := FRandSeed), so ports of such code use
// this instead of Godot's RNG. Engine.Math's varied values (RVariedSingle.Random etc.) are here as well.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>

namespace godot {

class DelphiRandom : public RefCounted {
	GDCLASS(DelphiRandom, RefCounted)

	// System.RandSeed, an Int32 (a global, not a threadvar).
	static int32_t RandSeed;

	static uint32_t Step();

protected:
	static void _bind_methods();

public:
	static int64_t GetRandSeed();
	static void SetRandSeed(int64_t p_seed);
	// System.Random: a float in [0, 1).
	static double Random();
	// System.Random(Range): an int in [0, Range).
	static int64_t RandomRange(int64_t p_range);
	// RVariedSingle.Random: Mean + (Random * 2 - 1) * Variance. `varied` = {Mean: float, Variance: float}.
	static double VariedSingle(const Dictionary &p_varied);
	// RVariedVector2.GetRandomVector with FRadialVaried false (callers force it, like the original's vegetation):
	// one roll per axis, x then y. `varied` = {Mean: [x, y], Variance: [x, y]}.
	static Vector2 VariedVector2(const Dictionary &p_varied);
	// RVariedVector3.GetRandomVector with FRadialVaried false: one roll per axis, x, y, z (also for zero variance).
	static Vector3 VariedVector3(const Dictionary &p_varied);
};

} // namespace godot
