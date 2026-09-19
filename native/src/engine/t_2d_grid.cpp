#include "engine/t_2d_grid.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

namespace godot {

void T2DGrid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "DefaultValue"), &T2DGrid::Create, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("GetWidth"), &T2DGrid::GetWidth);
	ClassDB::bind_method(D_METHOD("GetHeight"), &T2DGrid::GetHeight);
	ClassDB::bind_method(D_METHOD("GetSize"), &T2DGrid::GetSize);
	ClassDB::bind_method(D_METHOD("SetSize", "WidthHeight"), &T2DGrid::SetSize);
	ClassDB::bind_method(D_METHOD("GetNode", "xy"), &T2DGrid::GetNode);
	ClassDB::bind_method(D_METHOD("SetNode", "xy", "Node"), &T2DGrid::SetNode);
	ClassDB::bind_method(D_METHOD("Each", "function"), &T2DGrid::Each);
	ClassDB::bind_method(D_METHOD("Update", "function"), &T2DGrid::Update);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Width"), "", "GetWidth");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "Height"), "", "GetHeight");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "Size"), "SetSize", "GetSize");
}

Ref<T2DGrid> T2DGrid::Create(const Variant &p_default_value) {
	FDefaultValue = p_default_value;
	return Ref<T2DGrid>(this);
}

void T2DGrid::SetSize(const Vector2i &p_width_height) {
	FWidth = std::max<int64_t>(p_width_height.x, 0);
	FHeight = FWidth > 0 ? std::max<int64_t>(p_width_height.y, 0) : 0;
	FGrid.clear();
	FGrid.resize(uint32_t(FWidth * FHeight));
	for (uint32_t i = 0; i < FGrid.size(); i++) {
		FGrid[i] = FDefaultValue;
	}
}

Variant T2DGrid::GetNode(const Vector2i &p_xy) const {
	if (p_xy.x >= 0 && p_xy.x < FWidth && p_xy.y >= 0 && p_xy.y < FHeight) {
		return FGrid[p_xy.x * FHeight + p_xy.y];
	}
	return FDefaultValue;
}

void T2DGrid::SetNode(const Vector2i &p_xy, const Variant &p_node) {
	if (p_xy.x >= 0 && p_xy.x < FWidth && p_xy.y >= 0 && p_xy.y < FHeight) {
		FGrid[p_xy.x * FHeight + p_xy.y] = p_node;
	}
}

Ref<T2DGrid> T2DGrid::Each(const Callable &p_function) {
	for (int64_t x = 0; x < FWidth; x++) {
		for (int64_t y = 0; y < FHeight; y++) {
			p_function.call(x, y, GetNode(Vector2i(int32_t(x), int32_t(y))));
		}
	}
	return Ref<T2DGrid>(this);
}

Ref<T2DGrid> T2DGrid::Update(const Callable &p_function) {
	for (int64_t x = 0; x < FWidth; x++) {
		for (int64_t y = 0; y < FHeight; y++) {
			const Vector2i xy{ int32_t(x), int32_t(y) };
			SetNode(xy, p_function.call(x, y, GetNode(xy)));
		}
	}
	return Ref<T2DGrid>(this);
}

} // namespace godot
