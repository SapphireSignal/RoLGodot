class_name TObject
extends RefCounted
## System.TObject as far as the game uses it. Delphi constructors are instance methods returning self
## (`TFoo.new().Create(...)`), so subclasses can extend Create with extra parameters only if they have defaults.
## Free calls the virtual destructor Destroy; the object itself is released when the last reference goes.


func Create() -> TObject:
	return self


## Destructor. Overrides call super() at the end, where the Delphi code says `inherited`.
func Destroy() -> void:
	pass


func Free() -> void:
	Destroy()


func ClassName() -> String:
	var script: Script = get_script()
	while script != null:
		var name := script.get_global_name()
		if name != &"":
			return name
		script = script.get_base_script()
	return "TObject"
