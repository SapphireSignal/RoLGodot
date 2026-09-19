#include "entity/t_entity.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <atomic>

#include "dws/dws_const.h"
#include "engine/t_thread_context.h"
#include "engine/t_time_manager.h"
#include "entity/base_conflict_constants.h"
#include "entity/d_set.h"
#include "entity/r_param.h"
#include "entity/t_entity_component.h"
#include "entity/t_entity_stream.h"

namespace godot {

namespace {

// BaseConflict.Constants.pas / BaseConflict.Constants.Cards.pas
const char *SCRIPT_INHERIT_VAR_NAME = "InheritsFrom";
const char *SCRIPT_INHERIT_PRECEDING_VAR_NAME = "InheritsFromPreceding";
const char *FILE_EXTENSION_ENTITY = ".ets";
const char *PATH_SCRIPT = "\\Scripts\\";
// Original script path (lower case, relative to Scripts\) -> generated GDScript, per side.
const char *SCRIPT_INDEX = "res://src/content/scripts/script_index.gd";

std::atomic<bool> g_quiet_script_errors{ false };

Array Values1(const Variant &p_value) {
	Array values;
	values.append(p_value);
	return values;
}

// `"Name" in Object` of GDScript: the object has the property.
bool HasProperty(const Variant &p_object, const StringName &p_name) {
	bool valid = false;
	p_object.get_named(p_name, valid);
	return valid;
}

} // namespace

void TEntity::_bind_methods() {
	ClassDB::bind_integer_constant(get_class_static(), "", "RESERVED_GROUPS", RESERVED_GROUPS);

	ClassDB::bind_method(D_METHOD("Create", "GlobalEventbus", "ID"), &TEntity::Create, DEFVAL(Variant()), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("Destroy"), &TEntity::Destroy);
	ClassDB::bind_method(D_METHOD("Free"), &TEntity::Free);
	ClassDB::bind_method(D_METHOD("ClassName"), &TEntity::ClassName);

	ClassDB::bind_static_method("TEntity", D_METHOD("CreateFromScript", "PatternFileName", "GlobalEventbus", "Initializer"),
			&TEntity::CreateFromScript, DEFVAL(Callable()));
	ClassDB::bind_static_method("TEntity", D_METHOD("CreateMetaFromScript", "PatternFileName", "GlobalEventbus", "Initializer"),
			&TEntity::CreateMetaFromScript, DEFVAL(Callable()));
	ClassDB::bind_static_method("TEntity", D_METHOD("CreateDataFromScript", "PatternFileName", "GlobalEventbus", "Initializer"),
			&TEntity::CreateDataFromScript, DEFVAL(Callable()));
	ClassDB::bind_static_method("TEntity", D_METHOD("CreateFromScriptProc", "PatternFileName", "ProcName", "GlobalEventbus", "Initializer", "IsMeta", "FileNameOverride"),
			&TEntity::CreateFromScriptProc, DEFVAL(Callable()), DEFVAL(false), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("ApplyScript", "ScriptFileName", "ProcName", "Parameters"), &TEntity::ApplyScript,
			DEFVAL(String()), DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("ApplyScriptReturnGroups", "ScriptFileName", "ProcName"), &TEntity::ApplyScriptReturnGroups,
			DEFVAL(String()));
	ClassDB::bind_static_method("TEntity", D_METHOD("CompileScriptFromFile", "FileName", "Server"), &TEntity::CompileScriptFromFile);
	ClassDB::bind_static_method("TEntity", D_METHOD("ExecuteFunction", "Script", "Name", "Parameters", "GlobalEventbus"),
			&TEntity::ExecuteFunction, DEFVAL(Variant()));
	ClassDB::bind_static_method("TEntity", D_METHOD("ScriptGame"), &TEntity::ScriptGame);
	ClassDB::bind_static_method("TEntity", D_METHOD("_SetScriptGlobals", "Script", "GlobalEventbus"), &TEntity::_SetScriptGlobals);
	ClassDB::bind_static_method("TEntity", D_METHOD("GetLastScriptError"), &TEntity::GetLastScriptError);
	ClassDB::bind_static_method("TEntity", D_METHOD("SetLastScriptError", "value"), &TEntity::SetLastScriptError);
	ClassDB::bind_static_method("TEntity", D_METHOD("GetQuietScriptErrors"), &TEntity::GetQuietScriptErrors);
	ClassDB::bind_static_method("TEntity", D_METHOD("SetQuietScriptErrors", "value"), &TEntity::SetQuietScriptErrors);
	ClassDB::bind_static_method("TEntity", D_METHOD("NewObjectOfClass", "Name"), &TEntity::NewObjectOfClass);
	ClassDB::bind_static_method("TEntity", D_METHOD("PrecedingInitializer", "Entity", "Initializer", "EntityPattern", "ProcName", "GlobalEventbus"),
			&TEntity::PrecedingInitializer);
	ClassDB::bind_static_method("TEntity", D_METHOD("DeserializeInitializer", "Entity", "SkinID", "Stream"), &TEntity::DeserializeInitializer);

	ClassDB::bind_method(D_METHOD("IsServer"), &TEntity::IsServer);
	ClassDB::bind_method(D_METHOD("ScriptFileName"), &TEntity::ScriptFileName);
	ClassDB::bind_method(D_METHOD("SkinFileSuffix"), &TEntity::SkinFileSuffix);
	ClassDB::bind_method(D_METHOD("HasSkin"), &TEntity::HasSkin);
	ClassDB::bind_method(D_METHOD("GetSkinID", "ComponentGroup"), &TEntity::GetSkinID);
	ClassDB::bind_method(D_METHOD("GetSkinFileSuffix", "ComponentGroup"), &TEntity::GetSkinFileSuffix);
	ClassDB::bind_method(D_METHOD("SetFront", "Value"), &TEntity::SetFront);
	ClassDB::bind_method(D_METHOD("SetPosition", "Value"), &TEntity::SetPosition);
	ClassDB::bind_method(D_METHOD("GetNewComponentID"), &TEntity::GetNewComponentID);
	ClassDB::bind_method(D_METHOD("ReserveFreeGroup"), &TEntity::ReserveFreeGroup);
	ClassDB::bind_method(D_METHOD("FreeGroups", "Groups"), &TEntity::FreeGroups);
	ClassDB::bind_method(D_METHOD("RemoveGroups", "Groups"), &TEntity::RemoveGroups);
	ClassDB::bind_method(D_METHOD("Deploy"), &TEntity::Deploy);
	ClassDB::bind_method(D_METHOD("Serialize", "Stream"), &TEntity::Serialize);
	ClassDB::bind_static_method("TEntity", D_METHOD("Deserialize", "EntityID", "Stream", "GlobalEventbus"), &TEntity::Deserialize);
	ClassDB::bind_method(D_METHOD("DeferFree"), &TEntity::DeferFree);
	ClassDB::bind_method(D_METHOD("UnitProperties"), &TEntity::UnitProperties);
	ClassDB::bind_method(D_METHOD("UnitData", "DataType"), &TEntity::UnitData);
	ClassDB::bind_method(D_METHOD("Balance", "ResourceType", "Group"), &TEntity::Balance, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("BalanceInt", "ResourceType"), &TEntity::BalanceInt);
	ClassDB::bind_method(D_METHOD("BalanceSingle", "ResourceType"), &TEntity::BalanceSingle);
	ClassDB::bind_method(D_METHOD("Cap", "ResourceType", "Group"), &TEntity::Cap, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("CapSingle", "ResourceType"), &TEntity::CapSingle);
	ClassDB::bind_method(D_METHOD("ResFill", "ResourceType", "Group"), &TEntity::ResFill, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("TeamID"), &TEntity::TeamID);
	ClassDB::bind_method(D_METHOD("CommanderID"), &TEntity::CommanderID);
	ClassDB::bind_method(D_METHOD("HasUnitProperty", "UnitProperty"), &TEntity::HasUnitProperty);
	ClassDB::bind_method(D_METHOD("HasDamageType", "DamageType"), &TEntity::HasDamageType);
	ClassDB::bind_method(D_METHOD("ColorIdentity", "Group"), &TEntity::ColorIdentity, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("ReadCollisionRadius", "Group"), &TEntity::ReadCollisionRadius);
	ClassDB::bind_method(D_METHOD("CardLevel", "Group"), &TEntity::CardLevel, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("CardLeague", "Group"), &TEntity::CardLeague, DEFVAL(Variant()));

	ClassDB::bind_method(D_METHOD("GetID"), &TEntity::GetID);
	ClassDB::bind_method(D_METHOD("SetID", "value"), &TEntity::SetID);
	ClassDB::bind_method(D_METHOD("GetUID"), &TEntity::GetUID);
	ClassDB::bind_method(D_METHOD("SetUID", "value"), &TEntity::SetUID);
	ClassDB::bind_method(D_METHOD("GetScriptFile"), &TEntity::GetScriptFile);
	ClassDB::bind_method(D_METHOD("SetScriptFile", "value"), &TEntity::SetScriptFile);
	ClassDB::bind_method(D_METHOD("GetEventbus"), &TEntity::GetEventbus);
	ClassDB::bind_method(D_METHOD("GetBlackboard"), &TEntity::GetBlackboard);
	ClassDB::bind_method(D_METHOD("GetGlobalEventbus"), &TEntity::GetGlobalEventbus);
	ClassDB::bind_method(D_METHOD("GetIsAbstract"), &TEntity::GetIsAbstract);
	ClassDB::bind_method(D_METHOD("SetIsAbstract", "value"), &TEntity::SetIsAbstract);
	ClassDB::bind_method(D_METHOD("GetCreatedTimestamp"), &TEntity::GetCreatedTimestamp);
	ClassDB::bind_method(D_METHOD("GetSkinIDField"), &TEntity::GetSkinIDField);
	ClassDB::bind_method(D_METHOD("SetSkinIDField", "value"), &TEntity::SetSkinIDField);
	ClassDB::bind_method(D_METHOD("GetPosition"), &TEntity::GetPosition);
	ClassDB::bind_method(D_METHOD("GetFront"), &TEntity::GetFront);
	ClassDB::bind_method(D_METHOD("SetFPosition", "value"), &TEntity::SetFPosition);
	ClassDB::bind_method(D_METHOD("SetFFront", "value"), &TEntity::SetFFront);
	ClassDB::bind_method(D_METHOD("GetCollisionRadius"), &TEntity::GetCollisionRadius);
	ClassDB::bind_method(D_METHOD("SetCollisionRadius", "value"), &TEntity::SetCollisionRadius);
	ClassDB::bind_method(D_METHOD("GetDisplayPosition"), &TEntity::GetDisplayPosition);
	ClassDB::bind_method(D_METHOD("SetDisplayPosition", "value"), &TEntity::SetDisplayPosition);
	ClassDB::bind_method(D_METHOD("GetDisplayFront"), &TEntity::GetDisplayFront);
	ClassDB::bind_method(D_METHOD("SetDisplayFront", "value"), &TEntity::SetDisplayFront);
	ClassDB::bind_method(D_METHOD("GetDisplayUp"), &TEntity::GetDisplayUp);
	ClassDB::bind_method(D_METHOD("SetDisplayUp", "value"), &TEntity::SetDisplayUp);
	ClassDB::bind_method(D_METHOD("GetGroupsInUse"), &TEntity::GetGroupsInUse);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "ID"), "SetID", "GetID");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "FID"), "SetID", "GetID");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "UID"), "SetUID", "GetUID");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "FUID"), "SetUID", "GetUID");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "ScriptFile"), "SetScriptFile", "GetScriptFile");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "FScriptFile"), "SetScriptFile", "GetScriptFile");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "Eventbus", PROPERTY_HINT_RESOURCE_TYPE, "TEventbus"), "", "GetEventbus");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FEventbus", PROPERTY_HINT_RESOURCE_TYPE, "TEventbus"), "", "GetEventbus");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "Blackboard", PROPERTY_HINT_RESOURCE_TYPE, "TBlackboard"), "", "GetBlackboard");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FBlackboard", PROPERTY_HINT_RESOURCE_TYPE, "TBlackboard"), "", "GetBlackboard");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "GlobalEventbus", PROPERTY_HINT_RESOURCE_TYPE, "TEventbus"), "", "GetGlobalEventbus");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "FGlobalEventbus", PROPERTY_HINT_RESOURCE_TYPE, "TEventbus"), "", "GetGlobalEventbus");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "IsAbstract"), "SetIsAbstract", "GetIsAbstract");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "FAbstract"), "SetIsAbstract", "GetIsAbstract");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "CreatedTimestamp"), "", "GetCreatedTimestamp");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "SkinID"), "SetSkinIDField", "GetSkinIDField");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "FSkinID"), "SetSkinIDField", "GetSkinIDField");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Position"), "SetPosition", "GetPosition");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "FPosition"), "SetFPosition", "GetPosition");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "Front"), "SetFront", "GetFront");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "FFront"), "SetFFront", "GetFront");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "CollisionRadius"), "SetCollisionRadius", "GetCollisionRadius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "FCollisionRadius"), "SetCollisionRadius", "GetCollisionRadius");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "DisplayPosition"), "SetDisplayPosition", "GetDisplayPosition");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "DisplayFront"), "SetDisplayFront", "GetDisplayFront");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "DisplayUp"), "SetDisplayUp", "GetDisplayUp");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "FGroupsInUse"), "", "GetGroupsInUse");
}

