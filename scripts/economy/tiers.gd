class_name Tiers
extends RefCounted
## Wohnstufen und Bedürfnisse (Auftrag 8, siehe docs/GROWTH_TIERS.md).
##
## Jede belegte Wohneinheit hat eine Stufe 1-4. Mit der Stufe wachsen die Ansprüche: Stufe 1 braucht Grundnahrung und Getränke, Stufe 2
## zusätzlich Haushaltswaren, Gesundheit und Bildung, Stufe 3 Gastronomie und Möbel, Stufe 4 Technik. Ob ein Bedürfnis im Viertel gedeckt ist,
## folgt aus den Geschäften: Es gibt ein offenes Geschäft der passenden Art, und seine Regale waren im letzten Monat nicht leer
## (Verhältnis verkaufter zu entgangenen Kunden). Ware kommt per Transportauftrag in die Geschäfte (Retail), die Versorgung der Stadt ist
## also zugleich der Transportbedarf der Spediteure.
##
## Aufstieg: alle Bedürfnisse der nächsten Stufe zu mindestens UP_AT gedeckt, Zufriedenheit der Wohnung mindestens UP_SAT, das über UP_MONTHS
## Monate in Folge und das Gebäude erlaubt die Stufe. Abstieg: ein Bedürfnis der eigenen Stufe liegt DOWN_MONTHS Monate unter DOWN_AT.
## Wirkung: Miete (+-15 % je Stufe um Stufe 2), Konsum (+-10 % je Stufe) und Nachfrage nach gehobenen Geschäften (Restaurant, Möbel, Technik).

const MAX_TIER := 4
const UP_AT := 0.75
const DOWN_AT := 0.40
const UP_SAT := 50.0
const UP_MONTHS := 2
const DOWN_MONTHS := 3
const MIN_PERSONS_FOR_SHOP := 60  # so viele Bewohner braucht ein Viertel für ein neues Geschäft
const NO_LOCAL_BELOW := 0.7        # unter dieser Deckung fehlt ein Geschäft im Viertel (nur Fernversorgung zählt höchstens FAR_FACTOR)
const FAR_FACTOR := 0.6            # Bedürfnis nur außerhalb des Viertels gedeckt: so viel zählt es
const RENT_STEP := 0.15
const SPEND_STEP := 0.10

const TIER_NAMES := {1: "Einfache Haushalte", 2: "Familien", 3: "Bürger", 4: "Wohlhabende"}
## Höchste Stufe je Gebäudeart und Startstufe
const CAP := {"apartment": 3, "house": 3, "semi": 3, "highrise": 4, "villa": 4}
const START := {"apartment": 2, "house": 2, "semi": 2, "highrise": 2, "villa": 3}

## Bedürfnis: Stufe, Geschäftsarten (Retail.KINDS) oder Gebäudearten, Ladung für die Anlieferung
const NEEDS := [
	{"id": "nahrung", "label": "Grundnahrung", "tier": 1, "kinds": ["lebensmittel", "baeckerei"], "cargo": "lebensmittel"},
	{"id": "getraenke", "label": "Getränke", "tier": 1, "kinds": ["getraenke", "lebensmittel"], "cargo": "getraenke"},
	{"id": "haushalt", "label": "Haushaltswaren", "tier": 2, "kinds": ["drogerie", "baumarkt"], "cargo": "pakete"},
	{"id": "gesundheit", "label": "Gesundheit", "tier": 2, "buildings": ["clinic", "pharmacy"], "cargo": "medikamente"},
	{"id": "bildung", "label": "Bildung und Betreuung", "tier": 2, "buildings": ["school", "kindergarten"], "cargo": ""},
	{"id": "gastro", "label": "Gastronomie", "tier": 3, "kinds": ["restaurant"], "cargo": "lebensmittel"},
	{"id": "wohnen", "label": "Möbel und Einrichtung", "tier": 3, "kinds": ["moebel"], "cargo": "moebel"},
	{"id": "technik", "label": "Technik", "tier": 4, "kinds": ["technik"], "cargo": "elektronik"},
]
## Ab welcher Stufe fragen Bewohner ein Geschäft überhaupt nach (Nachfragefaktor, siehe demand_factor)
const KIND_TIER := {"restaurant": 3, "moebel": 3, "technik": 4}

