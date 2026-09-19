#pragma once

// RRay2D (Engine/Engine.Math.Collision2D.pas:206): an infinite ray, Direction always normalized. A record in the
// original: treat it as a value.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class RRay2D : public RefCounted {
	GDCLASS(RRay2D, RefCounted)

protected:
	static void _bind_methods();

public:
	Vector2 Origin;
	Vector2 FDirection;

	static Ref<RRay2D> Create(const Vector2 &p_origin, const Vector2 &p_direction);
	Vector2 GetOrigin() const { return Origin; }
	void SetOrigin(const Vector2 &p_value) { Origin = p_value; }
	Vector2 GetDirection() const { return FDirection; }
	void SetDirection(const Vector2 &p_value) { FDirection = p_value.normalized(); }
	// Returns the intersection point; ZERO for parallel rays.
	Vector2 IntersectionWithRay(const Ref<RRay2D> &p_other_ray) const;
};

} // namespace godot
