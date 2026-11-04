class_name YardAdvisor
extends RefCounted
## Hof-Imperium (Auftrag 11, Etappe 2, docs/YARD_EMPIRE.md): Bauberater und Investitionsakte.
##
## Bauberater: misst die Engpaesse jeder Firma (Stellplaetze, Reparaturkosten, Treibstoff, Auftragskapazitaet, Erschoepfung, Fahrkoennen)
## aus taeglichen Momentaufnahmen des Hauptbuchs und schlaegt Gebaeude mit Nutzen je Monat, Unterhalt und Amortisation vor – jeweils mit
## fertiger Aktion. Modell und Regel-KI waehlen daraus oder bauen nach eigener Idee; die Engine prueft wie immer.
##
## Investitionsakte: Bei jedem Bau wird die Erwartung festgehalten (Angabe des Modells oder Schaetzung des Beraters). 10 Spieltage nach der
## Fertigstellung misst die Engine den tatsaechlichen Nutzen derselben Kennzahl und schreibt das Ergebnis ins Gedaechtnis der Firma.
## Das Verhaeltnis gemessen/geschaetzt je Gebaeudetyp ("Prognosefaktor") korrigiert die naechsten Schaetzungen – die KI lernt, welche
## Bauten sich wirklich lohnen. Mit `persist` (im Spiel an, in Tests aus) bleiben die Faktoren ueber Partien erhalten.

const MEASURE_DAYS := 10
const WINDOW := 30                       # Tage fuer die Engpassmessung
const MARGIN := 0.25                     # Anteil der Erloese, der als zusaetzlicher Gewinn zaehlt (Kapazitaetsbauten)
const LEARN_PATH := "user://yard_learning.json"
const MAX_CANDIDATES := 5
const PRIOR_WEIGHT := 2.0                # Vorannahme Faktor 1,0 zaehlt wie zwei Messungen (eine einzelne Messung schlaegt nicht voll durch)

var sim
var snaps := {}                          # cid -> Array der Momentaufnahmen {day, transport, repairs, fuel, completed, profit, vehicles, fatigue}
var records: Array = []                  # Investitionsakten
var factors := {}                        # Gebaeudetyp -> {f, n} gelernter Prognosefaktor
var persist := false
var loads := {}                          # cid -> Lade-/Entladevorgaenge am eigenen Hof (kumuliert, Messgroesse fuer Rampe/Halle/Kran)
const LOAD_SAVING := {"laderampe": 0.4, "umschlaghalle": 0.3, "kran": 0.4}   # gesparter Anteil der Ladezeit
const UTILIZATION := 0.5                 # Anteil der Zeit, in der ein Fahrzeug Erloes bringt (gesparte Minuten zaehlen so viel)
var _day := -1


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


## Faktoren aus frueheren Partien laden (nur im Spiel).
func load_learning() -> void:
	persist = true
	if FileAccess.file_exists(LEARN_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LEARN_PATH))
		if d is Dictionary:
			for k in d:
				factors[str(k)] = {"f": float(d[k].f), "n": int(d[k].n)}


func _save_learning() -> void:
	if not persist:
		return
	var f := FileAccess.open(LEARN_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(factors))


func factor(typ: String) -> float:
	return float(factors.get(typ, {}).get("f", 1.0))


# ------------------------------------------------------------------ Messung
func _snapshot(c: Company) -> Dictionary:
	var t: Dictionary = c.ledger.totals
	var ws: Array = sim.personnel.employed(c.id)
	var fat := 0.0
	for w in ws:
		fat += w.fatigue
	return {"day": GameCalendar.day_of(sim.game_min), "transport": float(t.get("transport", 0.0)), "repairs": -float(t.get("repairs", 0.0)),
		"fuel": -float(t.get("fuel", 0.0)) - float(t.get("supplies", 0.0)), "completed": int(c.stats.get("completed", 0)), "profit": c.ledger.profit(),
		"vehicles": sim.company_vehicles(c.id).size(), "fatigue": fat / maxf(1.0, float(ws.size())), "yard_loads": int(loads.get(c.id, 0))}


