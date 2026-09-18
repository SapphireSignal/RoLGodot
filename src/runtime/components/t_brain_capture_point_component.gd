class_name TBrainCapturePointComponent
extends TBrainComponent
## Port of TBrainCapturePointComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.Special.pas:31,
## implementation :74), server only. Handles capture points on the map (the LaneNode): each think, if its group is
## ready, it collects the teams of the units its targeting finds (eiWelaUpdateTargets). One team that is not blocked
## (eiIsReady of group TeamID + 10 is false) captures the point; several teams stop the capture. Then, while a team
## holds it, it fires (eiFire at its owner) the positive group of the capturing team (if not blocked) and the
## negative group of every other team; if nothing fired and an idle group is set, it fires that.
## Port note: the team groups fire in SetTeamGroup order (the original: TDictionary hash order; the one script uses
## teams 1 and 2).

var FFireInactive := false
var FCapturingTeamID := -1
var FIdleGroup: Array = []
var FTeamGroups := {}  # TeamID -> [PositiveGroup, NegativeGroup]


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func CreateGrouped(Entity = null, Group = []) -> TEntityComponent:
	super(Entity, Group)
	FCapturingTeamID = -1
	FTeamGroups = {}
	return self


func Destroy() -> void:
	FTeamGroups = {}
	super()


func IsBlockedForTeam(TeamID: int) -> bool:
	return not RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], [TeamID + 10]))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func SetIdleGroup(IdleGroup = []) -> TBrainCapturePointComponent:
	FFireInactive = true
	FIdleGroup = DSet.Make(IdleGroup)
	return self


func SetTeamGroup(TeamID: int, PositiveGroup = [], NegativeGroup = []) -> TBrainCapturePointComponent:
	if FTeamGroups.has(TeamID):
		push_error("TBrainCapturePointComponent.SetTeamGroup: duplicate team %d" % TeamID)  # TDictionary.Add raises
		return self
	FTeamGroups[TeamID] = [DSet.Make(PositiveGroup), DSet.Make(NegativeGroup)]
	return self


func Think() -> void:
	if not RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		return
	var Game = BrainGame()
	var TargetList: Array = []
	var NearTeams: Array = []
	Eventbus().Trigger(C.eiWelaUpdateTargets, [TargetList], ComponentGroup)
	for Target: RTarget in TargetList:
		if Target.IsEntity():
			var ent = Target.TryGetTargetEntity(Game)
			if ent != null:
				var TeamID: int = ent.TeamID()
				if not NearTeams.has(TeamID):
					NearTeams.append(TeamID)
	# one team primes the captures point if not blocked, more teams stops it completely
	if NearTeams.size() == 1 and not IsBlockedForTeam(NearTeams[0]):
		FCapturingTeamID = NearTeams[0]
	elif NearTeams.size() > 1:
		FCapturingTeamID = -1
	var active := false
	for TeamID: int in FTeamGroups:
		if FCapturingTeamID >= 0:
			if FCapturingTeamID == TeamID:
				if not IsBlockedForTeam(TeamID):
					Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FTeamGroups[TeamID][0])
					active = true
			# negative things if you have no unit near, but another team is there
			else:
				Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FTeamGroups[TeamID][1])
				active = true
	if not active and FFireInactive:
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FIdleGroup)
