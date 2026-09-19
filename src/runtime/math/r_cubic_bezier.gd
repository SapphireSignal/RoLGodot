class_name RCubicBezier
extends RefCounted
## Port of RCubicBezier (Engine/Engine.Math.pas:755, implementation :5170): a CSS-style timing function through
## (0, 0), (P1X, P1Y), (P2X, P2Y), (1, 1). Solve(t) finds the curve parameter whose x is t (Newton, then bisection)
## and returns its y.

var P1X := 0.0
var P1Y := 0.0
var P2X := 1.0
var P2Y := 1.0


static func Create(P1X_: float, P1Y_: float, P2X_: float, P2Y_: float) -> RCubicBezier:
	var Result := RCubicBezier.new()
	Result.P1X = P1X_
	Result.P1Y = P1Y_
	Result.P2X = P2X_
	Result.P2Y = P2Y_
	return Result


static func LINEAR() -> RCubicBezier:
	return Create(0, 0, 1, 1)


static func EASE() -> RCubicBezier:
	return Create(0.25, 0.1, 0.25, 1.0)


static func EASEIN() -> RCubicBezier:
	return Create(0.42, 0, 1.0, 1.0)


static func EASEOUT() -> RCubicBezier:
	return Create(0, 0, 0.58, 1.0)


static func EASEINOUT() -> RCubicBezier:
	return Create(0.42, 0, 0.58, 1.0)


func Solve(T: float, Epsilon := 1e-6) -> float:
	T = clampf(T, 0.0, 1.0)
	var cx := 3.0 * P1X
	var bx := 3.0 * (P2X - P1X) - cx
	var aX := 1.0 - cx - bx
	var cy := 3.0 * P1Y
	var by := 3.0 * (P2Y - P1Y) - cy
	var aY := 1.0 - cy - by
	var s := _solve_curve_x(T, Epsilon, aX, bx, cx)
	return ((aY * s + by) * s + cy) * s


static func _solve_curve_x(X: float, Epsilon: float, aX: float, bx: float, cx: float) -> float:
	var t2 := X
	for i in 8:
		var x2 := ((aX * t2 + bx) * t2 + cx) * t2 - X
		if absf(x2) < Epsilon:
			return t2
		var d2 := (3.0 * aX * t2 + 2.0 * bx) * t2 + cx
		if absf(d2) < 1e-6:
			break
		t2 = t2 - x2 / d2
	# fall back to the bisection method for reliability
	var t0 := 0.0
	var t1 := 1.0
	t2 = X
	if t2 < t0:
		return t0
	if t2 > t1:
		return t1
	while t0 < t1:
		var x2 := ((aX * t2 + bx) * t2 + cx) * t2
		if absf(x2 - X) < Epsilon:
			return t2
		if X > x2:
			t0 = t2
		else:
			t1 = t2
		t2 = (t1 - t0) * 0.5 + t0
	return t2
