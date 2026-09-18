class_name RVariedSingle
extends RefCounted
## Port of RVariedSingle (Engine/Engine.Math.pas): a value with a random variance. Scripts only create and pass
## it, so it is treated as immutable (Delphi records are copied by value).

var Mean: float = 0.0
var Variance: float = 0.0


static func Create(mean: float, variance: float = 0.0) -> RVariedSingle:
	var v := RVariedSingle.new()
	v.Mean = mean
	v.Variance = variance
	return v
