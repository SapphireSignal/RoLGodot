class_name TWelaTargetConstraintBooleanComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintBooleanComponent (BaseConflict.EntityComponents.Shared.Wela.pas:348,
## implementation :3030). A target is possible by combining the eiWelaTargetPossible checks of GroupA and GroupB
## (each optionally negated) with AND (default) or OR.

const boAnd = 0  # EnumBooleanOperator (not exposed to scripts)
const boOr = 1

var FGroupA: Array = []
var FGroupB: Array = []
var FNotA := false
var FNotB := false
var FOperator := boAnd


func IsPossible(Target: RTarget) -> bool:
	var Targets := ATarget.ToRParam(ATarget.Make(Target))
	var OperandA := RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [Targets], FGroupA)).IsValid()
	var OperandB := RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible, [Targets], FGroupB)).IsValid()
	if FNotA:
		OperandA = not OperandA
	if FNotB:
		OperandB = not OperandB
	if FOperator == boOr:
		return OperandA or OperandB
	return OperandA and OperandB


func GroupA(Group: Array) -> TWelaTargetConstraintBooleanComponent:
	FGroupA = DSet.Make(Group)
	return self


func GroupB(Group: Array) -> TWelaTargetConstraintBooleanComponent:
	FGroupB = DSet.Make(Group)
	return self


func OperatorOr() -> TWelaTargetConstraintBooleanComponent:
	FOperator = boOr
	return self


func OperatorAnd() -> TWelaTargetConstraintBooleanComponent:
	FOperator = boAnd
	return self


func NotA() -> TWelaTargetConstraintBooleanComponent:
	FNotA = true
	return self


func NotB() -> TWelaTargetConstraintBooleanComponent:
	FNotB = true
	return self
