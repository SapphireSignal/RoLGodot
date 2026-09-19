#pragma once

// T2DGrid<T> (Engine/Engine.Helferlein.DataStructures.pas:428, implementation :833): a Width x Height grid. Nodes are
// read and written safely: out of range, Get returns the default value and Set does nothing. Setting Size resets
// every node to the default value.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/local_vector.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>

namespace godot {

class T2DGrid : public RefCounted {
	GDCLASS(T2DGrid, RefCounted)

	Variant FDefaultValue;
	int64_t FWidth = 0;
	int64_t FHeight = 0;
	LocalVector<Variant> FGrid; // x * FHeight + y

protected:
	static void _bind_methods();

public:
	// Create(DefaultValue): an empty grid whose missing nodes read as DefaultValue.
	Ref<T2DGrid> Create(const Variant &p_default_value = Variant());
	int64_t GetWidth() const { return FWidth; }
	int64_t GetHeight() const { return FHeight; }
	Vector2i GetSize() const { return Vector2i(int32_t(FWidth), int32_t(FHeight)); }
	void SetSize(const Vector2i &p_width_height);
	Variant GetNode(const Vector2i &p_xy) const;
	void SetNode(const Vector2i &p_xy, const Variant &p_node);
	// Calls func(x, y, Item) for each item in this grid (x outer, y inner). Returns itself for chains.
	Ref<T2DGrid> Each(const Callable &p_function);
	// Calls func(x, y, Item) for each item in this grid and replaces the value with the result.
	Ref<T2DGrid> Update(const Callable &p_function);
};

} // namespace godot
