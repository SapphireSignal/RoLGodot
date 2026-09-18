class_name TModifierResourceComponent
extends TModifierComponent
## Port of TModifierResourceComponent (BaseConflict.EntityComponents.Shared.Wela.pas:102, implementation :1116).
## Changes the cap of a resource (eiResourceCapTransaction) once, on ApplyNow, and takes the change back when freed
## (unless the game is shutting down). Amount = eiWelaDamage of ValueGroup, times a resource of its own group
## (ScaleWithResource, balance or UseResourceCap), then times (or plus, AddModifier) eiWelaModifier of ValueGroup
## (default 1). A reduction leaves at least 1 of the modified resource's cap.

var FModifiedResource: int = C.reNone
var FScaleWithResource: int = C.reNone
var FUseResourceCap := false
var FAddModifier := false
var FDontFillCap := false
var FChangedResource := 0.0


func BeforeComponentFree() -> void:
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	if game != null and not game.IsShuttingDown():
		ModifyResource(-FChangedResource)
	super()


func ModifyResource(Amount: float) -> void:
	if BC.IsIntResource(FModifiedResource):
		Eventbus().Trigger(C.eiResourceCapTransaction, [FModifiedResource, L.Round(Amount), FDontFillCap], [])
	else:
		Eventbus().Trigger(C.eiResourceCapTransaction, [FModifiedResource, RParam.ToSingle(Amount), FDontFillCap], [])


func Resource(ModifiedResource: int) -> TModifierResourceComponent:
	FModifiedResource = ModifiedResource
	return self


func ScaleWithResource(Resource_: int) -> TModifierResourceComponent:
	FScaleWithResource = Resource_
	return self


## Uses the resource cap instead of balance for ScaleWithResource.
func UseResourceCap() -> TModifierResourceComponent:
	FUseResourceCap = true
	return self


## Adds the eiWelaModifier instead of multiplying it.
func AddModifier() -> TModifierResourceComponent:
	FAddModifier = true
	return self


func DontFillCap() -> TModifierResourceComponent:
	FDontFillCap = true
	return self


## As this modifier isn't based on altering an event, we have to trigger it manually.
func ApplyNow() -> TModifierResourceComponent:
	FChangedResource = RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], FValueGroup))
	if FScaleWithResource != C.reNone:
		var Res: float
		if FUseResourceCap:
			Res = BC.ResourceAsSingle(FScaleWithResource, Owner.Cap(FScaleWithResource, ComponentGroup))
		else:
			Res = BC.ResourceAsSingle(FScaleWithResource, Owner.Balance(FScaleWithResource, ComponentGroup))
		FChangedResource = RParam.ToSingle(FChangedResource * Res)
	var Modifier := RParam.AsSingleDefault(Eventbus().Read(C.eiWelaModifier, [], FValueGroup), 1.0)
	if FAddModifier:
		FChangedResource = RParam.ToSingle(FChangedResource + Modifier)
	else:
		FChangedResource = RParam.ToSingle(FChangedResource * Modifier)
	# resource cap of health can't be reduced below 1 health
	if FChangedResource < 0:
		var CapLeft := BC.ResourceAsSingle(FModifiedResource, Owner.Cap(FModifiedResource)) - 1.0
		FChangedResource = RParam.ToSingle(-minf(CapLeft, -FChangedResource))
	ModifyResource(FChangedResource)
	return self
