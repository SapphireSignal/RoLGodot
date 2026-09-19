class_name TEngineRawMesh
extends RefCounted
## Engine.Core.Mesh.pas TEngineRawMesh: the engine's own raw mesh format (.msh, "%KMF" V.01), which release builds
## load instead of the FBX (LOAD_RAW_MESH). Packed records:
##   RPreHeader  string[4] FileIdentifier, string[4] Protector, string[4] Version (5 bytes each), UInt32 HeaderLength
##   RHeader     UInt32 MorphTargetCount, RAABB BoundingBox (Min, Max), RSphere BoundingSphere (Center, Radius),
##               string[32] OriginalFileHash
##   vertices    chunk header (string[4] protector, UInt32 VertexSize, UInt32 VerticesCount), then VerticesCount
##               full RVertexMorphPositionNormalSNormalTextureTangentBinormalBoneIndicesWeight records (184 bytes:
##               Position[0..7], TextureCoordinate, Normal, Tangent, Binormal, BoneWeights, BoneIndices,
##               SmoothedNormal), then VerticesCount RVector4 colors
##   indices     chunk header (protector, UInt32 IndicesCount), then UInt32 indices
##   bones, skin, animations: see _read_skin_and_animations.

const HEADER_PROTECTOR := [0x6A, 0xB5, 0x3C, 0x6A]
const CHUNK_PROTECTOR := [0x4F, 0xE0, 0x5A, 0x94]
const MAX_MORPH_TARGET_COUNT := 8
const VERTEX_RECORD_SIZE := 184

var MorphTargetCount := 0
var BoundingBox := AABB()
var BoundingSphereCenter := Vector3.ZERO
var BoundingSphereRadius := 0.0
## Position[0] of each vertex (game space).
var Positions := PackedVector3Array()
var TextureCoordinates := PackedVector2Array()
var Normals := PackedVector3Array()
## SmoothedNormal of each vertex (the shader's SMOOTHED_NORMAL, used by mesh effects).
var SmoothedNormals := PackedVector3Array()
## ColorData: one RVector4 per vertex (x, y, z, w).
var Colors: Array[Vector4] = []
var Indices := PackedInt32Array()
## Position[1 .. MorphTargetCount - 1] of each vertex: the morph targets' offsets (the shader adds them weighted).
var MorphPositions: Array[PackedVector3Array] = []
## Four per vertex (only for meshes with a skin): BoneWeights and BoneIndices (stored as singles).
var BoneWeights := PackedFloat32Array()
var BoneIndices := PackedInt32Array()
## REngineRawMeshBone: {Name, Matrix (Transform3D), ChildCount}, the hierarchy depth first from the root.
var BoneData: Array = []
## REngineRawSkinBoneLink: {TargetBoneName, OffsetMatrix}; a vertex's BoneIndices index this list.
var SkinData: Array = []
## TMeshAssetAnimationBone: {Name, Channels: [{TargetBone, Times (ms), Translations, Scales, Rotations (x y z w)}]}
var BoneAnimationData: Array = []
## TMeshAssetAnimationMorph: {Name, Channels: [{MorphTarget, Times (ms), Weights}]}
var MorphAnimationData: Array = []
var MorphtargetMapping: Array[String] = []


## Returns null (and logs) when the file is missing or not a V.01 raw mesh.
static func CreateFromFile(path: String) -> TEngineRawMesh:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		push_error("TEngineRawMesh: cannot read %s" % path)
		return null
	var mesh := TEngineRawMesh.new()
	if not mesh._read(data):
		push_error("TEngineRawMesh: %s is not a V.01 raw mesh" % path)
		return null
	return mesh


static func _short_string(data: PackedByteArray, pos: int) -> String:
	return data.slice(pos + 1, pos + 1 + data[pos]).get_string_from_ascii()


static func _protector_at(data: PackedByteArray, pos: int, expected: Array) -> bool:
	return data[pos] == 4 and data.slice(pos + 1, pos + 5) == PackedByteArray(expected)


func _vector3(data: PackedByteArray, pos: int) -> Vector3:
	return Vector3(data.decode_float(pos), data.decode_float(pos + 4), data.decode_float(pos + 8))


func _read(data: PackedByteArray) -> bool:
	if _short_string(data, 0) != "%KMF" or not _protector_at(data, 5, HEADER_PROTECTOR) or _short_string(data, 10) != "V.01":
		return false
	var header_length := data.decode_u32(15)
	var pos := 19
	MorphTargetCount = data.decode_u32(pos)
	var box_min := _vector3(data, pos + 4)
	BoundingBox = AABB(box_min, _vector3(data, pos + 16) - box_min)
	BoundingSphereCenter = _vector3(data, pos + 28)
	BoundingSphereRadius = data.decode_float(pos + 40)
	pos += header_length
	if not _protector_at(data, pos, CHUNK_PROTECTOR):
		return false
	var count := data.decode_u32(pos + 9)
	pos += 13
	Positions.resize(count)
	TextureCoordinates.resize(count)
	Normals.resize(count)
	SmoothedNormals.resize(count)
	for i in count:
		var v := pos + i * VERTEX_RECORD_SIZE
		Positions[i] = _vector3(data, v)
		var t := v + 12 * MAX_MORPH_TARGET_COUNT
		TextureCoordinates[i] = Vector2(data.decode_float(t), data.decode_float(t + 4))
		Normals[i] = _vector3(data, t + 8)
		# after Normal, Tangent, Binormal, BoneWeights, BoneIndices
		SmoothedNormals[i] = _vector3(data, t + 76)
	pos += count * VERTEX_RECORD_SIZE
	Colors.resize(count)
	for i in count:
		var c := pos + i * 16
		Colors[i] = Vector4(data.decode_float(c), data.decode_float(c + 4), data.decode_float(c + 8), data.decode_float(c + 12))
	pos += count * 16
	if not _protector_at(data, pos, CHUNK_PROTECTOR):
		return false
	var index_count := data.decode_u32(pos + 5)
	pos += 9
	Indices = data.slice(pos, pos + index_count * 4).to_int32_array()
	if Indices.size() != index_count:
		return false
	pos += index_count * 4
	if pos >= data.size():
		return true  # port: files cut after the indices (none in the game) keep the static part
	return _read_skin_and_animations(data, pos)


