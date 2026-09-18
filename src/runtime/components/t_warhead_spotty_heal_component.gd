class_name TWarheadSpottyHealComponent
extends TWarheadSpottyHealthComponent
## Port of TWarheadSpottyHealComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:136,
## implementation :310), server only. Heals eiWelaDamage to the target (see TWarheadSpottyHealthComponent).


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FHeal = true
	return self