Ref<TEntity> TEntity::Create(const Variant &p_global_eventbus, int64_t p_id) {
	FID = p_id;
	FEventbus.instantiate();
	FEventbus->Create(Variant(this));
	FGlobalEventbus = p_global_eventbus;
	if (FGlobalEventbus.is_valid()) {
		FEventbus->ApplicationType = FGlobalEventbus->ApplicationType;
	}
	FBlackboard.instantiate();
	FBlackboard->Create(Variant(this));
	FGroupsInUse.clear();
	FCreatedTimestamp = TTimeManager::GetTimeStamp();
	// {$IFDEF SERVER} low(integer) {$ENDIF} {$IFDEF CLIENT} high(integer) {$ENDIF}
	FCurrentComponentID = IsServer() ? -2147483648LL : 2147483647LL;
	NewObjectOfClass("TResourceManagerComponent").call("CreateGroupedAll", Variant(this));
	return Ref<TEntity>(this);
}

void TEntity::Destroy() {
	// the components hold the last references: stay alive until the end
	const Variant keep(this);
	FEventbus->Trigger(C::eiBeforeFree, Array(), Array(), 0, false);
	FEventbus->Trigger(C::eiFree, Array(), Array(), 0, false);
	FEventbus->Free();
	FBlackboard->Free();
	FGroupsInUse.clear();
}

