class_name TGameManager
extends RefCounted
## Port of the game setups of TGameManager (GameServer/BaseConflict.Game.Server.pas:144, implementation :255-727):
## the test server's sandbox game (CreateTestserverGameInfo), its default commanders with every card of a color
## (CreateDefaultGameInfo) and the tutorial deck (InitTutorialCommander), which is also the sandbox players' deck.
## The rest of TGameManager (ports, game threads, the master server backchannel) is network only.

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")


## The sandbox game with 13 commanders: every card of one color each (black, green, white, golems as "red", every
## other color as "blue", colorless) for team 1 and team 2, and a colorless one for the PvE team; one player
## controls all of them.
static func CreateDefaultGameInfo() -> TServerGameInformation:
	# create default gamesettings
	var Result := TServerGameInformation.new().Create()
	Result.ScenarioUID = BC.TESTSERVER_SCENARIO_UID
	Result.League = BC.TESTSERVER_SENARIO_LEAGUE
	Result.IsSandboxOverride = BC.TESTSERVER_SCENARIO_UID.contains(BC.SCENARIO_SANDBOX_UID)
	Result.Scenario = HScenario.ResolveScenario(BC.TESTSERVER_SCENARIO_UID, BC.TESTSERVER_SENARIO_LEAGUE)

	Result.CoopVsAI = true

	var SecretKey := "1"
	Result.AddPlayer(SecretKey, TGamePlayer.new().Create(0, 0, "Player 1"))

	for TeamID in [1, 2]:
		for Color in [C.ecBlack, C.ecGreen, C.ecWhite, C.ecRed, C.ecBlue, C.ecColorless]:
			Result.Slots.append(_CreateCommander(Color, TeamID))
	Result.Slots.append(_CreateCommander(C.ecColorless, C.PVE_TEAM_ID))

	Result.Mapping[SecretKey] = range(13)
	return Result


static func _CreateCommander(Color: int, TeamID: int) -> TCommanderInformation:
	var Result := TCommanderInformation.new().Create()
	Result.TeamID = TeamID
	Result.Deckname = "Sandbox"
	var Order := {}  # Tier -> Array of RCommanderCard
	var Colors: Array
	if Color == C.ecWhite:
		Colors = [C.ecWhite]
	elif Color == C.ecGreen:
		Colors = [C.ecGreen]
	elif Color == C.ecBlack:
		Colors = [C.ecBlack]
	elif Color == C.ecColorless:
		Colors = [C.ecColorless]
	elif Color == C.ecRed:
		Colors = [C.ecColorless]
	else:
		Colors = DSet.Difference(BC.ALL_COLORS, DSet.Make([C.ecWhite, C.ecGreen, C.ecBlack, C.ecColorless]))
	var Manager := TCardInfoManager.Instance()
	for CardUID: String in Manager.GetAllCardUIDs():
		var CardInfo: TCardInfo = Manager.TryResolveCardUID(CardUID, BC.DEFAULT_LEAGUE, BC.DEFAULT_LEVEL)
		if CardInfo == null:
			continue
		if not DSet.Intersection(CardInfo.CardColors, Colors).is_empty() \
				and (Color != C.ecRed or CardInfo.Filename.contains(BC.FILE_IDENTIFIER_GOLEMS)) \
				and (Color != C.ecColorless or not CardInfo.Filename.contains(BC.FILE_IDENTIFIER_GOLEMS)):
			var Tier := CardInfo.Techlevel
			if not Order.has(Tier):
				Order[Tier] = []
			Order[Tier].append(RCommanderCard.Create(CardInfo.UID, BC.DEFAULT_LEAGUE, BC.DEFAULT_LEVEL))

	# sort for Tier
	for Tier in range(0, 11):
		if Order.has(Tier):
			Result.Cards.append_array(Order[Tier])
	return Result


## The sandbox of the test server: the default game plus a sandbox deck for team 1 and team 2 in front (slots 0 and 1).
static func CreateTestserverGameInfo() -> TServerGameInformation:
	var Result := CreateDefaultGameInfo()
	Result.IsSandboxOverride = true
	# add selected deck for team 2
	var Commander := TCommanderInformation.new().Create()
	Commander.TeamID = 2
	Commander.Deckname = "Sandbox"
	InitTutorialCommander(Commander)
	Result.Slots.insert(0, Commander)
	# add selected deck for team 1
	Commander = TCommanderInformation.new().Create()
	Commander.TeamID = 1
	Commander.Deckname = "Sandbox"
	InitTutorialCommander(Commander)
	Result.Slots.insert(0, Commander)

	var SecretKey := "1"
	Result.Player.clear()
	Result.AddPlayer(SecretKey, TGamePlayer.new().Create(1, 1, "Player"))
	Result.Mapping.clear()
	# sandbox commanders and real commanders
	Result.Mapping[SecretKey] = range(15)
	return Result


static func CreateTutorialGameInfo() -> TServerGameInformation:
	var Result := TServerGameInformation.new().Create()
	Result.CoopVsAI = true
	var Commander := TCommanderInformation.new().Create()
	Commander.TeamID = 1
	Commander.Deckname = "Tutorial"
	InitTutorialCommander(Commander)
	Result.Slots.insert(0, Commander)
	return Result


static func InitTutorialCommander(Commander: TCommanderInformation) -> void:
	Commander.Cards.append(RCommanderCard.Create("4a3d81c7-8c6b-454d-9469-95f6cf394c9b", 2, 1))  # 0 - FootmanDrop
	Commander.Cards.append(RCommanderCard.Create("51c25adb-3f4b-4e89-a972-15c2080933b9", 2, 1))  # 1 - ArcherDrop
	Commander.Cards.append(RCommanderCard.Create("d6775352-3586-4a2d-af0f-b3149d59dbec", 2, 1))  # 2 - BallistaDrop
	Commander.Cards.append(RCommanderCard.Create("527dd787-d8e9-4817-b45a-13b72495dbf7", 2, 1))  # 3 - HailOfArrows
	Commander.Cards.append(RCommanderCard.Create("21780eb8-3d2c-4c97-b279-59971475f3f8", 1, 1))  # 4 - DefenderDrop
	Commander.Cards.append(RCommanderCard.Create("30b4f36d-03d4-413c-8e9c-dc9f70346c15", 1, 1))  # 5 - ArcherSpawner
	Commander.Cards.append(RCommanderCard.Create("212b4d7e-65f9-43fa-a3df-50b31dd3da8f", 1, 1))  # 6 - FootmanSpawner
	Commander.Cards.append(RCommanderCard.Create("212b4d7e-65f9-43fa-a3df-50b31dd3da8f", 1, 1))  # 7 - FootmanSpawner
