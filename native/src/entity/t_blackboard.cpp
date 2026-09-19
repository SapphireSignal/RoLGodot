#include "entity/t_blackboard.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include <algorithm>

#include "dws/dws_const.h"
#include "entity/base_conflict_constants.h"
#include "entity/d_set.h"
#include "entity/r_param.h"
#include "entity/t_entity.h"
#include "entity/t_entity_stream.h"
#include "entity/t_eventbus.h"

namespace godot {

void TBlackboard::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "Owner"), &TBlackboard::Create, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("Destroy"), &TBlackboard::Destroy);
	ClassDB::bind_method(D_METHOD("Free"), &TBlackboard::Free);
	ClassDB::bind_method(D_METHOD("ClassName"), &TBlackboard::ClassName);
	ClassDB::bind_method(D_METHOD("GetValueRaw", "Event", "GroupIndex", "Index"), &TBlackboard::GetValueRaw);
	ClassDB::bind_method(D_METHOD("SetValueRaw", "Event", "GroupIndex", "Index", "Value"), &TBlackboard::SetValueRaw);
	ClassDB::bind_method(D_METHOD("DeleteValues", "Group"), &TBlackboard::DeleteValues);
	ClassDB::bind_method(D_METHOD("GetIndexedValue", "Event", "Group", "Index"), &TBlackboard::GetIndexedValue);
	ClassDB::bind_method(D_METHOD("GetIndexMap", "Event", "Group"), &TBlackboard::GetIndexMap);
	ClassDB::bind_method(D_METHOD("GetValue", "Event", "Group"), &TBlackboard::GetValue);
	ClassDB::bind_method(D_METHOD("SetIndexedValue", "Event", "Group", "Index", "Value"), &TBlackboard::SetIndexedValue);
	ClassDB::bind_method(D_METHOD("SetValue", "Event", "Group", "Value"), &TBlackboard::SetValue);
	ClassDB::bind_method(D_METHOD("SaveToStream", "Stream"), &TBlackboard::SaveToStream);
	ClassDB::bind_method(D_METHOD("LoadFromStream", "Stream"), &TBlackboard::LoadFromStream);
	ClassDB::bind_method(D_METHOD("SetIndexedValues", "Event", "Group", "Values"), &TBlackboard::SetIndexedValues);
	ClassDB::bind_static_method("TBlackboard", D_METHOD("VarToRParam", "Event", "Value"), &TBlackboard::VarToRParam);
	ClassDB::bind_method(D_METHOD("GetOwner"), &TBlackboard::GetOwner);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FOwner"), "", "GetOwner");
}

Ref<TBlackboard> TBlackboard::Create(const Variant &p_owner) {
	FOwnerRef = p_owner;
	FOwner = Object::cast_to<TEntity>(p_owner);
	return Ref<TBlackboard>(this);
}

void TBlackboard::Destroy() {
	// drop the values and the owner so no reference cycle keeps the entity alive
	FValues.clear();
	FOwner = nullptr;
	FOwnerRef = Variant();
}

Variant TBlackboard::GetValueRaw(int p_event, int p_group_index, int p_index) const {
	auto found = FValues.find(p_event);
	if (found == FValues.end()) {
		return Variant();
	}
	const std::vector<std::vector<Variant>> &groups = found->second;
	if (p_group_index >= 0 && size_t(p_group_index) < groups.size()) {
		const std::vector<Variant> &values = groups[p_group_index];
		if (p_index >= 0 && size_t(p_index) < values.size()) {
			return values[p_index];
		}
	}
	return Variant();
}

void TBlackboard::SetValueRaw(int p_event, int p_group_index, int p_index, const Variant &p_value) {
	std::vector<std::vector<Variant>> &groups = FValues[p_event];
	if (groups.size() <= size_t(p_group_index)) {
		groups.resize(p_group_index + 1);
	}
	std::vector<Variant> &values = groups[p_group_index];
	if (values.size() <= size_t(p_index)) {
		values.resize(p_index + 1);
	}
	values[p_index] = p_value;
}

void TBlackboard::DeleteValues(const Array &p_group) {
	if (p_group.is_empty()) {
		return;
	}
	const Array group = DSet::Make(p_group);
	for (auto &entry : FValues) {
		std::vector<std::vector<Variant>> &groups = entry.second;
		for (int64_t n = 0; n < group.size(); n++) {
			const int64_t i = group[n];
			if (int64_t(groups.size()) > i + 1) {
				groups[i + 1].clear();
			}
		}
	}
}

Variant TBlackboard::GetIndexedValue(int p_event, const Array &p_group, int p_index) const {
	// index 0 is reserved for the default index
	const int index = p_index + 1;
	if (p_group.is_empty()) {
		return GetValueRaw(p_event, 0, index);
	}
	if (p_group.size() == 1) {
		return GetValueRaw(p_event, int(int64_t(p_group[0])) + 1, index);
	}
	const Array group = DSet::Make(p_group);
	Variant result;
	for (int64_t n = 0; n < group.size(); n++) {
		result = GetValueRaw(p_event, int(int64_t(group[n])) + 1, index);
		if (result.get_type() != Variant::NIL) {
			break;
		}
	}
	return result;
}