// ---- script runner (BaseConflict.Entity.pas:587-712, Engine/Engine.Script.pas TScript) ------------------------------

Ref<TEntity> TEntity::CreateFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer) {
	return CreateFromScriptProc(p_pattern_file_name, "CreateEntity", p_global_eventbus, p_initializer, false, String());
}

Ref<TEntity> TEntity::CreateMetaFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer) {
	return CreateFromScriptProc(p_pattern_file_name, "CreateMeta", p_global_eventbus, p_initializer, true, String());
}

Ref<TEntity> TEntity::CreateDataFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer) {
	return CreateFromScriptProc(p_pattern_file_name, "CreateData", p_global_eventbus, p_initializer, true, String());
}

void TEntity::PrecedingInitializer(const Variant &p_entity, const Callable &p_initializer, const Variant &p_entity_pattern,
		const String &p_proc_name, const Variant &p_global_eventbus) {
	if (p_initializer.is_valid()) {
		p_initializer.call(p_entity);
	}
	ExecuteFunction(p_entity_pattern, p_proc_name, Values1(p_entity), p_global_eventbus);
}

// InheritsFrom: the parent chain builds the entity (its ProcName runs fully), then ours runs on it.
// InheritsFromPreceding: ours runs inside the initializer, right after TEntity.Create, before the base script's.
// Neither: this is the base script; it creates the entity and runs the initializer, then ProcName.
// The entity keeps the file name of the script first asked for. Returns nil where the original raised.
Ref<TEntity> TEntity::CreateFromScriptProc(const String &p_pattern_file_name, const String &p_proc_name, const Variant &p_global_eventbus,
		const Callable &p_initializer, bool p_is_meta, const String &p_file_name_override) {
	const String final_script_filename = p_file_name_override.is_empty() ? p_pattern_file_name : p_file_name_override;
	String script_file_path = String("scripts\\") + p_pattern_file_name;
	if (script_file_path.replace("\\", "/").get_file().get_extension().is_empty()) {
		script_file_path += FILE_EXTENSION_ENTITY;
	}
	const TEventbus *global_eventbus = Object::cast_to<TEventbus>(p_global_eventbus);
	const bool server = global_eventbus == nullptr || global_eventbus->ApplicationType == C::nsServer;
	// RunMain: init global variables of the script
	const Variant entity_pattern = CompileScriptFromFile(script_file_path, server);
	if (entity_pattern.get_type() == Variant::NIL) {
		return Ref<TEntity>();
	}
	_SetScriptGlobals(entity_pattern, p_global_eventbus);
	Ref<TEntity> result;
	if (HasProperty(entity_pattern, SCRIPT_INHERIT_VAR_NAME)) {
		bool valid = false;
		const String parent = entity_pattern.get_named(SCRIPT_INHERIT_VAR_NAME, valid);
		result = CreateFromScriptProc(parent, p_proc_name, p_global_eventbus, p_initializer, p_is_meta, final_script_filename);
	} else if (HasProperty(entity_pattern, SCRIPT_INHERIT_PRECEDING_VAR_NAME)) {
		bool valid = false;
		const String parent = entity_pattern.get_named(SCRIPT_INHERIT_PRECEDING_VAR_NAME, valid);
		const Callable preceding = callable_mp_static(&TEntity::PrecedingInitializer)
										   .bind(p_initializer, entity_pattern, p_proc_name, p_global_eventbus);
		result = CreateFromScriptProc(parent, p_proc_name, p_global_eventbus, preceding, p_is_meta, final_script_filename);
		if (result.is_valid()) {
			result->FScriptFile = final_script_filename;
		}
		return result;
	} else {
		// only base script file runs initilization methods
		result.instantiate();
		result->Create(p_global_eventbus, 0);
		result->FAbstract = p_is_meta;
		if (p_initializer.is_valid()) {
			p_initializer.call(result);
		}
	}
	if (result.is_null()) {
		return result;
	}
	result->FScriptFile = final_script_filename;
	ExecuteFunction(entity_pattern, p_proc_name, Values1(result), p_global_eventbus);
	return result;
}

