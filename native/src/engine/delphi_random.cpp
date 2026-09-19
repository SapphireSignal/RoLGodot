#include "engine/delphi_random.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

int32_t DelphiRandom::RandSeed = 0;

void DelphiRandom::_bind_methods() {
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("GetRandSeed"), &DelphiRandom::GetRandSeed);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("SetRandSeed", "seed"), &DelphiRandom::SetRandSeed);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("Random"), &DelphiRandom::Random);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("RandomRange", "range"), &DelphiRandom::RandomRange);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("VariedSingle", "varied"), &DelphiRandom::VariedSingle);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("VariedVector2", "varied"), &DelphiRandom::VariedVector2);
	ClassDB::bind_static_method("DelphiRandom", D_METHOD("VariedVector3", "varied"), &DelphiRandom::VariedVector3);
}

uint32_t DelphiRandom::Step() {
	const uint32_t next = uint32_t(RandSeed) * 0x08088405u + 1u;
	RandSeed = int32_t(next);
	return next;
}

int64_t DelphiRandom::GetRandSeed() {
	return RandSeed;
}

void DelphiRandom::SetRandSeed(int64_t p_seed) {
	RandSeed = int32_t(uint32_t(p_seed));
}

double DelphiRandom::Random() {
	return double(Step()) / 4294967296.0;
}

int64_t DelphiRandom::RandomRange(int64_t p_range) {
	return (int64_t(Step()) * p_range) >> 32;
}

// Mean + (Random * 2 - 1) * Variance
static double varied(double p_mean, double p_variance) {
	return p_mean + (DelphiRandom::Random() * 2.0 - 1.0) * p_variance;
}

double DelphiRandom::VariedSingle(const Dictionary &p_varied) {
	return varied(double(p_varied["Mean"]), double(p_varied["Variance"]));
}

Vector2 DelphiRandom::VariedVector2(const Dictionary &p_varied) {
	const Array mean = p_varied["Mean"];
	const Array variance = p_varied["Variance"];
	const double x = varied(double(mean[0]), double(variance[0]));
	const double y = varied(double(mean[1]), double(variance[1]));
	return Vector2(x, y);
}

Vector3 DelphiRandom::VariedVector3(const Dictionary &p_varied) {
	const Array mean = p_varied["Mean"];
	const Array variance = p_varied["Variance"];
	const double x = varied(double(mean[0]), double(variance[0]));
	const double y = varied(double(mean[1]), double(variance[1]));
	const double z = varied(double(mean[2]), double(variance[2]));
	return Vector3(x, y, z);
}

} // namespace godot
