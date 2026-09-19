#include "math/r_matrix.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

namespace godot {

void RMatrix::_bind_methods() {
	ClassDB::bind_static_method("RMatrix", D_METHOD("CreateTranslation", "Position"), &RMatrix::CreateTranslation);
	ClassDB::bind_static_method("RMatrix", D_METHOD("CreateBase", "Left", "Up", "Front"), &RMatrix::CreateBase);
	ClassDB::bind_static_method("RMatrix", D_METHOD("CreateSaveBase", "Front", "Up"), &RMatrix::CreateSaveBase);
	ClassDB::bind_static_method("RMatrix", D_METHOD("RotationPitchYawRoll", "PitchYawRoll"), &RMatrix::RotationPitchYawRoll);
	ClassDB::bind_static_method("RMatrix", D_METHOD("CreateRotationPitchYawRoll", "PitchYawRoll"), &RMatrix::CreateRotationPitchYawRoll);
	ClassDB::bind_static_method("RMatrix", D_METHOD("RotatePitchYawRoll", "v", "PitchYawRoll"), &RMatrix::RotatePitchYawRoll);
	ClassDB::bind_static_method("RMatrix", D_METHOD("GetColumn", "m", "Index"), &RMatrix::GetColumn);
	ClassDB::bind_static_method("RMatrix", D_METHOD("SetColumn", "m", "Index", "Value"), &RMatrix::SetColumn);
	ClassDB::bind_static_method("RMatrix", D_METHOD("SwapColumns", "m", "a", "b"), &RMatrix::SwapColumns);
}

static Basis columns(const Vector3 &p_x, const Vector3 &p_y, const Vector3 &p_z) {
	Basis result;
	result.set_column(0, p_x);
	result.set_column(1, p_y);
	result.set_column(2, p_z);
	return result;
}

// a Basis from the rows of the original's matrix (single components)
static Basis rows(double p_00, double p_01, double p_02, double p_10, double p_11, double p_12, double p_20, double p_21,
		double p_22) {
	return Basis(real_t(p_00), real_t(p_01), real_t(p_02), real_t(p_10), real_t(p_11), real_t(p_12), real_t(p_20),
			real_t(p_21), real_t(p_22));
}

Transform3D RMatrix::CreateTranslation(const Vector3 &p_position) {
	return Transform3D(Basis(), p_position);
}

Transform3D RMatrix::CreateBase(const Vector3 &p_left, const Vector3 &p_up, const Vector3 &p_front) {
	return Transform3D(columns(p_left, p_up, p_front), Vector3());
}

Transform3D RMatrix::CreateSaveBase(const Vector3 &p_front, const Vector3 &p_up) {
	const Vector3 f = p_front.normalized();
	Vector3 u = p_up.normalized();
	const Vector3 l = -f.cross(u).normalized();
	u = f.cross(l).normalized();
	return CreateBase(l, u, f);
}

Basis RMatrix::RotationPitchYawRoll(const Vector3 &p_pitch_yaw_roll) {
	const double y = p_pitch_yaw_roll.y;
	const double x = p_pitch_yaw_roll.x;
	const double z = p_pitch_yaw_roll.z;
	return rows(std::cos(y), 0, -std::sin(y), 0, 1, 0, std::sin(y), 0, std::cos(y)) *
			rows(1, 0, 0, 0, std::cos(x), std::sin(x), 0, -std::sin(x), std::cos(x)) *
			rows(std::cos(z), std::sin(z), 0, -std::sin(z), std::cos(z), 0, 0, 0, 1);
}

Transform3D RMatrix::CreateRotationPitchYawRoll(const Vector3 &p_pitch_yaw_roll) {
	return Transform3D(RotationPitchYawRoll(p_pitch_yaw_roll), Vector3());
}

Vector3 RMatrix::RotatePitchYawRoll(const Vector3 &p_v, const Vector3 &p_pitch_yaw_roll) {
	return RotationPitchYawRoll(p_pitch_yaw_roll).xform(p_v);
}

Vector3 RMatrix::GetColumn(const Transform3D &p_m, int64_t p_index) {
	return p_index == 3 ? p_m.origin : p_m.basis.get_column(int(p_index));
}

Transform3D RMatrix::SetColumn(Transform3D p_m, int64_t p_index, const Vector3 &p_value) {
	if (p_index == 3) {
		p_m.origin = p_value;
	} else {
		p_m.basis.set_column(int(p_index), p_value);
	}
	return p_m;
}

Transform3D RMatrix::SwapColumns(Transform3D p_m, int64_t p_a, int64_t p_b) {
	const Vector3 temp = p_m.basis.get_column(int(p_a));
	p_m.basis.set_column(int(p_a), p_m.basis.get_column(int(p_b)));
	p_m.basis.set_column(int(p_b), temp);
	return p_m;
}

} // namespace godot
