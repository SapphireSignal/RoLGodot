#include "math/r_line_2d.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

namespace godot {

void RLine2D::_bind_methods() {
	ClassDB::bind_static_method("RLine2D", D_METHOD("Create", "Origin", "Direction"), &RLine2D::Create);
	ClassDB::bind_static_method("RLine2D", D_METHOD("CreateFromPoints", "Startpoint", "Endpoint"), &RLine2D::CreateFromPoints);
	ClassDB::bind_method(D_METHOD("GetOrigin"), &RLine2D::GetOrigin);
	ClassDB::bind_method(D_METHOD("SetOrigin", "value"), &RLine2D::SetOrigin);
	ClassDB::bind_method(D_METHOD("GetDirection"), &RLine2D::GetDirection);
	ClassDB::bind_method(D_METHOD("SetDirection", "value"), &RLine2D::SetDirection);
	ClassDB::bind_method(D_METHOD("GetEndpoint"), &RLine2D::GetEndpoint);
	ClassDB::bind_method(D_METHOD("SetEndpoint", "value"), &RLine2D::SetEndpoint);
	ClassDB::bind_method(D_METHOD("GetCenter"), &RLine2D::GetCenter);
	ClassDB::bind_method(D_METHOD("Length"), &RLine2D::Length);
	ClassDB::bind_method(D_METHOD("IsLeft", "Point"), &RLine2D::IsLeft);
	ClassDB::bind_method(D_METHOD("DistanceToPoint", "Point"), &RLine2D::DistanceToPoint);
	ClassDB::bind_method(D_METHOD("NearestPointOnLine", "Point"),
			static_cast<Vector2 (RLine2D::*)(const Vector2 &) const>(&RLine2D::NearestPointOnLine));
	ClassDB::bind_method(D_METHOD("ToRay"), &RLine2D::ToRay);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Origin"), "SetOrigin", "GetOrigin");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Direction"), "SetDirection", "GetDirection");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Endpoint"), "SetEndpoint", "GetEndpoint");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Center"), "", "GetCenter");
}

Ref<RLine2D> RLine2D::Create(const Vector2 &p_origin, const Vector2 &p_direction) {
	Ref<RLine2D> result;
	result.instantiate();
	result->Origin = p_origin;
	result->Direction = p_direction;
	return result;
}

Ref<RLine2D> RLine2D::CreateFromPoints(const Vector2 &p_startpoint, const Vector2 &p_endpoint) {
	Ref<RLine2D> result;
	result.instantiate();
	result->Origin = p_startpoint;
	result->SetEndpoint(p_endpoint);
	return result;
}

double RLine2D::Length() const {
	return Direction.length();
}

bool RLine2D::IsLeft(const Vector2 &p_point) const {
	return Origin.direction_to(p_point).dot(Vector2(-Direction.y, Direction.x)) >= 0;
}

double RLine2D::DistanceToPoint(const Vector2 &p_point) const {
	return NearestPointOnLine(p_point).distance_to(p_point);
}

Vector2 RLine2D::NearestPointOnLine(const Vector2 &p_origin, const Vector2 &p_direction, const Vector2 &p_point) {
	const double dl = 1.0 / double(p_direction.length());
	const double along = double((p_point - p_origin).dot(p_direction * real_t(dl))) * dl;
	return p_direction * real_t(std::clamp(along, 0.0, 1.0)) + p_origin;
}

Ref<RRay2D> RLine2D::ToRay() const {
	return RRay2D::Create(Origin, Direction);
}

} // namespace godot
