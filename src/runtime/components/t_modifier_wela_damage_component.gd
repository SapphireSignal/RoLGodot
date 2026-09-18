class_name TModifierWelaDamageComponent
extends TModifierComponent
## Port of TModifierWelaDamageComponent (BaseConflict.EntityComponents.Shared.Wela.pas:151, implementation :1025).
## While active, changes eiWelaDamage of its groups by Factor = eiWelaModifier of ValueGroup (default 1):
## negated (Negate), times a resource balance + offset (ScaleWithResource, capped by MaximumResourceScaleFactor),
## times FFactor if the owner has all FactorForUnitProperty properties. Adds Factor, or multiplies / divides by it.

var FResourceGroup: Array = []
var FScalesWithResource: int = C.reNone
var FDivide := false
var FMultiply := false
var FNegate := false
var FFactor := 0.0
var FMaximumResourceScaleFactor := 0.0
var FResourceOffset := 0.0
var FMustHave: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaDamage", C.eiWelaDamage, C.epMiddle, C.etRead))


func OnWelaDamage(Previous):
	if RParam.IsEmpty(Previous) or not IsActive():
		return Previous
	var Factor := RParam.AsSingleDefault(Eventbus().Read(C.eiWelaModifier, [], FValueGroup), 1.0)
	if FNegate:
		Factor = -Factor
	if FScalesWithResource != C.reNone:
		var ResourceFactor := BC.ResourceAsSingle(FScalesWithResource, Owner.Balance(FScalesWithResource, FResourceGroup))
		ResourceFactor = RParam.ToSingle(ResourceFactor + FResourceOffset)
		if FMaximumResourceScaleFactor > 0:
			ResourceFactor = minf(ResourceFactor, FMaximumResourceScaleFactor)
		Factor = RParam.ToSingle(Factor * ResourceFactor)
	if not FMustHave.is_empty() and DSet.Difference(FMustHave, Owner.UnitProperties()).is_empty():
		Factor = RParam.ToSingle(Factor * FFactor)
	if FMultiply:
		return RParam.ToSingle(RParam.AsSingle(Previous) * Factor)
	if FDivide:
		return RParam.ToSingle(RParam.AsSingle(Previous) / Factor)
	return RParam.ToSingle(RParam.AsSingle(Previous) + Factor)


func ScaleWithResource(ResType: int) -> TModifierWelaDamageComponent:
	FScalesWithResource = ResType
	return self


func ResourceGroup(Group: Array) -> TModifierWelaDamageComponent:
	FResourceGroup = DSet.Make(Group)
	return self


func ResourceOffset(Offset: float) -> TModifierWelaDamageComponent:
	FResourceOffset = RParam.ToSingle(Offset)
	return self


func FactorForUnitProperty(UnitProperties: Array, Factor: float) -> TModifierWelaDamageComponent:
	FMustHave = DSet.Make(UnitProperties)
	FFactor = RParam.ToSingle(Factor)
	return self


func MaximumResourceScaleFactor(Maximum: float) -> TModifierWelaDamageComponent:
	FMaximumResourceScaleFactor = RParam.ToSingle(Maximum)
	return self


func Divide() -> TModifierWelaDamageComponent:
	FDivide = true
	return self


func Multiply() -> TModifierWelaDamageComponent:
	FMultiply = true
	return self


func Negate() -> TModifierWelaDamageComponent:
	FNegate = true
	return self
