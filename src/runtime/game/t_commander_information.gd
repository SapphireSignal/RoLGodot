class_name TCommanderInformation
extends TObject
## Port of TCommanderInformation (GameServer/BaseConflict.Types.Server.pas:37, implementation :164): a commander
## slot of a server game: its team (1 or 2, 0 neutral), bot settings and deck.

var TeamID := 0
var IsBot := false
var IsSpectator := false
var BotDifficulty := 0
## Any name of the deck.
var Deckname := ""
var Cards: Array = []  # of RCommanderCard


func Create() -> TCommanderInformation:
	Cards = []
	return self


func CreateSpectator() -> TCommanderInformation:
	TeamID = 0
	IsSpectator = true
	return Create()
