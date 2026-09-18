extends SceneTree
## Times the headless sandbox match (not a test: run it by hand).
##   Godot_console.exe --headless --path . --log-file <abs> --script res://tests/profile_sandbox.gd
## Both players drop a FootmanDrop and place a FootmanSpawner, then the game runs PROFILE_SECONDS of game time
## (env, default 60) at 32 ms frames. Prints the setup time, the wall time per game second and the slowest frames.
## PROFILE_HANDLERS=1 also times every event handler (TEventbus.Prof; slows the run down) and lists the top 40.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const FRAME = 32.0


func _init() -> void:
	var seconds := int(OS.get_environment("PROFILE_SECONDS")) if OS.get_environment("PROFILE_SECONDS") != "" else 60
	var t0 := Time.get_ticks_usec()
	TTimeManager.FakeTime = 1000.0
	TGameThread.new().Create(TGameManager.CreateTestserverGameInfo()).Free()
	print("first setup (loads scripts and data): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	var thread := TGameThread.new().Create(TGameManager.CreateTestserverGameInfo())
	var t1 := Time.get_ticks_usec()
	thread.SetAllPlayersPlaying()
	_run(thread, BC.GAME_WARMING_DURATION + 2 * FRAME)
	var t2 := Time.get_ticks_usec()
	var game := thread.InternalGame
	for i in 2:
		var commander: TEntity = game.Commanders[i]
		_play(commander, "Units\\White\\FootmanDrop", RCommanderAbilityTarget.Create(Vector2(-20 if i == 0 else 20, -23)))
		_play(commander, "Units\\White\\FootmanSpawner", RCommanderAbilityTarget.CreateBuildTarget(i, Vector2i(1, 1)))
	print("commanders: %d, global eiIdle subscribers: %d" % [game.Commanders.size(),
		game.GlobalEventbus.FEventhandler[C.eiIdle * 3 + C.etTrigger].Subscribers.size()])
	var frames: Array = []
	var units_max := 0
	var prof_on := OS.get_environment("PROFILE_HANDLERS") != ""
	if prof_on:
		TEventbus.Prof = {}
	var until: float = TTimeManager.FakeTime + seconds * 1000.0
	while TTimeManager.FakeTime + FRAME <= until and not thread.Terminated:
		var f0 := Time.get_ticks_usec()
		TTimeManager.FakeTime += FRAME
		thread.DoComputeGame()
		frames.append([Time.get_ticks_usec() - f0, TTimeManager.FakeTime])
		units_max = maxi(units_max, game.EntityManager.FilterEntities([C.upUnit], []).size())
	var t3 := Time.get_ticks_usec()
	var total_ms := (t3 - t2) / 1000.0
	print("setup (TGameThread.Create): %.0f ms" % ((t1 - t0) / 1000.0))
	print("warm-up (%d ms game time): %.0f ms" % [BC.GAME_WARMING_DURATION, (t2 - t1) / 1000.0])
	print("match: %d frames, %.1f s game time, %.0f ms wall, %.1f ms per frame, %.2f wall s per game s, max units %d" % [
		frames.size(), frames.size() * FRAME / 1000.0, total_ms, total_ms / maxi(frames.size(), 1),
		total_ms / (frames.size() * FRAME), units_max])
	frames.sort_custom(func(a, b): return a[0] > b[0])
	print("slowest frames (us @ game ms): %s" % str(frames.slice(0, 8)))
	print("script error: '%s'" % TEntity.LastScriptError)
	if prof_on:
		var rows: Array = []
		for k in TEventbus.Prof:
			rows.append([k] + TEventbus.Prof[k])
		TEventbus.Prof = null
		rows.sort_custom(func(a, b): return a[2] > b[2])
		print("handlers by self time (calls, self ms, incl ms):")
		for r in rows.slice(0, 40):
			print("  %-70s %8d %9.1f %9.1f" % [r[0], r[1], r[2] / 1000.0, r[3] / 1000.0])
	thread.Free()
	TTimeManager.FakeTime = null
	TCardInfoManager._Instance = null
	TScenarioInfoManager._Instance = null
	TEntityComponent.FComponentSubscriptionPatterns = {}
	quit(0)


func _run(thread: TGameThread, ms: float) -> void:
	var until: float = TTimeManager.FakeTime + ms
	while TTimeManager.FakeTime + FRAME <= until:
		TTimeManager.FakeTime += FRAME
		thread.DoComputeGame()


func _play(commander: TEntity, pattern: String, target) -> void:
	var group := -1
	for g in range(0, 64):
		if commander.Blackboard.GetValue(C.eiWelaUnitPattern, [g]) == pattern:
			group = g
	var targets := RCommanderAbilityTarget.ArrayToRParam([target])
	var can := RParam.AsBoolean(commander.Eventbus.Read(C.eiCanUseAbility, [targets], [group]))
	print("play %s (group %d): %s" % [pattern, group, can])
	commander.Eventbus.Trigger(C.eiUseAbility, [targets], [group])
