#include "math/r_cubic_bezier.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

namespace godot {

void RCubicBezier::_bind_methods() {
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("Create", "P1X", "P1Y", "P2X", "P2Y"), &RCubicBezier::Create);
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("LINEAR"), &RCubicBezier::LINEAR);
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("EASE"), &RCubicBezier::EASE);
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("EASEIN"), &RCubicBezier::EASEIN);
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("EASEOUT"), &RCubicBezier::EASEOUT);
	ClassDB::bind_static_method("RCubicBezier", D_METHOD("EASEINOUT"), &RCubicBezier::EASEINOUT);
	ClassDB::bind_method(D_METHOD("Solve", "T", "Epsilon"), &RCubicBezier::Solve, DEFVAL(1e-6));
	ClassDB::bind_method(D_METHOD("GetP1X"), &RCubicBezier::GetP1X);
	ClassDB::bind_method(D_METHOD("SetP1X", "value"), &RCubicBezier::SetP1X);
	ClassDB::bind_method(D_METHOD("GetP1Y"), &RCubicBezier::GetP1Y);
	ClassDB::bind_method(D_METHOD("SetP1Y", "value"), &RCubicBezier::SetP1Y);
	ClassDB::bind_method(D_METHOD("GetP2X"), &RCubicBezier::GetP2X);
	ClassDB::bind_method(D_METHOD("SetP2X", "value"), &RCubicBezier::SetP2X);
	ClassDB::bind_method(D_METHOD("GetP2Y"), &RCubicBezier::GetP2Y);
	ClassDB::bind_method(D_METHOD("SetP2Y", "value"), &RCubicBezier::SetP2Y);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "P1X"), "SetP1X", "GetP1X");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "P1Y"), "SetP1Y", "GetP1Y");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "P2X"), "SetP2X", "GetP2X");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "P2Y"), "SetP2Y", "GetP2Y");
}

Ref<RCubicBezier> RCubicBezier::Create(double p_p1x, double p_p1y, double p_p2x, double p_p2y) {
	Ref<RCubicBezier> result;
	result.instantiate();
	result->P1X = p_p1x;
	result->P1Y = p_p1y;
	result->P2X = p_p2x;
	result->P2Y = p_p2y;
	return result;
}

double RCubicBezier::Solve(double p_t, double p_epsilon) const {
	p_t = std::clamp(p_t, 0.0, 1.0);
	const double cx = 3.0 * P1X;
	const double bx = 3.0 * (P2X - P1X) - cx;
	const double ax = 1.0 - cx - bx;
	const double cy = 3.0 * P1Y;
	const double by = 3.0 * (P2Y - P1Y) - cy;
	const double ay = 1.0 - cy - by;
	const double s = SolveCurveX(p_t, p_epsilon, ax, bx, cx);
	return ((ay * s + by) * s + cy) * s;
}

double RCubicBezier::SolveCurveX(double p_x, double p_epsilon, double p_ax, double p_bx, double p_cx) {
	double t2 = p_x;
	for (int i = 0; i < 8; i++) {
		const double x2 = ((p_ax * t2 + p_bx) * t2 + p_cx) * t2 - p_x;
		if (std::fabs(x2) < p_epsilon) {
			return t2;
		}
		const double d2 = (3.0 * p_ax * t2 + 2.0 * p_bx) * t2 + p_cx;
		if (std::fabs(d2) < 1e-6) {
			break;
		}
		t2 = t2 - x2 / d2;
	}
	// fall back to the bisection method for reliability
	double t0 = 0.0;
	double t1 = 1.0;
	t2 = p_x;
	if (t2 < t0) {
		return t0;
	}
	if (t2 > t1) {
		return t1;
	}
	while (t0 < t1) {
		const double x2 = ((p_ax * t2 + p_bx) * t2 + p_cx) * t2;
		if (std::fabs(x2 - p_x) < p_epsilon) {
			return t2;
		}
		if (p_x > x2) {
			t0 = t2;
		} else {
			t1 = t2;
		}
		t2 = (t1 - t0) * 0.5 + t0;
	}
	return t2;
}

} // namespace godot
