#pragma once

// Engine.Math.pas RMatrix helpers on game-space Transform3D values. An RMatrix acts on column vectors (M * v) with
// Column[0..2] = Left, Up, Front and Column[3] = Translation; the port keeps it as a Transform3D in game space:
// basis.x = Left, basis.y = Up, basis.z = Front, origin = Translation, and RMatrix * RMatrix = Transform3D *
// Transform3D. (Game space is the original's left-handed world; TMesh.ToGodot maps it to Godot.)

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>

namespace godot {

class RMatrix : public RefCounted {
	GDCLASS(RMatrix, RefCounted)

protected:
	static void _bind_methods();

public:
	// RMatrix.CreateTranslation
	static Transform3D CreateTranslation(const Vector3 &p_position);
	// RMatrix.CreateBase(Left, Up, Front)
	static Transform3D CreateBase(const Vector3 &p_left, const Vector3 &p_up, const Vector3 &p_front);
	// RMatrix.CreateSaveBase(Front, Up): normalized, Up made orthogonal to Front and the derived Left.
	static Transform3D CreateSaveBase(const Vector3 &p_front, const Vector3 &p_up);
	// RMatrix.CreateRotationPitchYawRoll(Pitch = x, Yaw = y, Roll = z) = RotationY(Yaw) * RotationX(Pitch) *
	// RotationZ(Roll). The original's matrices (column X, row Y in _XY): RotationY rows [[c, 0, -s], [0, 1, 0],
	// [s, 0, c]], RotationX [[1, 0, 0], [0, c, s], [0, -s, c]], RotationZ [[c, s, 0], [-s, c, 0], [0, 0, 1]].
	static Basis RotationPitchYawRoll(const Vector3 &p_pitch_yaw_roll);
	static Transform3D CreateRotationPitchYawRoll(const Vector3 &p_pitch_yaw_roll);
	// RVector3.RotatePitchYawRoll = CreateRotationPitchYawRoll * v
	static Vector3 RotatePitchYawRoll(const Vector3 &p_v, const Vector3 &p_pitch_yaw_roll);
	// RMatrix.Column[Index] (0..2 the base vectors, 3 the translation).
	static Vector3 GetColumn(const Transform3D &p_m, int64_t p_index);
	static Transform3D SetColumn(Transform3D p_m, int64_t p_index, const Vector3 &p_value);
	// RMatrix.SwapXY / SwapXZ / SwapYZ: swap two base columns.
	static Transform3D SwapColumns(Transform3D p_m, int64_t p_a, int64_t p_b);
};

} // namespace godot
