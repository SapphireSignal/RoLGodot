class_name RIncome
extends RefCounted
## Port of RIncome (BaseConflict.Types.Shared.pas:47, implementation :226). A record: value semantics, so
## ToRParam stores a copy and FromRParam (RParam.AsType<RIncome>) returns one; empty = (0, 0).

var Gold := 0.0  # single
var Wood := 0.0  # single


func _init(gold: float = 0.0, wood: float = 0.0) -> void:
	Gold = RParam.ToSingle(gold)
	Wood = RParam.ToSingle(wood)


static func Create(gold: float, wood: float) -> RIncome:
	return RIncome.new(gold, wood)


## class operator Add
static func Add(a: RIncome, b: RIncome) -> RIncome:
	return RIncome.new(a.Gold + b.Gold, a.Wood + b.Wood)


func Copy() -> RIncome:
	return RIncome.new(Gold, Wood)


func ToRParam():
	return Copy()


static func FromRParam(p) -> RIncome:
	if p is RIncome:
		return p.Copy()
	if p != null:
		push_error("RIncome.FromRParam: not an RIncome: %s" % str(p))
	return RIncome.new()
