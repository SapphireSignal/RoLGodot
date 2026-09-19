#pragma once

// TMultipolygon (Engine/Engine.Math.Collision2D.pas:391, implementation :1664): an area made of additive and
// subtractive polygons. The maps' zones (walk zone, drop zones, spell zones, camera) are multipolygons.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "math/t_polygon.h"

namespace godot {

class TMultipolygon : public RefCounted {
	GDCLASS(TMultipolygon, RefCounted)

	static constexpr double COLLISIONEPSILON = 1E-4; // Engine.Math.Collision2D.pas:15

	struct RMultipolygon {
		Ref<TPolygon> Polygon;
		bool Subtractive = false;
	};

	LocalVector<RMultipolygon> Polygons;

protected:
	static void _bind_methods();

public:
	// Builds one from the map JSON (tools/convert_maps.py): [{Subtractive, Closed, Nodes: [[x, y], ...]}, ...].
	static Ref<TMultipolygon> CreateFromData(const Array &p_data);
	void AddPolygon(const Ref<TPolygon> &p_poly, bool p_subtractive);
	// Returns whether a point lies within the described area. For overlapping polygons the number of additive and
	// subtractive polygons are compared for this point.
	bool IsPointInMultiPolygon(const Vector2 &p_point) const;
	// Clamp a point to the multipolygon. If it's outside it will be clamped to the nearest border.
	Vector2 EnsurePointInMultiPoly(const Vector2 &p_point) const;
	Vector2 NextPointOnBorder(const Vector2 &p_point) const;
};

} // namespace godot
