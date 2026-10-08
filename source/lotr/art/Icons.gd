class_name Icons
## Ability and item icons. Skill art: Open Moba contributors (CC-BY-4.0); item art:
## game-icons.net (CC BY 3.0) via Open MOBA. See README Credits.

const ATLAS = {
	"skills": "res://assets/omoba/skills/skills-atlas.png",
	"roster": "res://assets/omoba/skills/roster-skills.png",
}
const CELL = 256

# [atlas, row, column] by ability kind; abilities may override with an "icon" entry
const BY_KIND = {
	"execute_strike": ["skills", 0, 2], "strike": ["skills", 0, 0], "pin_shot": ["skills", 2, 2],
	"nova": ["skills", 0, 3], "ground_aoe": ["skills", 2, 0], "skillshot": ["skills", 2, 2],
	"dash": ["roster", 2, 3], "leap": ["roster", 2, 1], "buff_self": ["skills", 0, 1],
	"rally_aura": ["skills", 3, 0], "heal_allies": ["skills", 3, 1], "team_haste": ["skills", 3, 3],
	"summon": ["skills", 4, 3],
}
const BY_ABILITY = {
	"Army of the Dead": ["roster", 7, 1], "Fell Beast": ["roster", 3, 2], "Web": ["skills", 4, 1],
	"Black Breath": ["roster", 3, 0], "Dread Shriek": ["roster", 5, 3], "Fireball": ["skills", 1, 3],
	"Fire of Orthanc": ["roster", 0, 3], "Voice of Saruman": ["skills", 1, 0],
	"Staff Blast": ["skills", 1, 2], "Morgul Blade": ["roster", 1, 0], "Sting": ["skills", 4, 2],
	"Lurk": ["roster", 3, 3], "Feast": ["skills", 4, 0], "Warg Pack": ["skills", 4, 0],
	"Bloodlust": ["skills", 0, 1], "Last Stand": ["skills", 3, 2], "Shield Wall": ["skills", 0, 0],
	"Ithilien Stealth": ["roster", 6, 2], "Rangers of Ithilien": ["skills", 2, 3],
	"Riders of the Mark": ["roster", 2, 3], "Uruk Ambush": ["skills", 0, 3],
}
const ITEMS = {
	"lembas": "vitality-gem", "athelas": "vitality-gem", "horse_rohan": "trail-boots",
	"elven_blade": "ember-blade", "westernesse": "ember-blade", "dwarf_mail": "guardian-crest",
	"mithril": "guardian-crest", "ring_barahir": "focus-charm", "phial": "focus-charm",
	"horn_mark": "swift-grip",
}

static var _cache = {}


static func ability(a: Dictionary) -> Texture2D:
	var spec = BY_ABILITY.get(a.name, BY_KIND.get(a.kind, ["skills", 0, 2]))
	var key = "%s/%d/%d" % spec
	if not _cache.has(key):
		var atlas = AtlasTexture.new()
		atlas.atlas = load(ATLAS[spec[0]])
		atlas.region = Rect2(spec[2] * CELL, spec[1] * CELL, CELL, CELL)
		_cache[key] = atlas
	return _cache[key]


static func item(key: String) -> Texture2D:
	var path = "res://assets/omoba/icons/item/%s-32@2x.png" % ITEMS.get(key, "vitality-gem")
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]