func on_day(day: int) -> void:
	if day == _day:
		return
	_day = day
	for c in sim.companies:
		var arr: Array = snaps.get(c.id, [])
		arr.append(_snapshot(c))
		if arr.size() > WINDOW + 1:
			arr.pop_front()
		snaps[c.id] = arr
	for r in records:
		if r.status == "messung" and day >= int(r.done_day) + MEASURE_DAYS:
			_measure(r)


## Werte je Monat (30 Tage) im Fenster der letzten `days` Tage (bis jetzt): Erloese, Reparaturen, Treibstoff, erledigte Auftraege.
func window(cid: int, days: int = WINDOW) -> Dictionary:
	var arr: Array = snaps.get(cid, [])
	var now := _snapshot(sim.company(cid))
	if arr.is_empty():
		return {"tage": 0, "transport": 0.0, "repairs": 0.0, "fuel": 0.0, "completed": 0.0, "profit": 0.0, "yard_loads": 0.0}
	var first: Dictionary = arr[maxi(0, arr.size() - days)]
	var span := maxf(1.0, float(now.day - int(first.day)))
	var k := 30.0 / span
	return {"tage": int(span), "transport": (now.transport - first.transport) * k, "repairs": (now.repairs - first.repairs) * k, "fuel": (now.fuel - first.fuel) * k,
		"completed": float(now.completed - int(first.completed)) * k, "profit": (now.profit - float(first.profit)) * k,
		"yard_loads": float(int(now.yard_loads) - int(first.get("yard_loads", 0))) * k}


## Vom Simulationskern: ein Lade- oder Entladevorgang auf einem Firmengrundstueck.
func note_load(cid: int) -> void:
	loads[cid] = int(loads.get(cid, 0)) + 1


## Wert gesparter Ladezeit je Monat: Vorgaenge am Hof × gesparte Minuten × Erloes je Fahrzeugminute.
func _loading_value(cid: int, typ: String, yard_loads_month: float, rev_v: float) -> float:
	var saved_min: float = yard_loads_month * Catalog.LOADING_MIN * float(LOAD_SAVING.get(typ, 0.0))
	return saved_min * rev_v / (30.0 * 1440.0 * UTILIZATION)