void TEntity::ApplyScript(const String &p_script_file_name, const String &p_proc_name, const Variant &p_parameters) {
	const String proc_name = p_proc_name.is_empty() ? String("Apply") : p_proc_name;
	String script_file_name = p_script_file_name;
	if (!script_file_name.is_absolute_path() && !script_file_name.begins_with(PATH_SCRIPT)) {
		script_file_name = String(PATH_SCRIPT) + script_file_name;
	}
	const Variant script = CompileScriptFromFile(script_file_name, IsServer());
	if (script.get_type() == Variant::NIL) {
		return;
	}
	_SetScriptGlobals(script, FGlobalEventbus);
	// assigned(Parameters): a dynamic array is nil when empty
	if (p_parameters.get_type() == Variant::ARRAY && !Array(p_parameters).is_empty()) {
		ExecuteFunction(script, proc_name, p_parameters, FGlobalEventbus);
	} else {
		ExecuteFunction(script, proc_name, Values1(Variant(this)), FGlobalEventbus);
	}
}

Array TEntity::ApplyScriptReturnGroups(const String &p_script_file_name, const String &p_proc_name) {
	const String proc_name = p_proc_name.is_empty() ? String("Apply") : p_proc_name;
	const Variant script = CompileScriptFromFile(String("scripts\\") + p_script_file_name, IsServer());
	if (script.get_type() == Variant::NIL) {
		return Array();
	}
	_SetScriptGlobals(script, FGlobalEventbus);
	const Variant return_value = ExecuteFunction(script, proc_name, Values1(Variant(this)), FGlobalEventbus);
	if (return_value.get_type() != Variant::ARRAY) {
		return Array();
	}
	// integer -> Byte (truncates like the original's assignment), then ByteArrayToComponentGroup
	const Array values = return_value;
	Array bytes;
	for (int64_t i = 0; i < values.size(); i++) {
		bytes.append(int64_t(values[i]) & 0xFF);
	}
	return DSet::Make(bytes);
}

