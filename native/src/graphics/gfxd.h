#pragma once

// The parts of the original's graphics device (Engine/Engine.GfxApi.pas GFXD) the ported client code reaches: MainScene,
// where meshes are drawn (a node the owner of the view sets; none = meshes stay out of any tree, e.g. in headless
// tests), and FPSCounter.FrameCount, the frame number that animations use to update once per frame. The owner of the
// view calls NextFrame once per drawn frame (tests call it to step animations).

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/object_id.hpp>

#include <cstdint>

namespace godot {

class GFXD : public RefCounted {
	GDCLASS(GFXD, RefCounted)

	static ObjectID FMainScene;
	static int64_t FFrameCount;
	// TFPSCounter (Engine.Helferlein.Windows.pas:4171): frames counted per window of at least 1 s
	static int64_t FFPSCounter;
	static int64_t FFPSWindowStart;
	static int64_t FCurrentFPS;

protected:
	static void _bind_methods();

public:
	static int64_t GetFrameCount() { return FFrameCount; }
	static void NextFrame() { FFrameCount++; }
	static Node *GetMainScene();
	static void SetMainScene(Node *p_node);
	// TFPSCounter.FrameTick, once per drawn frame (TGFXD's frame end): when a second or more has passed since the
	// window started, FPS = frames * 1000 div elapsed ms. The engine clock (TimeManager.GetTimeStamp).
	static void FPSFrameTick();
	// TGFXD.FPS = FFPSCounter.getFPS
	static int64_t FPS() { return FCurrentFPS; }
	// Adds a node to the main scene if there is one.
	static void AddToScene(Node *p_node);
};

} // namespace godot