# ------------------------------------------------------------------ Bauberater
## Geschaetzter Nutzen je Monat (EUR) eines Gebaeudetyps aus den gemessenen Engpaessen; dazu die begruendende Kennzahl.
func estimate(cid: int, typ: String) -> Dictionary:
	var c: Company = sim.company(cid)
	var w := window(cid)
	var n_v: int = sim.company_vehicles(cid).size()
	var rev_v: float = maxf(1500.0, w.transport / maxf(1.0, float(n_v)))
	var cap: int = c.contract_capacity()
	var active: int = sim.executor.active_contracts(cid)
	var ws: Array = sim.personnel.employed(cid)
	var fat := 0.0
	for x in ws:
		fat += x.fatigue
	fat = fat / maxf(1.0, float(ws.size()))
	var weak: int = ws.filter(func(x): return int(x.skills.get("fahren", 0)) <= 1 and x.vehicle_id >= 0).size()
	var open_jobs: int = sim.market.open_contracts().filter(func(k): return c.known.has(k.id)).size()
	var cold_jobs: Array = sim.market.open_contracts().filter(func(k): return c.known.has(k.id) and k.needs_cold)
	var has_reefer: bool = sim.company_vehicles(cid).any(func(v): return bool(v.spec().get("refrigerated", false)))
	var value := 0.0
	var why := ""
	var metric := ""
	match typ:
		"stellplatz", "garage":
			metric = "fahrzeuge"
			if n_v >= c.fleet_limit() and open_jobs >= 2:
				value = 2.0 * rev_v * MARGIN * (0.9 if typ == "garage" else 1.0)
				why = "alle %d Stellplätze belegt, %d bekannte offene Aufträge" % [c.fleet_limit(), open_jobs]
		"werkstatt":
			metric = "repairs"
			value = 0.4 * w.repairs
			why = "Reparaturkosten %s je Monat" % Catalog.money(w.repairs)
		"tankstelle":
			metric = "fuel"
			value = 0.07 * w.fuel
			why = "Treibstoff %s je Monat" % Catalog.money(w.fuel)
		"buero", "disposition":
			metric = "completed"
			if active >= cap:
				value = w.transport / maxf(1.0, float(cap)) * (3.0 if typ == "buero" else 2.0) * MARGIN
				why = "Auftragskapazität voll (%d/%d)" % [active, cap]
		"laderampe":
			metric = "yard_loading"
			value = _loading_value(cid, typ, w.yard_loads, rev_v)
			why = "%.0f Lade-/Entladevorgänge je Monat am eigenen Hof, Ladezeit ×0,6" % w.yard_loads if w.yard_loads >= 1.0 else ""
		"kuehllager":
			metric = "transport"
			if has_reefer and not cold_jobs.is_empty():
				value = 0.15 * float(cold_jobs.size()) * float(cold_jobs.map(func(k): return k.reward).reduce(func(a, b): return a + b, 0.0)) / float(cold_jobs.size())
				why = "%d Kühlaufträge offen, Kühlfahrzeug vorhanden" % cold_jobs.size()
		"pausenraum":
			metric = "fatigue"
			if fat > 40.0:
				value = 25.0 * float(ws.size())
				why = "mittlere Erschöpfung %.0f bei %d Beschäftigten" % [fat, ws.size()]
		"schulung":
			metric = "transport"
			value = 80.0 * float(weak)
			why = "%d Fahrer mit Fahrkönnen ≤ 1" % weak if weak > 0 else ""
		"waschplatz":
			metric = "transport"
			value = 0.02 * w.transport
			why = "Zuschlag +5 %% bei gehobenen Kunden (Erlöse %s je Monat)" % Catalog.money(w.transport)
		"mietbuero":
			metric = "rent"
			value = 2.0 * 60.0 * 30.0 * 0.6
			why = "Mieteinnahmen (2 Einheiten, 60 EUR/Tag, 60 % belegt)"
		"kran":
			metric = "yard_loading"
			var heavy: int = sim.company_vehicles(cid).filter(func(v): return bool(v.spec().get("heavy", false))).size()
			if heavy > 0:
				value = _loading_value(cid, typ, w.yard_loads * float(heavy) / maxf(1.0, float(n_v)), rev_v) + 0.1 * w.transport * MARGIN * float(heavy) / maxf(1.0, float(n_v))
				why = "%d schwere Fahrzeuge: Laden ×0,6, Spezialisierung Schwerlasthof" % heavy
		"umschlaghalle":
			metric = "yard_loading"
			if w.yard_loads >= 1.0:
				value = _loading_value(cid, typ, w.yard_loads, rev_v)
				why = "%.0f Lade-/Entladevorgänge je Monat am eigenen Hof: überdachter Umschlag ×0,7" % w.yard_loads
		"lager":
			metric = "transport"
			var lines: int = sim.operations.summary(cid).get("linien", []).filter(func(l): return bool(l.get("via_depot", false))).size()
			value = 150.0 * float(lines)
			why = "%d Linien über den eigenen Hof" % lines if lines > 0 else ""
	value *= factor(typ)
	return {"wert": value, "grund": why, "kennzahl": metric}


