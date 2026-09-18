class_name TBuildZoneManager
extends TObject
## Port of TBuildZoneManager (BaseConflict.Map.pas:115, implementation :796): the map's build zones by ID.
## BuildZones iterates in insertion order (the original's hash order; zones never overlap, so the first zone in
## range is the only one). Adding an ID twice is an error, as in TDictionary.Add.

var BuildZones := {}  # ID -> TBuildZone


func UpdateEntityIDInBuildZones(oldID: int, newID: int) -> void:
	for BuildZone: TBuildZone in BuildZones.values():
		BuildZone.UpdateEntityID(oldID, newID)


func AddBuildZone(BuildZone: TBuildZone) -> TBuildZoneManager:
	if BuildZones.has(BuildZone.ID):
		push_error("TBuildZoneManager.AddBuildZone: duplicate build zone ID %d" % BuildZone.ID)
	else:
		BuildZones[BuildZone.ID] = BuildZone
	return self


## TryGetBuildZone(ID, out BuildZone): the zone or null.
func TryGetBuildZone(ID: int) -> TBuildZone:
	return BuildZones.get(ID)


func GetBuildZone(ID: int) -> TBuildZone:
	return BuildZones.get(ID)


func GetBuildZoneByPosition(Position: Vector2) -> TBuildZone:
	for BuildZone: TBuildZone in BuildZones.values():
		if BuildZone.InRange(Position):
			return BuildZone
	return null


func GetWaveEntityIDByPosition(Position: Vector2) -> int:
	var BuildZone := GetBuildZoneByPosition(Position)
	if BuildZone != null:
		return BuildZone.GetFieldID(BuildZone.PositionToCoord(Position))
	return -1


func GetWaveEntityIDByCoord(ID: int, Coord: Vector2i) -> int:
	var BuildZone := GetBuildZone(ID)
	if BuildZone != null:
		return GetWaveEntityIDByPosition(BuildZone.GetCenterOfField(Coord))
	return -1


func Destroy() -> void:
	for BuildZone: TBuildZone in BuildZones.values():
		BuildZone.Free()
	BuildZones.clear()
	super()
