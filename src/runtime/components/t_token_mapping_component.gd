class_name TTokenMappingComponent
extends TEntityComponent
## Port of TTokenMappingComponent (GameServer/BaseConflict.EntityComponents.Server.pas:299, implementation :1476),
## server only, on the game entity: the player token -> commander IDs mapping, made by TServerGame.Initialize.
## eiTokenMapping [Token] answers a copy of the token's commander IDs, or null for an unknown token.

var FTokenMapping := {}  # String -> Array of int


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTokenMapping", C.eiTokenMapping, C.epFirst, C.etRead, C.esGlobal))


func Create(Owner = null, TokenMapping = {}) -> TEntityComponent:
	FTokenMapping = TokenMapping
	super(Owner)
	return self


func OnTokenMapping(Token, _Previous):
	var Key := RParam.AsString(Token)
	if FTokenMapping.has(Key):
		return FTokenMapping[Key].duplicate()
	return null