## Nummerierte Bauvorschlaege mit fertiger Aktion, nach Amortisation sortiert (nur mit positivem Nettonutzen und gueltigem Bauplatz).
func candidates(cid: int) -> Array:
	var E: Estate = sim.estate
	var c: Company = sim.company(cid)
	if c.depots.is_empty() or not E.is_plot(c.depots[0]):
		return []
	var root: int = c.depots[0]
	var sug: Dictionary = E.suggestions(cid, root)
	var free_workers: int = sim.personnel.employed(cid).filter(func(w): return w.task_id == "" and w.vehicle_id < 0).size()
	var out: Array = []
	for typ in Estate.FACILITIES:
		if not sug.has(typ):
			continue
		var spec: Dictionary = Estate.FACILITIES[typ]
		var have: int = E.facilities.values().filter(func(f): return f.owner == cid and f.typ == typ).size()
		if have > 0 and typ not in ["stellplatz", "garage", "laderampe"]:
			continue
		var est := estimate(cid, typ)
		var upkeep := float(spec.upkeep) * 30.0
		var net := float(est.wert) - upkeep
		if net <= 0.0 or str(est.grund) == "":
			continue
		var mode := "eigen" if free_workers >= 1 else "extern"
		var cost := float(spec.cost) * (1.0 if mode == "eigen" else 1.0 + Estate.EXTERNAL_SURCHARGE)
		var xy: Array = sug[typ]
		out.append({"typ": typ, "name": spec.name, "engpass": est.grund, "nutzen_monat": roundi(float(est.wert)), "unterhalt_monat": roundi(upkeep),
			"kosten": roundi(cost), "amortisation_monate": snappedf(cost / net, 0.1), "prognosefaktor": snappedf(factor(typ), 0.01),
			"material_stadtlager": sim.city_depot.material_offer(int(spec.mat)),
			"aktion": {"action": "place_building", "plot_id": root, "typ": typ, "x": int(xy[0]), "y": int(xy[1]), "rot": int(xy[2]), "bau": mode,
				"erwartung_eur_monat": roundi(float(est.wert))}})
	out.sort_custom(func(a, b): return float(a.amortisation_monate) < float(b.amortisation_monate))
	var nr := 1
	for x in out:
		x["nr"] = nr
		nr += 1
	return out.slice(0, MAX_CANDIDATES)


# ------------------------------------------------------------------ Investitionsakte
## Beim Baubeginn (Estate.place): Erwartung festhalten. expected < 0 = Schaetzung des Beraters.
func on_place(cid: int, fid: String, typ: String, expected: float) -> void:
	var est := estimate(cid, typ)
	var exp_val := expected if expected >= 0.0 else float(est.wert)
	records.append({"fid": fid, "cid": cid, "typ": typ, "day": GameCalendar.day_of(sim.game_min), "erwartung": snappedf(exp_val, 1.0), "beraterschaetzung": snappedf(float(est.wert), 1.0),
		"kennzahl": est.kennzahl, "status": "bau", "done_day": -1, "vorher": window(cid), "vorher_snap": _snapshot(sim.company(cid))})
	if records.size() > 80:
		records.pop_front()


## Fertigstellung (Estate.minute_tick): Messzeit beginnt.
func on_complete(fid: String) -> void:
	for r in records:
		if r.fid == fid and r.status == "bau":
			r.status = "messung"
			r.done_day = GameCalendar.day_of(sim.game_min)


