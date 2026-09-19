#pragma once

// TBlackboard (BaseConflict.Entity.pas:100, implementation :2257): a value for every event, the entity-local pool of
// values. The script side (TBlackboardScriptInvoker, :1871) calls the same methods: its overloads are folded into
// SetValue / SetIndexedValue / SetIndexedValues (the value's type picks the overload). SaveToStream / LoadFromStream
// carry the values in a TEntityStream (the network's byte stream in the original).

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <unordered_map>
#include <vector>

namespace godot {

class TEntity;
class TEntityStream;

class TBlackboard : public RefCounted {
	GDCLASS(TBlackboard, RefCounted)

	// the owning entity (a strong reference like the original's field; Destroy drops it)
	Variant FOwnerRef;

protected:
	static void _bind_methods();

public:
	TEntity *FOwner = nullptr;
	// Values for [Event][GroupIndex][SubIndex]. GroupIndex 0 = no group, g + 1 = group g; SubIndex 0 = the plain value,
	// i + 1 = indexed value i. A missing entry / nil = not assigned.
	std::unordered_map<int, std::vector<std::vector<Variant>>> FValues;

	Ref<TBlackboard> Create(const Variant &p_owner);
	void Destroy();
	void Free() { Destroy(); }
	String ClassName() const { return "TBlackboard"; }

	Variant GetValueRaw(int p_event, int p_group_index, int p_index) const;
	void SetValueRaw(int p_event, int p_group_index, int p_index, const Variant &p_value);
	void DeleteValues(const Array &p_group);
	// The global group has index -1. Other indices as usual. If value is not present returns RPARAMEMPTY.
	Variant GetIndexedValue(int p_event, const Array &p_group, int p_index) const;
	// Returns index -> value (TDictionary<integer, RParam>).
	Dictionary GetIndexMap(int p_event, const Array &p_group) const;
	Variant GetValue(int p_event, const Array &p_group) const { return GetIndexedValue(p_event, p_group, -1); }
	void SetIndexedValue(int p_event, const Array &p_group, int p_index, const Variant &p_value);
	void SetValue(int p_event, const Array &p_group, const Variant &p_value) { SetIndexedValue(p_event, p_group, -1, p_value); }
	void SaveToStream(const Ref<TEntityStream> &p_stream) const;
	void LoadFromStream(const Ref<TEntityStream> &p_stream);
	// Script side SetIndexedValues(Event, Group, Values: TArray<integer|single|string>): value i at index i.
	void SetIndexedValues(int p_event, const Array &p_group, const Array &p_values);

	static Variant VarToRParam(int p_event, const Variant &p_value);

	Variant GetOwner() const { return FOwnerRef; }
};

} // namespace godot
