class_name TServerGameInformation
extends TGameInformation
## Port of TServerGameInformation (GameServer/BaseConflict.Types.Server.pas:50, implementation :88): who plays a
## server game. Player: token -> TGamePlayer; Slots: the commanders (TCommanderInformation) by slot index;
## Mapping: token -> the slot indices it controls. GameID / GamePort serve the network.
## Port note: Player and Mapping are Dictionaries in insertion order (the original: TDictionary hash order; with one
## player, as in every local game, the orders agree).

var CoopVsAI := false
var Player := {}  # String -> TGamePlayer
var Slots: Array = []  # of TCommanderInformation
var Mapping := {}  # String -> Array of int
var GameID := ""
var GamePort := 0


func Create() -> TServerGameInformation:
	super()
	Player = {}
	Slots = []
	Mapping = {}
	return self


func AddPlayer(Token: String, GamePlayer: TGamePlayer) -> void:
	GamePlayer.Token = Token
	Player[Token] = GamePlayer


## Marks players as bots if they control a bot slot and gives them the team of their first slot.
func UpdateGamePlayers() -> void:
	for Token: String in Mapping:
		var IsBotPlayer := false
		var TeamID := -1
		var ControlledCommanders: Array = Mapping[Token]
		for i in ControlledCommanders.size():
			IsBotPlayer = IsBotPlayer or Slots[ControlledCommanders[i]].IsBot
			if i == 0:
				TeamID = Slots[ControlledCommanders[i]].TeamID
		if Player.has(Token):
			Player[Token].IsBot = IsBotPlayer
			Player[Token].TeamID = TeamID


func TokenToTeamID(Token: String) -> int:
	if Mapping.has(Token):
		for Slot: int in Mapping[Token]:
			if Slot < Slots.size():
				return Slots[Slot].TeamID
	return -1


func RealPlayerCount() -> int:
	var Result := 0
	for Token: String in Player:
		if not Player[Token].IsBot:
			Result += 1
	return Result
