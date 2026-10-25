class_name Residents
extends RefCounted
## Kundenfiguren mit Namen, Rolle, Wohn-/Arbeitsort und Bedarf. Der Bedarf waechst aus Tageszeit, Oeffnungszeiten, Wetter und
## Ereignissen (Druck 0..1). Bei Druck >= 1 stellt die Figur eine Anfrage: ein echter Auftrag auf dem Markt (Contract.requester).
## Erfuellte Anliegen haben eine Sperrfrist; unerfuellte verschlechtern die Stimmung und werden hoechstens einmal dringlicher
## wiederholt. Nur Figuren mit offenem Anliegen oder frischem Ergebnis werden in der Stadt gezeigt (stehen am Eingang).

const FEMALE := ["Anna", "Lena", "Sophie", "Mia", "Hannah", "Elif", "Clara", "Marta", "Greta", "Yasmin", "Jule", "Nora"]
const MALE := ["Jonas", "Mehmet", "Lukas", "Paul", "Finn", "Emil", "Karl", "Tobias", "Ali", "Henrik", "Oskar", "Ben"]
const OPEN_MAX := 5                      # gleichzeitige offene Kundenanfragen: OPEN_MAX + 3 je Unternehmen
const COOLDOWN_DONE := [600.0, 1100.0]   # Spielminuten Sperrfrist nach erfuelltem Anliegen
const COOLDOWN_FAILED := 300.0
const SHOW_RESULT_MIN := 90.0            # so lange bleibt die Figur nach Erledigung sichtbar

