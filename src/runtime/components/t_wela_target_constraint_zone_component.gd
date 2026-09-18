class_name TWelaTargetConstraintZoneComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintZoneComponent (BaseConflict.EntityComponents.Shared.Wela.pas:367, implementation
## :1327). Only targets inside a map zone (Game.Map.Zones), e.g. drops in the drop zone; with Prefix the owner's
## team ID is appended to the zone name. With a padding the target must also be at least that far from the
## zone's border. A map without the zone allows everything.

var FZone := ""
var FPrefix := false
var FPadding := 0.0


func CreateGrouped(Owner = null, Group = [], Zone: String = "", Prefix: bool = false) -> TEntityComponent:
	super(Owner, Group)
	FZone = Zone
	FPrefix = Prefix
	return self


func IsPossible(Target: RTarget) -> bool:
	var temp := FZone
	if FPrefix:
		temp += str(Owner.TeamID())
	var Zones: Dictionary = TargetGame().Map.Zones
	if not Zones.has(temp):
		return true
	var BuildZone: TMultipolygon = Zones[temp]
	var targetPos := Target.GetTargetPosition(TargetGame())
	var Result := BuildZone.IsPointInMultiPolygon(targetPos)
	if Result and FPadding > 0:
		var NextValidPos := BuildZone.NextPointOnBorder(targetPos)
		Result = targetPos.distance_to(NextValidPos) >= FPadding
	return Result


func SetPadding(Padding: float) -> TWelaTargetConstraintZoneComponent:
	FPadding = RParam.ToSingle(Padding)
	return self