Dictionary TBlackboard::GetIndexMap(int p_event, const Array &p_group) const {
	Dictionary result;
	auto found = FValues.find(p_event);
	if (found == FValues.end()) {
		return result;
	}
	const std::vector<std::vector<Variant>> &groups = found->second;
	if (p_group.is_empty()) {
		if (!groups.empty()) {
			for (size_t i = 1; i < groups[0].size(); i++) {
				const Variant &value = groups[0][i];
				if (value.get_type() != Variant::NIL) {
					result[int64_t(i) - 1] = value;
				}
			}
		}
	} else {
		const Array group = DSet::Make(p_group);
		for (int64_t n = 0; n < group.size(); n++) {
			const int64_t i = group[n];
			if (int64_t(groups.size()) > i + 1 && !groups[i + 1].empty()) {
				const std::vector<Variant> &values = groups[i + 1];
				for (size_t j = 1; j < values.size(); j++) {
					if (values[j].get_type() != Variant::NIL) {
						result[int64_t(j) - 1] = values[j];
					}
				}
				if (result.is_empty()) {
					break;
				}
			}
		}
	}
	return result;
}

void TBlackboard::SetIndexedValue(int p_event, const Array &p_group, int p_index, const Variant &p_value) {
	const Variant value = VarToRParam(p_event, p_value);
	const int index = p_index + 1;
	if (p_group.is_empty()) {
		SetValueRaw(p_event, 0, index, value);
	} else {
		const Array group = DSet::Make(p_group);
		for (int64_t n = 0; n < group.size(); n++) {
			SetValueRaw(p_event, int(int64_t(group[n])) + 1, index, value);
		}
	}
}

// SaveToStream: the count of assigned values, then each as event, group slot, index slot, value, in event order.
// The values are deep copies (the original serializes the RParam).
void TBlackboard::SaveToStream(const Ref<TEntityStream> &p_stream) const {
	std::vector<int> events;
	events.reserve(FValues.size());
	for (const auto &entry : FValues) {
		events.push_back(entry.first);
	}
	std::sort(events.begin(), events.end());
	int64_t count = 0;
	for (int i : events) {
		for (const std::vector<Variant> &values : FValues.at(i)) {
			for (const Variant &value : values) {
				if (value.get_type() != Variant::NIL) {
					count++;
				}
			}
		}
	}
	p_stream->Write(count);
	for (int i : events) {
		const std::vector<std::vector<Variant>> &groups = FValues.at(i);
		for (size_t j = 0; j < groups.size(); j++) {
			for (size_t k = 0; k < groups[j].size(); k++) {
				if (groups[j][k].get_type() != Variant::NIL) {
					p_stream->Write(i);
					p_stream->Write(int64_t(j));
					p_stream->Write(int64_t(k));
					p_stream->Write(RParam::Copy(groups[j][k]));
				}
			}
		}
	}
}

// LoadFromStream: blackboard events (EventIdentifierToBlackboardEvent) are written through the owner (position and
// front through its setters), the others go into the blackboard raw.
void TBlackboard::LoadFromStream(const Ref<TEntityStream> &p_stream) {
	const int64_t count = p_stream->Read();
	for (int64_t n = 0; n < count; n++) {
		const int i = int64_t(p_stream->Read());
		const int j = int64_t(p_stream->Read());
		const int k = int64_t(p_stream->Read());
		const Variant para = RParam::Copy(p_stream->Read());
		if (para.get_type() == Variant::NIL) {
			continue;
		}
		if (BC::EventIdentifierToBlackboardEvent(i)) {
			DEV_ASSERT(k == 0); // Blackboardevents cannot have indices!
			Array group;
			if (j > 0) {
				group.append(j - 1);
			}
			if (i == C::eiPosition) {
				FOwner->SetPosition(RParam::AsVector2(para));
			} else if (i == C::eiFront) {
				FOwner->SetFront(RParam::AsVector2(para));
			} else {
				Array values;
				values.append(para);
				FOwner->FEventbus->Write(i, values, group, 0);
			}
		} else {
			SetValueRaw(i, j, k, para);
		}
	}
}

void TBlackboard::SetIndexedValues(int p_event, const Array &p_group, const Array &p_values) {
	for (int64_t i = 0; i < p_values.size(); i++) {
		SetIndexedValue(p_event, p_group, int(i), p_values[i]);
	}
}

// TBlackboardScriptInvoker.VarToRParam and SetValueByteArrayInvoker (:2592, :2622). A script float becomes a single;
// an array is a byte array, or a set for eiUnitProperties / eiDamageType (sets are Arrays in the port too, so both keep
// the members; the set is normalised). Arrays are copied: RParam.FromArray copies the data.
Variant TBlackboard::VarToRParam(int p_event, const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::FLOAT:
			return RParam::ToSingle(double(p_value));
		case Variant::ARRAY:
			if (p_event == C::eiUnitProperties || p_event == C::eiDamageType) {
				return DSet::Make(p_value);
			}
			return Array(p_value).duplicate();
		default:
			return p_value;
	}
}

} // namespace godot
