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


## The code, not the doc comment ("3.6 => 2.6"): StartWithRest keeps Min(0, trunc(p) - 1) + frac(p) intervals,
## so 3.6 -> 0.6 like StartWithFrac, and 0.5 -> -0.5 (the timer starts in the future).
func test_start_with_rest_and_frac() -> void:
	TTimeManager.SetFakeTime(0.0)
	var t := TGameTimer.new().CreateAndStart(100)
	TTimeManager.SetFakeTime(360.0)
	t.StartWithRest()
	check_eq(t.TimeSinceStart(), 60.0, "3.6 -> 0.6")
	TTimeManager.SetFakeTime(350.0)
	t.StartWithRest()
	check_eq(t.StartingTime, 400.0, "0.5 -> -0.5")
	check(t.HasStarted(), "HasStarted: FLastTime >= now")
	check_eq(t.TimeSinceStart(), 0.0, "clamped to 0")
	TTimeManager.SetFakeTime(690.0)
	t.StartWithFrac()
	check_eq(t.TimeSinceStart(), 90.0, "2.9 -> 0.9")
