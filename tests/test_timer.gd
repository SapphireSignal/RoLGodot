extends "res://tests/test_case.gd"
## TTimer (Engine/Engine.Helferlein.Windows.pas:2013) on a frozen TTimeManager clock.


func after_each() -> void:
	TTimeManager.SetFakeTime(null)


func test_create_is_expired_create_and_start_is_not() -> void:
	TTimeManager.SetFakeTime(10000.0)
	check(TTimer.new().Create(500).Expired, "Create(Interval): FLastTime 0, expired")
	var t := TTimer.new().CreateAndStart(500)
	check(not t.Expired, "just started")
	TTimeManager.SetFakeTime(10499.0)
	check(not t.Expired, "499 ms")
	TTimeManager.SetFakeTime(10500.0)
	check(t.Expired, "500 ms: >= Interval")
	check_eq(t.TimesExpired(), 1, "TimesExpired")
	check_eq(t.Progress(), 1.0, "Progress clamped")


func test_interval_at_least_one() -> void:
	check_eq(TTimer.new().Create(0).Interval, 1, "Max(1, 0)")
	check_eq(TTimer.new().Create(-5).Interval, 1, "Max(1, -5)")
	check_eq(TTimer.new().Create().Interval, 1, "Create: 1")


func test_pause_and_weiter() -> void:
	TTimeManager.SetFakeTime(0.0)
	var t := TTimer.new().CreateAndStart(100)
	TTimeManager.SetFakeTime(40.0)
	t.Pause()
	TTimeManager.SetFakeTime(1000.0)
	check_eq(t.TimeSinceStart(), 40.0, "paused at 40")
	check(not t.Expired, "paused, not expired")
	t.Weiter()
	check_eq(t.TimeSinceStart(), 40.0, "resumes at 40")
	TTimeManager.SetFakeTime(1060.0)
	check(t.Expired, "40 + 60")


func test_expire_and_set_interval_and_start() -> void:
	TTimeManager.SetFakeTime(0.0)
	var t := TTimer.new().CreateAndStart(100)
	t.Expire()
	check(t.Expired, "Expire")
	t.Expired = false
	check(not t.Expired, "Expired := False restarts")
	TTimeManager.SetFakeTime(50.0)
	t.SetIntervalAndStart(30)
	check_eq(t.Interval, 30, "new interval")
	TTimeManager.SetFakeTime(80.0)
	check(t.Expired, "restarted at 50")
	check_eq(t.ZeitDiffProzent(), 1.0, "30 / 30")


## As the original documents it (its code had a bug): StartWithRest takes off at most one interval (3.6 -> 2.6,
## 0.5 -> 0), StartWithFrac all whole ones (2.9 -> 0.9).
func test_start_with_rest_and_frac() -> void:
	TTimeManager.SetFakeTime(0.0)
	var t := TGameTimer.new().CreateAndStart(100)
	TTimeManager.SetFakeTime(360.0)
	t.StartWithRest()
	check_eq(t.TimeSinceStart(), 260.0, "3.6 -> 2.6")
	TTimeManager.SetFakeTime(410.0)
	t.StartWithRest()
	check_eq(t.TimeSinceStart(), 210.0, "3.1 -> 2.1")
	TTimeManager.SetFakeTime(250.0)
	t.StartWithRest()
	check_eq([t.StartingTime, t.TimeSinceStart()], [250.0, 0.0], "0.5 -> 0")
	TTimeManager.SetFakeTime(540.0)
	t.StartWithFrac()
	check_eq(t.TimeSinceStart(), 90.0, "2.9 -> 0.9")


## Paused := True pauses, Paused := False runs on (the original's setter was inverted).
func test_paused_property() -> void:
	TTimeManager.SetFakeTime(0.0)
	var t := TTimer.new().CreateAndStart(100)
	TTimeManager.SetFakeTime(30.0)
	t.Paused = true
	check(t.Paused, "paused")
	TTimeManager.SetFakeTime(80.0)
	check_eq(t.TimeSinceStart(), 30.0, "frozen while paused")
	t.Paused = false
	check(not t.Paused, "running")
	TTimeManager.SetFakeTime(100.0)
	check_eq(t.TimeSinceStart(), 50.0, "runs on from 30")
