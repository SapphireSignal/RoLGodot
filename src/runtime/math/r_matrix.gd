class_name RMatrix
extends RefCounted
## Engine.Math.pas RMatrix helpers on game-space Transform3D values. An RMatrix acts on column vectors (M * v) with
## Column[0..2] = Left, Up, Front and Column[3] = Translation; the port keeps it as a Transform3D in game space:
## basis.x = Left, basis.y = Up, basis.z = Front, origin = Translation, and RMatrix * RMatrix = Transform3D *
## Transform3D. (Game space is the original's left-handed world; TMesh.ToGodot maps it to Godot.)

const IDENTITY := Transform3D.IDENTITY


## RMatrix.CreateTranslation
static func CreateTranslation(Position: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Position)


## RMatrix.CreateBase(Left, Up, Front)
static func CreateBase(Left: Vector3, Up: Vector3, Front: Vector3) -> Transform3D:
	return Transform3D(Basis(Left, Up, Front), Vector3.ZERO)


## RMatrix.CreateSaveBase(Front, Up): normalized, Up made orthogonal to Front and the derived Left.
static func CreateSaveBase(Front: Vector3, Up: Vector3) -> Transform3D:
	var f := Front.normalized()
	var u := Up.normalized()
	var l := -f.cross(u).normalized()
	u = f.cross(l).normalized()
	return CreateBase(l, u, f)


## RMatrix.CreateRotationPitchYawRoll(Pitch = x, Yaw = y, Roll = z) = RotationY(Yaw) * RotationX(Pitch) *
## RotationZ(Roll). The original's matrices (column X, row Y in _XY): RotationY rows [[c, 0, -s], [0, 1, 0],
## [s, 0, c]], RotationX [[1, 0, 0], [0, c, s], [0, -s, c]], RotationZ [[c, s, 0], [-s, c, 0], [0, 0, 1]].
static func RotationPitchYawRoll(PitchYawRoll: Vector3) -> Basis:
	var y := PitchYawRoll.y
	var x := PitchYawRoll.x
	var z := PitchYawRoll.z
	return _rows([[cos(y), 0, -sin(y)], [0, 1, 0], [sin(y), 0, cos(y)]]) \
		* _rows([[1, 0, 0], [0, cos(x), sin(x)], [0, -sin(x), cos(x)]]) \
		* _rows([[cos(z), sin(z), 0], [-sin(z), cos(z), 0], [0, 0, 1]])


static func CreateRotationPitchYawRoll(PitchYawRoll: Vector3) -> Transform3D:
	return Transform3D(RotationPitchYawRoll(PitchYawRoll), Vector3.ZERO)


static func _rows(r: Array) -> Basis:
	return Basis(Vector3(r[0][0], r[1][0], r[2][0]), Vector3(r[0][1], r[1][1], r[2][1]), Vector3(r[0][2], r[1][2], r[2][2]))


## RVector3.RotatePitchYawRoll = CreateRotationPitchYawRoll * v
static func RotatePitchYawRoll(v: Vector3, PitchYawRoll: Vector3) -> Vector3:
	return RotationPitchYawRoll(PitchYawRoll) * v


## RMatrix.Column[Index] (0..2 the base vectors, 3 the translation).
static func GetColumn(m: Transform3D, Index: int) -> Vector3:
	return m.origin if Index == 3 else m.basis[Index]


static func SetColumn(m: Transform3D, Index: int, Value: Vector3) -> Transform3D:
	if Index == 3:
		m.origin = Value
	else:
		m.basis[Index] = Value
	return m


## RMatrix.SwapXY / SwapXZ / SwapYZ: swap two base columns.
static func SwapColumns(m: Transform3D, a: int, b: int) -> Transform3D:
	var temp: Vector3 = m.basis[a]
	m.basis[a] = m.basis[b]
	m.basis[b] = temp
	return m
