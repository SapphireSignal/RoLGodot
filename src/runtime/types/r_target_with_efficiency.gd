class_name RTargetWithEfficiency
extends RefCounted
## Port of RTargetWithEfficiency (GameServer/BaseConflict.Types.Server.pas:20, implementation :73): a target and
## how well a wela fits it (server targeting). A record in the original: treat it as a value.

var Target: RTarget
var Efficiency := 0.0


static func Create(Target_: RTarget, Efficiency_: float) -> RTargetWithEfficiency:
	var Result := RTargetWithEfficiency.new()
	Result.Target = Target_
	Result.Efficiency = RParam.ToSingle(Efficiency_)
	return Result
