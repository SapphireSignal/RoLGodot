extends Control
## Entry scene. Placeholder until the client boot flow (splash, login, main menu) is ported.


func _ready() -> void:
	print("RoLGodot boot: %s" % ProjectSettings.get_setting("application/config/name"))