var sim: Simulation
var coverage := {}                 # Viertelindex (str) -> {Bedürfnis-ID: 0..1}
var mix := {}                      # Viertelindex (str) -> {"personen": n, "stufen": {1: n, ..}, "mittel": x}
var _snap := {}                    # Geschäft -> {units, lost} Stand zum letzten Monatswechsel
var stats := {"up": 0, "down": 0}
var history: Array = []            # Monatsberichte (max. 24)


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


# ------------------------------------------------------------------ Einheiten
static func cap_of(building_type: String) -> int:
	return int(CAP.get(building_type, 3))


func tier_of(u: Dictionary) -> int:
	if not u.has("tier"):
		var t: String = str(sim.city.building(int(u.building)).get("type", "house"))
		var start := int(START.get(t, 2))
		if start == 2 and (str(u.id).hash() % 100) < 30:
			start = 3   # ein Teil der Haushalte startet gehoben, sonst fehlt gehobenen Geschäften die Kundschaft
		u["tier"] = mini(start, cap_of(t))
		u["up"] = 0
		u["down"] = 0
	return int(u.tier)


func _district_of(u: Dictionary) -> int:
	return int(sim.city.building(int(u.building)).get("district", 0))


func rent_factor(u: Dictionary) -> float:
	return 1.0 + RENT_STEP * float(tier_of(u) - 2)


# ------------------------------------------------------------------ Deckung
## Versorgungsgrad eines Geschäfts: verkaufte Kunden / (verkaufte + entgangene) im Zeitraum seit dem letzten Monatswechsel.
func shop_level(shop: Dictionary) -> float:
	if shop.status != "offen":
		return 0.0
	var snap: Dictionary = _snap.get(shop.id, {"units": 0, "lost": 0})
	var sold := float(int(shop.units) - int(snap.units))
	var lost := float(int(shop.lost) - int(snap.lost))
	if sold + lost < 3.0:
		return 1.0 if lost <= 0.0 else 0.5   # kaum Kundschaft: kein Beleg für Mangel
	return clampf(sold / (sold + lost), 0.0, 1.0)


## Deckung des Bedürfnisses in einem Viertel: bestes Angebot im Viertel (voll) bzw. außerhalb (FAR_FACTOR).
func need_coverage(need: Dictionary, district: int) -> float:
	var best := 0.0
	if need.has("kinds"):
		for shop in sim.retail.shops.values():
			if not need.kinds.has(shop.kind):
				continue
			var d := int(sim.city.building(int(shop.building)).get("district", 0))
			best = maxf(best, shop_level(shop) * (1.0 if d == district else FAR_FACTOR))
	else:
		for b in sim.city.buildings:
			if need.buildings.has(b.type):
				var d2 := int(b.get("district", 0))
				best = maxf(best, 1.0 if d2 == district else FAR_FACTOR)
	return best


func coverage_of(district: int, need_id: String) -> float:
	return float(coverage.get(str(district), {}).get(need_id, 1.0))


func _recompute_coverage() -> void:
	coverage = {}
	for d in Catalog.DISTRICTS.size():
		var c := {}
		for need in NEEDS:
			c[need.id] = snappedf(need_coverage(need, d), 0.01)
		coverage[str(d)] = c


# ------------------------------------------------------------------ Monat
func on_month(month: int) -> void:
	_recompute_coverage()
	var occ: Dictionary = sim.housing._citizen_occupants()
	var ups := {}
	var downs := {}
	for u in sim.housing.units.values():
		if u.tenant != "":
			_update_unit(u, ups, downs)
	_recompute_mix(occ)
	_expand_supply()
	_log_changes(ups, downs)
	for shop in sim.retail.shops.values():
		_snap[shop.id] = {"units": int(shop.units), "lost": int(shop.lost)}
	history.append({"monat": month, "mittel": snappedf(city_mean(), 0.01), "auf": ups.values().reduce(func(a, b): return a + b, 0),
		"ab": downs.values().reduce(func(a, b): return a + b, 0)})
	if history.size() > 24:
		history.pop_front()