// TScriptmanager.CompileScriptFromFile + TScript.RunMain: the generated script of one side for an original path (any
// case, either slash, relative to or inside the Scripts folder), instantiated (= globals initialised). Fails like the
// original on a missing file and on a file the original could not compile.
Variant TEntity::CompileScriptFromFile(const String &p_file_name, bool p_server) {
	String key = String("\\") + p_file_name.replace("/", "\\").to_lower();
	// Windows takes doubled separators as one: '\Scripts\' + '\Environment\Bridge11.ets' (TClientMap decorations)
	while (key.contains("\\\\")) {
		key = key.replace("\\\\", "\\");
	}
	const int64_t at = key.rfind("\\scripts\\");
	key = at >= 0 ? key.substr(at + 9) : key.substr(1);
	TThreadContext *ctx = TThreadContext::Get();
	if (ctx->ScriptIndex.is_empty()) {
		const Ref<Script> index_script = ResourceLoader::get_singleton()->load(SCRIPT_INDEX);
		ctx->ScriptIndex = index_script->get_script_constant_map();
	}
	const Dictionary index = ctx->ScriptIndex[p_server ? "SERVER" : "CLIENT"];
	if (!index.has(key)) {
		ScriptError(vformat("TScriptmanager.CompileScriptFromFile: Can't find scriptfile \"%s\".", p_file_name));
		return Variant();
	}
	const Ref<Script> source = ResourceLoader::get_singleton()->load(index[key]);
	const Dictionary constants = source->get_script_constant_map();
	if (constants.has("ORIGINAL_COMPILE_ERROR")) {
		ScriptError(vformat("Error while compiling scriptfile (%s): %s", p_file_name, constants["ORIGINAL_COMPILE_ERROR"]));
		return Variant();
	}
	return Variant(source).call("new");
}

// TScript.ExecuteFunction: the parameter count must match the routine's exactly. GlobalEventbus: the side the script
// runs for; while it runs, the exposed Game() (L.Game) returns its Game.
Variant TEntity::ExecuteFunction(const Variant &p_script, const String &p_name, const Array &p_parameters, const Variant &p_global_eventbus) {
	Object *script = p_script;
	if (!script->has_method(p_name)) {
		ScriptError(vformat("TScript.ExecuteFunction: Unknown function \"%s\".", p_name));
		return Variant();
	}
	if (script->get_method_argument_count(p_name) != p_parameters.size()) {
		ScriptError("TScript.ExecuteFunction: Parametercount doesn't match.");
		return Variant();
	}
	TThreadContext::Get()->ScriptEventbusStack.push_back(p_global_eventbus);
	const Variant result = script->callv(p_name, p_parameters);
	TThreadContext::Get()->ScriptEventbusStack.pop_back();
	return result;
}

Variant TEntity::ScriptGame() {
	const Array &stack = TThreadContext::Get()->ScriptEventbusStack;
	if (stack.is_empty()) {
		return Variant();
	}
	const TEventbus *bus = Object::cast_to<TEventbus>(stack.back());
	return bus != nullptr ? bus->GetGame() : Variant();
}

