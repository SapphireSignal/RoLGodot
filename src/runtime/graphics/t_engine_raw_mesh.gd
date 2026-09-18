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
## The bone, skin and animation chunks that follow are not read (the vegetation, the only user so far, ignores them).

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
## ColorData: one RVector4 per vertex (x, y, z, w).
var Colors: Array[Vector4] = []
var Indices := PackedInt32Array()


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
	for i in count:
		var v := pos + i * VERTEX_RECORD_SIZE
		Positions[i] = _vector3(data, v)
		var t := v + 12 * MAX_MORPH_TARGET_COUNT
		TextureCoordinates[i] = Vector2(data.decode_float(t), data.decode_float(t + 4))
		Normals[i] = _vector3(data, t + 8)
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
	return Indices.size() == index_count
