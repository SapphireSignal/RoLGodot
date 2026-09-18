class_name TWelaReadySpawnedComponent
extends TWelaReadyComponent
## Port of TWelaReadySpawnedComponent (BaseConflict.EntityComponents.Shared.Wela.pas:661, implementation :2210).
## The associated wela is ready if the spawned unit also is ready. Used to determine things like legendary and
## heroic unique checks: writes the wela's eiOwnerCommander into the data entity of its eiWelaUnitPattern (at the
## component's card league/level, EntityDataCache) and reads that entity's eiIsReady, bypassing the cache.


func IsReady() -> bool:
	var SpawnedUnit := RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], ComponentGroup))
	if SpawnedUnit == "":
		# HLog.AssertAndLog: logged, stays ready
		push_warning("TWelaReadySpawnedComponent.IsReady: Wela Unit Pattern assumed if this component is used.")
		return true
	var Cache: TEntityDataCache = GlobalEventbus().EntityDataCache
	Cache.Write(SpawnedUnit, CardLeague(), CardLevel(), C.eiOwnerCommander, [Eventbus().Read(C.eiOwnerCommander, [])])
	return RParam.AsBooleanDefaultTrue(Cache.Read(SpawnedUnit, CardLeague(), CardLevel(), C.eiIsReady, [], -1, true))
