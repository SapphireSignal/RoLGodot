extends "res://tests/test_case.gd"
## Script runner in TEntity (BaseConflict.Entity.pas:587-712). Expected values are copied from the original scripts
## named in each test (Scripts\...), the order rules from TEntity.CreateFromScriptProc.
## Scripts that read card league/level: tests/test_resource_manager.gd.

const C = preload("res://src/runtime/dws/dws_const.gd")

var _free: Array = []


func after_each() -> void:
	for o in _free:
		o.Free()
	_free.clear()
	TEntity.SetLastScriptError("")
	TEntity.SetQuietScriptErrors(false)


func _bus(side: int) -> TEventbus:
	var bus := TEventbus.new().Create(null)
	bus.ApplicationType = side
	_free.append(bus)
	return bus


func _keep(e: TEntity) -> TEntity:
	if e != null:
		_free.push_front(e)  # entities before their global bus
	return e


## Units\White\Footman.ets CreateData (server side: no tooltip components).
func test_base_script_data() -> void:
	var e := _keep(TEntity.CreateDataFromScript("Units\\White\\Footman", _bus(C.nsServer)))
	check(e != null, "entity created: " + TEntity.GetLastScriptError())
	if e == null:
		return
	check_eq(e.ScriptFile, "Units\\White\\Footman", "ScriptFile")
	check_eq(e.IsAbstract, true, "CreateData makes a meta entity")
	check_eq(e.CollisionRadius, RParam.ToSingle(0.55), "CollisionRadius")
	check_eq(e.Blackboard.GetValue(C.eiArmorType, []), C.atMedium, "armor")
	check_eq(e.Blackboard.GetIndexedValue(C.eiResourceCap, [], C.reHealth), RParam.ToSingle(32.0), "health cap")
	check_eq(e.Blackboard.GetValue(C.eiCooldown, [1]), 2000, "sword cooldown")
	check_eq(e.Blackboard.GetValue(C.eiWelaDamage, [2]), RParam.ToSingle(10.0), "shield damage")
	# UnitTemplate.dws InitUnitData
	check_eq(e.Blackboard.GetValue(C.eiWelaUnitPattern, [C.GROUP_SOUL]), "Projectiles\\Black\\SoulGatherProjectileSpawner", "soul pattern")
	check_eq(TEntity.GetLastScriptError(), "", "no script error")


## Units\Neutral\LaneNode_Blue.ets: InheritsFrom LaneNode.ets. Base runs first (after the initializer), then the child.
func test_inherits_from() -> void:
	var seen: Array = []
	var init := func(Entity: TEntity) -> void:
		seen.append(Entity.IsAbstract)
		Entity.Blackboard.SetValue(C.eiCooldown, [1], 7)
	var e := _keep(TEntity.CreateMetaFromScript("Units/Neutral/LaneNode_Blue", _bus(C.nsServer), init))
	check(e != null, "entity created: " + TEntity.GetLastScriptError())
	if e == null:
		return
	check_eq(seen, [true], "initializer ran once, on the meta entity")
	check_eq(e.ScriptFile, "Units/Neutral/LaneNode_Blue", "keeps the child's file name")
	check_eq(e.Blackboard.GetValue(C.eiCooldown, [1]), 500, "base CreateData ran after the initializer")
	check_eq(e.Blackboard.GetValue(C.eiCooldown, [12]), 40000, "child CreateData ran")
	check_eq(RParam.AsSet(e.Blackboard.GetValue(C.eiUnitProperties, [])), DSet.Make([C.upGround, C.upBase, C.upLaneNode]), "base properties")
	# CardLeague() is 0 (not set): LaneNode.ets line 17 takes the else branch
	check_eq(e.Blackboard.GetIndexedValue(C.eiWelaUnitPattern, [4, 5], 2), "Units\\Neutral\\LanetowerLevel2.ets", "league branch")


## Projectiles\Blue\AegisMissile.ets: InheritsFromPreceding Missile.ets. Initializer, then the child, then the base.
func test_inherits_from_preceding_on_client() -> void:
	var bus := _bus(C.nsClient)
	var init := func(Entity: TEntity) -> void:
		Entity.Blackboard.SetValue(C.eiSpeed, [], 1.0)
	var e := _keep(TEntity.CreateDataFromScript("Projectiles\\Blue\\AegisMissile", bus, init))
	check(e != null, "entity created: " + TEntity.GetLastScriptError())
	if e == null:
		return
	check_eq(e.IsServer(), false, "client entity")
	check_eq(e.ScriptFile, "Projectiles\\Blue\\AegisMissile", "keeps the child's file name")
	check_eq(e.Blackboard.GetValue(C.eiSpeed, []), RParam.ToSingle(20.0 / 1000), "base CreateData ran last")
	check_eq(e.Blackboard.GetValue(C.eiWelaModifier, [1]), RParam.ToSingle(2.0), "base value")


func test_sides_and_paths() -> void:
	var s = TEntity.CompileScriptFromFile("Scripts\\Units\\White\\Footman.ets", true)
	var c = TEntity.CompileScriptFromFile("\\scripts\\units/white/FOOTMAN.ets", false)
	check(s != null and s.get_script().resource_path.contains("/server/"), "server script")
	check(c != null and c.get_script().resource_path.contains("/client/"), "client script, any case and slash")


## SetGlobalVariableValueIfExist: Units\Neutral\NexusLevel1.ets declares Game, Environment\Bridge1.ets GlobalEventbus.
func test_script_globals() -> void:
	var bus := _bus(C.nsServer)
	var game := RefCounted.new()
	bus.Game = game
	var nexus = TEntity.CompileScriptFromFile("Units\\Neutral\\NexusLevel1.ets", true)
	TEntity._SetScriptGlobals(nexus, bus)
	check(nexus.Game == game, "Game set from the bus")
	var bridge = TEntity.CompileScriptFromFile("Environment\\Bridge1.ets", true)
	TEntity._SetScriptGlobals(bridge, bus)
	check(bridge.GlobalEventbus == bus, "GlobalEventbus set")
	bus.Game = null


func test_apply_script() -> void:
	var e := _keep(TEntity.new().Create(_bus(C.nsServer)))
	e.ApplyScript("Modifiers\\Death.dws")
	check_eq(TEntity.GetLastScriptError(), "", "Apply(Entity) with the entity")
	e.ApplyScript("\\Scripts\\Modifiers\\Death.dws", "Apply", [e])
	check_eq(TEntity.GetLastScriptError(), "", "explicit parameters, PATH_SCRIPT prefix kept")
	check_eq(e.ApplyScriptReturnGroups("Modifiers\\Death.dws"), [], "no array returned: []")


func test_failures() -> void:
	TEntity.SetQuietScriptErrors(true)
	var bus := _bus(C.nsServer)
	check(TEntity.CreateFromScript("Units\\White\\NoSuchUnit", bus) == null, "missing script")
	check(TEntity.GetLastScriptError().contains("Can't find scriptfile"), "missing script error")
	var e := _keep(TEntity.new().Create(bus))
	e.ApplyScript("Modifiers\\Death.dws", "Apply", [e, 1])
	check(TEntity.GetLastScriptError().contains("Parametercount"), "parameter count must match")
	TEntity.SetLastScriptError("")
	e.ApplyScript("AI\\MegaRootDude.dws", "Prepare", [e])
	check(TEntity.GetLastScriptError().contains("Error while compiling"), "server cannot compile MegaRootDude")
