#include "math/r_ray_2d.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void RRay2D::_bind_methods() {
	ClassDB::bind_static_method("RRay2D", D_METHOD("Create", "Origin", "Direction"), &RRay2D::Create);
	ClassDB::bind_method(D_METHOD("GetOrigin"), &RRay2D::GetOrigin);
	ClassDB::bind_method(D_METHOD("SetOrigin", "value"), &RRay2D::SetOrigin);
	ClassDB::bind_method(D_METHOD("GetDirection"), &RRay2D::GetDirection);
	ClassDB::bind_method(D_METHOD("SetDirection", "value"), &RRay2D::SetDirection);
	ClassDB::bind_method(D_METHOD("IntersectionWithRay", "otherRay"), &RRay2D::IntersectionWithRay);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Origin"), "SetOrigin", "GetOrigin");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Direction"), "SetDirection", "GetDirection");
}

Ref<RRay2D> RRay2D::Create(const Vector2 &p_origin, const Vector2 &p_direction) {
	Ref<RRay2D> result;
	result.instantiate();
	result->Origin = p_origin;
	result->SetDirection(p_direction);
	return result;
}

Vector2 RRay2D::IntersectionWithRay(const Ref<RRay2D> &p_other_ray) const {
	const double rs = FDirection.cross(p_other_ray->FDirection);
	if (rs == 0) {
		return Vector2(); // Parallel
	}
	const double u = double((p_other_ray->Origin - Origin).cross(p_other_ray->FDirection)) / rs;
	return Origin + (FDirection * real_t(u));
}

} // namespace godot