## Bedarf je Gebaeudetyp: rate = Druck pro Spielstunde, rain/hot/cold = Wettermultiplikatoren, peak = Stunden mit doppeltem Druck
const PROFILES := {
	"house": {"role": ["Bewohnerin", "Bewohner"], "hours": [0, 24], "needs": [
		{"cargo": "moebel", "concern": "zieht um und braucht einen Möbeltransport", "q": [4, 12], "rate": 0.025},
		{"cargo": "pakete", "concern": "erwartet eine große Paketlieferung", "q": [2, 6], "rate": 0.04, "rain": 1.3}]},
	"apartment": {"role": ["Bewohnerin", "Bewohner"], "hours": [0, 24], "needs": [
		{"cargo": "moebel", "concern": "richtet eine neue Wohnung ein und braucht Möbel", "q": [5, 14], "rate": 0.03},
		{"cargo": "getraenke", "concern": "organisiert eine Hausfeier und braucht Getränkekisten", "q": [4, 10], "rate": 0.03, "hot": 1.8}]},
	"shop": {"role": ["Inhaberin", "Inhaber"], "hours": [8, 20], "needs": [
		{"cargo": "pakete", "concern": "hat leere Regale und wartet auf Ware", "q": [3, 12], "rate": 0.07, "rain": 1.2, "peak": [8, 10]},
		{"cargo": "getraenke", "concern": "hat zu wenig Getränke im Verkauf", "q": [5, 16], "rate": 0.05, "hot": 2.0},
		{"cargo": "lebensmittel", "concern": "braucht frische Ware für die Theke", "q": [4, 10], "rate": 0.05, "hot": 1.3, "peak": [8, 10]}]},
	"pharmacy": {"role": ["Apothekerin", "Apotheker"], "hours": [8, 19], "needs": [
		{"cargo": "medikamente", "concern": "braucht gekühlte Medikamente nachgeliefert", "q": [2, 7], "rate": 0.07, "cold": 1.3}]},
	"restaurant": {"role": ["Restaurantbetreiberin", "Restaurantbetreiber"], "hours": [11, 23], "needs": [
		{"cargo": "getraenke", "concern": "hat zu wenig Getränke", "q": [4, 14], "rate": 0.08, "hot": 2.0, "peak": [11, 14, 17, 21]},
		{"cargo": "lebensmittel", "concern": "braucht frisches Gemüse und Zutaten", "q": [3, 10], "rate": 0.07, "peak": [11, 14, 17, 21]}]},
	"office": {"role": ["Büroverwalterin", "Büroverwalter"], "hours": [8, 17], "needs": [
		{"cargo": "moebel", "concern": "organisiert einen Umzug in neue Büros", "q": [6, 16], "rate": 0.025},
		{"cargo": "elektronik", "concern": "braucht Technik für neue Arbeitsplätze", "q": [3, 9], "rate": 0.03},
		{"cargo": "pakete", "concern": "wartet auf dringende Unterlagen und Material", "q": [2, 6], "rate": 0.04}]},
	"school": {"role": ["Hausmeisterin", "Hausmeister"], "hours": [7, 16], "needs": [
		{"cargo": "moebel", "concern": "erwartet neue Schulmöbel", "q": [8, 20], "rate": 0.03},
		{"cargo": "pakete", "concern": "braucht Lehrmaterial für das neue Halbjahr", "q": [3, 8], "rate": 0.035}]},
	"kindergarten": {"role": ["Kindergartenleiterin", "Kindergartenleiter"], "hours": [7, 17], "needs": [
		{"cargo": "lebensmittel", "concern": "braucht eine Lebensmittellieferung für die Mittagsverpflegung", "q": [4, 10], "rate": 0.07, "hot": 1.2, "peak": [8, 10]},
		{"cargo": "getraenke", "concern": "braucht Getränke für das Sommerfest", "q": [3, 8], "rate": 0.03, "hot": 2.0}]},
	"clinic": {"role": ["Praxisleiterin", "Praxisleiter"], "hours": [0, 24], "needs": [
		{"cargo": "medikamente", "concern": "braucht Medikamente und Verbrauchsmaterial", "q": [2, 7], "rate": 0.07},
		{"cargo": "elektronik", "concern": "wartet auf medizinische Geräte", "q": [2, 5], "rate": 0.03}]},
	"factory": {"role": ["Fabrikmitarbeiterin", "Fabrikmitarbeiter"], "hours": [6, 22], "needs": [
		{"cargo": "maschinenteile", "concern": "meldet fehlende Bauteile an der Linie", "q": [8, 18], "rate": 0.06, "cold": 1.2},
		{"cargo": "baustoffe", "concern": "braucht Rohstoffe für die nächste Schicht", "q": [8, 16], "rate": 0.04}]},
	"construction": {"role": ["Bauleiterin", "Bauleiter"], "hours": [7, 17], "needs": [
		{"cargo": "baustoffe", "concern": "meldet fehlendes Material auf der Baustelle", "q": [8, 18], "rate": 0.08, "rain": 1.3, "cold": 1.2},
		{"cargo": "maschinenteile", "concern": "braucht Ersatzteile für die Baumaschinen", "q": [6, 14], "rate": 0.04}]},
	"warehouse": {"role": ["Lagerleiterin", "Lagerleiter"], "hours": [6, 20], "needs": [
		{"cargo": "pakete", "concern": "braucht kurzfristigen Weitertransport", "q": [4, 20], "rate": 0.05, "rain": 1.2},
		{"cargo": "getraenke", "concern": "muss Getränkepaletten weiterleiten", "q": [10, 28], "rate": 0.03, "hot": 1.6}]},
	"airport_cargo": {"role": ["Lagerleiterin am Flughafen", "Lagerleiter am Flughafen"], "hours": [0, 24], "needs": [
		{"cargo": "container", "concern": "braucht kurzfristigen Weitertransport einer Luftfracht", "q": [2, 6], "rate": 0.05},
		{"cargo": "elektronik", "concern": "hat Elektronik-Luftfracht, die weiter muss", "q": [3, 8], "rate": 0.04}]},
	"bank": {"role": ["Filialleiterin", "Filialleiter"], "hours": [9, 17], "needs": [
		{"cargo": "pakete", "concern": "erwartet eine Wertsendung", "q": [1, 3], "rate": 0.03}]},
	"gas_station": {"role": ["Pächterin", "Pächter"], "hours": [5, 23], "needs": [
		{"cargo": "getraenke", "concern": "hat leere Kühlregale", "q": [4, 10], "rate": 0.05, "hot": 2.0}]},
}

