class_name TCommanderAbilityComponent
extends TSerializableEntityComponent
## Port of TCommanderAbilityComponent (BaseConflict.EntityComponents.Shared.pas:236, implementation :2098-2159).
## Puts one deck card on a commander: resolves the card (TCardInfoManager) and applies its script to the commander,
## drops / buildings / spawners through Commander\CommanderMethods (AddDrop / AddBuilding / AddSpawner), spells
## through their own file's AddSpell, each with the card info and the deck slot. The server makes it in
## TServerGame.Initialize (constructor: Init at once); the original then sends it to the clients, where eiAfterCreate
## (epLast) runs Init there and frees the component.
## Port: an unknown card UID (the original crashes on the nil card info) is an error and adds nothing.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FSlot := 0
# deserialization of records with string explodes, so don't use RCommanderCard here
var FCardUID := ""
var FCardLeague := 0
var FCardLevel := 0


func CreateGrouped(Owner = null, Group = [], Card: RCommanderCard = null) -> TEntityComponent:
	super(Owner, Group)
	FCardUID = Card.CardUID
	assert(Card.League >= BC.MIN_LEAGUE and Card.League <= BC.MAX_LEAGUE,
		"TCommanderAbilityComponent.CreateGrouped: Invalid card league %d passed to server!" % Card.League)
	assert(Card.Level >= BC.MIN_LEVEL and Card.Level <= BC.MAX_LEVEL,
		"TCommanderAbilityComponent.CreateGrouped: Invalid card level %d passed to server!" % Card.Level)
	FCardLeague = Card.League
	FCardLevel = Card.Level
	Init()  # Server only
	return self


func CreateGroupedSlot(Owner, Group, Card: RCommanderCard, Slot: int) -> TEntityComponent:
	FSlot = Slot
	return CreateGrouped(Owner, Group, Card)


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))


func Init() -> void:
	var CardInfo := TCardInfoManager.Instance().ResolveCardUID(FCardUID, FCardLeague, FCardLevel)
	if CardInfo == null:
		push_error("TCommanderAbilityComponent.Init: unknown card " + FCardUID)
		return
	match CardInfo.CardType:
		C.ctDrop:
			Owner.ApplyScript("Commander\\CommanderMethods.dws", "AddDrop", [Owner, CardInfo, FSlot])
		C.ctBuilding:
			Owner.ApplyScript("Commander\\CommanderMethods.dws", "AddBuilding", [Owner, CardInfo, FSlot])
		C.ctSpell:
			Owner.ApplyScript(CardInfo.Filename, "AddSpell", [Owner, CardInfo, FSlot])
		C.ctSpawner:
			Owner.ApplyScript("Commander\\CommanderMethods.dws", "AddSpawner", [Owner, CardInfo, FSlot])


## Apply the scripts on the client.
func OnAfterCreate() -> bool:
	Init()  # Client only
	Free()
	return true
