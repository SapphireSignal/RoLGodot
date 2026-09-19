class_name TAnimationController
extends RefCounted
## Port of TAnimationController and TAnimation (Engine/Engine.Animation.pas). The frontend of a mesh's animations:
## a stack of playing animations with 500 ms fades, a looping default animation, and its drivers (here the TMesh,
## whose bone driver samples the imported take, see TMesh.UpdateAnimation). Times are TTimeManager timestamps (ms);
## GFXD.FrameCount keeps it to one update per frame, as the original's FPSCounter.FrameCount does.

## EnumAnimationPlayMode
const alSingle = 0
const alLoop = 1
const alSymmetricLoop = 2
## EnumAnimationState
const asPlaying = 0
const asPaused = 1
const asStopped = 2


## TAnimation: one playback of a named animation.
class TAnimation:
	const FADEOUT_LENGTH = 500
	var FPlayMode := 0
	var FName := ""
	var FBlend := false
	var FLength := 0
	var FStartTime := 0
	var FEndTime := 0
	var FEndFadeOut := 0
	var FStartFadeOut := 0

	func _init(Name: String, CurrentTime: int, Length: int, PlayMode: int, Blend: bool) -> void:
		FPlayMode = PlayMode
		FName = Name
		FBlend = Blend
		FLength = maxi(1, Length)
		Reset(CurrentTime)

	func Reset(CurrentTime: int) -> void:
		FStartTime = CurrentTime
		FEndTime = CurrentTime + FLength
		if FPlayMode != TAnimationController.alLoop and FPlayMode != TAnimationController.alSymmetricLoop:
			FEndFadeOut = FEndTime - FADEOUT_LENGTH
			FStartFadeOut = CurrentTime + FADEOUT_LENGTH
		else:
			FEndFadeOut = 0
			FStartFadeOut = CurrentTime + FADEOUT_LENGTH

	## Instruct animation to stop and start fadeout.
	func StartFadeOut(CurrentTime: int) -> void:
		FEndFadeOut = CurrentTime

	## Weight 0..1 by time: fades in over the first 500 ms and out after the fade-out start (blended only).
	func ComputeWeight(CurrentTime: int) -> float:
		if FBlend:
			if CurrentTime < FStartFadeOut and FStartFadeOut > 0:
				return 1.0 - (float(FStartFadeOut - CurrentTime) / FADEOUT_LENGTH)
			elif CurrentTime > FEndFadeOut and FEndFadeOut > 0:
				return 1.0 - (float(CurrentTime - FEndFadeOut) / FADEOUT_LENGTH)
			return 1.0
		return 1.0

	## Position 0..1 of the playback at CurrentTime (Frac: wraps); [key, finished].
	func ComputeTimeKey(CurrentTime: int) -> Array:
		var x := float(CurrentTime - FStartTime) / float(FEndTime - FStartTime)
		var key := x - floorf(x) if x >= 0.0 else x - ceilf(x)  # Delphi Frac keeps the sign
		var finished := (CurrentTime - FEndFadeOut > FADEOUT_LENGTH) and not (FEndFadeOut == 0)
		return [key, finished]


var FStatus := asStopped
var FDefaultAnimation: TAnimation = null
var FAnimationStack: Array[TAnimation] = []
## Drivers: objects with HasAnimation(name), AnimationLength(name), AnimationFrameCount(name), UpdateAnimation(name,
## start, end, weight) and UpdateWithoutAnimation(). The TMesh owning this controller.
var FDrivers: Array = []
var FFrameCounter := 0
var FLastPosition := 0.0
var FTimeStamp := [0, 0]

var DefaultAnimation: String:
	get:
		return FDefaultAnimation.FName if FDefaultAnimation != null else ""
	set(value):
		SetDefaultAnimation(value)
var Status: int:
	get:
		return FStatus
	set(value):
		SetStatus(value)


func AddDriver(Driver) -> void:
	assert(not FDrivers.has(Driver))
	FDrivers.append(Driver)


func RemoveDriver(Driver) -> void:
	FDrivers.erase(Driver)


## Port: drop the drivers (the mesh) so no reference cycle keeps them alive.
func Clear() -> void:
	FDrivers.clear()
	FAnimationStack.clear()
	FDefaultAnimation = null


func HasAnimation(Animation: String) -> bool:
	for Driver in FDrivers:
		if Driver.HasAnimation(Animation):
			return true
	return false


func AssertHasAnimation(Animation: String) -> bool:
	if not HasAnimation(Animation):
		push_error("TAnimationController: Animation %s was not found." % Animation)
		return false
	return true


func GetAnimationLength(Name: String) -> int:
	if not AssertHasAnimation(Name):
		return 0
	for Driver in FDrivers:
		if Driver.HasAnimation(Name):
			return Driver.AnimationLength(Name)
	return 0


