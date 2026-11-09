class_name CivicWorks
extends RefCounted
## Auftrag 19: autonome Stadtentwicklung der Buergermeister.
##
## Jeder Buergermeister hat eine Persoenlichkeit (familie | wirtschaft | prestige | sport), eine langfristige Vision und lernende
## Vorlieben je Kategorie. Alle 10 Spieltage (zeitversetzt je Stadt) analysiert er im Rathaus den Bedarf, waehlt Projekte aus eigenen
## Ideen (LLM-Aktion propose_project) und Regel-Ideen nach einem Punktesystem, faehrt mit dem Dienstwagen zum Grosslager, gibt dort die
## Materialbestellungen frei (Lieferung per Lkw ins Stadtlager), faehrt zurueck und beauftragt das Projekt: Rat (ab 30 000 EUR),
## Ausschreibung, Baufirma mit Bautrupp, Bau erst mit vollstaendigem Material, Eroeffnung mit Wirkung.
##
## Die KI entscheidet, WAS gebaut wird; die Engine entscheidet, WIE: Vorlagen aus vorhandenen Bauteilen (TEMPLATES), Standort,
## Strassenanschluss, Kollision, Material und Kosten prueft der Validator (validate). Nichts wird ungeprueft in die Welt gesetzt.

signal ground_changed(cells: Array)
signal anlage_changed(id: String)

const VISIT_EVERY := 10                # Spieltage zwischen zwei Besuchen im Grosslager
const FIRST_VISIT := 10
const STAY_MIN := 60.0                 # Spielminuten Aufenthalt im Grosslager
const MAX_PER_VISIT := 2
const MAX_OPEN := 2                    # hoechstens so viele unfertige Projekte je Stadt; erst fertig bauen, dann Neues
const PROPOSALS_MAX := 6
const EVAL_DAYS := 8                   # Erfolgskontrolle fruehestens so viele Tage nach der Eroeffnung

## Persoenlichkeiten: Gewichte je Kategorie, Eitelkeit (Denkmal-Lust), Vision zum Start.
const PERSONAS := {
	"familie": {"label": "familienfreundlich", "eitel": 0.15,
		"w": {"familie": 1.6, "gruen": 1.3, "bildung": 1.5, "sport": 1.0, "markt": 0.8, "prestige": 0.5},
		"vision": "Eine familienfreundliche Wohnstadt mit vielen Spielplätzen, Parks und guten Kindergärten."},
	"wirtschaft": {"label": "wirtschaftsorientiert", "eitel": 0.35,
		"w": {"familie": 0.9, "gruen": 0.8, "bildung": 1.1, "sport": 0.8, "markt": 1.8, "prestige": 0.7},
		"vision": "Das wirtschaftliche Zentrum der Region: Märkte, Handel und gute Infrastruktur."},
	"prestige": {"label": "prestigeorientiert", "eitel": 0.95,
		"w": {"familie": 0.8, "gruen": 1.0, "bildung": 0.8, "sport": 0.9, "markt": 1.1, "prestige": 1.9},
		"vision": "Die repräsentativste Stadt der Region mit großen Plätzen und beeindruckenden Denkmälern."},
	"sport": {"label": "sportbegeistert", "eitel": 0.4,
		"w": {"familie": 1.1, "gruen": 1.1, "bildung": 0.9, "sport": 1.9, "markt": 0.8, "prestige": 0.8},
		"vision": "Eine aktive Sportstadt mit Bolzplätzen, Sportanlagen und irgendwann einem eigenen Stadion."},
}
const CAT_LABEL := {"familie": "Familie und Spiel", "gruen": "Grün und Erholung", "markt": "Markt und Handel", "sport": "Sport",
	"prestige": "Prestige und Denkmäler", "bildung": "Bildung und Betreuung"}
const MAYOR_COLORS := [Color("#d4a017"), Color("#8e44ad"), Color("#16a085"), Color("#c0392b")]

