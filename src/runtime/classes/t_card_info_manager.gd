class_name TCardInfoManager
extends TObject
## Port of TCardInfoManager (BaseConflict.Constants.Cards.pas:172, implementation :249-425): every card of the game
## by its UID, and a cache of the card infos per UID, league and level. The original fills its global instance in
## the unit's initialization section; the port replays that list from src/content/cards.json (made by
## tools/convert_cards.py) into the one shared instance, TCardInfoManager.Instance().
## FServerUnitMapping is a DelphiDictionary with the string hash (DelphiHash.StringHash): GetAllCardUIDs and
## ScriptFilenameToCardInfo walk it in the original's slot order.
## Not here: ScriptFilenameToCardStringInfo (translated card texts) comes with the localization (client UI).

const C = preload("res://src/runtime/dws/dws_const.gd")
const BC = preload("res://src/runtime/base_conflict_constants.gd")
const CARD_LIST = "res://src/content/cards.json"

static var _Instance: TCardInfoManager = null

## UID -> TCardInfo (at MAX_LEAGUE / MAX_LEVEL)
var FServerUnitMapping: DelphiDictionary
## UID -> {[League, Level]: TCardInfo}
var FCardInfoCache := {}


## The global CardInfoManager, built on first use.
static func Instance() -> TCardInfoManager:
	if _Instance == null:
		_Instance = TCardInfoManager.new().Create()
		_Instance.LoadCardList(CARD_LIST)
	return _Instance


func Create() -> TCardInfoManager:
	FServerUnitMapping = DelphiDictionary.new().Create(DelphiHash.StringHash,
		func(Left: String, Right: String) -> bool: return Left == Right)
	return self


## Replays the original's AddCard / AddSkin calls in their order.
func LoadCardList(Filename: String) -> void:
	var Entries = JSON.parse_string(FileAccess.get_file_as_string(Filename))
	if not Entries is Array:
		push_error("TCardInfoManager: cannot read the card list " + Filename)
		return
	for Entry: Array in Entries:
		if Entry[0] == "card":
			var Colors: Array = []
			for Color in Entry[3]:
				Colors.append(int(Color))
			AddCard(Entry[1], TCardInfo.new().Create(int(Entry[2]), Colors, Entry[4], int(Entry[5])), Entry[6])
		else:
			AddSkin(Entry[1], Entry[2], Entry[3])


func AddCard(UID: String, CardInfo: TCardInfo, SkinID: String = "") -> void:
	CardInfo.FUID = UID
	# unskinned cards have themselves as base
	if CardInfo.BaseUID == "":
		CardInfo.FBaseUID = CardInfo.UID
	CardInfo.FSkinID = SkinID
	FServerUnitMapping.Add(UID, CardInfo)


func AddSkin(BaseUID: String, UID: String, SkinID: String) -> void:
	var CardInfo: TCardInfo = FServerUnitMapping.GetItem(BaseUID)
	# if first skin is added to a card its default entry is the default skin
	if not CardInfo.HasSkin():
		CardInfo.FSkinID = C.SKIN_GROUP_DEFAULT
	CardInfo = CardInfo.Clone(BC.MAX_LEAGUE, BC.MAX_LEVEL)
	CardInfo.FBaseUID = BaseUID
	AddCard(UID, CardInfo, SkinID)


func GetAllCardUIDs() -> Array:
	return FServerUnitMapping.Keys()


## Resolves a card uid to its meta info; null if the card is unknown. '_' in the UID reads as '-'.
func ResolveCardUID(CardUID: String, League: int, Level: int) -> TCardInfo:
	if BC.DISABLE_LEAGUE_SYSTEM:
		League = BC.DEFAULT_LEAGUE
		Level = BC.DEFAULT_LEVEL
	# replace is hack for dui
	return TryResolveCardUID(CardUID.replace("_", "-"), League, Level)


## The card info of CardUID at League / Level (one shared instance per triple), or null (logged) if unknown.
func TryResolveCardUID(CardUID: String, League: int, Level: int) -> TCardInfo:
	if BC.DISABLE_LEAGUE_SYSTEM:
		League = BC.DEFAULT_LEAGUE
		Level = BC.DEFAULT_LEVEL
	if not FCardInfoCache.has(CardUID):
		FCardInfoCache[CardUID] = {}
	var CardInfos: Dictionary = FCardInfoCache[CardUID]
	var Key := [League, Level]
	if not CardInfos.has(Key):
		if FServerUnitMapping.ContainsKey(CardUID):
			CardInfos[Key] = FServerUnitMapping.GetItem(CardUID).Clone(League, Level)
		else:
			push_warning('TCardInfoManager.ResolveCardUID: Card "%s" is not present in client!' % CardUID)
			return null
	return CardInfos[Key]


## The first card (in the dictionary's walk order) with this script file and skin (both case-insensitive), resolved
## at League / Level; null if none.
func ScriptFilenameToCardInfo(ScriptFile: String, SkinID: String, League: int, Level: int) -> TCardInfo:
	var Slot := FServerUnitMapping.NextSlot(-1)
	while Slot >= 0:
		var CardInfo: TCardInfo = FServerUnitMapping.ValueAt(Slot)
		if DelphiRtl.SameText(CardInfo.Filename, ScriptFile) and DelphiRtl.SameText(CardInfo.SkinID, SkinID):
			return ResolveCardUID(CardInfo.UID, League, Level)
		Slot = FServerUnitMapping.NextSlot(Slot)
	return null


## Transforms a filename to the identifier of a unit (no path, no extension, without Drop / Spawner / Building /
## Spell), used by localization or to create the base unit of a drop or template.
static func ScriptFilenameToCardIdentifier(ScriptFile: String) -> String:
	var Result := DelphiRtl.ChangeFileExt(DelphiRtl.ExtractFileName(ScriptFile), "")
	for Identifier in [BC.FILE_IDENTIFIER_DROP, BC.FILE_IDENTIFIER_SPAWNER, BC.FILE_IDENTIFIER_BUILDING,
			BC.FILE_IDENTIFIER_SPELL]:
		Result = Result.replace(Identifier, "")
	return Result


static func ScriptFilenameToCardColors(ScriptFile: String) -> Array:
	return BC.ScriptFilenameToCardColors(ScriptFile)


static func ScriptFilenameToCardType(ScriptFile: String) -> int:
	return BC.ScriptFilenameToCardType(ScriptFile)


## The folder of a color set: the color names in the order Black, Blue, Colorless, Green, Red, White, then '\'.
static func EntityColorsToFolder(EntityColors: Array) -> String:
	var Result := ""
	if EntityColors.has(C.ecBlack):
		Result += "Black"
	if EntityColors.has(C.ecBlue):
		Result += "Blue"
	if EntityColors.has(C.ecColorless):
		Result += "Colorless"
	if EntityColors.has(C.ecGreen):
		Result += "Green"
	if EntityColors.has(C.ecRed):
		Result += "Red"
	if EntityColors.has(C.ecWhite):
		Result += "White"
	return Result + "\\"
