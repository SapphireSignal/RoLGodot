shader_type canvas_item;
render_mode unshaded;
// Port of Engine/Shader/FXAA.fx: NVIDIA FXAA 3.11, the PC quality path as the original compiles it (FXAA_PC,
// FXAA_HLSL_4: no gather, FXAA_GREEN_AS_LUMA: the green channel is the luma, FXAA_DISCARD: a pixel without an edge
// keeps the scene, which SwitchScene copied into the target). The quality preset (FXAA_QUALITY__PRESET, set by
// TPostEffectFXAA.BuildShader) is the search step list quality_p[0 .. quality_ps - 1] (TPostEffectManager.FXAA_PRESETS);
// the nested "if (doneNP)" blocks are the loop. Linear sampling, clamped, at lod 0; UV is the pixel center.
// DX11 arithmetic kept: the stack's EdgeThreshold and EdgeThresholdMin are 0, so no pixel exits early, and a flat
// cross (range 0) makes 1 / range infinite: saturate(0 * inf = NaN) is 0 there, saturate(x * inf) 1.

uniform sampler2D color_texture : filter_linear, repeat_disable;
uniform float pixelwidth = 0.0;
uniform float pixelheight = 0.0;
uniform float subpixel_quality = 0.75;    // fxaaQualitySubpix
uniform float edge_threshold = 0.166;     // fxaaQualityEdgeThreshold
uniform float edge_threshold_min = 0.0833; // fxaaQualityEdgeThresholdMin
uniform int quality_ps = 5;               // FXAA_QUALITY__PS
uniform float quality_p[12];              // FXAA_QUALITY__P0 ..

vec4 tex_top(vec2 p) {
	return textureLod(color_texture, p, 0.0);
}

float luma_off(vec2 p, vec2 o, vec2 rcp_frame) {
	return textureLod(color_texture, p + o * rcp_frame, 0.0).g;
}

