#pragma once

// RLine2D (Engine/Engine.Math.Collision2D.pas:225): a finite line segment, Origin + Direction (the length of Direction
// is the length of the segment). A record in the original: treat it as a value.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "math/r_ray_2d.h"

namespace godot {

class RLine2D : public RefCounted {
	GDCLASS(RLine2D, RefCounted)

protected:
	static void _bind_methods();

public:
	Vector2 Origin;
	Vector2 Direction;

	static Ref<RLine2D> Create(const Vector2 &p_origin, const Vector2 &p_direction);
	static Ref<RLine2D> CreateFromPoints(const Vector2 &p_startpoint, const Vector2 &p_endpoint);
	Vector2 GetOrigin() const { return Origin; }
	void SetOrigin(const Vector2 &p_value) { Origin = p_value; }
	Vector2 GetDirection() const { return Direction; }
	void SetDirection(const Vector2 &p_value) { Direction = p_value; }
	Vector2 GetEndpoint() const { return Origin + Direction; }
	void SetEndpoint(const Vector2 &p_value) { Direction = p_value - Origin; }
	Vector2 GetCenter() const { return Origin + (Direction * real_t(0.5)); }
	double Length() const;
	// Returns whether the given point lies at the left of the line looked from above an in direction.
	bool IsLeft(const Vector2 &p_point) const;
	// Returns the shortest distance of a point to the line.
	double DistanceToPoint(const Vector2 &p_point) const;
	// Returns the closest point on the line to a point.
	Vector2 NearestPointOnLine(const Vector2 &p_point) const { return NearestPointOnLine(Origin, Direction, p_point); }
	// the same for the line Origin + Direction, without an RLine2D object
	static Vector2 NearestPointOnLine(const Vector2 &p_origin, const Vector2 &p_direction, const Vector2 &p_point);
	// Returns the infinite ray which contains the line.
	Ref<RRay2D> ToRay() const;
};

} // namespace godot
