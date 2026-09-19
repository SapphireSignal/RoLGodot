#pragma once

// TTimeManager (Engine/Engine.Helferlein.Windows.pas:1060, implementation :2214). Every time manager of the original
// reads the same clock (milliseconds since program start, TTimeManager.Initialize), so the clock is static here; an
// instance is one frame counter: ZDiff between its last two TickTacks. The game's clock is the threadvar
// GameTimeManager (BaseConflict.Globals.pas:21), TThreadContext.GameTimeManager in the port. The pause (SetPause) is
// not ported yet.
// Tests freeze the clock with SetFakeTime (milliseconds, a float; null = the real clock).

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace godot {

class TTimeManager : public RefCounted {
	GDCLASS(TTimeManager, RefCounted)

	static bool FFakeTimeSet;
	static double FFakeTime;

	// FZDiff : Single
	double FZDiff = 0.0;
	// LetzteZeit, in milliseconds
	double FLastTickTime = 0.0;

protected:
	static void _bind_methods();

public:
	// constructor Create: TickTack measures from now.
	TTimeManager();

	double GetZDiff() const { return FZDiff; }
	void SetZDiff(double p_value);
	double GetLastTickTime() const { return FLastTickTime; }
	void SetLastTickTime(double p_value) { FLastTickTime = p_value; }

	// Restarts the measurement at now (what Create does).
	void StartTickTack();
	// Call every frame: ZDiff = milliseconds since the last TickTack.
	void TickTack();

	static void SetFakeTime(const Variant &p_time);
	static Variant GetFakeTime();
	// GetFloatingTimestamp: milliseconds as a double.
	static double GetFloatingTimestamp();
	// GetTimeStamp: whole milliseconds (Round).
	static int64_t GetTimeStamp();
};

} // namespace godot
