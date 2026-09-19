#include "math/t_multipolygon.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cmath>

namespace godot {

void TMultipolygon::_bind_methods() {
	ClassDB::bind_static_method("TMultipolygon", D_METHOD("CreateFromData", "Data"), &TMultipolygon::CreateFromData);
	ClassDB::bind_method(D_METHOD("AddPolygon", "Poly", "Subtractive"), &TMultipolygon::AddPolygon);
	ClassDB::bind_method(D_METHOD("IsPointInMultiPolygon", "Point"), &TMultipolygon::IsPointInMultiPolygon);
	ClassDB::bind_method(D_METHOD("EnsurePointInMultiPoly", "Point"), &TMultipolygon::EnsurePointInMultiPoly);
	ClassDB::bind_method(D_METHOD("NextPointOnBorder", "Point"), &TMultipolygon::NextPointOnBorder);
}

Ref<TMultipolygon> TMultipolygon::CreateFromData(const Array &p_data) {
	Ref<TMultipolygon> result;
	result.instantiate();
	for (int64_t i = 0; i < p_data.size(); i++) {
		const Dictionary item = p_data[i];
		const Array xys = item["Nodes"];
		Array nodes;
		for (int64_t j = 0; j < xys.size(); j++) {
			const Array xy = xys[j];
			nodes.append(Vector2(real_t(double(xy[0])), real_t(double(xy[1]))));
		}
		result->AddPolygon(TPolygon::Create(nodes, item["Closed"]), item["Subtractive"]);
	}
	return result;
}

void TMultipolygon::AddPolygon(const Ref<TPolygon> &p_poly, bool p_subtractive) {
	Polygons.push_back(RMultipolygon{ p_poly, p_subtractive });
}

bool TMultipolygon::IsPointInMultiPolygon(const Vector2 &p_point) const {
	int counter = 0;
	for (const RMultipolygon &item : Polygons) {
		if (item.Polygon->IsPointInPolygon(p_point)) {
			if (item.Subtractive) {
				counter--;
			} else {
				counter++;
			}
		}
	}
	return counter > 0;
}

Vector2 TMultipolygon::EnsurePointInMultiPoly(const Vector2 &p_point) const {
	if (IsPointInMultiPolygon(p_point)) {
		return p_point;
	}
	return NextPointOnBorder(p_point);
}

Vector2 TMultipolygon::NextPointOnBorder(const Vector2 &p_point) const {
	Vector2 result(NAN, 0);
	for (const RMultipolygon &item : Polygons) {
		const Vector2 temp = item.Polygon->NearestPointAtBorder(p_point);
		if (std::isnan(result.x) || result.distance_to(p_point) > temp.distance_to(p_point)) {
			result = temp;
		}
	}
	// prevent rounding error, pushin result slightly into polygon
	return result + ((result - p_point).normalized() * real_t(COLLISIONEPSILON));
}

} // namespace godot
