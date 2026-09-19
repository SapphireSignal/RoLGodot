#include "graphics/t_skinned_mesh_animation_driver.h"

#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

#include "engine/delphi_math.h"
#include "graphics/gfxd.h"

namespace godot {

namespace {

// TBone.Create(Data): each bone takes its ChildCount children from the rest of the list. Returns the next index.
int LinkBones(TSkinnedMeshAnimationDriver::RSkeleton &r_skeleton, const Array &p_bone_data, int p_index) {
	int next = p_index + 1;
	const int child_count = int(int64_t(Dictionary(p_bone_data[p_index])["ChildCount"]));
	for (int c = 0; c < child_count; c++) {
		if (next >= p_bone_data.size()) {
			break;
		}
		r_skeleton.ChildBones[p_index].push_back(next);
		next = LinkBones(r_skeleton, p_bone_data, next);
	}
	return next;
}

const Transform3D ZERO_MATRIX{ Basis{ Vector3(), Vector3(), Vector3() }, Vector3() };

} // namespace

void TSkinnedMeshAnimationDriver::_bind_methods() {
	ClassDB::bind_method(D_METHOD("Create", "BoneData", "SkinData", "AnimationData"), &TSkinnedMeshAnimationDriver::Create);
	ClassDB::bind_method(D_METHOD("GetCopy"), &TSkinnedMeshAnimationDriver::GetCopy);
	ClassDB::bind_method(D_METHOD("HasSkin"), &TSkinnedMeshAnimationDriver::HasSkin);
	ClassDB::bind_method(D_METHOD("BoneCount"), &TSkinnedMeshAnimationDriver::BoneCount);
	ClassDB::bind_method(D_METHOD("SkinLinkCount"), &TSkinnedMeshAnimationDriver::SkinLinkCount);
	ClassDB::bind_method(D_METHOD("BoneIndex", "Name"), &TSkinnedMeshAnimationDriver::BoneIndex);
	ClassDB::bind_method(D_METHOD("BoneMatrix", "Bone"), &TSkinnedMeshAnimationDriver::BoneMatrix);
	ClassDB::bind_method(D_METHOD("SkinMatrix", "Link"), &TSkinnedMeshAnimationDriver::SkinMatrix);
	ClassDB::bind_method(D_METHOD("HasAnimation", "Name"), &TSkinnedMeshAnimationDriver::HasAnimation);
	ClassDB::bind_method(D_METHOD("AnimationFrameCount", "Name"), &TSkinnedMeshAnimationDriver::AnimationFrameCount);
	ClassDB::bind_method(D_METHOD("AnimationLength", "Name"), &TSkinnedMeshAnimationDriver::AnimationLength);
	ClassDB::bind_method(D_METHOD("AnimationNames"), &TSkinnedMeshAnimationDriver::AnimationNames);
	ClassDB::bind_method(D_METHOD("UpdateAnimation", "Animation", "StartKey", "EndKey", "Weight"), &TSkinnedMeshAnimationDriver::UpdateAnimation);
	ClassDB::bind_method(D_METHOD("UpdateWithoutAnimation"), &TSkinnedMeshAnimationDriver::UpdateWithoutAnimation);
	ClassDB::bind_method(D_METHOD("CreateNewAnimation", "NewAnimationName", "SourceAnimation", "StartFrame", "EndFrame"),
			&TSkinnedMeshAnimationDriver::CreateNewAnimation);
	ClassDB::bind_method(D_METHOD("SetShaderSettings", "Materials"), &TSkinnedMeshAnimationDriver::SetShaderSettings);
	ClassDB::bind_static_method("TSkinnedMeshAnimationDriver", D_METHOD("QuaternionToBasis", "q"), &TSkinnedMeshAnimationDriver::QuaternionToBasis);
	ClassDB::bind_static_method("TSkinnedMeshAnimationDriver", D_METHOD("QuaternionSlerp", "a", "b", "s"), &TSkinnedMeshAnimationDriver::QuaternionSlerp);
}

Ref<TSkinnedMeshAnimationDriver> TSkinnedMeshAnimationDriver::Create(const Array &p_bone_data, const Array &p_skin_data,
		const Array &p_animation_data) {
	auto skeleton = std::make_shared<RSkeleton>();
	for (int64_t i = 0; i < p_bone_data.size(); i++) {
		const Dictionary bone = p_bone_data[i];
		skeleton->OriginalMatrix.push_back(bone["Matrix"]);
		skeleton->ChildBones.emplace_back();
	}
	// every mesh has at least one root bone; loading it loads the children (depth first)
	if (!p_bone_data.is_empty()) {
		LinkBones(*skeleton, p_bone_data, 0);
	}
	for (int64_t i = 0; i < p_bone_data.size(); i++) {
		skeleton->BoneLookup[String(Dictionary(p_bone_data[i])["Name"]).to_lower()] = int(i);
	}
	for (int64_t i = 0; i < p_skin_data.size(); i++) {
		const Dictionary link = p_skin_data[i];
		const String name = String(link["TargetBoneName"]).to_lower();
		int bone = 0;
		if (skeleton->BoneLookup.has(name)) {
			bone = skeleton->BoneLookup[name];
		} else {
			UtilityFunctions::push_error(vformat("TSkinnedMeshAnimationDriver: referenced bone \"%s\" not found", link["TargetBoneName"]));
		}
		skeleton->SkinBones.push_back(bone);
		skeleton->SkinOffsets.push_back(link["OffsetMatrix"]);
	}
	if (skeleton->SkinBones.size() > size_t(HW_MAX_BONES)) {
		UtilityFunctions::push_error(vformat("TSkinnedMeshAnimationDriver: too many bones (%d, max %d)", int64_t(skeleton->SkinBones.size()), HW_MAX_BONES));
	}
	FSkeleton = skeleton;

	// TSkinnedMeshAnimationData.Create: the length is the last keyframe's time of the last channel (a channel without
	// keyframes resets it to 0, as the original's GetAnimationLength does); only channels of existing bones with
	// keyframes are kept, their times normalized to 0..1
	FAnimationData.clear();
	for (int64_t a = 0; a < p_animation_data.size(); a++) {
		const Dictionary animation = p_animation_data[a];
		const Array channels = animation["Channels"];
		int64_t length = 0;
		for (int64_t c = 0; c < channels.size(); c++) {
			const PackedInt32Array times = Dictionary(channels[c])["Times"];
			length = times.size() > 0 ? std::max<int64_t>(times[times.size() - 1], length) : 0;
		}
		auto data = std::make_shared<RAnimationData>();
		data->Name = animation["Name"];
		data->Length = length;
		for (int64_t c = 0; c < channels.size(); c++) {
			const Dictionary channel = channels[c];
			const String bone_name = String(channel["TargetBone"]).to_lower();
			const PackedInt32Array times = channel["Times"];
			if (!skeleton->BoneLookup.has(bone_name) || times.size() == 0) {
				continue;
			}
			RSubAnimation sub;
			sub.Bone = skeleton->BoneLookup[bone_name];
			data->FrameCount = std::max<int64_t>(data->FrameCount, times.size());
			const PackedVector3Array translations = channel["Translations"];
			const PackedVector3Array scales = channel["Scales"];
			const PackedVector4Array rotations = channel["Rotations"];
			for (int64_t k = 0; k < times.size(); k++) {
				// normalize data in range 0..1
				sub.PointInTime.push_back(float(length != 0 ? double(times[k]) / double(length) : 0.0));
				sub.Translation.push_back(translations[k]);
				sub.Scale.push_back(scales[k]);
				sub.Rotation.push_back(rotations[k]);
			}
			data->Sub.push_back(std::move(sub));
		}
		FAnimationData[data->Name] = data;
	}
	ResetPose();
	return Ref<TSkinnedMeshAnimationDriver>(this);
}

Ref<TSkinnedMeshAnimationDriver> TSkinnedMeshAnimationDriver::GetCopy() const {
	Ref<TSkinnedMeshAnimationDriver> result;
	result.instantiate();
	result->FSkeleton = FSkeleton;
	result->FAnimationData = FAnimationData;
	result->ResetPose();
	return result;
}

void TSkinnedMeshAnimationDriver::ResetPose() {
	const size_t count = FSkeleton ? FSkeleton->OriginalMatrix.size() : 0;
	FBoneAnimations.assign(count * MAX_ANIMATIONS_PER_FRAME, RBoneAnimation());
	FBoneAnimationsCount.assign(count, 0);
	FCombinedMatrix.assign(count, Transform3D());
	FCombinedSet.assign(count, false);
	FLastFrameKey = -1;
}

int64_t TSkinnedMeshAnimationDriver::BoneIndex(const String &p_name) const {
	if (!FSkeleton) {
		return -1;
	}
	const String name = p_name.to_lower();
	return FSkeleton->BoneLookup.has(name) ? FSkeleton->BoneLookup[name] : -1;
}

Transform3D TSkinnedMeshAnimationDriver::BoneMatrix(int64_t p_bone) const {
	ERR_FAIL_INDEX_V(p_bone, BoneCount(), Transform3D());
	return FCombinedSet[p_bone] ? FCombinedMatrix[p_bone] : FSkeleton->OriginalMatrix[p_bone];
}

Transform3D TSkinnedMeshAnimationDriver::SkinMatrix(int64_t p_link) const {
	ERR_FAIL_INDEX_V(p_link, SkinLinkCount(), Transform3D());
	const int bone = FSkeleton->SkinBones[p_link];
	if (!FCombinedSet[bone]) {
		return ZERO_MATRIX;
	}
	return FCombinedMatrix[bone] * FSkeleton->SkinOffsets[p_link];
}

int64_t TSkinnedMeshAnimationDriver::AnimationFrameCount(const String &p_name) const {
	return FAnimationData.has(p_name) ? FAnimationData[p_name]->FrameCount : 0;
}

int64_t TSkinnedMeshAnimationDriver::AnimationLength(const String &p_name) const {
	return FAnimationData.has(p_name) ? FAnimationData[p_name]->Length : 0;
}

PackedStringArray TSkinnedMeshAnimationDriver::AnimationNames() const {
	PackedStringArray names;
	for (const KeyValue<String, std::shared_ptr<const RAnimationData>> &entry : FAnimationData) {
		names.push_back(entry.key);
	}
	return names;
}

// ---- TBone ------------------------------------------------------------------------------------------------------------

// new frame? -> all old animated matrices not longer useful
void TSkinnedMeshAnimationDriver::ClearAnimatedMatricesIfOld() {
	if (GFXD::GetFrameCount() != FLastFrameKey) {
		std::fill(FBoneAnimationsCount.begin(), FBoneAnimationsCount.end(), 0);
		FLastFrameKey = GFXD::GetFrameCount();
	}
}

void TSkinnedMeshAnimationDriver::AddBoneAnimation(int p_bone, const Vector3 &p_translation, const Vector3 &p_scale,
		const Vector4 &p_rotation, double p_weight) {
	ClearAnimatedMatricesIfOld();
	int &count = FBoneAnimationsCount[p_bone];
	// if array already full, skip new animations
	if (count < MAX_ANIMATIONS_PER_FRAME - 1) {
		RBoneAnimation &entry = FBoneAnimations[size_t(p_bone) * MAX_ANIMATIONS_PER_FRAME + count];
		entry.Translation = p_translation;
		entry.Scale = p_scale;
		entry.Rotation = p_rotation;
		entry.Weight = p_weight;
		count++;
	}
}

// A bone with animations sums translation and scale by weight and slerps the rotations in order (the weight sum stays
// the first one's, as in the original); a bone without keeps its OriginalMatrix.
void TSkinnedMeshAnimationDriver::PassAnimationToHierarchy(int p_bone, const Transform3D &p_parent) {
	Transform3D animated;
	const int count = FBoneAnimationsCount[p_bone];
	if (count > 0) {
		const RBoneAnimation *list = &FBoneAnimations[size_t(p_bone) * MAX_ANIMATIONS_PER_FRAME];
		Vector3 translation;
		Vector3 scale;
		for (int i = 0; i < count; i++) {
			translation += list[i].Translation * real_t(list[i].Weight);
			scale += list[i].Scale * real_t(list[i].Weight);
		}
		Vector4 rotation = list[0].Rotation;
		const double weight_sum = list[0].Weight;
		for (int i = 1; i < count; i++) {
			rotation = QuaternionSlerp(rotation, list[i].Rotation, list[i].Weight / (list[i].Weight + weight_sum));
		}
		animated = Transform3D(QuaternionToBasis(rotation) * Basis::from_scale(scale), translation);
	} else {
		animated = FSkeleton->OriginalMatrix[p_bone];
	}
	const Transform3D combined = p_parent * animated;
	FCombinedMatrix[p_bone] = combined;
	FCombinedSet[p_bone] = true;
	for (int child : FSkeleton->ChildBones[p_bone]) {
		PassAnimationToHierarchy(child, combined);
	}
}

Basis TSkinnedMeshAnimationDriver::QuaternionToBasis(const Vector4 &p_q) {
	const double qx = p_q.x;
	const double qy = p_q.y;
	const double qz = p_q.z;
	const double qw = p_q.w;
	const double sqw = qw * qw;
	const double sqx = qx * qx;
	const double sqy = qy * qy;
	const double sqz = qz * qz;
	double invs = sqx + sqy + sqz + sqw;
	invs = invs == 0.0 ? 1.0 : 1.0 / invs;
	const double m11 = (sqx - sqy - sqz + sqw) * invs;
	const double m22 = (-sqx + sqy - sqz + sqw) * invs;
	const double m33 = (-sqx - sqy + sqz + sqw) * invs;
	const double m12 = 2.0 * (qx * qy + qz * qw) * invs;
	const double m21 = 2.0 * (qx * qy - qz * qw) * invs;
	const double m13 = 2.0 * (qx * qz - qy * qw) * invs;
	const double m31 = 2.0 * (qx * qz + qy * qw) * invs;
	const double m23 = 2.0 * (qy * qz + qx * qw) * invs;
	const double m32 = 2.0 * (qy * qz - qx * qw) * invs;
	// Column[i] = (_i1, _i2, _i3)
	Basis result;
	result.set_column(0, Vector3(m11, m12, m13));
	result.set_column(1, Vector3(m21, m22, m23));
	result.set_column(2, Vector3(m31, m32, m33));
	return result;
}

Vector4 TSkinnedMeshAnimationDriver::QuaternionSlerp(const Vector4 &p_a, const Vector4 &p_b, double p_s) {
	const Vector4 q1 = p_a.normalized();
	Vector4 q2 = p_b.normalized();
	double dot = q1.dot(q2);
	if (dot < 0) {
		q2 = -q2;
		dot = -dot;
	}
	double scale0 = 1.0 - p_s;
	double scale1 = p_s;
	if ((1.0 - dot) > 0.00001) {
		const double om = std::acos(dot);
		const double sinom = std::sin(dot);
		scale0 = std::sin((1.0 - p_s) * om) / sinom;
		scale1 = std::sin(p_s * om) / sinom;
	}
	return (q1 * real_t(scale0) + q2 * real_t(scale1)).normalized();
}

// ---- animations ---------------------------------------------------------------------------------------------------------

void TSkinnedMeshAnimationDriver::UpdateAnimation(const String &p_animation, double p_start_key, double p_end_key, double p_weight) {
	if (FAnimationData.has(p_animation)) {
		const std::shared_ptr<const RAnimationData> data = FAnimationData[p_animation];
		for (const RSubAnimation &sub : data->Sub) {
			UpdateSub(sub, p_end_key, p_weight);
		}
	}
	UpdateWithoutAnimation();
}

void TSkinnedMeshAnimationDriver::UpdateWithoutAnimation() {
	if (HasSkin()) {
		ClearAnimatedMatricesIfOld();
		if (BoneCount() > 0) {
			PassAnimationToHierarchy(0, Transform3D());
		}
	}
}

// RSkinnedMeshSubAnimationData.UpdateAnimation (:2481): the two keyframes around the time key (guessed, then searched),
// translation and scale lerped, rotation slerped.
void TSkinnedMeshAnimationDriver::UpdateSub(const RSubAnimation &p_sub, double p_timekey, double p_weight) {
	const std::vector<float> &times = p_sub.PointInTime;
	const int count = int(times.size());
	if (count == 0) {
		return;
	}
	int first = 0;
	int sec = count - 1;
	if (count > 2) {
		sec = int((count - 1) * p_timekey);
		first = std::max(sec - 1, 0);
		while (!(times[first] <= p_timekey && p_timekey <= times[sec])) {
			const int direction = p_timekey > times[sec] ? 1 : (p_timekey < times[sec] ? -1 : 0);
			sec = std::clamp(sec + direction, 0, count - 1);
			first = std::clamp(sec - 1, 0, count - 1);
			if (first <= 0 || sec >= count - 1 || direction == 0) {
				break;
			}
		}
	}
	double a = 1.0;
	if (first != sec) {
		a = 1.0 - ((p_timekey - times[first]) / std::abs(double(times[sec]) - double(times[first])));
	}
	a = std::clamp(a, 0.0, 1.0);
	const Vector3 translation = p_sub.Translation[first].lerp(p_sub.Translation[sec], real_t(1.0 - a));
	const Vector3 scale = p_sub.Scale[first].lerp(p_sub.Scale[sec], real_t(1.0 - a));
	const Vector4 rotation = QuaternionSlerp(p_sub.Rotation[first], p_sub.Rotation[sec], 1.0 - a);
	AddBoneAnimation(p_sub.Bone, translation, scale, rotation, p_weight);
}

// Frames StartFrame..EndFrame (both included, clamped to every channel's keyframes) become a new animation; its length
// is the time between the two keyframes of the first channel.
void TSkinnedMeshAnimationDriver::CreateNewAnimation(const String &p_new_animation_name, const String &p_source_animation,
		int64_t p_start_frame, int64_t p_end_frame) {
	if (FAnimationData.has(p_new_animation_name)) {
		UtilityFunctions::push_warning(vformat("TAnimationDriver: Animation \"%s\" already exists!", p_new_animation_name));
		return;
	}
	if (!FAnimationData.has(p_source_animation)) {
		return;
	}
	const std::shared_ptr<const RAnimationData> source = FAnimationData[p_source_animation];
	int64_t start_frame = p_start_frame;
	int64_t end_frame = p_end_frame;
	for (const RSubAnimation &sub : source->Sub) {
		start_frame = std::min<int64_t>(start_frame, int64_t(sub.PointInTime.size()) - 1);
		end_frame = std::min<int64_t>(end_frame, int64_t(sub.PointInTime.size()) - 1);
	}
	auto data = std::make_shared<RAnimationData>();
	data->Name = p_new_animation_name;
	if (!source->Sub.empty()) {
		const RSubAnimation &first = source->Sub[0];
		data->Length = delphi::Round(double(source->Length) * (double(first.PointInTime[end_frame]) - double(first.PointInTime[start_frame])));
		for (const RSubAnimation &sub : source->Sub) {
			RSubAnimation slice;
			slice.Bone = sub.Bone;
			for (int64_t frame = start_frame; frame <= end_frame; frame++) {
				slice.PointInTime.push_back(end_frame != start_frame ? float(double(frame - start_frame) / double(end_frame - start_frame)) : NAN);
				slice.Translation.push_back(sub.Translation[frame]);
				slice.Scale.push_back(sub.Scale[frame]);
				slice.Rotation.push_back(sub.Rotation[frame]);
			}
			data->Sub.push_back(std::move(slice));
		}
	}
	FAnimationData[p_new_animation_name] = data;
}

void TSkinnedMeshAnimationDriver::SetShaderSettings(const Array &p_materials) {
	if (!HasSkin()) {
		return;
	}
	Array matrices;
	matrices.resize(HW_MAX_BONES);
	const int64_t links = SkinLinkCount();
	for (int64_t i = 0; i < HW_MAX_BONES; i++) {
		matrices[i] = Projection(i < links ? SkinMatrix(i) : Transform3D());
	}
	const StringName bone_transforms("bone_transforms");
	for (int64_t i = 0; i < p_materials.size(); i++) {
		ShaderMaterial *material = Object::cast_to<ShaderMaterial>(p_materials[i]);
		if (material != nullptr) {
			material->set_shader_parameter(bone_transforms, matrices);
		}
	}
}

} // namespace godot