void TEntity::_SetScriptGlobals(const Variant &p_script, const Variant &p_global_eventbus) {
	Object *script = p_script;
	if (HasProperty(p_script, "GlobalEventbus")) {
		script->set("GlobalEventbus", p_global_eventbus);
	}
	if (HasProperty(p_script, "Game")) {
		const TEventbus *bus = Object::cast_to<TEventbus>(p_global_eventbus);
		script->set("Game", bus != nullptr ? bus->GetGame() : Variant());
	}
}

void TEntity::ScriptError(const String &p_message) {
	TThreadContext::Get()->LastScriptError = p_message;
	if (!g_quiet_script_errors.load()) {
		UtilityFunctions::push_error(p_message);
	}
}

String TEntity::GetLastScriptError() {
	return TThreadContext::Get()->LastScriptError;
}

void TEntity::SetLastScriptError(const String &p_value) {
	TThreadContext::Get()->LastScriptError = p_value;
}

bool TEntity::GetQuietScriptErrors() {
	return g_quiet_script_errors.load();
}

void TEntity::SetQuietScriptErrors(bool p_value) {
	g_quiet_script_errors.store(p_value);
}

Variant TEntity::NewObjectOfClass(const String &p_name) {
	if (ClassDB::class_exists(p_name)) {
		return ClassDB::instantiate(p_name);
	}
	TThreadContext *ctx = TThreadContext::Get();
	if (ctx->ComponentClasses.is_empty()) {
		const TypedArray<Dictionary> classes = ProjectSettings::get_singleton()->get_global_class_list();
		for (int64_t i = 0; i < classes.size(); i++) {
			const Dictionary entry = classes[i];
			ctx->ComponentClasses[String(entry["class"])] = entry["path"];
		}
	}
	Variant found = ctx->ComponentClasses.get(p_name, Variant());
	if (found.get_type() == Variant::STRING) {
		found = ResourceLoader::get_singleton()->load(found);
		ctx->ComponentClasses[p_name] = found;
	}
	if (found.get_type() == Variant::NIL) {
		return Variant();
	}
	return found.call("new");
}

// ---- TEntity -----------------------------------------------------------------------------------------------------------

bool TEntity::IsServer() const {
	return FEventbus->ApplicationType == C::nsServer;
}

String TEntity::ScriptFileName() const {
	return FScriptFile.replace("\\", "/").get_file().get_basename();
}

String TEntity::SkinFileSuffix() const {
	return HasSkin() ? String("_") + FSkinID : String();
}

String TEntity::GetSkinID(const Array &p_component_group) {
	String result = RParam::AsString(FEventbus->ReadHierarchic(C::eiSkinIdentifier, Array(), p_component_group));
	if (result.is_empty()) {
		result = FSkinID;
	}
	return result;
}

String TEntity::GetSkinFileSuffix(const Array &p_component_group) {
	const String result = GetSkinID(p_component_group);
	return result.is_empty() ? result : String("_") + result;
}

void TEntity::SetFront(const Vector2 &p_value) {
	FFront = p_value;
	FEventbus->Write(C::eiFront, Values1(p_value), Array(), 0);
}

void TEntity::SetPosition(const Vector2 &p_value) {
	FPosition = p_value;
	FEventbus->Write(C::eiPosition, Values1(p_value), Array(), 0);
}

void TEntity::SetCollisionRadius(double p_value) {
	FCollisionRadius = RParam::ToSingle(p_value);
}

int64_t TEntity::GetNewComponentID() {
	const int64_t result = FCurrentComponentID;
	if (IsServer()) {
		FCurrentComponentID++;
	} else {
		FCurrentComponentID--;
	}
	return result;
}

void TEntity::RegisterComponent(const TEntityComponent *p_entity_component) {
	if (p_entity_component->IsAllGroup()) {
		return;
	}
	const Array group = p_entity_component->GetComponentGroup();
	for (int64_t n = 0; n < group.size(); n++) {
		const int64_t i = group[n];
		if (int64_t(FGroupsInUse.size()) <= i) {
			FGroupsInUse.resize(i + 1, 0);
		}
		// if group is reserved, first component dereserves it
		if (FGroupsInUse[i] < 0) {
			FGroupsInUse[i] = 0;
		}
		FGroupsInUse[i]++;
	}
}

void TEntity::DeregisterComponent(const TEntityComponent *p_entity_component) {
	if (p_entity_component->IsAllGroup()) {
		return;
	}
	const Array group = p_entity_component->GetComponentGroup();
	for (int64_t n = 0; n < group.size(); n++) {
		const int64_t i = group[n];
		ERR_CONTINUE_MSG(int64_t(FGroupsInUse.size()) <= i,
				"TEntity.DeregisterComponent: Some component seems to deregister but never registered or changed its group without notifing the entity.");
		FGroupsInUse[i]--;
	}
}