## Bauvorlagen (Baukasten). ground: Bodenart; pieces: Hauptbauteile; extra: [Bauteil, Anzahl] als Ausstattung; building: echtes Gebaeude;
## rank: Groesse eines Denkmals (Wettstreit); vote: Ratsart; keys: Stichworte fuer die Zuordnung von KI-Ideen.
const TEMPLATES := {
	"spielplatz_s": {"label": "Kleiner Spielplatz", "cat": "familie", "w": 4, "h": 4, "cost": 16000.0, "days": 6, "ground": "sand",
		"pieces": ["d_swing", "d_slide", "d_sandbox"], "extra": [["d_bench", 2], ["d_tree0", 2], ["d_lamp", 1]], "keys": ["spielplatz", "schaukel", "rutsche", "sandkasten", "kinder"]},
	"spielplatz_m": {"label": "Spielplatz", "cat": "familie", "w": 6, "h": 5, "cost": 30000.0, "days": 8, "ground": "sand",
		"pieces": ["d_swing", "d_slide", "d_climber", "d_sandbox", "d_seesaw"], "extra": [["d_bench", 3], ["d_tree0", 3], ["d_lamp", 2], ["d_flowerbed", 1]], "keys": ["spielplatz", "klettergerüst", "wippe", "familie"]},
	"spielplatz_l": {"label": "Großer Abenteuerspielplatz", "cat": "familie", "w": 8, "h": 6, "cost": 52000.0, "days": 11, "ground": "sand",
		"pieces": ["d_swing", "d_swing", "d_slide", "d_climber", "d_climber", "d_sandbox", "d_seesaw", "d_picnic"], "extra": [["d_bench", 4], ["d_tree0", 5], ["d_lamp", 3], ["d_flowerbed", 2]], "keys": ["abenteuerspielplatz", "großer spielplatz", "spielbereiche"]},
	"park_s": {"label": "Kleine Grünanlage", "cat": "gruen", "w": 4, "h": 4, "cost": 12000.0, "days": 5, "ground": "park",
		"pieces": ["d_flowerbed", "d_picnic"], "extra": [["d_bench", 2], ["d_tree0", 4], ["d_bush", 3], ["d_lamp", 1]], "keys": ["grünanlage", "garten", "picknick", "grün"]},
	"park_m": {"label": "Stadtpark", "cat": "gruen", "w": 6, "h": 6, "cost": 28000.0, "days": 8, "ground": "park", "building": "fountain",
		"pieces": ["d_flowerbed", "d_flowerbed", "d_picnic"], "extra": [["d_bench", 4], ["d_tree0", 6], ["d_bush", 4], ["d_lamp", 2]], "keys": ["park", "stadtpark", "erholung", "bäume"]},
	"park_l": {"label": "Großer Stadtpark mit Brunnen", "cat": "gruen", "w": 9, "h": 7, "cost": 50000.0, "days": 11, "ground": "park", "building": "fountain",
		"pieces": ["d_flowerbed", "d_flowerbed", "d_flowerbed", "d_picnic", "d_picnic", "d_swing"], "extra": [["d_bench", 6], ["d_tree0", 10], ["d_bush", 6], ["d_lamp", 4]], "keys": ["großer park", "promenade", "öffentlicher garten"]},
	"markt_m": {"label": "Marktplatz", "cat": "markt", "w": 6, "h": 5, "cost": 34000.0, "days": 8, "ground": "plaza", "building": "fountain",
		"pieces": ["d_stall0", "d_stall1", "d_stall2", "d_stall3"], "extra": [["d_bench", 2], ["d_tree0", 2], ["d_lamp", 2], ["d_flowerbed", 1]], "keys": ["marktplatz", "wochenmarkt", "marktstände", "brunnen"]},
	"markt_l": {"label": "Großer Marktplatz mit Brunnen", "cat": "markt", "w": 8, "h": 6, "cost": 60000.0, "days": 12, "ground": "plaza", "building": "fountain",
		"pieces": ["d_stall0", "d_stall1", "d_stall2", "d_stall3", "d_stall0", "d_stall2"], "extra": [["d_bench", 4], ["d_tree0", 4], ["d_lamp", 4], ["d_flowerbed", 3]], "keys": ["großer marktplatz", "fußgängerzone", "markthalle", "rathausplatz"]},
	"basketball": {"label": "Basketballplatz", "cat": "sport", "w": 4, "h": 4, "cost": 15000.0, "days": 5, "ground": "concrete", "lines": "court",
		"pieces": ["d_hoop", "d_hoop"], "extra": [["d_bench", 2], ["d_lamp", 2]], "keys": ["basketball", "streetball", "korb"]},
	"bolzplatz": {"label": "Bolzplatz", "cat": "sport", "w": 6, "h": 4, "cost": 20000.0, "days": 6, "ground": "park", "lines": "pitch",
		"pieces": ["d_goal", "d_goal"], "extra": [["d_bench", 2], ["d_tree0", 2]], "keys": ["bolzplatz", "fußball", "kicken"]},
	"sportplatz": {"label": "Fußballplatz mit Flutlicht", "cat": "sport", "w": 9, "h": 6, "cost": 65000.0, "days": 14, "ground": "park", "lines": "pitch",
		"pieces": ["d_goal", "d_goal", "d_tribune"], "extra": [["d_floodlight", 4], ["d_bench", 2]], "keys": ["fußballplatz", "sportplatz", "flutlicht", "tribüne", "vereinsheim"]},
	"stadion": {"label": "Stadion", "cat": "sport", "w": 11, "h": 8, "cost": 150000.0, "days": 24, "ground": "park", "lines": "stadium", "vote": "denkmal",
		"pieces": ["d_goal", "d_goal", "d_tribune", "d_tribune"], "extra": [["d_floodlight", 4], ["d_lamp", 4]], "keys": ["stadion", "arena", "großes stadion"]},
	"buste": {"label": "Büste des Bürgermeisters", "cat": "prestige", "w": 2, "h": 2, "cost": 12000.0, "days": 5, "ground": "plaza", "rank": 1,
		"pieces": ["m_bust"], "extra": [], "keys": ["büste", "kleine statue"]},
	"bronzestatue": {"label": "Bronzestatue des Bürgermeisters", "cat": "prestige", "w": 3, "h": 3, "cost": 28000.0, "days": 8, "ground": "plaza", "rank": 2,
		"pieces": ["m_bronze"], "extra": [["d_bench", 2], ["d_lamp", 2]], "keys": ["statue", "bronzestatue", "denkmal"]},
	"obelisk": {"label": "Obelisk", "cat": "prestige", "w": 3, "h": 3, "cost": 42000.0, "days": 10, "ground": "plaza", "rank": 3,
		"pieces": ["m_obelisk"], "extra": [["d_flowerbed", 2], ["d_lamp", 2]], "keys": ["obelisk", "säule", "gründungsdenkmal"]},
	"reiterstandbild": {"label": "Reiterstandbild", "cat": "prestige", "w": 3, "h": 3, "cost": 46000.0, "days": 10, "ground": "plaza", "rank": 3,
		"pieces": ["m_rider"], "extra": [["d_bench", 2], ["d_lamp", 2]], "keys": ["reiterstandbild", "reiter", "pferd"]},
	"brunnendenkmal": {"label": "Denkmal mit Brunnen", "cat": "prestige", "w": 4, "h": 4, "cost": 72000.0, "days": 14, "ground": "plaza", "rank": 4, "vote": "denkmal",
		"pieces": ["m_fountain"], "extra": [["d_bench", 3], ["d_tree0", 2], ["d_lamp", 2]], "keys": ["springbrunnen", "brunnen", "denkmal mit brunnen", "riesiger springbrunnen"]},
	"triumphbogen": {"label": "Triumphbogen", "cat": "prestige", "w": 4, "h": 3, "cost": 98000.0, "days": 18, "ground": "plaza", "rank": 5, "vote": "denkmal",
		"pieces": ["m_arch"], "extra": [["d_lamp", 2], ["d_flowerbed", 2]], "keys": ["triumphbogen", "stadttor", "bogen", "wahrzeichen"]},
	"monumentalstatue": {"label": "Monumentale Bürgermeisterstatue", "cat": "prestige", "w": 5, "h": 5, "cost": 165000.0, "days": 26, "ground": "plaza", "rank": 6, "vote": "denkmal",
		"pieces": ["m_giant"], "extra": [["d_tree0", 4], ["d_bench", 2]], "keys": ["monumental", "riesige statue", "kolossal", "gigantisch"]},
	"kindergarten": {"label": "Kindergarten", "cat": "bildung", "w": 4, "h": 3, "cost": 110000.0, "days": 20, "ground": "", "building": "kindergarten",
		"pieces": [], "extra": [], "keys": ["kindergarten", "kita", "betreuung"]},
	"schule": {"label": "Schule", "cat": "bildung", "w": 6, "h": 4, "cost": 210000.0, "days": 30, "ground": "", "building": "school",
		"pieces": [], "extra": [], "keys": ["schule", "grundschule", "bildung"]},
}
## Material je Bauteil und je Bodenfeld (die Engine berechnet die Mengen, nicht die KI).
const PIECE_MAT := {
	"d_swing": {"stahl": 2, "spielgeraet": 1}, "d_slide": {"spielgeraet": 1, "stahl": 1}, "d_climber": {"spielgeraet": 1, "holz": 3},
	"d_sandbox": {"sand": 4, "holz": 1}, "d_seesaw": {"spielgeraet": 1}, "d_bench": {"holz": 1}, "d_tree0": {"jungbaum": 1},
	"d_bush": {"pflanzen": 4}, "d_flowerbed": {"pflanzen": 8, "naturstein": 1}, "d_lamp": {"strassenleuchte": 1, "kabel": 15},
	"d_picnic": {"holz": 2}, "d_stall0": {"marktstand": 1}, "d_stall1": {"marktstand": 1}, "d_stall2": {"marktstand": 1}, "d_stall3": {"marktstand": 1},
	"d_goal": {"stahl": 1, "sportmaterial": 1}, "d_floodlight": {"flutlicht": 1, "kabel": 30}, "d_tribune": {"tribuenenteil": 4, "beton": 4},
	"d_hoop": {"sportmaterial": 1, "stahl": 1}, "fountain": {"naturstein": 3, "rohr": 12, "pflaster": 2},
	"m_bust": {"bronze": 1, "naturstein": 2}, "m_bronze": {"bronze": 3, "naturstein": 4}, "m_rider": {"bronze": 6, "naturstein": 6},
	"m_obelisk": {"naturstein": 14}, "m_fountain": {"bronze": 3, "naturstein": 10, "rohr": 20}, "m_arch": {"naturstein": 30, "beton": 10, "bronze": 1},
	"m_giant": {"naturstein": 50, "beton": 20, "kunstwerk": 1},
	"kindergarten": {"ziegel": 120, "holz": 20, "glas": 15, "betonfertigteil": 20, "dachmaterial": 40},
	"school": {"ziegel": 260, "holz": 40, "glas": 40, "betonfertigteil": 50, "dachmaterial": 90},
}
const GROUND_MAT := {"sand": {"sand": 1}, "park": {"pflanzen": 1}, "plaza": {"pflaster": 1}, "concrete": {"betonfertigteil": 1}}
const LINE_MAT := {"pitch": {"sportbelag": 3}, "court": {"sportbelag": 3}, "stadium": {"sportbelag": 3}}
## Grosse Sprites belegen 2x2 bzw. 2x1 Felder.
const BIG := {"m_giant": Vector2i(2, 2), "m_fountain": Vector2i(2, 2), "m_arch": Vector2i(2, 1), "d_tribune": Vector2i(2, 1)}
const COMMENTS := {
	"prestige": ["Niedlich, das Ding. Unser nächstes Denkmal wird man vom Großlager aus sehen.", "Eine Statue? Wir bauen eine größere. Mit Brunnen.",
		"Respekt – aber unser Bürgermeister hat das bessere Profil für Bronze."],
	"familie": ["Für das Geld hätte man drei Spielplätze bauen können.", "Schön für den Bürgermeister. Unsere Kinder freuen sich über Rutschen."],
	"wirtschaft": ["Bringt das Denkmal auch Umsatz? Unser Marktplatz schon.", "Steine statt Standortpolitik – bitte sehr."],
	"sport": ["Statuen schießen keine Tore. Unser Bolzplatz ist voll.", "Wir messen Größe in Tribünenplätzen."],
}