## Gebaeudetypen ohne eigenes Profil teilen sich das eines verwandten Typs.
const ALIAS := {"villa": "house", "semi": "house", "highrise": "apartment"}

var sim
var people := {}               # "P1" -> Figur
var next_id := 1
var rng := RandomNumberGenerator.new()
var open_requests := 0         # laufende Kundenanfragen (Gewichtung am Markt)
var enabled := true            # Diagnose: false = keine neuen Kundenanfragen
var _ids: Array = []           # alle Figuren (fuer die Verarbeitung in Zeitscheiben)
var _active := {}              # Figuren mit laufender Anfrage: ID -> true
const SLICES := 10             # je Spielminute wird 1/SLICES der Figuren aktualisiert (mit SLICES-fachem Zuwachs)


func setup(simulation) -> void:
	sim = simulation
	rng.seed = int(sim.city.seed_value) + 991   # eigener Zufall: beeinflusst die Simulation nicht
	add_for_buildings(range(sim.city.buildings.size()))


func add_for_buildings(ids: Array) -> void:
	for id in ids:
		var b: Dictionary = sim.city.building(int(id))
		if b.role != "customer" or not PROFILES.has(prof(b.type)):
			continue
		var pr: Dictionary = PROFILES[prof(b.type)]
		var female := rng.randf() < 0.5
		var first: String = (FEMALE if female else MALE)[rng.randi() % 12]
		var sur: String = CityGenerator.SURNAMES[rng.randi() % CityGenerator.SURNAMES.size()]
		var pid := "P%d" % next_id
		next_id += 1
		_ids.append(pid)
		people[pid] = {"id": pid, "ptype": prof(b.type), "name": "%s %s" % [first, sur], "role": pr.role[0 if female else 1], "building": int(id),
			"pressure": rng.randf_range(0.0, 0.7), "need": -1, "state": "ruhig", "contract": "", "cooldown_until": 0.0,
			"mood": 70.0, "done": 0, "failed": 0, "escalated": false, "result_until": 0.0, "last_concern": "", "last_cause": ""}


# ------------------------------------------------------------------ Takt
func minute_tick(now: float) -> void:
	var hour := Catalog.hour_of_day(now)
	# laufende Anfragen: jede Minute pruefen (kleine Menge)
	for id in _active.keys():
		var p: Dictionary = people[id]
		var k: Contract = sim.contracts.get(p.contract)
		if k == null or k.status in ["delivered", "failed", "expired", "cancelled"]:
			_active.erase(id)
			_close(p, k, now)
	open_requests = _active.size()
	# Beduerfnisdruck: nur eine Zeitscheibe der Figuren je Minute
	var open_now := {}
	for t in PROFILES:
		open_now[t] = is_open(t, hour)
	var ready: Array = []
	for i in range(sim.minute_index % SLICES, _ids.size(), SLICES):
		var p: Dictionary = people[_ids[i]]
		if p.contract != "":
			continue
		if p.state in ["zufrieden", "verärgert"] and now >= float(p.result_until):
			p.state = "ruhig"
		if now < float(p.cooldown_until) or not open_now[p.ptype]:
			continue
		var pr: Dictionary = PROFILES[p.ptype]
		if p.need < 0 or rng.randf() < 0.01:
			p.need = rng.randi() % pr.needs.size()   # welcher Bedarf gerade drueckt
		p.pressure = minf(1.5, float(p.pressure) + need_rate(pr.needs[p.need], hour) / 60.0 * SLICES)
		if float(p.pressure) >= 1.0:
			ready.append(p)
	if enabled and not ready.is_empty() and open_requests < OPEN_MAX + 3 * sim.companies.size():
		request(ready[rng.randi() % ready.size()], now)   # zufaellig, damit nicht immer dieselbe Figur dran ist


static func prof(type: String) -> String:
	return ALIAS.get(type, type)


static func is_open(type: String, hour: float) -> bool:
	var h: Array = PROFILES[type].hours
	return hour >= float(h[0]) and hour < float(h[1])


