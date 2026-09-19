#pragma once

// TSkinnedMeshAnimationDriver (Engine/Engine.Mesh.pas:162, implementation :2210) with its skeleton
// (TMeshAnimatedGeometry.TBone :67, TSkin :119): the bone animations of one mesh. Per animation the channels of existing
// bones with keyframes, their times normalized by the animation's length (TSkinnedMeshAnimationData.Create :2375); every
// frame the weighted animations of each bone are collected (TBone.AddBoneAnimation :2053), blended and passed down the
// hierarchy (PassAnimationToHierarchy :2156), and the skin matrices go to the shader (SetShaderSettings :2347).
// The skeleton and the animation data are parsed once per geometry and shared by its meshes (GetCopy :2255); a copy
// has its own animations list (CreateNewAnimation adds slices) and its own pose.

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/templates/hash_map.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector4.hpp>

#include <cstdint>
#include <memory>
#include <vector>

namespace godot {

class TSkinnedMeshAnimationDriver : public RefCounted {
	GDCLASS(TSkinnedMeshAnimationDriver, RefCounted)

public:
	// TMeshAnimatedGeometry.TBone.MAX_ANIMATIONS_PER_FRAME
	static constexpr int MAX_ANIMATIONS_PER_FRAME = 10;
	// HW_MAX_BONES: the shader's bone matrix count
	static constexpr int HW_MAX_BONES = 66;

	// the bone hierarchy flattened depth first (the file's order) and the skin links
	struct RSkeleton {
		std::vector<Transform3D> OriginalMatrix;
		std::vector<std::vector<int>> ChildBones;
		// lower-case name -> bone (GetBoneByName; a later duplicate wins, AddOrSetValue)
		HashMap<String, int> BoneLookup;
		// per skin link: its bone and BoneSpaceOffsetMatrix
		std::vector<int> SkinBones;
		std::vector<Transform3D> SkinOffsets;
	};

	// RSkinnedMeshSubAnimationData: one bone's keyframes
	struct RSubAnimation {
		int Bone = 0;
		std::vector<float> PointInTime;
		std::vector<Vector3> Translation;
		std::vector<Vector3> Scale;
		std::vector<Vector4> Rotation;
	};

	// TSkinnedMeshAnimationData
	struct RAnimationData {
		String Name;
		int64_t Length = 0;
		int64_t FrameCount = 0;
		std::vector<RSubAnimation> Sub;
	};

private:
	struct RBoneAnimation {
		Vector3 Translation;
		Vector3 Scale;
		Vector4 Rotation;
		double Weight = 0.0;
	};

	std::shared_ptr<const RSkeleton> FSkeleton;
	HashMap<String, std::shared_ptr<const RAnimationData>> FAnimationData;
	// the frame's collected animations per bone, and the result of the last pass (CombinedMatrix, unset until passed)
	std::vector<RBoneAnimation> FBoneAnimations;
	std::vector<int> FBoneAnimationsCount;
	std::vector<Transform3D> FCombinedMatrix;
	std::vector<bool> FCombinedSet;
	int64_t FLastFrameKey = -1;

	void ClearAnimatedMatricesIfOld();
	void AddBoneAnimation(int p_bone, const Vector3 &p_translation, const Vector3 &p_scale, const Vector4 &p_rotation, double p_weight);
	void PassAnimationToHierarchy(int p_bone, const Transform3D &p_parent);
	void UpdateSub(const RSubAnimation &p_sub, double p_timekey, double p_weight);
	void ResetPose();

protected:
	static void _bind_methods();

public:
	// constructor Create(TargetGeometry, AnimationData): the raw mesh's bones ({Name, Matrix, ChildCount}, depth
	// first), skin links ({TargetBoneName, OffsetMatrix}) and bone animations ({Name, Channels: [{TargetBone, Times
	// (ms), Translations, Scales, Rotations}]}). Referenced bones that do not exist are reported and bound to the root.
	Ref<TSkinnedMeshAnimationDriver> Create(const Array &p_bone_data, const Array &p_skin_data, const Array &p_animation_data);
	// GetCopy: a driver of its own over the same skeleton and animation data.
	Ref<TSkinnedMeshAnimationDriver> GetCopy() const;

	bool HasSkin() const { return FSkeleton && !FSkeleton->SkinBones.empty(); }
	int64_t BoneCount() const { return FSkeleton ? int64_t(FSkeleton->OriginalMatrix.size()) : 0; }
	int64_t SkinLinkCount() const { return FSkeleton ? int64_t(FSkeleton->SkinBones.size()) : 0; }
	// GetBoneByName: the bone of a name (any case), -1 if there is none.
	int64_t BoneIndex(const String &p_name) const;
	// CombinedMatrix of a bone, its OriginalMatrix if it was never passed down.
	Transform3D BoneMatrix(int64_t p_bone) const;
	// BoneTransforms[link] = CombinedMatrix * BoneSpaceOffsetMatrix (a bone never passed down has a zero matrix).
	Transform3D SkinMatrix(int64_t p_link) const;

	bool HasAnimation(const String &p_name) const { return FAnimationData.has(p_name); }
	int64_t AnimationFrameCount(const String &p_name) const;
	int64_t AnimationLength(const String &p_name) const;
	PackedStringArray AnimationNames() const;

	// TAnimationDriver.UpdateAnimation -> TSkinnedMeshAnimationData.UpdateAnimation (only the end of the time frame
	// matters), then the hierarchy is passed down.
	void UpdateAnimation(const String &p_animation, double p_start_key, double p_end_key, double p_weight);
	void UpdateWithoutAnimation();
	// TAnimationDriver.CreateNewAnimation + TSkinnedMeshAnimationData.ExtractPart (:2432)
	void CreateNewAnimation(const String &p_new_animation_name, const String &p_source_animation, int64_t p_start_frame, int64_t p_end_frame);
	// SetShaderSettings: the skin matrices as the shader's bone_transforms on every material.
	void SetShaderSettings(const Array &p_materials);

	// RVector4Helper.QuaternionToMatrix4x3 (the rotation of an unnormalized x y z w quaternion).
	static Basis QuaternionToBasis(const Vector4 &p_q);
	// RVector4.SLerp (its sin(Dot) for sin(om) cancels in the final normalization).
	static Vector4 QuaternionSlerp(const Vector4 &p_a, const Vector4 &p_b, double p_s);
};

} // namespace godot
