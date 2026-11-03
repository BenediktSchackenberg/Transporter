class_name DispatchCandidates
extends RefCounted
## Gueltige Zuweisungen "freies Fahrzeug -> offener Marktauftrag" als nummerierte Kandidatenliste (reine Regeln, testbar).
## Der Disponent (Claude) waehlt nur aus dieser Liste; jede Wahl prueft der ActionExecutor erneut. Gleiche Filter wie die
## Regel-KI (Kapazitaet, Kuehlung, Schwerlast, Ruf, Frist), damit nie etwas vorgeschlagen wird, das ohnehin scheitern wuerde.

const PER_VEHICLE := 3          # beste Kandidaten je Fahrzeug
const MIN_MARGIN := 150.0       # Kandidaten mit weniger Marge (EUR) werden nicht angeboten
const MIN_MARGIN_SHARE := 0.10  # ... oder weniger als 10 % der Verguetung


## obs: Beobachtung der Firma (ObservationBuilder). first_nr: laufende Nummer, ab der gezaehlt wird.
## Liefert {vehicles:[...], candidates:[{nr, vehicle_id, contract_id, ...}], slots_left}.
static func build(obs: Dictionary, first_nr: int = 1) -> Dictionary:
	var out := {"vehicles": [], "candidates": [], "slots_left": 0}
	if obs.is_empty() or not obs.has("ich"):
		return out
	var me: Dictionary = obs.ich
	var models: Dictionary = obs.fahrzeugmodelle
	var load: PackedStringArray = str(me.buero.laufende_auftraege).split("/")
	var slots := load[1].to_int() - load[0].to_int()
	out.slots_left = slots
	if slots <= 0:
		return out
	var ready: Array = obs.fahrzeuge.filter(func(v): return v.status in ["bereit", "fährt zum Depot"] \
		and str(v.get("linie", "")) == "" and v.warteschlange.is_empty() and v.fahrer != null and int(v.zustand) >= 45)
	var taken := {}
	var nr := first_nr
	for v in ready:
		var spec: Dictionary = models[v.modell]
		out.vehicles.append({"id": int(v.id), "modell": v.modell, "kapazitaet": int(spec.kapazitaet), "kuehlung": bool(spec.kuehlung), "schwer": bool(spec.schwer)})
		var pool: Array = obs.markt.filter(func(k): return not taken.has(k.id))
		for i in PER_VEHICLE:
			var best := RuleBrain._best_contract(pool, v, spec, float(me.reputation))
			if best.is_empty():
				break
			pool.erase(best)
			var tiles := float(best.strecke) + RuleBrain._dist(best.von_pos, v.pos)
			var revenue := float(best.verguetung) + float(best.get("praemie_stadt", 0))
			var margin := revenue - tiles * float(spec.kosten_pro_tile) * 1.1
			if margin < maxf(MIN_MARGIN, MIN_MARGIN_SHARE * revenue):
				continue   # lohnt nicht: gar nicht erst zur Wahl stellen
			out.candidates.append({"nr": nr, "vehicle_id": int(v.id), "contract_id": str(best.id), "ware": str(best.get("bezeichnung", "")),
				"menge": int(best.menge), "verguetung": int(revenue), "strecke_kacheln": int(tiles), "frist_min": int(best.frist_in_min), "angebot_noch_min": int(best.get("angebot_noch_min", -1)),
				"marge": int(margin), "score": snappedf(margin / (tiles + 30.0), 0.01)})
			nr += 1
	return out


## Regelwahl: je Fahrzeug der Kandidat mit dem besten Score, jeder Auftrag nur einmal, hoechstens `limit` Zuweisungen.
static func rule_pick(cands: Array, limit: int) -> Array:
	var sorted := cands.duplicate()
	sorted.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var used_v := {}
	var used_c := {}
	var picks: Array = []
	for c in sorted:
		if used_v.has(c.vehicle_id) or used_c.has(c.contract_id) or picks.size() >= limit:
			continue
		used_v[c.vehicle_id] = true
		used_c[c.contract_id] = true
		picks.append(int(c.nr))
	return picks