## Marktzutritt: Fehlt in einem Viertel mit genug Bewohnern jedes Geschäft einer benötigten Art, eröffnet in einem passenden leeren
## Ladengebäude des Viertels ein neues (höchstens eines je Viertel und Monat). Fehlt dagegen nur Ware, ist das Sache der Transporteure.
func _expand_supply() -> void:
	for d in Catalog.DISTRICTS.size():
		var m: Dictionary = mix.get(str(d), {})
		if m.is_empty() or int(m.personen) < MIN_PERSONS_FOR_SHOP:
			continue
		for need in missing(d, NO_LOCAL_BELOW):
			if not need.has("kinds"):
				continue
			var b := _free_building(d, need.kinds)
			if b.is_empty():
				continue
			var kind: String = Retail.kind_for(b)
			sim.retail.open_shop(b, kind)
			sim.log_event("%s: Neues Geschäft %s (%s) – %s wurde im Viertel nachgefragt." % [Catalog.DISTRICTS[d], b.name, Retail.KINDS[kind].label, need.label], "good")
			break


func _free_building(district: int, kinds: Array) -> Dictionary:
	for b in sim.city.buildings:
		if b.role != "customer" or int(b.get("district", 0)) != district:
			continue
		var kind := Retail.kind_for(b)
		if kind != "" and kinds.has(kind) and sim.retail.shop_of_building(int(b.id)).is_empty():
			return b
	return {}


## Stufenwechsel einer Einheit aus der Deckung ihres Viertels (ups/downs zählen die Wechsel je Viertel).
func _update_unit(u: Dictionary, ups: Dictionary, downs: Dictionary) -> void:
	var d := _district_of(u)
	var tier := tier_of(u)
	var btype: String = str(sim.city.building(int(u.building)).get("type", "house"))
	var sat := float(u.get("sat", 50.0))
	var lower_ok := true
	for need in NEEDS:
		if int(need.tier) <= tier and coverage_of(d, need.id) < DOWN_AT:
			lower_ok = false
	u["down"] = 0 if lower_ok else int(u.get("down", 0)) + 1
	var next_ok := tier < cap_of(btype) and sat >= UP_SAT
	if next_ok:
		for need in NEEDS:
			if int(need.tier) <= tier + 1 and coverage_of(d, need.id) < UP_AT:
				next_ok = false
				break
	u["up"] = int(u.get("up", 0)) + 1 if next_ok else 0
	if int(u.up) >= UP_MONTHS:
		u.tier = tier + 1
		u.up = 0
		u.down = 0
		ups[d] = int(ups.get(d, 0)) + 1
		stats.up += 1
	elif int(u.down) >= DOWN_MONTHS and tier > 1:
		u.tier = tier - 1
		u.up = 0
		u.down = 0
		downs[d] = int(downs.get(d, 0)) + 1
		stats.down += 1


func _log_changes(ups: Dictionary, downs: Dictionary) -> void:
	for d in ups:
		sim.log_event("%s: %d Haushalte steigen auf (Bedürfnisse gedeckt)." % [Catalog.DISTRICTS[d], int(ups[d])], "good")
	for d in downs:
		sim.log_event("%s: %d Haushalte sinken ab (%s)." % [Catalog.DISTRICTS[d], int(downs[d]), ", ".join(missing_labels(d))], "bad")


func _recompute_mix(occ: Dictionary) -> void:
	mix = {}
	for u in sim.housing.units.values():
		if u.tenant == "":
			continue
		var d := str(_district_of(u))
		if not mix.has(d):
			mix[d] = {"personen": 0, "stufen": {1: 0, 2: 0, 3: 0, 4: 0}, "summe": 0.0}
		var persons: int = occ.get(u.id, []).size() if u.tenant == "B" else 2
		var t := tier_of(u)
		mix[d].personen += persons
		mix[d].stufen[t] += persons
		mix[d].summe += float(t * persons)
	for d in mix:
		mix[d]["mittel"] = snappedf(float(mix[d].summe) / maxf(1.0, float(mix[d].personen)), 0.01)


