class_name TWarheadSplashHealComponent
extends TWarheadSplashHealthComponent
## Port of TWarheadSplashHealComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:276,
## implementation :299), server only. Heals a capped amount of health (eiWelaDamage × eiWelaSplashfactor) to all
## targets in range (eiWelaAreaOfEffect); see TWarheadSplashHealthComponent.


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FHeal = true
	return self