## Druckzuwachs pro Spielstunde: Grundrate x Tageszeit x Wetter x Ereignisse x Stimmung.
func need_rate(need: Dictionary, hour: float) -> float:
	var r := float(need.rate)
	var w: Weather = sim.wx
	if need.has("peak"):
		var pk: Array = need.peak
		for i in range(0, pk.size() - 1, 2):
			if hour >= float(pk[i]) and hour < float(pk[i + 1]):
				r *= 2.0
		if pk.size() == 2 and not (hour >= float(pk[0]) and hour < float(pk[1])):
			r *= 0.8
	if need.has("rain") and w.is_rain():
		r *= float(need.rain)
	if need.has("hot") and w.is_hot():
		r *= float(need.hot)
	if need.has("cold") and (w.is_cold() or w.is_snow()):
		r *= float(need.cold)
	return r * sim.world_events.need_factor(str(need.cargo))


# ------------------------------------------------------------------ Anfrage
## Erzeugt aus dem Anliegen der Figur einen echten Auftrag. force_cause: Ereignis-ID (z. B. Sturm) oder "".
func request(p: Dictionary, now: float, need_idx: int = -1, force_cause: String = "", concern_override: String = "",
		need_override: Dictionary = {}) -> Contract:
	var b: Dictionary = sim.city.building(p.building)
	var pr: Dictionary = PROFILES[prof(b.type)]
	var need: Dictionary = need_override if not need_override.is_empty() else pr.needs[need_idx if need_idx >= 0 else maxi(0, int(p.need))]
	var pick := _source_for(int(p.building), str(need.cargo))
	if pick.is_empty():
		p.pressure = 0.5   # keine Quelle gefunden: spaeter erneut versuchen
		return null
	var urgent := bool(p.escalated) or float(p.mood) < 35.0
	var k: Contract = sim.market.build_contract(int(pick.src), int(p.building), str(need.cargo), str(pick.label), 1, 1, now,
		rng.randi_range(int(need.q[0]), int(need.q[1])), 1 if urgent else 0)
	if k == null:
		return null
	var cause: String = force_cause if force_cause != "" else sim.world_events.boost_cause(str(need.cargo))
	for c in sim.companies:   # Kunden melden sich online: wer Internet hat, sieht die Anfrage sofort (sonst Jobbörse/Büro)
		if c.internet_level >= 1:
			c.known[k.id] = true
	k.requester = p.id
	k.cause = cause
	k.concern = concern_override if concern_override != "" else str(need.concern)
	if bool(p.escalated):
		k.reward = roundf(k.reward * 1.25 / 10.0) * 10.0
		k.concern += " (zweiter Anlauf, Kunde wartet schon länger)"
	k.offer_until = now + rng.randf_range(100.0, 170.0)
	p.contract = k.id
	_active[p.id] = true
	p.state = "wartet"
	p.pressure = 0.0
	p.need = -1
	p.last_concern = k.concern
	p.last_cause = cause
	sim.log_event("%s (%s, %s): %s – Auftrag %s%s" % [p.name, p.role, b.name, k.concern, k.id,
		(" · Anlass: " + sim.world_events.title_of(cause)) if cause != "" else ""], "info")
	return k


## Quelle fuer die Ware: passende Lieferkette (Brauerei -> Restaurant), sonst naechster passender Lieferant.
func _source_for(dst_id: int, cargo: String) -> Dictionary:
	var dst: Dictionary = sim.city.building(dst_id)
	var best := {}
	var best_d := INF
	for ch in sim.market.chain_ends:
		if ch[3] == cargo and dst_id in ch[1]:
			for i in 4:
				var s: int = ch[0][rng.randi() % ch[0].size()]
				var d := float(sim.market._manhattan(sim.city.building(s), dst))
				if s != dst_id and d >= 12.0 and d < best_d:
					best_d = d
					best = {"src": s, "label": ch[2]}
	if not best.is_empty():
		return best
	var cands: Array = []
	for s in sim.market.sources:
		var sb: Dictionary = sim.city.building(int(s[0]))
		if cargo in sb.out and int(s[0]) != dst_id and sim.market._manhattan(sb, dst) >= 12:
			cands.append(int(s[0]))
	if cands.is_empty():
		return {}
	for i in mini(6, cands.size()):
		var s: int = cands[rng.randi() % cands.size()]
		var d := float(sim.market._manhattan(sim.city.building(s), dst))
		if d < best_d:
			best_d = d
			best = {"src": s, "label": ""}
	return best


