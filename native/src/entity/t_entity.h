#pragma once

// TEntity (BaseConflict.Entity.pas:323, implementation :507). An entity is its eventbus, blackboard and components;
// everything else lives in components. The script runner (:587-712, Engine/Engine.Script.pas TScript) builds entities
// from the transpiled game scripts; Serialize / Deserialize use TEntityStream (an in-memory stand-in for the network
// stream).

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

#include "entity/t_blackboard.h"
#include "entity/t_eventbus.h"

namespace godot {

class TEntityComponent;
class TEntityStream;

class TEntity : public RefCounted {
	GDCLASS(TEntity, RefCounted)

	// the initializers the script runner hands on (the lambdas of the original's anonymous methods)
	static void PrecedingInitializer(const Variant &p_entity, const Callable &p_initializer, const Variant &p_entity_pattern,
			const String &p_proc_name, const Variant &p_global_eventbus);
	static void DeserializeInitializer(const Variant &p_entity, const String &p_skin_id, const Ref<TEntityStream> &p_stream);
	// TScriptmanager: the error of the last failed call (the original raised an exception)
	static void ScriptError(const String &p_message);

protected:
	static void _bind_methods();

public:
	// reserve the first n groups, so the user can hardcode something
	static constexpr int RESERVED_GROUPS = 20;

	double FCollisionRadius = 0.0;
	Vector2 FPosition;
	Vector2 FFront;
	// {$IFDEF CLIENT} display transform
	Vector3 DisplayPosition;
	Vector3 DisplayFront;
	Vector3 DisplayUp;

	Ref<TEventbus> FEventbus;
	Ref<TEventbus> FGlobalEventbus;
	Ref<TBlackboard> FBlackboard;
	bool FAbstract = false;
	int64_t FID = 0;
	int64_t FCreatedTimestamp = 0;
	String FScriptFile;
	String FUID;
	String FSkinID;
	int64_t FCurrentComponentID = 0;
	// Count of entity components in each group. If 0 group is free to use, if <0 group is reserved by someone
	std::vector<int> FGroupsInUse;

	// Creates the entity. Now components can be added.
	Ref<TEntity> Create(const Variant &p_global_eventbus, int64_t p_id);
	void Destroy();
	void Free() { Destroy(); }
	String ClassName() const { return "TEntity"; }

