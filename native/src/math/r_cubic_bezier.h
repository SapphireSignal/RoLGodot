#pragma once

// RCubicBezier (Engine/Engine.Math.pas:755, implementation :5170): a CSS-style timing function through (0, 0),
// (P1X, P1Y), (P2X, P2Y), (1, 1). Solve(t) finds the curve parameter whose x is t (Newton, then bisection) and returns
// its y.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

class RCubicBezier : public RefCounted {
	GDCLASS(RCubicBezier, RefCounted)

	static double SolveCurveX(double p_x, double p_epsilon, double p_ax, double p_bx, double p_cx);

protected:
	static void _bind_methods();

public:
	double P1X = 0.0;
	double P1Y = 0.0;
	double P2X = 1.0;
	double P2Y = 1.0;

	static Ref<RCubicBezier> Create(double p_p1x, double p_p1y, double p_p2x, double p_p2y);
	static Ref<RCubicBezier> LINEAR() { return Create(0, 0, 1, 1); }
	static Ref<RCubicBezier> EASE() { return Create(0.25, 0.1, 0.25, 1.0); }
	static Ref<RCubicBezier> EASEIN() { return Create(0.42, 0, 1.0, 1.0); }
	static Ref<RCubicBezier> EASEOUT() { return Create(0, 0, 0.58, 1.0); }
	static Ref<RCubicBezier> EASEINOUT() { return Create(0.42, 0, 0.58, 1.0); }
	double Solve(double p_t, double p_epsilon = 1e-6) const;

	double GetP1X() const { return P1X; }
	void SetP1X(double p_value) { P1X = p_value; }
	double GetP1Y() const { return P1Y; }
	void SetP1Y(double p_value) { P1Y = p_value; }
	double GetP2X() const { return P2X; }
	void SetP2X(double p_value) { P2X = p_value; }
	double GetP2Y() const { return P2Y; }
	void SetP2Y(double p_value) { P2Y = p_value; }
};

} // namespace godot