# ------------------------------------------------------------------ Ergebnis
## Anfrage ist abgeschlossen (geliefert, gescheitert, nie angenommen/abgelaufen).
func _close(p: Dictionary, k: Contract, now: float) -> void:
	var status: String = k.status if k else "cancelled"
	p.contract = ""
	if status == "delivered":
		p.state = "zufrieden"
		p.done = int(p.done) + 1
		p.mood = minf(100.0, float(p.mood) + 12.0)
		p.escalated = false
		p.cooldown_until = now + rng.randf_range(COOLDOWN_DONE[0], COOLDOWN_DONE[1])   # nicht sofort wieder dieselbe Anfrage
		p.result_until = now + SHOW_RESULT_MIN
		p.pressure = 0.0
		sim.log_event("%s (%s) ist zufrieden: %s geliefert." % [p.name, p.role, k.cargo_name()], "good")
	elif status in ["failed", "expired"]:
		var accepted := k != null and k.owner >= 0
		p.state = "verärgert"
		p.failed = int(p.failed) + 1
		p.mood = maxf(0.0, float(p.mood) - (20.0 if accepted else 10.0))
		p.escalated = int(p.failed) <= 2   # hoechstens zwei dringlichere Wiederholungen
		p.cooldown_until = now + (COOLDOWN_FAILED if int(p.failed) < 3 else COOLDOWN_FAILED * 4.0)   # wiederholt Enttaeuschte melden sich seltener
		p.result_until = now + SHOW_RESULT_MIN
		p.pressure = 0.6 if p.escalated else 0.0
		var why := "Lieferung nicht ausgeführt (Frist überschritten)" if accepted else "Anliegen blieb unbeantwortet"
		sim.world_events.note_customer_disappointed(p, k, why)
	else:
		p.state = "ruhig"


func of_building(building_id: int) -> Array:
	return people.values().filter(func(p): return p.building == building_id)


func person_at(building_id: int) -> Dictionary:
	for p in people.values():
		if p.building == building_id and p.state != "ruhig":
			return p
	return {}


func visible_people() -> Array:
	return people.values().filter(func(p): return p.state != "ruhig")


func describe(p: Dictionary) -> String:
	var b: Dictionary = sim.city.building(p.building)
	var s := "%s · %s\n%s (%s)\n" % [p.name, p.role, b.name, Catalog.DISTRICTS[b.district]]
	match p.state:
		"wartet":
			var k: Contract = sim.contracts.get(p.contract)
			s += "Anliegen: %s\n" % p.last_concern
			if k:
				s += "Auftrag %s: %d× %s, %s – %s\n" % [k.id, k.qty, k.cargo_name(), Catalog.money(k.reward),
					("angenommen von " + sim.company(k.owner).company_name) if k.owner >= 0 else "noch niemand hat angenommen"]
		"zufrieden":
			s += "Zufrieden – das Anliegen wurde erledigt.\n"
		"verärgert":
			s += "Verärgert – das Anliegen blieb unerledigt.\n"
		_:
			s += "Aktuell kein Anliegen.\n"
	if p.last_cause != "":
		s += "Anlass: %s\n" % sim.world_events.title_of(p.last_cause)
	return s + "Stimmung %d/100 · erledigt %d · gescheitert %d" % [int(p.mood), int(p.done), int(p.failed)]


func to_dict() -> Dictionary:
	return {"people": people, "next_id": next_id}


func from_dict(d: Dictionary) -> void:
	people = d.get("people", people)
	next_id = int(d.get("next_id", next_id))
	_ids = people.keys()
	_active.clear()
	for p in people.values():
		p.building = int(p.building)
		p.need = int(p.need)
		if not p.has("ptype"):
			p["ptype"] = prof(sim.city.building(p.building).type)
		if p.contract != "":
			_active[p.id] = true