void fragment() {
	vec2 rcp_frame = vec2(pixelwidth, pixelheight);
	vec2 posM = UV;
	vec4 rgbyM = tex_top(posM);
	float lumaM = rgbyM.g;
	float lumaS = luma_off(posM, vec2(0.0, 1.0), rcp_frame);
	float lumaE = luma_off(posM, vec2(1.0, 0.0), rcp_frame);
	float lumaN = luma_off(posM, vec2(0.0, -1.0), rcp_frame);
	float lumaW = luma_off(posM, vec2(-1.0, 0.0), rcp_frame);

	float maxSM = max(lumaS, lumaM);
	float minSM = min(lumaS, lumaM);
	float maxESM = max(lumaE, maxSM);
	float minESM = min(lumaE, minSM);
	float maxWN = max(lumaN, lumaW);
	float minWN = min(lumaN, lumaW);
	float rangeMax = max(maxWN, maxESM);
	float rangeMin = min(minWN, minESM);
	float rangeMaxScaled = rangeMax * edge_threshold;
	float range = rangeMax - rangeMin;
	float rangeMaxClamped = max(edge_threshold_min, rangeMaxScaled);
	bool earlyExit = range < rangeMaxClamped;

	vec3 result = rgbyM.rgb;
	if (!earlyExit) {
		float lumaNW = luma_off(posM, vec2(-1.0, -1.0), rcp_frame);
		float lumaSE = luma_off(posM, vec2(1.0, 1.0), rcp_frame);
		float lumaNE = luma_off(posM, vec2(1.0, -1.0), rcp_frame);
		float lumaSW = luma_off(posM, vec2(-1.0, 1.0), rcp_frame);

		float lumaNS = lumaN + lumaS;
		float lumaWE = lumaW + lumaE;
		float subpixNSWE = lumaNS + lumaWE;
		float edgeHorz1 = (-2.0 * lumaM) + lumaNS;
		float edgeVert1 = (-2.0 * lumaM) + lumaWE;

		float lumaNESE = lumaNE + lumaSE;
		float lumaNWNE = lumaNW + lumaNE;
		float edgeHorz2 = (-2.0 * lumaE) + lumaNESE;
		float edgeVert2 = (-2.0 * lumaN) + lumaNWNE;

		float lumaNWSW = lumaNW + lumaSW;
		float lumaSWSE = lumaSW + lumaSE;
		float edgeHorz4 = (abs(edgeHorz1) * 2.0) + abs(edgeHorz2);
		float edgeVert4 = (abs(edgeVert1) * 2.0) + abs(edgeVert2);
		float edgeHorz3 = (-2.0 * lumaW) + lumaNWSW;
		float edgeVert3 = (-2.0 * lumaS) + lumaSWSE;
		float edgeHorz = abs(edgeHorz3) + edgeHorz4;
		float edgeVert = abs(edgeVert3) + edgeVert4;

		float subpixNWSWNESE = lumaNWSW + lumaNESE;
		float lengthSign = rcp_frame.x;
		bool horzSpan = edgeHorz >= edgeVert;
		float subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;

		if (!horzSpan) lumaN = lumaW;
		if (!horzSpan) lumaS = lumaE;
		if (horzSpan) lengthSign = rcp_frame.y;
		float subpixB = (subpixA * (1.0 / 12.0)) - lumaM;

		float gradientN = lumaN - lumaM;
		float gradientS = lumaS - lumaM;
		float lumaNN = lumaN + lumaM;
		float lumaSS = lumaS + lumaM;
		bool pairN = abs(gradientN) >= abs(gradientS);
		float gradient = max(abs(gradientN), abs(gradientS));
		if (pairN) lengthSign = -lengthSign;
		// FxaaSat(abs(subpixB) * (1.0 / range)) with DX11's inf / NaN
		float subpixC = range > 0.0 ? clamp(abs(subpixB) / range, 0.0, 1.0) : (abs(subpixB) > 0.0 ? 1.0 : 0.0);

		vec2 posB = posM;
		vec2 offNP;
		offNP.x = (!horzSpan) ? 0.0 : rcp_frame.x;
		offNP.y = (horzSpan) ? 0.0 : rcp_frame.y;
		if (!horzSpan) posB.x += lengthSign * 0.5;
		if (horzSpan) posB.y += lengthSign * 0.5;

		vec2 posN = posB - offNP * quality_p[0];
		vec2 posP = posB + offNP * quality_p[0];
		float subpixD = ((-2.0) * subpixC) + 3.0;
		float lumaEndN = tex_top(posN).g;
		float subpixE = subpixC * subpixC;
		float lumaEndP = tex_top(posP).g;

		if (!pairN) lumaNN = lumaSS;
		float gradientScaled = gradient * 1.0 / 4.0;
		float lumaMM = lumaM - lumaNN * 0.5;
		float subpixF = subpixD * subpixE;
		bool lumaMLTZero = lumaMM < 0.0;

		lumaEndN -= lumaNN * 0.5;
		lumaEndP -= lumaNN * 0.5;
		bool doneN = abs(lumaEndN) >= gradientScaled;
		bool doneP = abs(lumaEndP) >= gradientScaled;
		if (!doneN) posN -= offNP * quality_p[1];
		bool doneNP = (!doneN) || (!doneP);
		if (!doneP) posP += offNP * quality_p[1];

		for (int i = 2; i < quality_ps; i++) {
			if (!doneNP) break;
			if (!doneN) lumaEndN = tex_top(posN).g;
			if (!doneP) lumaEndP = tex_top(posP).g;
			if (!doneN) lumaEndN = lumaEndN - lumaNN * 0.5;
			if (!doneP) lumaEndP = lumaEndP - lumaNN * 0.5;
			doneN = abs(lumaEndN) >= gradientScaled;
			doneP = abs(lumaEndP) >= gradientScaled;
			if (!doneN) posN -= offNP * quality_p[i];
			doneNP = (!doneN) || (!doneP);
			if (!doneP) posP += offNP * quality_p[i];
		}

		float dstN = posM.x - posN.x;
		float dstP = posP.x - posM.x;
		if (!horzSpan) dstN = posM.y - posN.y;
		if (!horzSpan) dstP = posP.y - posM.y;

		bool goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
		float spanLength = (dstP + dstN);
		bool goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
		float spanLengthRcp = 1.0 / spanLength;

		bool directionN = dstN < dstP;
		float dst = min(dstN, dstP);
		bool goodSpan = directionN ? goodSpanN : goodSpanP;
		float subpixG = subpixF * subpixF;
		float pixelOffset = (dst * (-spanLengthRcp)) + 0.5;
		float subpixH = subpixG * subpixel_quality;

		float pixelOffsetGood = goodSpan ? pixelOffset : 0.0;
		float pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
		if (!horzSpan) posM.x += pixelOffsetSubpix * lengthSign;
		if (horzSpan) posM.y += pixelOffsetSubpix * lengthSign;
		result = tex_top(posM).rgb;
	}
	COLOR = vec4(result, 1.0);
}
