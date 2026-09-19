#include "math/t_polygon.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <cmath>

namespace godot {

void TPolygon::_bind_methods() {
	ClassDB::bind_static_method("TPolygon", D_METHOD("Create", "Nodes", "Closed"), &TPolygon::Create, DEFVAL(Array()), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("AddNode", "Node"), &TPolygon::AddNode);
	ClassDB::bind_method(D_METHOD("GetNodes"), &TPolygon::GetNodes);
	ClassDB::bind_method(D_METHOD("GetClosed"), &TPolygon::GetClosed);
	ClassDB::bind_method(D_METHOD("SetClosed", "value"), &TPolygon::SetClosed);
	ClassDB::bind_method(D_METHOD("EdgeCount"), &TPolygon::EdgeCount);
	ClassDB::bind_method(D_METHOD("Edge", "index"), &TPolygon::Edge);
	ClassDB::bind_method(D_METHOD("IsPointInPolygon", "Point"), &TPolygon::IsPointInPolygon);
	ClassDB::bind_method(D_METHOD("NearestPointAtBorder", "Point"), &TPolygon::NearestPointAtBorder);
	ClassDB::bind_method(D_METHOD("EnsurePointInPoly", "Point"), &TPolygon::EnsurePointInPoly);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "Nodes"), "", "GetNodes");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "Closed"), "SetClosed", "GetClosed");
}

Ref<TPolygon> TPolygon::Create(const Array &p_nodes, bool p_closed) {
	Ref<TPolygon> result;
	result.instantiate();
	for (int64_t i = 0; i < p_nodes.size(); i++) {
		result->AddNode(p_nodes[i]);
	}
	result->Closed = p_closed;
	return result;
}

Array TPolygon::GetNodes() const {
	Array result;
	for (const Vector2 &node : Nodes) {
		result.append(node);
	}
	return result;
}

int64_t TPolygon::EdgeCount() const {
	return Closed ? int64_t(Nodes.size()) : int64_t(Nodes.size()) - 1;
}

Ref<RLine2D> TPolygon::Edge(int64_t p_index) const {
	const int64_t count = int64_t(Nodes.size());
	DEV_ASSERT((Closed && p_index <= count - 1) || p_index <= count - 2);
	return RLine2D::CreateFromPoints(Nodes[p_index], Nodes[(p_index + 1) % count]);
}

bool TPolygon::IsPointInPolygon(const Vector2 &p_point) const {
	if (!Closed) {
		return false;
	}
	bool result = false;
	const uint32_t count = Nodes.size();
	const double px = p_point.x;
	const double py = p_point.y;
	for (uint32_t i = 0; i < count; i++) {
		const Vector2 &startpoint = Nodes[i];
		const Vector2 &endpoint = Nodes[(i + 1) % count];
		const double sx = startpoint.x;
		const double sy = startpoint.y;
		const double ex = endpoint.x;
		const double ey = endpoint.y;
		if (((sy > py) != (ey > py)) && (px < (ex - sx) * (py - sy) / (ey - sy) + sx)) {
			result = !result;
		}
	}
	return result;
}

Vector2 TPolygon::NearestPointAtBorder(const Vector2 &p_point) const {
	Vector2 result(NAN, 0);
	const int64_t edges = EdgeCount();
	const int64_t count = int64_t(Nodes.size());
	for (int64_t i = 0; i < edges; i++) {
		// Edge(i).NearestPointOnLine(Point)
		const Vector2 &startpoint = Nodes[i];
		const Vector2 &endpoint = Nodes[(i + 1) % count];
		const Vector2 nearest = RLine2D::NearestPointOnLine(startpoint, endpoint - startpoint, p_point);
		if (std::isnan(result.x) || p_point.distance_to(nearest) < p_point.distance_to(result)) {
			result = nearest;
		}
	}
	return result;
}

Vector2 TPolygon::EnsurePointInPoly(const Vector2 &p_point) const {
	if (IsPointInPolygon(p_point)) {
		return p_point;
	}
	return NearestPointAtBorder(p_point);
}

} // namespace godot
