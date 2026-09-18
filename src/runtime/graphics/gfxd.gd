class_name GFXD
extends RefCounted
## The parts of the original's graphics device (Engine.GfxApi.pas GFXD) the ported client code reaches:
## MainScene, where meshes are drawn (a Node3D the owner of the view sets; null = meshes stay out of any tree, e.g. in
## headless tests), and FPSCounter.FrameCount, the frame number that animations use to update once per frame. The
## owner of the view calls NextFrame once per drawn frame (tests call it to step animations).

static var MainScene: Node = null
static var FrameCount := 0


static func NextFrame() -> void:
	FrameCount += 1


## Adds a node to the main scene if there is one.
static func AddToScene(node: Node) -> void:
	if MainScene != null and is_instance_valid(MainScene) and node.get_parent() == null:
		MainScene.add_child(node)
