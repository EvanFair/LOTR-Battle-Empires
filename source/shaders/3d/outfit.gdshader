// Low-poly "outfit" for the Quaternius mannequin (CC0): each body part takes a colour from the
// bone that moves it most (legs, boots, torso, arms, hands, head), with flat faceted shading.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec3 legs : source_color = vec3(0.3);
uniform vec3 boots : source_color = vec3(0.2);
uniform vec3 torso : source_color = vec3(0.6);
uniform vec3 arms : source_color = vec3(0.5);
uniform vec3 hands : source_color = vec3(0.7, 0.55, 0.45);
uniform vec3 head : source_color = vec3(0.7, 0.55, 0.45);
uniform float shade = 1.0;  // the joint surface is drawn a little darker
uniform vec3 glow : source_color = vec3(0.0);

varying flat int part;

void vertex() {
	// strongest bone -> body part (bone order of the UAL rig, see Art.gd)
	int b = int(BONE_INDICES.x);
	float w = BONE_WEIGHTS.x;
	if (BONE_WEIGHTS.y > w) { b = int(BONE_INDICES.y); w = BONE_WEIGHTS.y; }
	if (BONE_WEIGHTS.z > w) { b = int(BONE_INDICES.z); w = BONE_WEIGHTS.z; }
	if (BONE_WEIGHTS.w > w) { b = int(BONE_INDICES.w); }
	if (b == 5 || b == 6) part = 5;                       // neck, head
	else if (b == 9 || b == 33) part = 3;                 // forearms
	else if ((b >= 10 && b <= 30) || (b >= 34 && b <= 54)) part = 4;  // hands
	else if (b == 55 || b == 60 || b <= 1) part = 0;      // pelvis, thighs
	else if (b >= 56) part = 1;                           // calves, feet
	else part = 2;                                        // spine, shoulders, upper arms
}

void fragment() {
	vec3 c = torso;
	if (part == 0) c = legs;
	else if (part == 1) c = boots;
	else if (part == 3) c = arms;
	else if (part == 4) c = hands;
	else if (part == 5) c = head;
	ALBEDO = min(c * shade * 1.55, vec3(1.0));  // brighter than the palette: the match lighting is moody
	ROUGHNESS = 0.85;
	RIM = 0.35;
	RIM_TINT = 0.4;
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	EMISSION = glow;
}