int TEntity::ReserveFreeGroup() {
	for (int i = RESERVED_GROUPS - 1; i < 256; i++) {
		if (int(FGroupsInUse.size()) <= i) {
			FGroupsInUse.resize(i + 1, 0);
		}
		if (FGroupsInUse[i] == 0) {
			// reserve group
			FGroupsInUse[i] = -1;
			return i;
		}
	}
	// should never happen, except we exaggerate with buffs (256 groups are filled up = ~ 128 Buffs)
	UtilityFunctions::push_error("TEntity.ReserveFreeGroup: Could not find free group!");
	return -1;
}

void TEntity::FreeGroups(const Array &p_groups) {
	const Array groups = DSet::Make(p_groups);
	FEventbus->Trigger(C::eiBeforeFree, Array(), groups, 0, false);
	FEventbus->Trigger(C::eiFree, Array(), groups, 0, false);
	FBlackboard->DeleteValues(groups);
	for (int64_t n = 0; n < groups.size(); n++) {
		const int64_t i = groups[n];
		if (int64_t(FGroupsInUse.size()) > i) {
			DEV_ASSERT(FGroupsInUse[i] <= 0); // Some components seems to ignore to call to free them.
			FGroupsInUse[i] = 0;
		}
	}
}

void TEntity::RemoveGroups(const Array &p_groups) {
	Array values;
	values.append(FID);
	values.append(DSet::Make(p_groups));
	FGlobalEventbus->Trigger(C::eiRemoveComponentGroup, values, Array(), 0, false);
}

void TEntity::Deploy() {
	FGlobalEventbus->Trigger(C::eiNewEntity, Values1(Variant(this)), Array(), 0, false);
	FEventbus->Trigger(C::eiDeploy, Array(), Array(), 0, false);
}

// TEntity.Serialize (:801): ID, script, skin, UID and the blackboard, then eiSerialize: every serializable component
// writes itself (TSerializableEntityComponent.Serialize).
void TEntity::Serialize(const Ref<TEntityStream> &p_stream) {
	p_stream->Write(FID);
	p_stream->Write(FScriptFile);
	p_stream->Write(FSkinID);
	p_stream->Write(FUID);
	FBlackboard->SaveToStream(p_stream);
	FEventbus->Trigger(C::eiSerialize, Values1(p_stream), Array(), 0, false);
}

void TEntity::DeserializeInitializer(const Variant &p_entity, const String &p_skin_id, const Ref<TEntityStream> &p_stream) {
	TEntity *entity = Object::cast_to<TEntity>(p_entity);
	entity->FSkinID = p_skin_id;
	// init all values set by the server to the entity, so all components have access to them
	entity->FBlackboard->LoadFromStream(p_stream);
}

// TEntity.Deserialize (:733): the client builds the entity from its script with the server's blackboard already in place
// (so the creating components see the server's values), then loads the blackboard again over what the script set. The
// stream stands after the ID (TClientNetworkComponent.DeserializeEntity reads it first). The rest of the stream are the
// serialized components: each is created on the new entity (its class's Create(Owner)), reads its data back
// (TSerializableEntityComponent.Deserialize) and its XNetworkSerialize fields are written to the bus.
Ref<TEntity> TEntity::Deserialize(int64_t p_entity_id, const Ref<TEntityStream> &p_stream, const Variant &p_global_eventbus) {
	const String script_file = p_stream->Read();
	const String skin_id = p_stream->Read();
	const String uid = p_stream->Read();
	const int64_t blackboard_stream_position = p_stream->Position;
	const Ref<TEntity> result = CreateFromScript(script_file, p_global_eventbus,
			callable_mp_static(&TEntity::DeserializeInitializer).bind(skin_id, p_stream));
	if (result.is_null()) {
		return result;
	}
	TEntity *entity = result.ptr();
	// now override all values already overwritten by the server, but set by the creation script
	p_stream->Position = blackboard_stream_position;
	entity->FBlackboard->LoadFromStream(p_stream);
	entity->FID = p_entity_id;
	entity->FUID = uid;
	// the serializable components the server sent
	while (p_stream->Position < p_stream->Size()) {
		const String qualified_name = p_stream->Read();
		Variant component = NewObjectOfClass(qualified_name);
		if (component.get_type() == Variant::NIL) {
			UtilityFunctions::push_error(vformat("TEntity.DeSerialize: Can't find typeinfo for type \"%s\"", qualified_name));
			return result;
		}
		component = component.call("Create", result);
		component.call("Deserialize", p_stream);
		const Dictionary serialize_events = component.call("NetworkSerializeEvents");
		const Array fields = serialize_events.keys();
		for (int64_t i = 0; i < fields.size(); i++) {
			bool valid = false;
			const Variant value = component.get_named(StringName(String(fields[i])), valid);
			entity->FEventbus->Write(int64_t(serialize_events[fields[i]]), Values1(value), Array(), 0);
		}
	}
	return result;
}

