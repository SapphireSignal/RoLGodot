#pragma once

// System / System.Math functions the ports need, with Delphi's semantics.

#include <cmath>
#include <cstdint>

namespace godot {
namespace delphi {

// System.Round: to the nearest integer, halves to the even neighbour (banker's rounding, the FPU default).
inline int64_t Round(double p_x) {
	const double fl = std::floor(p_x);
	const double diff = p_x - fl;
	if (diff > 0.5) {
		return int64_t(fl) + 1;
	}
	if (diff < 0.5) {
		return int64_t(fl);
	}
	return int64_t(fl) + (int64_t(fl) & 1);
}

// System.Trunc
inline int64_t Trunc(double p_x) {
	return int64_t(p_x);
}

// System.Frac: the fractional part, sign kept.
inline double Frac(double p_x) {
	return p_x - double(int64_t(p_x));
}

// System.Math.SameValue(A, B: Single; Epsilon = 0): with Epsilon 0 values within a relative 1E-4 (SingleResolution
// = 1E-7 * FuzzFactor 1000, at least 1E-4 absolute) count as the same.
inline bool SameValue(double p_a, double p_b, double p_epsilon = 0.0) {
	if (p_epsilon == 0) {
		p_epsilon = std::fmax(std::fmin(std::fabs(p_a), std::fabs(p_b)) * 1E-4, 1E-4);
	}
	if (p_a > p_b) {
		return (p_a - p_b) <= p_epsilon;
	}
	return (p_b - p_a) <= p_epsilon;
}

// System.Math.CompareValue(A, B: Single; Epsilon = 0): -1 (LessThanValue), 0 (EqualsValue) or 1 (GreaterThanValue).
inline int CompareValue(double p_a, double p_b, double p_epsilon = 0.0) {
	if (SameValue(p_a, p_b, p_epsilon)) {
		return 0;
	}
	return p_a < p_b ? -1 : 1;
}

} // namespace delphi
} // namespace godot