func city_mean() -> float:
	var s := 0.0
	var n := 0
	for d in mix:
		s += float(mix[d].summe)
		n += int(mix[d].personen)
	return s / float(n) if n > 0 else 2.0


## Anteil der Bewohner eines Viertels mit mindestens dieser Stufe (ohne Bewohner: Stadtschnitt).
func share_at_least(district: int, tier: int) -> float:
	var m: Dictionary = mix.get(str(district), {})
	if m.is_empty() or int(m.personen) <= 0:
		return 0.5 if tier <= 3 else 0.2
	var n := 0
	for t in range(tier, MAX_TIER + 1):
		n += int(m.stufen[t])
	return float(n) / float(m.personen)


# ------------------------------------------------------------------ Wirkung
## Konsumfaktor des Viertels (+-10 % je Stufe um Stufe 2).
func spend_factor(district: int) -> float:
	var m: Dictionary = mix.get(str(district), {})
	var mean_tier: float = float(m.get("mittel", 2.0)) if not m.is_empty() else 2.0
	return 1.0 + SPEND_STEP * (mean_tier - 2.0)


## Nachfragefaktor eines Geschäfts: gehobene Angebote (Restaurant, Möbel, Technik) leben von höheren Stufen im Viertel.
func demand_factor(shop: Dictionary) -> float:
	if mix.is_empty():
		return 1.0
	var d := int(sim.city.building(int(shop.building)).get("district", 0))
	var f := spend_factor(d)
	var min_tier := int(KIND_TIER.get(shop.kind, 1))
	if min_tier > 1:
		f *= clampf(0.75 + 0.6 * share_at_least(d, min_tier), 0.75, 1.35)
	return f


## Welche Bedürfnisse der im Viertel vertretenen Stufen sind schlecht gedeckt (für Meldungen und KI).
func missing(district: int, below: float = UP_AT) -> Array:
	var out: Array = []
	var top := 1
	var m: Dictionary = mix.get(str(district), {})
	if not m.is_empty():
		for t in range(1, MAX_TIER + 1):
			if int(m.stufen[t]) > 0:
				top = t
	for need in NEEDS:
		if int(need.tier) <= mini(top + 1, MAX_TIER) and coverage_of(district, need.id) < below:
			out.append(need)
	return out


func missing_labels(district: int) -> Array:
	return missing(district, DOWN_AT).map(func(n): return n.label)


# ------------------------------------------------------------------ Auskunft
func summary() -> Dictionary:
	var out := {}
	for d in Catalog.DISTRICTS.size():
		var m: Dictionary = mix.get(str(d), {})
		if m.is_empty():
			continue
		out[Catalog.DISTRICTS[d]] = {
			"personen": int(m.personen), "stufen": m.stufen.duplicate(), "mittel": float(m.mittel),
			"deckung": coverage.get(str(d), {}).duplicate(),
			"fehlt": missing(d).map(func(n): return {"bedarf": n.label, "ware": n.cargo, "deckung": coverage_of(d, n.id), "stufe": n.tier})}
	return out


func to_dict() -> Dictionary:
	return {"coverage": coverage, "mix": mix, "snap": _snap, "stats": stats, "history": history}


func from_dict(d: Dictionary) -> void:
	coverage = d.get("coverage", {})
	mix = {}
	for k in d.get("mix", {}):
		var m: Dictionary = d.mix[k].duplicate(true)
		var st := {}
		for t in m.get("stufen", {}):
			st[int(t)] = int(m.stufen[t])
		m["stufen"] = st
		mix[str(k)] = m
	_snap = d.get("snap", {})
	stats = d.get("stats", stats)
	history = d.get("history", [])