var sim
var profiles := {}       # Stadt -> {persona, eitel, vision, weights, color, lessons: [], target_rank, last_visit, next_visit}
var anlagen := {}        # "AN<n>" -> Anlage (siehe _new_anlage)
var proposals := {}      # Stadt -> [KI-Idee (propose_project)]
var trips := {}          # Stadt -> {phase, plan: [ids], vehicle, until, day}
var log: Array = []      # [{day, town, text}] Entscheidungsverlauf (sichtbar im Buergermeisterfenster)
var comments: Array = [] # [{day, from, about, text}]
var stats := {"besuche": 0, "eroeffnet": 0, "abgelehnt": 0}
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	if sim.towns == null or not sim.towns.is_region() or sim.city.hub.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) * 13 + 777
	var personas: Array = PERSONAS.keys()
	for i in range(personas.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = personas[i]
		personas[i] = personas[j]
		personas[j] = t
	for k in sim.towns.count():
		var pk: String = personas[k % personas.size()]
		var P: Dictionary = PERSONAS[pk]
		profiles[k] = {"persona": pk, "eitel": float(P.eitel), "vision": str(P.vision), "weights": P.w.duplicate(),
			"color": MAYOR_COLORS[k % MAYOR_COLORS.size()].to_html(false), "lessons": [], "target_rank": 0, "last_visit": -1,
			"next_visit": FIRST_VISIT + (k % 2), "visit_hour": 8.0 + 2.0 * float(k)}
		proposals[k] = []
	sim.day_changed.connect(on_day)


func enabled() -> bool:
	return not profiles.is_empty()


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _note(k: int, text: String, kind: String = "info") -> void:
	log.append({"day": _today(), "town": k, "text": text})
	if log.size() > 300:
		log = log.slice(-300)
	sim.log_event("%s: %s" % [_mayor_label(k), text], kind)


func _mayor_label(k: int) -> String:
	return "Bürgermeister %s (%s)" % [sim.towns.mayor(k).name, sim.towns.name_of(k)]


# ------------------------------------------------------------------ Stadtanalyse
## Bedarf je Kategorie (0..100) aus den Kennzahlen der Stadt und den vorhandenen Anlagen.
func analyze(k: int) -> Dictionary:
	var pop: int = sim.citizens.population_of(k)
	var kids := int(round(float(pop) * 0.2))
	for h in sim.households.homes.values():
		var addr := int(h.get("address", -1))
		if addr >= 0 and sim.towns.of_building(addr) == k:
			kids += int(h.get("dependents", 0))
	var have := {}
	for a in anlagen.values():
		if int(a.town) == k and str(a.status) not in ["abgelehnt", "verworfen"]:
			have[a.cat] = int(have.get(a.cat, 0)) + 1
	var kgs := 0
	var schools := 0
	for b in sim.city.buildings:
		if str(b.type) in ["kindergarten", "school"] and sim.towns.of_building(int(b.id)) == k:
			if b.type == "kindergarten":
				kgs += 1
			else:
				schools += 1
	var M: Mayor = sim.towns.mayor(k)
	var need := {}
	need["familie"] = clampf(float(kids) / (12.0 * float(int(have.get("familie", 0)) + 1)) * 40.0, 0.0, 100.0)
	need["gruen"] = clampf(float(pop) / (60.0 * float(int(have.get("gruen", 0)) + 1)) * 45.0, 0.0, 100.0)
	need["markt"] = clampf((float(pop) - 30.0) / 50.0 * 60.0, 0.0, 100.0) if int(have.get("markt", 0)) == 0 else clampf(float(pop) / 400.0 * 30.0, 0.0, 40.0)
	need["sport"] = clampf(float(pop) / (70.0 * float(int(have.get("sport", 0)) + 1)) * 45.0, 0.0, 100.0)
	need["bildung"] = clampf(float(kids) / (30.0 * float(kgs + schools + int(have.get("bildung", 0)) + 1)) * 70.0, 0.0, 100.0)
	var P: Dictionary = profiles[k]
	var rival_rank := 0
	for a in anlagen.values():
		if int(a.town) != k and str(a.status) == "eroeffnet":
			rival_rank = maxi(rival_rank, int(TEMPLATES[a.template].get("rank", 0)))
	need["prestige"] = clampf(15.0 + float(P.eitel) * 45.0 + (25.0 if rival_rank > _own_rank(k) else 0.0) - float(int(have.get("prestige", 0))) * 12.0, 0.0, 100.0)
	var urgent := maxf(float(need.familie), float(need.bildung)) > 70.0
	return {"einwohner": pop, "kinder_geschaetzt": kids, "vorhanden": have, "kindergaerten": kgs, "schulen": schools, "bedarf": need,
		"dringend": urgent, "beschaeftigung": snappedf(sim.citizens.employment_rate_of(k), 0.01), "zustimmung": snappedf(M.approval, 0.1),
		"mittel": int(M.available_budget()), "rivalen_hoechstes_denkmal": rival_rank, "eigenes_hoechstes_denkmal": _own_rank(k)}


func _own_rank(k: int) -> int:
	var r := 0
	for a in anlagen.values():
		if int(a.town) == k and str(a.status) not in ["abgelehnt", "verworfen"]:
			r = maxi(r, int(TEMPLATES[a.template].get("rank", 0)))
	return r


# ------------------------------------------------------------------ Ideen (KI) und Zuordnung zu Vorlagen
## KI-Idee eines Buergermeisters (Aktion propose_project): wird gespeichert und beim naechsten Besuch mitbewertet.
func propose(k: int, a: Dictionary) -> Dictionary:
	if not enabled():
		return {"ok": false, "msg": "Keine autonome Stadtentwicklung auf dieser Karte."}
	var idea := {"project": str(a.get("project", "")).left(80), "category": str(a.get("category", "")).to_lower(), "reason": str(a.get("reason", "")).left(240),
		"priority": clampi(int(a.get("priority", 50)), 0, 100), "district": str(a.get("desiredDistrict", a.get("district", ""))).left(60),
		"features": (a.get("features", []) if a.get("features") is Array else []).slice(0, 10), "size": str(a.get("size", "")).to_lower(), "day": _today()}
	var tid := match_template(idea)
	if tid == "":
		return {"ok": false, "msg": "Für '%s' gibt es (noch) keine Bauvorlage. Möglich: %s." % [idea.project, ", ".join(TEMPLATES.keys())]}
	idea["template"] = tid
	var list: Array = proposals.get(k, [])
	list.append(idea)
	proposals[k] = list.slice(-PROPOSALS_MAX)
	return {"ok": true, "msg": "Idee '%s' vorgemerkt (Vorlage %s). Entscheidung beim nächsten Besuch im Großlager (Tag %d)." % [idea.project, TEMPLATES[tid].label, int(profiles[k].next_visit)]}


## Zuordnung einer freien Idee zu einer Vorlage: Stichworte in Name, Merkmalen und Kategorie; Groessenwunsch waehlt die Variante.
func match_template(idea: Dictionary) -> String:
	if TEMPLATES.has(str(idea.get("template", ""))):
		return str(idea.template)
	var text := (str(idea.get("project", "")) + " " + " ".join(idea.get("features", [])) + " " + str(idea.get("category", ""))).to_lower()
	var best := ""
	var best_s := 0
	var cat_hint: String = {"recreation": "familie", "freizeit": "familie", "familie": "familie", "gruen": "gruen", "park": "gruen", "economy": "markt",
		"wirtschaft": "markt", "markt": "markt", "sport": "sport", "prestige": "prestige", "denkmal": "prestige", "monument": "prestige",
		"bildung": "bildung", "education": "bildung"}.get(str(idea.get("category", "")), "")
	for tid in TEMPLATES:
		var s := 0
		for key in TEMPLATES[tid].keys:
			if text.contains(str(key)):
				s += str(key).length()   # laengere, genauere Stichworte zaehlen mehr
		if s > 0 and cat_hint == str(TEMPLATES[tid].cat):
			s += 10
		if s > best_s:
			best_s = s
			best = tid
	if best == "":
		var cat_map := {"recreation": "spielplatz_m", "freizeit": "spielplatz_m", "familie": "spielplatz_m", "gruen": "park_m", "park": "park_m",
			"economy": "markt_m", "wirtschaft": "markt_m", "markt": "markt_m", "sport": "bolzplatz", "prestige": "bronzestatue", "denkmal": "bronzestatue",
			"monument": "bronzestatue", "bildung": "kindergarten", "education": "kindergarten", "infrastructure": "kindergarten"}
		best = str(cat_map.get(str(idea.get("category", "")), ""))
	if best == "":
		return ""
	var size := str(idea.get("size", ""))
	var family := best.trim_suffix("_s").trim_suffix("_m").trim_suffix("_l")
	if size in ["klein", "small", "s"] and TEMPLATES.has(family + "_s"):
		return family + "_s"
	if size in ["groß", "gross", "large", "l", "riesig"] and TEMPLATES.has(family + "_l"):
		return family + "_l"
	return best


# ------------------------------------------------------------------ Validator: Vorlage -> konkrete, pruefbare Anlage
## Materialbedarf einer Vorlage (vom Bausystem berechnet).
static func materials_of(tid: String) -> Dictionary:
	var t: Dictionary = TEMPLATES[tid]
	var out := {}
	var add := func(m: Dictionary, n: int):
		for it in m:
			out[it] = int(out.get(it, 0)) + int(m[it]) * n
	for p in t.pieces:
		add.call(PIECE_MAT.get(p, {}), 1)
	for e in t.extra:
		add.call(PIECE_MAT.get(e[0], {}), int(e[1]))
	if t.has("building"):
		add.call(PIECE_MAT.get(t.building, {}), 1)
	var cells := int(t.w) * int(t.h)
	add.call(GROUND_MAT.get(str(t.ground), {}), cells)
	if t.has("lines"):
		add.call(LINE_MAT.get(str(t.lines), {}), cells)
	return out


## Prueft eine Vorlage fuer eine Stadt: Bauplatz (freies stadteigenes Grundstueck, Strasse direkt am Rand, keine Kollision),
## Kosten, Rat, Baufirma, Material. Ergebnis {ok, msg, rect, parcel, cost, materials, material_ok, mangel}.
func validate(k: int, tid: String, district: String = "") -> Dictionary:
	if not TEMPLATES.has(tid):
		return {"ok": false, "msg": "Keine Bauvorlage %s." % tid}
	var t: Dictionary = TEMPLATES[tid]
	var M: Mayor = sim.towns.mayor(k)
	var cost := float(t.cost)
	if cost > M.available_budget():
		return {"ok": false, "msg": "%s kostet %s, verfügbar %s." % [t.label, Catalog.money(cost), Catalog.money(M.available_budget())], "grund": "geld"}
	if sim.construction.make_offers(cost, int(t.days), "civic%d" % k).is_empty():
		return {"ok": false, "msg": "Keine Baufirma kann %s bauen." % t.label, "grund": "baufirma"}
	var site := _find_site(k, int(t.w), int(t.h), district)
	if site.is_empty():
		return {"ok": false, "msg": "Kein freier städtischer Bauplatz %d×%d mit Straßenanschluss in %s." % [int(t.w), int(t.h), sim.towns.name_of(k)], "grund": "platz"}
	var mats := materials_of(tid)
	var mangel := {}
	var D: CityDepot = sim.towns.depot(k)
	for it in mats:
		var avail: int = D.stock_of(it) + (sim.hub.stock_of(it) if sim.hub.enabled else 0)
		if avail < int(mats[it]):
			mangel[it] = int(mats[it]) - avail
	return {"ok": true, "msg": "%s auf %s geprüft: Platz, Straße, Kosten %s, Baufirma vorhanden%s." % [t.label, site.parcel, Catalog.money(cost),
		"" if mangel.is_empty() else ", Material knapp: " + ", ".join(mangel.keys())], "rect": site.rect, "parcel": site.parcel, "cost": cost,
		"materials": mats, "material_ok": mangel.is_empty(), "mangel": mangel}


## Bauplatz: rechteckiger Ausschnitt eines freien, stadteigenen Grundstuecks; alle Zellen frei (kein Gebaeude, keine Strasse, kein Wasser,
## keine andere Anlage, keine geplante Zufahrt), eine Strasse direkt am Rand. Wunschviertel: Zentrum (Rathaus), Wohngebiet oder Rand.
func _find_site(k: int, w: int, h: int, district: String = "") -> Dictionary:
	var C: CityData = sim.city
	var th: Dictionary = C.building(int(sim.towns.get_t(k).town_hall))
	var anchor := Vector2i(int(th.x), int(th.y))
	var d := district.to_lower()
	var want_res := d.contains("wohn") or d.contains("famil") or d.contains("neu")
	var want_edge := d.contains("rand") or d.contains("außen") or d.contains("aussen") or d.contains("sport")
	var best := {}
	var best_s := INF
	for p in sim.parcels.items.values():
		if p.state != "frei" or not Towns.is_public(str(p.owner)) or Towns.town_of_owner(str(p.owner)) != k or int(p.area) < w * h:
			continue
		if not sim.parcels.is_buildable(p) or str(p.zone) in ["korridor", "industrie"]:
			continue
		var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
		if pr.size.x < w or pr.size.y < h:
			continue
		var dist := float(absi(pr.position.x - anchor.x) + absi(pr.position.y - anchor.y))
		if dist > 70.0:
			continue
		var s := dist
		if want_res and str(p.zone) != "wohnen":
			s += 25.0
		if want_edge:
			s = 80.0 - dist
		if s >= best_s:
			continue
		var r := _fit(pr, w, h)
		if r.size.x == 0:
			continue
		best_s = s
		best = {"rect": [r.position.x, r.position.y, w, h], "parcel": str(p.id)}
	return best


func _fit(pr: Rect2i, w: int, h: int) -> Rect2i:
	var C: CityData = sim.city
	for y in range(pr.position.y, pr.end.y - h + 1):
		for x in range(pr.position.x, pr.end.x - w + 1):
			var r := Rect2i(x, y, w, h)
			if _cells_free(r) and _touches_road(r):
				return r
	return Rect2i()


func _cells_free(r: Rect2i) -> bool:
	var C: CityData = sim.city
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not C.inside(q) or C.building_at[C.idx(q)] != -1 or C.g(q) in [CityData.G.ROAD, CityData.G.WATER, CityData.G.RAIL, CityData.G.QUAY, CityData.G.RUNWAY]:
				return false
			if sim.access != null and sim.access.reserved(q):
				return false
	for a in anlagen.values():
		if str(a.status) not in ["abgelehnt", "verworfen"] and Rect2i(int(a.rect[0]), int(a.rect[1]), int(a.rect[2]), int(a.rect[3])).intersects(r):
			return false
	return true


func _touches_road(r: Rect2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			if sim.city.inside(Vector2i(x, y)) and sim.city.is_road(Vector2i(x, y)):
				return true
	return false


# ------------------------------------------------------------------ Bauplaner: Ideen bewerten und entscheiden
## Ideen erzeugen (Regel-Ideen aus allen Vorlagen + eigene KI-Ideen), nach Punktesystem bewerten. Liefert absteigend sortierte Liste.
func ideas(k: int, ana: Dictionary = {}) -> Array:
	if ana.is_empty():
		ana = analyze(k)
	var P: Dictionary = profiles[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(sim.city.seed_value), k, _today()])
	var budget := maxf(1.0, float(ana.mittel))
	var out: Array = []
	var cands: Array = []
	for tid in TEMPLATES:
		cands.append({"template": tid, "project": TEMPLATES[tid].label, "reason": "", "origin": "regel", "priority": 50})
	for idea in proposals.get(k, []):
		var c: Dictionary = idea.duplicate()
		c["origin"] = "ki"
		cands.append(c)
	for c in cands:
		var t: Dictionary = TEMPLATES[c.template]
		var cat := str(t.cat)
		var need := float(ana.bedarf.get(cat, 0.0))
		var s := {}
		s["bedarf"] = need * 0.35
		s["wirtschaft"] = {"markt": 12.0, "sport": 4.0, "prestige": 3.0 + float(t.get("rank", 0)), "gruen": 2.0, "familie": 4.0, "bildung": 6.0}[cat]
		s["zufriedenheit"] = {"familie": 10.0, "gruen": 9.0, "sport": 8.0, "bildung": 12.0, "markt": 8.0, "prestige": 3.0}[cat]
		s["kosten"] = -25.0 * float(t.cost) / budget
		s["persoenlichkeit"] = 12.0 * float(P.weights.get(cat, 1.0))
		s["vielfalt"] = -14.0 * float(anlagen.values().filter(func(a): return int(a.town) == k and a.template == c.template and str(a.status) not in ["abgelehnt", "verworfen"]).size()) \
			- 5.0 * float(int(ana.vorhanden.get(cat, 0)))
		s["stadtentwicklung"] = 8.0 if str(P.vision).to_lower().contains(cat.left(5)) or (cat == "prestige" and str(P.vision).contains("Denkm")) else 0.0
		s["kreativitaet"] = rng.randf_range(-6.0, 6.0)
		if cat == "prestige":
			if bool(ana.dringend):
				s["vorrang"] = -30.0   # dringende Grundversorgung geht vor Prestige
			if int(t.get("rank", 0)) > int(ana.rivalen_hoechstes_denkmal) and int(ana.rivalen_hoechstes_denkmal) > 0:
				s["wettstreit"] = 12.0 * float(P.eitel) + 6.0   # Nachbarn uebertrumpfen
			if int(t.get("rank", 0)) <= int(ana.eigenes_hoechstes_denkmal):
				s["wettstreit"] = -15.0
		if str(c.origin) == "ki":
			s["eigene_idee"] = 10.0 + float(c.get("priority", 50)) * 0.1
		if float(t.cost) > float(ana.mittel):
			s["kosten"] = -100.0
		var total := 0.0
		for v in s.values():
			total += float(v)
		out.append({"template": c.template, "project": str(c.get("project", t.label)), "reason": str(c.get("reason", "")), "origin": c.origin,
			"district": str(c.get("district", "")), "features": c.get("features", []), "score": snappedf(total, 0.1), "teile": s})
	out.sort_custom(func(a, b): return float(a.score) > float(b.score))
	return out


## Bedarfsanalyse im Rathaus und Entscheidung: bis zu zwei gepruefte Projekte, sonst Begruendung, warum nicht.
func decide(k: int) -> Array:
	var ana := analyze(k)
	var chosen: Array = []
	var open: Array = anlagen.values().filter(func(a): return int(a.town) == k and str(a.status) in ["geplant", "material", "im_bau"])
	if open.size() >= MAX_OPEN:
		_note(k, "prüft die Baustellen (%s) – erst fertig bauen, dann Neues." % ", ".join(open.map(func(a): return "%s %s" % [a.title, a.status])))
		return []
	var prestige_open := open.any(func(a): return a.cat == "prestige")
	var spent := 0.0
	var cats := {}
	var checks := 0
	for idea in ideas(k, ana).slice(0, 10):
		if chosen.size() >= MAX_PER_VISIT or float(idea.score) < 8.0 or checks >= 4:
			break   # hoechstens 4 Pruefungen je Besuch (Bauplatzsuche ist die teure Stelle)
		var t: Dictionary = TEMPLATES[idea.template]
		if cats.has(t.cat) or spent + float(t.cost) > float(ana.mittel) * 0.8 or chosen.size() + open.size() >= MAX_OPEN:
			continue
		if t.cat == "prestige" and prestige_open:
			continue   # ein Denkmal nach dem anderen
		checks += 1
		var v := validate(k, idea.template, str(idea.district))
		if not v.ok:
			continue
		if not v.material_ok and _scarce(v.mangel):
			_note(k, "verschiebt '%s': %s im Großlager knapp." % [idea.project, ", ".join(v.mangel.keys())])
			continue
		var a := _new_anlage(k, idea, v)
		chosen.append(a.id)
		spent += float(t.cost)
		cats[t.cat] = true
	if chosen.is_empty():
		_note(k, "analysiert die Stadt (Bedarf %s) – kein Projekt passt in Kasse und Bauplätze (verfügbar %s)." % [_need_text(ana), Catalog.money(float(ana.mittel))])
	return chosen


## Material ist dauerhaft knapp, wenn selbst der Import es nicht rechtzeitig bringt (sehr teure Einzelstuecke fehlen ganz).
func _scarce(mangel: Dictionary) -> bool:
	for it in mangel:
		if int(mangel[it]) > 60 or it in ["kunstwerk", "bronze"]:
			return true
	return false


func _need_text(ana: Dictionary) -> String:
	var parts: Array = []
	for c in ana.bedarf:
		parts.append("%s %d" % [CAT_LABEL[c], int(ana.bedarf[c])])
	return ", ".join(parts)


func _new_anlage(k: int, idea: Dictionary, v: Dictionary) -> Dictionary:
	var t: Dictionary = TEMPLATES[idea.template]
	var id := "AN%d" % _next
	_next += 1
	var a := {"id": id, "town": k, "template": idea.template, "cat": t.cat, "title": idea.project, "reason": idea.reason if idea.reason != "" else _auto_reason(k, t),
		"origin": idea.origin, "score": idea.score, "rect": v.rect, "parcel": v.parcel, "cost": v.cost, "materials": v.materials, "status": "geplant",
		"project": "", "day": _today(), "opened": -1, "approval_at_open": -1.0, "evaluated": false, "seed": hash([id, int(sim.city.seed_value)]),
		"color": profiles[k].color, "features": idea.get("features", []), "pieces": []}
	a.pieces = _layout(a)
	anlagen[id] = a
	_note(k, "plant %s: %s (Begründung: %s; Punkte %.0f, %s)." % [a.title, t.label, a.reason, float(a.score), "eigene KI-Idee" if a.origin == "ki" else "Bauplaner"])
	if a.origin == "ki":
		proposals[k] = proposals.get(k, []).filter(func(x): return x.template != idea.template)
	return a


func _auto_reason(k: int, t: Dictionary) -> String:
	var ana := analyze(k)
	return "Bedarf %s %d von 100 bei %d Einwohnern; passt zur Linie (%s)." % [CAT_LABEL[t.cat], int(ana.bedarf.get(t.cat, 0)), int(ana.einwohner), PERSONAS[profiles[k].persona].label]


# ------------------------------------------------------------------ Baukasten: Anordnung der Bauteile
## Bauteile auf dem Bauplatz verteilen (seedstabil): Hauptbauteile in der Mitte, Baenke/Laternen an der Strasse, Baeume an den Raendern.
func _layout(a: Dictionary) -> Array:
	var t: Dictionary = TEMPLATES[a.template]
	var r := Rect2i(int(a.rect[0]), int(a.rect[1]), int(a.rect[2]), int(a.rect[3]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.seed)
	var used := {}
	var out: Array = []
	var place := func(sprite: String, cells: Array) -> bool:
		var sz: Vector2i = BIG.get(sprite, Vector2i.ONE)
		for c in cells:
			var ok := true
			for dy in sz.y:
				for dx in sz.x:
					var q: Vector2i = c + Vector2i(dx, dy)
					if used.has(q) or not r.has_point(q):
						ok = false
			if ok:
				for dy in sz.y:
					for dx in sz.x:
						used[c + Vector2i(dx, dy)] = true
				out.append({"sprite": sprite, "x": c.x, "y": c.y, "w": sz.x, "h": sz.y})
				return true
		return false
	var all: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			all.append(Vector2i(x, y))
	var ctr := Vector2(r.position) + Vector2(r.size) * 0.5 - Vector2(0.5, 0.5)
	var inner := all.duplicate()
	inner.sort_custom(func(p, q): return Vector2(p).distance_to(ctr) < Vector2(q).distance_to(ctr))
	var edge := all.filter(func(p): return p.x == r.position.x or p.y == r.position.y or p.x == r.end.x - 1 or p.y == r.end.y - 1)
	if t.has("building"):
		var bsz: Array = CityGenerator.TYPES[str(t.building)]
		var bw := mini(int(bsz[1]), r.size.x)
		var bh := mini(int(bsz[2]), r.size.y)
		var bc := Vector2i(r.position.x + (r.size.x - bw) / 2, r.position.y + (r.size.y - bh) / 2) if str(t.cat) in ["gruen", "markt"] else r.position
		for dy in bh:
			for dx in bw:
				used[bc + Vector2i(dx, dy)] = true
		out.append({"sprite": "#" + str(t.building), "x": bc.x, "y": bc.y, "w": bw, "h": bh})
	var lines := str(t.get("lines", ""))
	var pieces: Array = t.pieces.duplicate()
	for p in pieces:
		var cells: Array = inner.duplicate()
		if p == "d_goal" and lines != "":
			cells = [Vector2i(r.position.x, r.position.y + r.size.y / 2), Vector2i(r.end.x - 1, r.position.y + r.size.y / 2)] + cells
		elif p == "d_tribune":
			cells = range(r.position.x + 1, r.end.x - 2).map(func(x): return Vector2i(x, r.position.y)) + range(r.position.x + 1, r.end.x - 2).map(func(x): return Vector2i(x, r.end.y - 1)) + cells
		elif p == "d_hoop":
			cells = [Vector2i(r.position.x + r.size.x / 2, r.position.y), Vector2i(r.position.x + r.size.x / 2, r.end.y - 1)] + cells
		elif lines != "":
			cells = edge.duplicate()
		else:
			var shift := rng.randi_range(0, 2)
			cells = cells.slice(shift) + cells.slice(0, shift)
		place.call(p, cells)
	for e in t.extra:
		for i in int(e[1]):
			var cells: Array = edge.duplicate()
			if str(e[0]) == "d_floodlight":
				cells = [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE] + cells
			elif str(e[0]) in ["d_bench", "d_lamp"]:
				cells.sort_custom(func(p, q): return _road_dist(p) < _road_dist(q))
			else:
				for j in range(cells.size() - 1, 0, -1):
					var m := rng.randi_range(0, j)
					var tmp = cells[j]
					cells[j] = cells[m]
					cells[m] = tmp
			place.call(str(e[0]), cells)
	return out


func _road_dist(p: Vector2i) -> int:
	for d in range(1, 4):
		for q in [p + Vector2i(d, 0), p - Vector2i(d, 0), p + Vector2i(0, d), p - Vector2i(0, d)]:
			if sim.city.inside(q) and sim.city.is_road(q):
				return d
	return 9


# ------------------------------------------------------------------ Besuche im Grosslager (Dienstwagen)
func on_day(day: int) -> void:
	if not enabled():
		return
	for k in profiles:
		_evaluate(k)
		var tr: Dictionary = trips.get(k, {})
		if tr.is_empty() and day >= int(profiles[k].next_visit):
			trips[k] = {"phase": "wartet", "plan": [], "day": day}
	_follow_projects()


## Minutentakt (aus der Simulation): Abfahrt zur Besuchszeit, Ankunft, Aufenthalt, Rueckkehr.
func tick() -> void:
	if not enabled():
		return
	var hour := Catalog.hour_of_day(sim.game_min)
	for k in trips.keys():
		var tr: Dictionary = trips[k]
		match str(tr.phase):
			"wartet":
				if hour >= float(profiles[k].visit_hour):
					_depart(int(k), tr)
			"hinfahrt":
				if _arrived(tr):
					_at_hub(int(k), tr)
			"im_lager":
				if sim.game_min >= float(tr.until):
					_return(int(k), tr)
			"rueckfahrt":
				if _arrived(tr):
					_home(int(k), tr)


func _depart(k: int, tr: Dictionary) -> void:
	stats.besuche = int(stats.besuche) + 1
	profiles[k].last_visit = _today()
	profiles[k].next_visit = _today() + VISIT_EVERY
	tr.plan = decide(k)
	var M: Mayor = sim.towns.mayor(k)
	var hall: Vector2i = sim.city.building(int(sim.towns.get_t(k).town_hall)).road
	tr["vehicle"] = _spawn_car(k, hall, _hub_road(), "%s fährt zum Großlager" % M.name)
	tr.phase = "hinfahrt"
	if not tr.plan.is_empty():
		_note(k, "fährt mit dem Dienstwagen zum Großlager (%s)." % ", ".join(tr.plan.map(func(id): return anlagen[id].title)))
	sim.activity.add("stadt", -1, "fahrt", "%s fährt zum Großlager" % _mayor_label(k), "Dienstwagen", hall)


func _at_hub(k: int, tr: Dictionary) -> void:
	tr.phase = "im_lager"
	tr.until = sim.game_min + STAY_MIN
	var bought: Array = []
	for id in tr.plan:
		var a: Dictionary = anlagen.get(id, {})
		if a.is_empty() or a.status != "geplant":
			continue
		bought.append(_procure(k, a))
	if not bought.is_empty():
		_note(k, "ist im Großlager: %s." % "; ".join(bought))


func _return(k: int, tr: Dictionary) -> void:
	tr.phase = "rueckfahrt"
	var hall: Vector2i = sim.city.building(int(sim.towns.get_t(k).town_hall)).road
	var v: Dictionary = _vehicle(tr)
	if v.is_empty():
		tr["vehicle"] = _spawn_car(k, _hub_road(), hall, "%s fährt zurück" % sim.towns.mayor(k).name)
	else:
		v.label = "%s fährt zurück" % sim.towns.mayor(k).name
		sim.fleet.reroute(v, hall)


func _home(k: int, tr: Dictionary) -> void:
	var v: Dictionary = _vehicle(tr)
	if not v.is_empty():
		sim.fleet.vehicles.erase(v)
	for id in tr.plan:
		var a: Dictionary = anlagen.get(id, {})
		if not a.is_empty() and a.status == "material":
			_commission(k, a)
	trips.erase(k)


func _arrived(tr: Dictionary) -> bool:
	var v: Dictionary = _vehicle(tr)
	return v.is_empty() or v.mover.arrived()


func _vehicle(tr: Dictionary) -> Dictionary:
	for v in sim.fleet.vehicles:
		if int(v.id) == int(tr.get("vehicle", -1)):
			return v
	return {}


func _spawn_car(k: int, from: Vector2i, to: Vector2i, label: String) -> int:
	var v: Dictionary = sim.fleet._spawn("dienstwagen", from, to, INF, from, label)
	v["town"] = k
	v["color"] = profiles[k].color
	return int(v.id)


## Strassenzelle an den Dienstwagen-Stellplaetzen des Grosslagers.
func _hub_road() -> Vector2i:
	var B: Dictionary = sim.city.hub.buildings
	var b: Dictionary = sim.city.building(int(B.get("verwaltung", B.get("hauptlager", 0))))
	return b.road


## Im Grosslager: Projekt beim Bauamt anlegen (noch nicht beauftragt), Material reservieren und die Bestellungen freigeben - bevorzugt
## beim Grosslager, sonst beim guenstigsten Anbieter. Geliefert wird per Lkw ins Stadtlager.
func _procure(k: int, a: Dictionary) -> String:
	var M: Mayor = sim.towns.mayor(k)
	var D: CityDepot = sim.towns.depot(k)
	var t: Dictionary = TEMPLATES[a.template]
	var vote := M.civic_vote(str(t.get("vote", "oeffentlich_bau")), float(a.cost))
	if not vote.passed:
		a.status = "abgelehnt"
		a["vote"] = vote.text
		stats.abgelehnt = int(stats.abgelehnt) + 1
		_learn(k, str(t.cat), -0.15, "Der Rat hat %s abgelehnt (%s)." % [a.title, Catalog.money(float(a.cost))])
		return "%s vom Rat abgelehnt" % a.title
	var prj := M.add_civic_project(a.id, [a.parcel], float(a.cost), int(t.days), a.materials, "%s: %s" % [a.title, a.reason])
	a.project = prj.id
	a.status = "material"
	a["vote"] = vote.text
	sim.parcels.parcel(a.parcel).state = "reserviert"
	D.reserve_for_project(prj.id, a.materials, "ueberlassen")
	var n := 0
	for o in D.orders.values():
		if str(o.get("project", "")) == prj.id and o.status == "vorschlag":
			o["prefer"] = CentralHub.ACCT
			var ar: Dictionary = D.approve(str(o.id), "Bürgermeister %s im Großlager" % M.name, "Material für %s" % a.title)
			if ar.ok:
				n += 1
			else:
				a["procure_note"] = str(ar.msg)
	anlage_changed.emit(a.id)
	return "%s: Material reserviert, %d Bestellungen freigegeben%s" % [a.title, n, (" (" + str(a.get("procure_note", "")) + ")") if a.has("procure_note") else ""]


## Nach der Rueckkehr: Projekt beauftragen (Ausschreibung, Baufirma, Bautrupp; gebaut wird, sobald das Material im Stadtlager ist).
func _commission(k: int, a: Dictionary) -> void:
	var M: Mayor = sim.towns.mayor(k)
	var prj: Dictionary = M.projects.get(a.project, {})
	if prj.is_empty():
		return
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": _today() - 1, "bids": [], "by": "Bürgermeister %s" % M.name}
	a.status = "im_bau"
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	p.state = "im_bau"
	p.use = "anlage"
	p.project = a.project
	sim.parcels.touch(a.parcel)
	_note(k, "beauftragt %s (Projekt %s, Bauzeit etwa %d Tage)." % [a.title, a.project, int(TEMPLATES[a.template].days)])
	anlage_changed.emit(a.id)


## Taeglich: abgelehnte/abgebrochene Projekte erkennen, Baufortschritt fuer die Darstellung.
func _follow_projects() -> void:
	for a in anlagen.values():
		if a.status != "im_bau":
			continue
		var e: Dictionary = sim.construction.public.get(a.project, {})
		if not e.is_empty():
			a["progress"] = clampf(1.0 - float(e.days_left) / maxf(1.0, float(e.days)), 0.0, 1.0)
			anlage_changed.emit(a.id)


## Abnahme (Construction._finish_public): Boden, Bauteile, echtes Gebaeude, Wirkung, Kommentare der Nachbarn.
func on_finished(prj: Dictionary) -> void:
	var a: Dictionary = {}
	for x in anlagen.values():
		if x.project == prj.id:
			a = x
	if a.is_empty():
		return
	var k := int(a.town)
	var t: Dictionary = TEMPLATES[a.template]
	a.status = "eroeffnet"
	a.opened = _today()
	a.progress = 1.0
	a.approval_at_open = sim.towns.mayor(k).approval
	_apply_ground(a)
	for pc in a.pieces:
		if str(pc.sprite).begins_with("#"):
			var b: Dictionary = sim.events._add_building(str(pc.sprite).substr(1), Rect2i(int(pc.x), int(pc.y), int(pc.w), int(pc.h)), "%s %s" % [t.label if not t.has("pieces") or t.pieces.is_empty() else "Brunnen", sim.towns.name_of(k)])
			if not b.is_empty():
				b["town"] = k
				pc["building"] = int(b.id)
				sim.events.buildings_added.emit([b.id])
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	p.state = "bebaut"
	sim.parcels.touch(a.parcel)
	stats.eroeffnet = int(stats.eroeffnet) + 1
	_note(k, "eröffnet %s. %s" % [a.title, _effect_text(a)], "good")
	sim.activity.add("stadt", -1, "bau", "Eröffnung: %s in %s" % [a.title, sim.towns.name_of(k)], _mayor_label(k), sim.city.tile_center(Vector2i(int(a.rect[0]), int(a.rect[1]))))
	if str(t.cat) == "prestige":
		_monument_reactions(a)
	elif int(t.get("rank", 0)) == 0 and str(t.cat) in ["markt", "sport"]:
		for j in profiles:
			if int(j) != k and float(profiles[j].weights.get(t.cat, 1.0)) >= 1.5:
				profiles[j].weights[t.cat] = minf(2.2, float(profiles[j].weights[t.cat]) + 0.1)   # Konkurrenz: wir wollen das auch, nur groesser
				_comment(int(j), k, "%s in %s? Wir bauen bald etwas Größeres." % [a.title, sim.towns.name_of(k)])
	anlage_changed.emit(a.id)


func _apply_ground(a: Dictionary) -> void:
	var t: Dictionary = TEMPLATES[a.template]
	var g := str(t.ground)
	if g == "":
		return
	var gt: int = {"sand": CityData.G.SAND, "park": CityData.G.PARK, "plaza": CityData.G.PLAZA, "concrete": CityData.G.CONCRETE}[g]
	var cells: Array = []
	var C: CityData = sim.city
	for y in range(int(a.rect[1]), int(a.rect[1]) + int(a.rect[3])):
		for x in range(int(a.rect[0]), int(a.rect[0]) + int(a.rect[2])):
			var q := Vector2i(x, y)
			if C.building_at[C.idx(q)] == -1 and C.g(q) not in [CityData.G.ROAD, CityData.G.WATER]:
				C.ground[C.idx(q)] = gt
				cells.append(q)
	ground_changed.emit(cells)


# ------------------------------------------------------------------ Wirkung
## Zustimmungsbeitrag der eroeffneten Anlagen einer Stadt (Mayor._update_approval): Bedarf gedeckt = Zuspruch; Prunk bei fehlender
## Grundversorgung = Unmut.
func approval_bonus(k: int) -> float:
	var b := 0.0
	var ana := {}
	for a in anlagen.values():
		if int(a.town) != k or a.status != "eroeffnet":
			continue
		var t: Dictionary = TEMPLATES[a.template]
		if str(t.cat) == "prestige":
			if ana.is_empty():
				ana = analyze(k)
			b += -4.0 if bool(ana.dringend) or float(t.cost) > float(sim.towns.mayor(k).available_budget()) * 2.0 else 1.5
		else:
			b += 2.5
	return clampf(b, -12.0, 15.0)


## Zuzugsfaktor fuer Familien (Spielplaetze, Parks, Kindergaerten, Schulen).
func family_factor(k: int) -> float:
	var f := 1.0
	for a in anlagen.values():
		if int(a.town) == k and a.status == "eroeffnet" and str(a.cat) in ["familie", "bildung", "gruen"]:
			f += 0.05
	return minf(f, 1.4)


## Anziehungskraft fuer Besucher (Denkmaeler, Stadion, Marktplatz): zusaetzliche Gaeste in den Hotels der Stadt.
func attraction(k: int) -> int:
	var n := 0
	for a in anlagen.values():
		if int(a.town) == k and a.status == "eroeffnet":
			n += int(TEMPLATES[a.template].get("rank", 0)) + (2 if a.template == "stadion" else 0) + (1 if str(a.cat) == "markt" else 0)
	return mini(n, 8)


func _effect_text(a: Dictionary) -> String:
	match str(a.cat):
		"prestige":
			return "Besucher kommen (Anziehung %d); die Bürger beobachten die Kosten." % attraction(int(a.town))
		"familie", "bildung":
			return "Familien ziehen lieber hierher (Faktor %.2f)." % family_factor(int(a.town))
		"markt":
			return "Händler bieten jetzt Waren an; mehr Gäste in der Stadt."
		"sport":
			return "Mehr Freizeitwert, die Vereine trainieren."
	return "Mehr Lebensqualität im Viertel."


# ------------------------------------------------------------------ Lernen, Wettstreit, Kommentare
## Erfolgskontrolle: einige Tage nach der Eroeffnung Zustimmung und Bedarf vergleichen und die Vorliebe der Kategorie anpassen.
func _evaluate(k: int) -> void:
	for a in anlagen.values():
		if int(a.town) != k or a.status != "eroeffnet" or bool(a.evaluated) or _today() - int(a.opened) < EVAL_DAYS:
			continue
		a.evaluated = true
		var delta: float = sim.towns.mayor(k).approval - float(a.approval_at_open)
		var ok := delta >= -3.0   # kleine Schwankungen haben meist andere Ursachen (Arbeit, Wohnungen)
		var lesson := "%s: Zustimmung %+.1f Punkte seit der Eröffnung – %s." % [a.title, delta, "bewährt, gern wieder" if ok else "kam schlecht an, künftig zurückhaltender"]
		_learn(k, str(a.cat), 0.1 if ok else -0.15, lesson)
		a["result"] = lesson


func _learn(k: int, cat: String, step: float, lesson: String) -> void:
	var P: Dictionary = profiles[k]
	P.weights[cat] = clampf(float(P.weights.get(cat, 1.0)) + step, 0.3, 2.4)
	P.lessons.append({"day": _today(), "text": lesson})
	P.lessons = P.lessons.slice(-12)
	_note(k, "lernt: %s" % lesson)
	# Vision anpassen, wenn eine Kategorie klar dominiert oder die bisherige Linie scheitert
	var top := ""
	var top_w := 0.0
	for c in P.weights:
		if float(P.weights[c]) > top_w:
			top_w = float(P.weights[c])
			top = c
	if step < 0.0 and cat == "prestige" and float(P.weights.prestige) < 1.2 and str(P.vision).contains("Denkm"):
		P.vision = "Weniger Prunk, mehr Nutzen: %s für die Bürger." % CAT_LABEL[top]
		_note(k, "ändert die Linie: %s" % P.vision)


func _monument_reactions(a: Dictionary) -> void:
	var k := int(a.town)
	var rank := int(TEMPLATES[a.template].get("rank", 0))
	for j in profiles:
		if int(j) == k:
			continue
		var P: Dictionary = profiles[j]
		var lines: Array = COMMENTS.get(P.persona, COMMENTS.wirtschaft)
		var text: String = lines[(int(a.seed) + int(j)) % lines.size()]
		_comment(int(j), k, "Zu %s in %s: %s" % [a.title, sim.towns.name_of(k), text])
		if float(P.eitel) >= 0.35:
			P.target_rank = maxi(int(P.target_rank), rank + 1)
	var M: Mayor = sim.towns.mayor(k)
	_comment(k, -1, "Ein Denkmal für die Ewigkeit – %s hat %s bekommen, was es verdient." % [sim.towns.name_of(k), a.title])


func _comment(from_k: int, about: int, text: String) -> void:
	comments.append({"day": _today(), "from": from_k, "about": about, "text": text})
	comments = comments.slice(-60)
	sim.log_event("%s: „%s“" % [_mayor_label(from_k), text], "info")
	if sim.get("news") != null and sim.news.has_method("add"):
		sim.news.add("Rathaus %s" % sim.towns.name_of(from_k), text)


# ------------------------------------------------------------------ Beobachtung (LLM-Buergermeister) und Fenster
func mayor_obs(k: int) -> Dictionary:
	if not enabled():
		return {}
	var P: Dictionary = profiles[k]
	var ana := analyze(k)
	var cat_list := {}
	for tid in TEMPLATES:
		var t: Dictionary = TEMPLATES[tid]
		cat_list[tid] = "%s (%s, %d×%d Felder, %s, %d Tage)" % [t.label, CAT_LABEL[t.cat], int(t.w), int(t.h), Catalog.money(float(t.cost)), int(t.days)]
	var own: Array = anlagen.values().filter(func(a): return int(a.town) == k).slice(-6).map(func(a): return "%s: %s (%s)" % [a.id, a.title, a.status])
	var rivals: Array = anlagen.values().filter(func(a): return int(a.town) != k and a.status in ["im_bau", "eroeffnet"]).slice(-6).map(func(a): return "%s baut %s (%s)" % [sim.towns.name_of(int(a.town)), a.title, a.status])
	return {"persoenlichkeit": PERSONAS[P.persona].label, "vision": P.vision, "bedarf": ana.bedarf, "kinder_geschaetzt": ana.kinder_geschaetzt,
		"naechster_besuch_grosslager_tag": int(P.next_visit), "eigene_anlagen": own, "andere_staedte": rivals,
		"vorgemerkte_ideen": proposals.get(k, []).map(func(i): return i.project), "lernerfahrungen": P.lessons.slice(-4).map(func(l): return l.text),
		"bauvorlagen": cat_list, "grosslager_knapp": sim.hub.summary().get("waren", []).filter(func(w): return w.knapp).map(func(w): return w.artikel) if sim.hub.enabled else [],
		"hinweis": "Eigene Bauideen mit propose_project (project, category, reason, priority, desiredDistrict, features, size). Die Engine wählt Bauvorlage, Standort und Material; entschieden wird beim Besuch im Großlager."}


## Daten fuer das Buergermeisterfenster.
func window(k: int) -> Dictionary:
	if not enabled() or not profiles.has(k):
		return {}
	var P: Dictionary = profiles[k]
	var M: Mayor = sim.towns.mayor(k)
	var D: CityDepot = sim.towns.depot(k)
	var mine: Array = anlagen.values().filter(func(a): return int(a.town) == k)
	var orders: Array = []
	for o in D.orders.values():
		if str(o.get("project", "")) != "" and mine.any(func(a): return a.project == str(o.project)) and o.status not in ["bezahlt", "abgelehnt"]:
			orders.append("%d × %s (%s, %s)" % [int(o.qty), CityGoods.get_item(o.item).name, o.status, "Großlager" if o.supplier == CentralHub.ACCT else str(o.supplier)])
	var tr: Dictionary = trips.get(k, {})
	return {"name": M.name, "stadt": sim.towns.name_of(k), "persoenlichkeit": PERSONAS[P.persona].label, "vision": P.vision, "farbe": P.color,
		"zustimmung": snappedf(M.approval, 0.1), "kasse": int(M.cash()), "verfuegbar": int(M.available_budget()),
		"unterwegs": {"wartet": "bereitet den Besuch vor", "hinfahrt": "fährt zum Großlager", "im_lager": "ist im Großlager", "rueckfahrt": "fährt zurück"}.get(str(tr.get("phase", "")), "im Rathaus"),
		"naechster_besuch": int(P.next_visit), "projekte": mine.map(func(a): return {"titel": a.title, "status": a.status, "grund": a.reason, "fortschritt": float(a.get("progress", 0.0)),
			"ergebnis": a.get("result", ""), "herkunft": a.origin}), "bestellungen": orders, "lernen": P.lessons.slice(-3).map(func(l): return l.text),
		"verlauf": log.filter(func(e): return int(e.town) == k).slice(-6).map(func(e): return "Tag %d: %s" % [int(e.day), e.text])}


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	var tr := {}
	for k in trips:
		tr[str(k)] = {"phase": trips[k].phase, "plan": trips[k].plan, "day": trips[k].get("day", 0), "until": trips[k].get("until", 0.0)}
	var pr := {}
	for k in profiles:
		pr[str(k)] = profiles[k]
	var pp := {}
	for k in proposals:
		pp[str(k)] = proposals[k]
	return {"profiles": pr, "anlagen": anlagen, "proposals": pp, "trips": tr, "log": log.slice(-120), "comments": comments, "stats": stats, "next": _next}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or not enabled():
		return
	profiles = {}
	for k in d.get("profiles", {}):
		profiles[int(k)] = d.profiles[k]
	anlagen = d.get("anlagen", {})
	proposals = {}
	for k in d.get("proposals", {}):
		proposals[int(k)] = d.proposals[k]
	trips = {}
	for k in d.get("trips", {}):
		var t: Dictionary = d.trips[k]
		# Fahrzeuge werden nicht gespeichert: laufende Fahrten setzen am naechsten sinnvollen Punkt fort
		match str(t.phase):
			"hinfahrt", "im_lager":
				t.phase = "im_lager"
				t.until = sim.game_min
			"rueckfahrt":
				t.phase = "rueckfahrt"
		trips[int(k)] = t
	log = d.get("log", [])
	comments = d.get("comments", [])
	stats.merge(d.get("stats", {}), true)
	_next = int(d.get("next", 1))
	for a in anlagen.values():
		if a.status == "eroeffnet":
			_apply_ground(a)