void TEntity::DeferFree() {
	const Variant game = FGlobalEventbus.is_valid() ? FGlobalEventbus->GetGame() : Variant();
	if (game.get_type() != Variant::NIL) {
		bool valid = false;
		Variant entity_manager = game.get_named("EntityManager", valid);
		if (entity_manager.get_type() != Variant::NIL) {
			entity_manager.call("FreeEntity", Variant(this));
			return;
		}
	}
	Free();
}

Array TEntity::UnitProperties() {
	return RParam::AsSet(FEventbus->Read(C::eiUnitProperties, Array(), Array(), 0));
}

Variant TEntity::UnitData(int p_data_type) {
	return FBlackboard->GetIndexedValue(C::eiUnitData, Array(), p_data_type);
}

Variant TEntity::Balance(int p_resource_type, const Variant &p_group) {
	if (p_group.get_type() == Variant::NIL) {
		return FEventbus->Read(C::eiResourceBalance, Values1(p_resource_type), Array(), 0);
	}
	return FEventbus->ReadHierarchic(C::eiResourceBalance, Values1(p_resource_type), p_group);
}

int64_t TEntity::BalanceInt(int p_resource_type) {
	return RParam::AsInteger(FEventbus->Read(C::eiResourceBalance, Values1(p_resource_type), Array(), 0));
}

double TEntity::BalanceSingle(int p_resource_type) {
	return RParam::AsSingle(FEventbus->Read(C::eiResourceBalance, Values1(p_resource_type), Array(), 0));
}

Variant TEntity::Cap(int p_resource_type, const Variant &p_group) {
	if (p_group.get_type() == Variant::NIL) {
		return FEventbus->Read(C::eiResourceCap, Values1(p_resource_type), Array(), 0);
	}
	return FEventbus->ReadHierarchic(C::eiResourceCap, Values1(p_resource_type), p_group);
}

double TEntity::CapSingle(int p_resource_type) {
	return RParam::AsSingle(Cap(p_resource_type, Variant()));
}

double TEntity::ResFill(int p_resource_type, const Variant &p_group) {
	if (BC::IsIntResource(p_resource_type)) {
		return double(RParam::AsInteger(Balance(p_resource_type, p_group))) / double(RParam::AsInteger(Cap(p_resource_type, p_group)));
	}
	return RParam::AsSingle(Balance(p_resource_type, p_group)) / RParam::AsSingle(Cap(p_resource_type, p_group));
}

int64_t TEntity::TeamID() {
	return RParam::AsInteger(FEventbus->Read(C::eiTeamID, Array(), Array(), 0));
}

int64_t TEntity::CommanderID() {
	return RParam::AsInteger(FEventbus->Read(C::eiOwnerCommander, Array(), Array(), 0));
}

bool TEntity::HasUnitProperty(int p_unit_property) {
	return RParam::AsSet(FEventbus->Read(C::eiUnitProperties, Array(), Array(), 0)).has(p_unit_property);
}

bool TEntity::HasDamageType(int p_damage_type) {
	return RParam::AsSet(FEventbus->Read(C::eiDamageType, Array(), Values1(C::GROUP_MAINWEAPON), 0)).has(p_damage_type);
}

int64_t TEntity::ColorIdentity(const Variant &p_group) {
	if (p_group.get_type() == Variant::NIL) {
		return RParam::AsInteger(FEventbus->Read(C::eiColorIdentity, Array(), Array(), 0));
	}
	return RParam::AsInteger(FEventbus->Read(C::eiColorIdentity, Array(), p_group, 0));
}

double TEntity::ReadCollisionRadius(const Array &p_group) {
	return RParam::AsSingle(FEventbus->Read(C::eiCollisionRadius, Array(), p_group, 0));
}

int64_t TEntity::CardLevel(const Variant &p_group) {
	if (p_group.get_type() == Variant::NIL) {
		return RParam::AsInteger(FEventbus->Read(C::eiResourceBalance, Values1(C::reCardLevel), Array(), 0));
	}
	const Array group = p_group.get_type() == Variant::ARRAY ? Array(p_group) : Values1(p_group);
	return RParam::AsInteger(FEventbus->Read(C::eiResourceBalance, Values1(C::reCardLevel), group, 0));
}

int64_t TEntity::CardLeague(const Variant &p_group) {
	if (p_group.get_type() == Variant::NIL) {
		return RParam::AsInteger(FEventbus->Read(C::eiResourceBalance, Values1(C::reCardLeague), Array(), 0));
	}
	const Array group = p_group.get_type() == Variant::ARRAY ? Array(p_group) : Values1(p_group);
	return RParam::AsInteger(FEventbus->ReadHierarchic(C::eiResourceBalance, Values1(C::reCardLeague), group));
}

Array TEntity::GetGroupsInUse() const {
	Array result;
	for (int count : FGroupsInUse) {
		result.append(count);
	}
	return result;
}

} // namespace godot