func _measure(r: Dictionary) -> void:
	var cid := int(r.cid)
	var after := window(cid, MEASURE_DAYS)
	var before: Dictionary = r.vorher
	var now := _snapshot(sim.company(cid))
	var gained := 0.0
	match str(r.kennzahl):
		"fahrzeuge":
			var extra := maxi(0, int(now.vehicles) - int(r.vorher_snap.vehicles))
			gained = float(extra) * maxf(1500.0, float(after.transport) / maxf(1.0, float(now.vehicles))) * MARGIN
		"repairs":
			gained = float(before.repairs) - float(after.repairs)
		"fuel":
			gained = float(before.fuel) - float(after.fuel) * (float(before.transport) / maxf(1.0, float(after.transport)) if float(after.transport) > 0.0 else 1.0)
		"completed":
			gained = (float(after.completed) - float(before.completed)) * float(after.transport) / maxf(1.0, float(after.completed)) * MARGIN
		"fatigue":
			gained = (float(r.vorher_snap.fatigue) - float(now.fatigue)) * float(sim.personnel.employed(cid).size()) * 25.0 / 20.0
		"rent":
			gained = float(sim.estate.leased_units(r.fid)) * 60.0 * 30.0
		"yard_loading":
			gained = _loading_value(cid, str(r.typ), float(after.yard_loads), maxf(1500.0, float(after.transport) / maxf(1.0, float(now.vehicles))))
		_:
			# Umsatz je Fahrzeug statt Gesamtgewinn: Fahrzeugkaeufe, Loehne und Abschreibungen sollen die Messung nicht ueberdecken
			var per_before := float(before.transport) / maxf(1.0, float(r.vorher_snap.vehicles))
			var per_after := float(after.transport) / maxf(1.0, float(now.vehicles))
			gained = (per_after - per_before) * float(now.vehicles) * MARGIN
	var cap := 3.0 * maxf(300.0, float(r.beraterschaetzung))
	gained = clampf(gained, -cap, cap)   # Ausreisser (Einzelauftraege, Krisen) begrenzen
	r.status = "gemessen"
	r["gemessen"] = snappedf(gained, 1.0)
	var est := float(r.beraterschaetzung)
	if est > 0.0:
		var ratio := clampf(gained / est, 0.0, 2.5)
		var fe: Dictionary = factors.get(r.typ, {"f": 1.0, "n": 0})
		fe.f = (float(fe.f) * (float(fe.n) + PRIOR_WEIGHT) + ratio) / (float(fe.n) + PRIOR_WEIGHT + 1.0)   # Mittelwert mit Vorannahme
		fe.n = int(fe.n) + 1
		fe.f = clampf(float(fe.f), 0.2, 2.0)
		factors[r.typ] = fe
		_save_learning()
	var name: String = Estate.FACILITIES[r.typ].name
	var verdict := "lohnt sich" if gained >= float(Estate.FACILITIES[r.typ].upkeep) * 30.0 else "trägt sich noch nicht"
	var text := "Hof: %s (%s) – erwartet %s/Monat, gemessen %s/Monat nach %d Tagen; %s." % [name, r.fid, Catalog.money(float(r.erwartung)), Catalog.money(gained), MEASURE_DAYS, verdict]
	sim.memory.upsert(cid, {"inhalt": text, "bereich": ["betriebshof", r.typ], "art": "tatsache", "vertrauen": 0.8}, "messung")
	sim.log_event(text, "good" if verdict == "lohnt sich" else "info", cid)


func summary(cid: int) -> Dictionary:
	var mine: Array = records.filter(func(r): return int(r.cid) == cid)
	return {"vorschlaege": candidates(cid), "investitionsakten": mine.slice(-6).map(func(r): return {"gebaeude": r.fid, "typ": r.typ, "status": r.status,
		"erwartung_eur_monat": r.erwartung, "gemessen_eur_monat": r.get("gemessen", null)}),
		"hinweis": "Vorschläge aus gemessenen Engpässen; 'aktion' direkt ausführbar. Eigene Ideen sind erlaubt (place_building mit erwartung_eur_monat). Nach Fertigstellung misst das Spiel den echten Nutzen."}


func to_dict() -> Dictionary:
	var s := {}
	for cid in snaps:
		s[str(cid)] = snaps[cid]
	var ld := {}
	for cid in loads:
		ld[str(cid)] = loads[cid]
	return {"snaps": s, "records": records, "factors": factors, "loads": ld}


func from_dict(d: Dictionary) -> void:
	snaps = {}
	for k in d.get("snaps", {}):
		snaps[int(k)] = d.snaps[k]
		for x in snaps[int(k)]:
			x.day = int(x.day)
	records = d.get("records", [])
	for r in records:
		r.cid = int(r.cid)
		r.done_day = int(r.done_day)
	for k in d.get("loads", {}):
		loads[int(k)] = int(d.loads[k])
	for k in d.get("factors", {}):
		factors[str(k)] = {"f": float(d.factors[k].f), "n": int(d.factors[k].n)}
