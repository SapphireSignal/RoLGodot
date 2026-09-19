#pragma once

// TPolygon (Engine/Engine.Math.Collision2D.pas:334, implementation :1402): a polyline, a polygon when Closed. Only the
// members the game uses are ported (the rest serve the map editor).

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>

#include "math/r_line_2d.h"

namespace godot {

class TPolygon : public RefCounted {
	GDCLASS(TPolygon, RefCounted)

protected:
	static void _bind_methods();

public:
	LocalVector<Vector2> Nodes;
	bool Closed = false;

	static Ref<TPolygon> Create(const Array &p_nodes = Array(), bool p_closed = false);
	void AddNode(const Vector2 &p_node) { Nodes.push_back(p_node); }
	Array GetNodes() const;
	bool GetClosed() const { return Closed; }
	void SetClosed(bool p_value) { Closed = p_value; }
	int64_t EdgeCount() const;
	Ref<RLine2D> Edge(int64_t p_index) const;
	// Returns whether a point lies within the polygon (even-odd rule); an open polyline contains nothing.
	bool IsPointInPolygon(const Vector2 &p_point) const;
	// Returns the closest point on the border of the poly to a point (EMPTY = NaN x without edges).
	Vector2 NearestPointAtBorder(const Vector2 &p_point) const;
	// Clamp a point to the polygon. If it's outside it will be clamped to the nearest border.
	Vector2 EnsurePointInPoly(const Vector2 &p_point) const;
};

} // namespace godot