## GetAnimationInfoExtendedForItem: {Name, Length, FrameCount} or null.
func GetAnimationInfoExtendedForItem(Animation: String):
	for Driver in FDrivers:
		if Driver.HasAnimation(Animation):
			return {"Name": Animation, "Length": Driver.AnimationLength(Animation),
				"FrameCount": Driver.AnimationFrameCount(Animation)}
	return null


## [start, end] of the current frame's time span; paused controllers keep the last one.
func GetCurrentTime() -> Array:
	if Status == asPaused:
		FFrameCounter = GFXD.GetFrameCount()
	else:
		# prevent get different timekey per frame if UpdateAnimations is called more then once per frame
		if GFXD.GetFrameCount() != FFrameCounter:
			# new timeframe starts 1 ms after last timeframe
			FTimeStamp = [FTimeStamp[1] + 1, TTimeManager.GetTimeStamp()]
			FFrameCounter = GFXD.GetFrameCount()
	return FTimeStamp


func GetPosition() -> float:
	return FLastPosition


## Updates all drivers once per frame: the stack from the top down takes the weight it needs, the default
## animation gets the rest.
func UpdateAnimations() -> void:
	if FFrameCounter == GFXD.GetFrameCount():
		return
	if Status == asPlaying or Status == asPaused:
		var weightRemaining := 1.0
		for i in range(FAnimationStack.size() - 1, -1, -1):
			var time := GetCurrentTime()
			var start_key: Array = FAnimationStack[i].ComputeTimeKey(time[0])
			var end_key: Array = FAnimationStack[i].ComputeTimeKey(time[1])
			var finished: bool = end_key[1]
			if i == 0:
				FLastPosition = end_key[0]
			if not finished and weightRemaining > 0:
				var Weight := FAnimationStack[i].ComputeWeight(GetCurrentTime()[1])
				if Weight > weightRemaining:
					Weight = weightRemaining
				# no other animation exists, can't fade to another animation
				if FAnimationStack.size() == 1 and FDefaultAnimation == null:
					Weight = weightRemaining
				for Driver in FDrivers:
					Driver.UpdateAnimation(FAnimationStack[i].FName, start_key[0], end_key[0], Weight)
				weightRemaining -= Weight
			else:
				FAnimationStack.remove_at(i)
				if FDefaultAnimation != null and FAnimationStack.size() <= 0:
					FDefaultAnimation.Reset(GetCurrentTime()[1])
		if FAnimationStack.is_empty() and FDefaultAnimation == null:
			Status = asStopped
			for Driver in FDrivers:
				Driver.UpdateWithoutAnimation()
			return
		if weightRemaining > 0.01 and FDefaultAnimation != null:
			for Driver in FDrivers:
				var time := GetCurrentTime()
				Driver.UpdateAnimation(FDefaultAnimation.FName, FDefaultAnimation.ComputeTimeKey(time[0])[0],
					FDefaultAnimation.ComputeTimeKey(time[1])[0], weightRemaining)
	else:
		for Driver in FDrivers:
			Driver.UpdateWithoutAnimation()


func Pause() -> void:
	if Status == asPlaying:
		Status = asPaused


func Resume() -> void:
	if Status == asPaused:
		Status = asPlaying


## Plays an animation now; without Blend the running ones are dropped, else the last one fades out.
func Play(Animation: String, PlayMode: int = alSingle, Length: int = 0, Blend: bool = true, TimeOffset: int = 0) -> void:
	if not AssertHasAnimation(Animation):
		return
	if not Blend:
		FAnimationStack.clear()
	if not FAnimationStack.is_empty():
		FAnimationStack.back().StartFadeOut(GetCurrentTime()[1] - TimeOffset)
	var playtime := GetAnimationLength(Animation) if Length <= 0 else Length
	FAnimationStack.append(TAnimation.new(Animation, GetCurrentTime()[1] - TimeOffset, playtime, PlayMode, Blend))
	Status = asPlaying


func SetDefaultAnimation(Value: String) -> void:
	if not AssertHasAnimation(Value):
		return
	FDefaultAnimation = TAnimation.new(Value, GetCurrentTime()[1], GetAnimationLength(Value), alLoop, true)
	if Status == asStopped:
		Status = asPlaying


func SetStatus(Value: int) -> void:
	if FStatus == Value:
		return
	match Value:
		asPlaying:
			# if there is no animation to play, go immediately to stop
			FStatus = asPlaying if (not FAnimationStack.is_empty() or FDefaultAnimation != null) else asStopped
		asPaused:
			if FStatus != asStopped:
				FStatus = asPaused
		asStopped:
			FAnimationStack.clear()
			FStatus = asStopped


func Stop(_NoDefaultAnimation := false) -> void:
	Status = asStopped
