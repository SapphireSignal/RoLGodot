class_name RCommanderCard
extends RefCounted
## Port of RCommanderCard (BaseConflict.EntityComponents.Shared.pas:225, implementation :2443): a card in a
## commander's deck, by UID, league and level. A record in the original: treat it as a value.

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var CardUID := ""
var League := 0
var Level := 0


static func Create(CardUID_: String, League_: int, Level_: int) -> RCommanderCard:
	var Result := RCommanderCard.new()
	Result.CardUID = CardUID_
	Result.League = League_
	Result.Level = Level_
	return Result


static func CreateMaxed(CardUID_: String) -> RCommanderCard:
	return Create(CardUID_, BC.DEFAULT_LEAGUE, BC.DEFAULT_LEVEL)