## The morph positions, bone weights and indices of every vertex (only for meshes that use them).
func _read_vertex_extras(data: PackedByteArray, vertices_pos: int) -> void:
	var count := Positions.size()
	for k in range(1, MorphTargetCount):
		var morph := PackedVector3Array()
		morph.resize(count)
		for i in count:
			morph[i] = _vector3(data, vertices_pos + i * VERTEX_RECORD_SIZE + 12 * k)
		MorphPositions.append(morph)
	if SkinData.is_empty():
		return
	BoneWeights.resize(count * 4)
	BoneIndices.resize(count * 4)
	for i in count:
		# after Position[0..7], TextureCoordinate, Normal, Tangent, Binormal
		var w := vertices_pos + i * VERTEX_RECORD_SIZE + 12 * MAX_MORPH_TARGET_COUNT + 8 + 36
		for j in 4:
			BoneWeights[i * 4 + j] = data.decode_float(w + j * 4)
			BoneIndices[i * 4 + j] = int(data.decode_float(w + 16 + j * 4))


## Bone, skin and animation chunks: REngineRawMeshBone (string[128], RMatrix4x3, Int32 ChildCount: 181 bytes, the
## hierarchy depth first), REngineRawSkinBoneLink (string[128], RMatrix4x3: 177 bytes), then the animations
## (TMeshAssetAnimationBone / Morph .CreateFromStream: ShortString name, Int32 channel count, per channel Int32 key
## count, the keys (RKeyFrameBone: Int32 Time, Translation, Scale, RQuaternion x y z w = 44 bytes; RKeyFrameMorph:
## Int32 Time, Single Weight), ShortString target) and the morph target mapping (Int32 count, ShortStrings).
func _read_skin_and_animations(data: PackedByteArray, pos: int) -> bool:
	var vertices_pos := 19 + data.decode_u32(15) + 13
	if not _protector_at(data, pos, CHUNK_PROTECTOR):
		return false
	var bone_count := data.decode_u32(pos + 5)
	pos += 9
	for i in bone_count:
		BoneData.append({"Name": _short_string(data, pos), "Matrix": _matrix4x3(data, pos + 129),
			"ChildCount": data.decode_s32(pos + 177)})
		pos += 181
	if not _protector_at(data, pos, CHUNK_PROTECTOR):
		return false
	var skin_count := data.decode_u32(pos + 5)
	pos += 9
	for i in skin_count:
		SkinData.append({"TargetBoneName": _short_string(data, pos), "OffsetMatrix": _matrix4x3(data, pos + 129)})
		pos += 177
	if not _protector_at(data, pos, CHUNK_PROTECTOR):
		return false
	var bone_animations := data.decode_u32(pos + 5)
	var morph_animations := data.decode_u32(pos + 9)
	pos += 13
	for a in bone_animations:
		var animation := {"Name": _short_string(data, pos), "Channels": []}
		pos += 256
		var channels := data.decode_s32(pos)
		pos += 4
		for c in channels:
			var keys := data.decode_s32(pos)
			pos += 4
			var channel := {"Times": PackedInt32Array(), "Translations": PackedVector3Array(), "Scales": PackedVector3Array(),
				"Rotations": PackedVector4Array()}
			for k in keys:
				var p := pos + k * 44
				channel.Times.append(data.decode_s32(p))
				channel.Translations.append(_vector3(data, p + 4))
				channel.Scales.append(_vector3(data, p + 16))
				channel.Rotations.append(Vector4(data.decode_float(p + 28), data.decode_float(p + 32), data.decode_float(p + 36),
					data.decode_float(p + 40)))
			pos += keys * 44
			channel["TargetBone"] = _short_string(data, pos)
			pos += 256
			animation.Channels.append(channel)
		BoneAnimationData.append(animation)
	for a in morph_animations:
		var animation := {"Name": _short_string(data, pos), "Channels": []}
		pos += 256
		var channels := data.decode_s32(pos)
		pos += 4
		for c in channels:
			var keys := data.decode_s32(pos)
			pos += 4
			var channel := {"Times": PackedInt32Array(), "Weights": PackedFloat32Array()}
			for k in keys:
				channel.Times.append(data.decode_s32(pos + k * 8))
				channel.Weights.append(data.decode_float(pos + k * 8 + 4))
			pos += keys * 8
			channel["MorphTarget"] = _short_string(data, pos)
			pos += 256
			animation.Channels.append(channel)
		MorphAnimationData.append(animation)
	var mapping := data.decode_s32(pos)
	pos += 4
	for i in mapping:
		MorphtargetMapping.append(_short_string(data, pos))
		pos += 256
	_read_vertex_extras(data, vertices_pos)
	return pos == data.size()


## RMatrix4x3 in memory: _11 _12 _13 _41, _21 _22 _23 _42, _31 _32 _33 _43; Column[i] = (_i1, _i2, _i3), the
## translation (_41, _42, _43). As a Transform3D acting like M * v (see RMatrix).
func _matrix4x3(data: PackedByteArray, pos: int) -> Transform3D:
	var f := data.slice(pos, pos + 48).to_float32_array()
	return Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[4], f[5], f[6]), Vector3(f[8], f[9], f[10])),
		Vector3(f[3], f[7], f[11]))
