#pragma once

// TTimer (Engine/Engine.Helferlein.Windows.pas:985, implementation :2013): a millisecond countdown on TTimeManager's
// clock. A timer made with Create(Interval) starts expired; CreateAndStart starts it now.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace godot {

class TTimer : public RefCounted {
	GDCLASS(TTimer, RefCounted)

protected:
	int64_t FInterval = 1;
	double FLastTime = 0.0;
	double FPauseTime = 0.0;
	bool FPaused = false;

	static void _bind_methods();

public:
	// Create / Create(Interval): initially expired.
	Ref<TTimer> Create(const Variant &p_new_interval = Variant());
	Ref<TTimer> CreateAndStart(int64_t p_new_interval);
	Ref<TTimer> CreatePaused(int64_t p_new_interval);
	// TObject.Free: the object goes with its last reference.
	void Free() {}
	Ref<TTimer> Clone() const;

	void Delay(int64_t p_delay_ms);
	void Expire();
	bool getExpired() const;
	double GetTimeStamp() const;
	bool HasStarted() const;
	void setExpired(bool p_is_expired);
	double ZeitDiffProzent(bool p_clamp_zero_one = false) const;
	double ZeitDiffProzentInverted(bool p_clamp_zero_one = false) const;
	// Start / Start(NewInterval): restart the timer to zero and unpause it.
	void Start(const Variant &p_new_interval = Variant());
	void StartAndPause();
	void StartWithRest();
	void StartWithFrac();
	int64_t TimesExpired(int64_t p_maximum = -1) const;
	double TimeSinceStart() const;
	double TimeToExpired() const;
	void Pause();
	double Progress() const;
	double ProgressInverted() const;
	void Reset();
	// Weiter: a paused timer runs on, time stays consistent.
	void Weiter();
	int64_t GetInterval() const { return FInterval; }
	void SetInterval(int64_t p_new_interval);
	void SetIntervalAndStart(int64_t p_new_interval);
	bool getPaused() const { return FPaused; }
	// Kept as in the original, which is inverted: Paused := True on a running timer calls Weiter (no-op), Paused :=
	// False on a paused timer calls Pause again.
	void setPaused(bool p_is_expired);
	void SetZeitDiffProzent(double p_wert);
};

// TGameTimer (BaseConflict.Types.Shared.pas:54, implementation :214): a TTimer on the game clock, with its start time
// exposed (StartingTime) so the server can send it to the client. The original reads GameTimeManager (server) or
// Game.ServerTime (client); both are TTimeManager's clock here.
class TGameTimer : public TTimer {
	GDCLASS(TGameTimer, TTimer)

protected:
	static void _bind_methods();

public:
	double GetStartingTime() const { return FLastTime; }
	void SetStartingTime(double p_value) { FLastTime = p_value; }
};

} // namespace godot
