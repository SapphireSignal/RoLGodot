class_name TAutoBrainOnFreeComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnFreeComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:620, implementation
## :2984), server only. When it is freed (not while the game shuts down, nor without a game) and eiIsReady of its
## group allows, fires (Fire: the chosen targets, default the owner) — even when exiled and without CanThink.


func BeforeComponentFree() -> void:
	var game = GlobalEventbus().Game if GlobalEventbus() != null else null
	if game != null and not game.IsShuttingDown and \
		RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		Fire()
	super()