	// ---- script runner
	// CreateFromScript(PatternFileName, GlobalEventbus[, Initializer]): builds an entity with the script's CreateEntity.
	// Initializer: Callable(Entity) or an empty Callable (nil).
	static Ref<TEntity> CreateFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer);
	static Ref<TEntity> CreateMetaFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer);
	static Ref<TEntity> CreateDataFromScript(const String &p_pattern_file_name, const Variant &p_global_eventbus, const Callable &p_initializer);
	static Ref<TEntity> CreateFromScriptProc(const String &p_pattern_file_name, const String &p_proc_name, const Variant &p_global_eventbus,
			const Callable &p_initializer, bool p_is_meta, const String &p_file_name_override);
	// Runs ProcName (default 'Apply') of a script with Parameters, or with this entity if there are none.
	void ApplyScript(const String &p_script_file_name, const String &p_proc_name, const Variant &p_parameters);
	// Runs ProcName (default 'Apply') with this entity; it returns the component groups it created (array of integer).
	Array ApplyScriptReturnGroups(const String &p_script_file_name, const String &p_proc_name);
	static Variant CompileScriptFromFile(const String &p_file_name, bool p_server);
	static Variant ExecuteFunction(const Variant &p_script, const String &p_name, const Array &p_parameters, const Variant &p_global_eventbus);
	// BaseConflict.Globals.Game, a threadvar in the original (one game per server thread): the Game of the global bus of
	// the innermost running script.
	static Variant ScriptGame();
	// SetGlobalVariableValueIfExist for 'GlobalEventbus' and 'Game' (the Game of the bus's side).
	static void _SetScriptGlobals(const Variant &p_script, const Variant &p_global_eventbus);
	static String GetLastScriptError();
	static void SetLastScriptError(const String &p_value);
	// Tests that provoke script errors on purpose set this to keep the log free of expected errors.
	static bool GetQuietScriptErrors();
	static void SetQuietScriptErrors(bool p_value);
	// A new object of a class by its global name: a C++ class or a GDScript class_name (nil if there is none).
	static Variant NewObjectOfClass(const String &p_name);

	// ---- TEntity
	// Which side this entity lives on ({$IFDEF SERVER} in the original).
	bool IsServer() const;
	// Same as ScriptFile, but without file path and extension.
	String ScriptFileName() const;
	String SkinFileSuffix() const;
	bool HasSkin() const { return !FSkinID.is_empty(); }
	String GetSkinID(const Array &p_component_group);
	String GetSkinFileSuffix(const Array &p_component_group);
	void SetFront(const Vector2 &p_value);
	void SetPosition(const Vector2 &p_value);
	int64_t GetNewComponentID();
	void RegisterComponent(const TEntityComponent *p_entity_component);
	void DeregisterComponent(const TEntityComponent *p_entity_component);
	// Reserves a unused group for further usage. The first component placed in this group will free the reserved state.
	// So if killed the group is free for next use.
	int ReserveFreeGroup();
	// Release all content of the groups and unreserves them.
	void FreeGroups(const Array &p_groups);
	// Adds the groups to be removed by the entity manager.
	void RemoveGroups(const Array &p_groups);
	// Registers the entity in the game. Should be called after adding the components.
	void Deploy();
	void Serialize(const Ref<TEntityStream> &p_stream);
	static Ref<TEntity> Deserialize(int64_t p_entity_id, const Ref<TEntityStream> &p_stream, const Variant &p_global_eventbus);
	void DeferFree();

	// Shortcut to read unit properties from eventbus (SetUnitProperty as an Array).
	Array UnitProperties();
	// Shortcut to read unit data from blackboads.
	Variant UnitData(int p_data_type);
	// Balance(ResourceType) / Balance(ResourceType, Group)
	Variant Balance(int p_resource_type, const Variant &p_group);
	int64_t BalanceInt(int p_resource_type);
	double BalanceSingle(int p_resource_type);
	// Cap(ResourceType) / Cap(ResourceType, Group)
	Variant Cap(int p_resource_type, const Variant &p_group);
	double CapSingle(int p_resource_type);
	// ResFill(ResourceType) / ResFill(ResourceType, Group)
	double ResFill(int p_resource_type, const Variant &p_group);
	int64_t TeamID();
	int64_t CommanderID();
	// Returns whether this unit has this property or not.
	bool HasUnitProperty(int p_unit_property);
	// Returns whether the main weapon of this unit has this type or not.
	bool HasDamageType(int p_damage_type);
	// ColorIdentity() / ColorIdentity(Group: TArray<Byte>)
	int64_t ColorIdentity(const Variant &p_group);
	double ReadCollisionRadius(const Array &p_group);
	// CardLevel() / CardLevel(Group: Byte) / CardLevel(Group: TArray<Byte>): all plain reads.
	int64_t CardLevel(const Variant &p_group);
	// CardLeague() reads plainly; CardLeague(Group: Byte) and CardLeague(Group: TArray<Byte>) read hierarchically.
	int64_t CardLeague(const Variant &p_group);

	// ---- properties
	int64_t GetID() const { return FID; }
	void SetID(int64_t p_value) { FID = p_value; }
	String GetUID() const { return FUID; }
	void SetUID(const String &p_value) { FUID = p_value; }
	String GetScriptFile() const { return FScriptFile; }
	void SetScriptFile(const String &p_value) { FScriptFile = p_value; }
	Ref<TEventbus> GetEventbus() const { return FEventbus; }
	Ref<TBlackboard> GetBlackboard() const { return FBlackboard; }
	Ref<TEventbus> GetGlobalEventbus() const { return FGlobalEventbus; }
	bool GetIsAbstract() const { return FAbstract; }
	void SetIsAbstract(bool p_value) { FAbstract = p_value; }
	int64_t GetCreatedTimestamp() const { return FCreatedTimestamp; }
	String GetSkinIDField() const { return FSkinID; }
	void SetSkinIDField(const String &p_value) { FSkinID = p_value; }
	Vector2 GetPosition() const { return FPosition; }
	Vector2 GetFront() const { return FFront; }
	double GetCollisionRadius() const { return FCollisionRadius; }
	void SetCollisionRadius(double p_value);
	Vector3 GetDisplayPosition() const { return DisplayPosition; }
	void SetDisplayPosition(const Vector3 &p_value) { DisplayPosition = p_value; }
	Vector3 GetDisplayFront() const { return DisplayFront; }
	void SetDisplayFront(const Vector3 &p_value) { DisplayFront = p_value; }
	Vector3 GetDisplayUp() const { return DisplayUp; }
	void SetDisplayUp(const Vector3 &p_value) { DisplayUp = p_value; }
	void SetFPosition(const Vector2 &p_value) { FPosition = p_value; }
	void SetFFront(const Vector2 &p_value) { FFront = p_value; }
	Array GetGroupsInUse() const;
};

} // namespace godot
