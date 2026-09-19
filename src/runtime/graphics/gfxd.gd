class_name GFXD
extends RefCounted
## The parts of the original's graphics device (Engine.GfxApi.pas GFXD) the ported client code reaches:
## MainScene, where meshes are drawn (a Node3D the owner of the view sets; null = meshes stay out of any tree, e.g. in
## headless tests), and FPSCounter.FrameCount, the frame number that animations use to update once per frame. The
## owner of the view calls NextFrame once per drawn frame (tests call it to step animations).

static var MainScene: Node = null
static var FrameCount := 0
## TFPSCounter (Engine.Helferlein.Windows.pas:4171): frames counted per window of at least 1 s
static var _fps_counter := 0
static var _fps_window_start := 0
static var _current_fps := 0


static func NextFrame() -> void:
	FrameCount += 1


## TFPSCounter.FrameTick, once per drawn frame (TGFXD's frame end): when a second or more has passed since the window
## started, FPS = frames * 1000 div elapsed ms. The engine clock (TimeManager.GetTimeStamp).
static func FPSFrameTick() -> void:
	_fps_counter += 1
	var now := TTimeManager.GetTimeStamp()
	var delta := now - _fps_window_start
	if delta >= 1000:
		_current_fps = _fps_counter * 1000 / delta
		_fps_counter = 0
		_fps_window_start = now


## TGFXD.FPS = FFPSCounter.getFPS
static func FPS() -> int:
	return _current_fps


## Adds a node to the main scene if there is one.
static func AddToScene(node: Node) -> void:
	if MainScene != null and is_instance_valid(MainScene) and node.get_parent() == null:
		MainScene.add_child(node)
