class_name BuildingDesigns
extends RefCounted
## Bauentwuerfe sind Daten, keine neuen Gebaeudearten. Die Basisart bleibt fuer Zone,
## Lieferverkehr und Betrieb gueltig; das Sprite und die Ausstattung gehoeren zum Entwurf.

static var _catalog: Dictionary = {}
static var _by_base: Dictionary = {}


static func all() -> Dictionary:
	if _catalog.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://config/building_designs.json"))
		if data is Dictionary:
			for entry in data.get("designs", []):
				if not entry is Dictionary:
					continue
				var id := str(entry.get("id", ""))
				if id != "":
					_catalog[id] = entry
					var base := str(entry.get("base", ""))
					if not _by_base.has(base):
						_by_base[base] = []
					_by_base[base].append(entry)
	return _catalog


static func design(id: String) -> Dictionary:
	return all().get(id, {})


static func valid_for(id: String, base: String) -> bool:
	return id == "" or str(design(id).get("base", "")) == base


## Belegte Wohnungen bestimmen die Grundlast der Stadt. Altbauten ohne Entwurf
## bleiben bei Faktor 1; Ausstattung neuer Häuser verändert den Bedarf messbar.
static func residential_factor(sim, town: int, field: String) -> float:
	if sim.housing == null:
		return 1.0
	var total := 0.0
	var count := 0
	for u in sim.housing.units.values():
		if str(u.get("tenant", "")) == "" or sim.towns.of_building(int(u.building)) != town:
			continue
		var b: Dictionary = sim.city.building(int(u.building))
		total += float(b.get(field, 1.0))
		count += 1
	return clampf(total / float(count), 0.65, 1.25) if count > 0 else 1.0


static func options(base: String, city_style: String = "") -> Array:
	all()
	var choices: Array = _by_base.get(base, [])
	if city_style == "":
		return choices
	return choices.filter(func(d): return str(d.style) == city_style)


## Eine kleine, wirtschaftlich lesbare Auswahlliste fuer die lokale KI.
static func shortlist(base: String, city_style: String, budget: float = INF) -> Array:
	var out: Array = []
	for d in options(base, city_style):
		var floors := 3 if base == "mehrfamilienhaus" else int(Planning.def(base).get("floors", [1])[0])
		var cost := Planning.build_cost(base, floors) * float(d.cost_factor)
		if cost <= budget:
			out.append({"id": d.id, "typ": base, "name": d.label, "funktion": d.get("function", "wohnen"),
				"kosten": int(cost), "komfort": int(d.comfort), "attraktivitaet": float(d.appeal),
				"ausstattung": d.amenities, "wohnflaeche": int(d.get("area", 0)), "energiebedarf": float(d.energy_factor)})
	return out


## Der Bautraeger bzw. der KI-Fallback waehlt reproduzierbar nach Stadtmarke,
## Kapital und Bedarf. Der Seed rotiert zwischen Silhouetten und Ausstattungen.
static func pick(base: String, city_style: String, seed: int, budget: float = INF, demand: float = 0.5, recent: Array = []) -> Dictionary:
	var pool := options(base, city_style)
	if pool.is_empty():
		pool = options(base)
	var affordable: Array = []
	for d in pool:
		var floors := int(Planning.def(base).get("floors", [1])[0])
		if Planning.build_cost(base, floors) * float(d.cost_factor) <= budget:
			affordable.append(d)
	if affordable.is_empty():
		return {}
	var choice: Dictionary = {}
	var best := -INF
	for d in affordable:
		var variety := float(posmod(seed * 17 + int(str(d.id).right(3)) * 13, 101)) / 101.0
		var score := variety * 0.55 + float(d.appeal) * 0.25 + float(d.comfort) / 100.0 * demand * 0.20 - (float(d.cost_factor) - 1.0) * (1.0 - demand) * 0.55
		var last_use: int = recent.rfind(str(d.id))
		if last_use >= 0:
			score -= 0.8 + 0.25 * float(last_use + 1) / float(recent.size())
		if score > best:
			best = score
			choice = d
	return choice
