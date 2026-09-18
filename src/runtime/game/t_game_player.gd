class_name TGamePlayer
extends TObject
## Port of TGamePlayer (GameServer/BaseConflict.Types.Server.pas:29, implementation :81): a real user (or bot) of a
## server game, found by its token.

var PlayerID := 0
var TeamID := 0
var Name := ""
var Token := ""
var IsBot := false


func Create(PlayerID_: int = 0, TeamID_: int = 0, Name_: String = "") -> TGamePlayer:
	PlayerID = PlayerID_
	Name = Name_
	TeamID = TeamID_
	return self
