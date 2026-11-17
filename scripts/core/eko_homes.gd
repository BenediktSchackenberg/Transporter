class_name EkoHomes
extends RefCounted
## Neubeginn, Etappe B (Benedikt 17.11.2026): KI-Unternehmer bauen Wohnhaeuser selbst.
##
## Ablauf je Baustelle: Grundstueck der Stadt kaufen und Bauantrag stellen (Buergermeister bzw. Bauamt entscheiden) -> Material im
## Grosslager kaufen und mit dem eigenen LKW auf den Betriebshof holen (hub_buy) -> sobald alles da ist, wird es verbaut -> die
## Bautruppe arbeitet: der Inhaber (wenn sein LKW steht) und die Mitarbeiter, die der Unternehmer der Baustelle zuteilt (bauleute) ->
## fertig: Gebaeude mit Wohnungen im Eigentum der Firma. Mieter zahlen an die Firma (Housing); verkaufen mit sell_property.

const BOM := {   # Material je Haus (Grosslager-Waren)
	"einfamilienhaus": {"holz": 16, "ziegel": 40, "beton": 12, "glas": 4, "installation": 2},
	"doppelhaus": {"holz": 24, "ziegel": 64, "beton": 20, "glas": 6, "installation": 4},
	"mehrfamilienhaus": {"holz": 30, "ziegel": 120, "beton": 50, "glas": 14, "stahl": 10, "installation": 6},
}
const WORK_HOURS := {"einfamilienhaus": 24.0, "doppelhaus": 36.0, "mehrfamilienhaus": 80.0}   # Arbeitsstunden der Bautruppe
const MAX_SITES := 3        # gleichzeitige Baustellen je Firma
const MAX_CREW := 6

var w                       # EkoWorld
var sites := {}             # ID -> Baustelle
var _next := 1


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


func _depot(cid: int) -> int:
	var c = _sim().company(cid)
	return int(c.depots[0]) if not c.depots.is_empty() else -1


## Firma {aktion: {action: "haus_bauen", typ, grundstueck?}}
func plan(cid: int, a: Dictionary) -> Dictionary:
	var sim = _sim()
	var typ := str(a.get("typ", a.get("art", "einfamilienhaus"))).to_lower().replace(" ", "")
	if not BOM.has(typ):
		return {"ok": false, "msg": "typ: einfamilienhaus | doppelhaus | mehrfamilienhaus."}
	if sites.values().filter(func(s): return int(s.cid) == cid and s.status not in ["fertig", "abgelehnt"]).size() >= MAX_SITES:
		return {"ok": false, "msg": "Höchstens %d Baustellen gleichzeitig – erst eine fertigstellen." % MAX_SITES}
	if not sim.tiers.unlocked(typ):
		return {"ok": false, "msg": sim.tiers.unlock_text(typ)}
	var who := "C%d" % cid
	var floors := 3 if typ == "mehrfamilienhaus" else 1
	var probe := {"def": typ, "floors": floors, "parking": int(Planning.DEFS[typ].parking), "financing": {"eigenmittel": sim.company(cid).ledger.cash}}
	var cands: Array = []
	if str(a.get("grundstueck", "")) != "":
		var p0: Dictionary = sim.parcels.parcel(str(a.grundstueck))
		if p0.is_empty():
			return {"ok": false, "msg": "Grundstück %s gibt es nicht." % a.grundstueck}
		cands = [p0]
		if not Planning.assess(p0, probe).ok:   # 17.11.: Bodo nannte einen 2x6-Streifen - dann selbst ein passendes suchen
			cands = []
	if cands.is_empty():
		var town: int = sim.towns.home_of(cid)
		for z in ["wohnen", "mischgebiet"]:
			for u in ["voll", "teilweise"]:   # nur an einer Strasse (sonst kann das fertige Haus nicht uebergeben werden)
				cands += sim.parcels.search({"zone": z, "utilities": u, "town": town, "min_area": 12, "limit": 30})
	var why := "kein freies, bebaubares Wohngrundstück an einer Straße deiner Stadt – erst eine Straße bauen (strasse_bauen)"
	for p in cands:
		var chk := Planning.assess(p, probe)
		if not chk.ok:
			why = " ".join(chk.blocking)
			continue
		if float(p.price) > sim.company(cid).ledger.cash:
			why = "Grundstück %s kostet %s" % [p.id, Catalog.money(float(p.price))]
			continue
		if not sim.parcels.reserve(p.id, who).ok:
			continue
		var dr: Dictionary = sim.permits.draft(who, p.id, probe)
		if not dr.ok:
			sim.parcels.release(p.id, who)
			why = str(dr.msg)
			continue
		# Grundstueckskauf von der Stadt (wie Haushalte, Parcels.buy_for_household)
		var k: int = Towns.town_of_owner(str(p.owner)) if sim.towns.is_region() else 0
		sim.company(cid).ledger.invest(float(p.price), Towns.account_of(maxi(0, k)))   # Grund ist Vermoegen, kein Aufwand
		p.owner = who
		p.state = "privat_gehalten"
		p.reservation = {}
		sim.permits.submit(dr.id)
		var s := {"id": "BS%d" % _next, "cid": cid, "typ": typ, "floors": floors, "parcel": p.id, "app": dr.id, "status": "genehmigung",
			"need": BOM[typ].duplicate(), "progress": 0.0, "crew": [], "building": -1, "day": sim.game_min}
		_next += 1
		sites[s.id] = s
		sim.log_event("%s plant ein %s auf %s (Antrag %s)." % [sim.company(cid).company_name, Planning.DEFS[typ].label, p.id, dr.id], "info", cid)
		return {"ok": true, "msg": "Baustelle %s: %s auf %s gekauft (%s), Bauantrag %s gestellt. Material: %s – im Großlager kaufen (hub_buy) und mit dem LKW holen." % [
			s.id, Planning.DEFS[typ].label, p.id, Catalog.money(float(p.price)), dr.id, _need_text(s)], "baustelle": s.id}
	return {"ok": false, "msg": "Kein Bauplatz gefunden: %s." % why}


## Firma {aktion: {action: "bauleute", baustelle, worker_ids}} – Mitarbeiter der Baustelle zuteilen (ersetzt die bisherige Truppe).
func assign_crew(cid: int, a: Dictionary) -> Dictionary:
	var s: Dictionary = sites.get(str(a.get("baustelle", "")), {})
	if s.is_empty() or int(s.cid) != cid:
		return {"ok": false, "msg": "Baustelle %s gehört dir nicht. Deine: %s." % [a.get("baustelle", ""), ", ".join(sites.values().filter(func(x): return int(x.cid) == cid).map(func(x): return x.id))]}
	var ids: Array = a.get("worker_ids", a.get("mitarbeiter", [])) if (a.get("worker_ids", a.get("mitarbeiter", [])) is Array) else [str(a.get("worker_ids", a.get("mitarbeiter", "")))]
	var crew: Array = []
	for id in ids:
		var wk = _sim().personnel.workers.get(str(id))
		if wk == null or wk.employer != cid or wk.lost:
			return {"ok": false, "msg": "%s ist nicht bei dir angestellt." % id}
		crew.append(str(id))
	s.crew = crew.slice(0, MAX_CREW)
	return {"ok": true, "msg": "Baustelle %s: Bautruppe %s (dazu du selbst, wenn dein LKW steht)." % [s.id, ", ".join(s.crew) if not s.crew.is_empty() else "keine"]}


func _need_text(s: Dictionary) -> String:
	var parts: Array = []
	for item in s.need:
		parts.append("%d %s" % [int(s.need[item]), item])
	return ", ".join(parts)


## Was fehlt noch auf dem Betriebshof? {item: menge}
func missing(s: Dictionary) -> Dictionary:
	var sim = _sim()
	var out := {}
	for item in s.need:
		var have: int = sim.stock.available(item, "C%d" % int(s.cid), _depot(int(s.cid)))
		if have < int(s.need[item]):
			out[item] = int(s.need[item]) - have
	return out


## Arbeitende Bautruppe: zugeteilte Mitarbeiter ohne andere Aufgabe und nicht am Steuer, der Inhaber wenn sein LKW steht.
func crew_now(s: Dictionary) -> int:
	var sim = _sim()
	var n := 0
	for id in s.crew:
		var wk = sim.personnel.workers.get(str(id))
		if wk != null and wk.employer == int(s.cid) and not wk.lost and str(wk.task_id) == "" and int(wk.vehicle_id) < 0:
			n += 1
	for wk in sim.personnel.employed(int(s.cid)):
		if wk.role == "owner":
			var v = sim.vehicles.get(int(wk.vehicle_id))
			if v == null or (v.state == "idle" and v.queue.is_empty() and str(v.contract_id) == ""):
				n += 1
	return n


func tick(dt_min: float) -> void:
	var sim = _sim()
	for s in sites.values():
		match str(s.status):
			"genehmigung":
				var app: Dictionary = sim.permits.apps.get(str(s.app), {})
				if app.is_empty():
					continue
				if str(app.status) == "entschieden":
					if str(app.result).begins_with("genehmigt"):
						s.status = "material"
						sim.notify(int(s.cid), "Baustelle %s genehmigt – Material holen: %s." % [s.id, _need_text(s)])
					else:
						s.status = "abgelehnt"
						sim.notify(int(s.cid), "Baustelle %s: Antrag abgelehnt (%s)." % [s.id, str(app.get("decision", "")).left(120)])
			"material":
				if missing(s).is_empty():
					for item in s.need:
						sim.stock.consume(item, int(s.need[item]), "C%d" % int(s.cid), _depot(int(s.cid)), "Baustelle %s" % s.id, sim.game_min)
					s.status = "bau"
					sim.parcels.mark(str(s.parcel), "im_bau", str(s.app))
					sim.log_event("%s: Baustelle %s – Material da, der Bau beginnt." % [sim.company(int(s.cid)).company_name, s.id], "info", int(s.cid))
			"bau":
				s.progress = float(s.progress) + float(crew_now(s)) * dt_min / 60.0
				if float(s.progress) >= float(WORK_HOURS[s.typ]):
					_finish(s)


func _finish(s: Dictionary) -> void:
	var sim = _sim()
	var parcel: Dictionary = sim.parcels.parcel(str(s.parcel))
	var d: Dictionary = Planning.DEFS[s.typ]
	var pw := int(d.w)
	var ph := int(d.h)
	if pw > int(parcel.rect[2]) or ph > int(parcel.rect[3]):
		var t := pw
		pw = ph
		ph = t
	var r := Rect2i(int(parcel.rect[0]), int(parcel.rect[1]), int(parcel.rect[2]), int(parcel.rect[3]))
	var b: Dictionary = sim.events._add_building(str(d.sprite), r, "%s (%s)" % [d.label, sim.company(int(s.cid)).company_name])
	if b.is_empty():
		s["blockiert"] = "Gebäude passt nicht oder hat keinen Straßenzugang."
		return
	s.status = "fertig"
	s.building = int(b.id)
	sim.market.refresh()
	sim.residents.add_for_buildings([b.id])
	sim.events.buildings_added.emit([b.id])
	var n := Planning.units_of(str(s.typ), int(s.floors))
	var k: int = sim.towns.of_building(int(b.id))
	sim.towns.mayor(maxi(0, k)).stock_units += n
	for i in n:
		sim.housing.register_unit(int(b.id), 60.0 + 10.0 * float(i % 3), "C%d" % int(s.cid))
	sim.log_event("%s hat ein %s fertig gebaut (%d Wohnungen) – Zuzug möglich." % [sim.company(int(s.cid)).company_name, d.label, n], "good", int(s.cid))
	sim.activity.add("stadt", int(s.cid), "bau", "Neues %s" % d.label, sim.company(int(s.cid)).company_name, b.walk)


## Fuer Beobachtung und naechste_schritte.
func summary(cid: int) -> Array:
	var out: Array = []
	for s in sites.values():
		if int(s.cid) != cid or s.status == "abgelehnt":
			continue
		var e := {"id": s.id, "typ": s.typ, "grundstueck": s.parcel, "status": s.status, "antrag": s.app}
		if s.status == "material":
			e["fehlt_auf_dem_betriebshof"] = missing(s)
		if s.status == "bau":
			e["fortschritt"] = "%d %%" % int(100.0 * float(s.progress) / float(WORK_HOURS[s.typ]))
			e["bautruppe_jetzt"] = crew_now(s)
			e["bautruppe"] = s.crew
		if s.status == "fertig":
			e["gebaeude"] = s.building
		out.append(e)
	return out


## Naechster sinnvoller Schritt fuer die Firma ("" = keiner).
func next_step(cid: int) -> String:
	var sim = _sim()
	var open: Array = sites.values().filter(func(s): return int(s.cid) == cid and s.status in ["genehmigung", "material", "bau"])
	for s in open:
		if s.status == "material":
			var m := missing(s)
			var item: String = m.keys()[0]
			var pend: int = sim.hub.pending("C%d" % cid, item)
			if pend >= int(m[item]):
				return "Baustelle %s: %d %s sind gekauft – mit dem LKW im Großlager abholen (Auftrag annehmen bzw. Fahrer einsetzen)." % [s.id, pend, item]
			return "Baustelle %s braucht Material: Firma {aktion: {action: \"hub_buy\", item: \"%s\", qty: %d}} – dann mit dem LKW abholen. Fehlt insgesamt: %s." % [
				s.id, item, int(m[item]) - pend, ", ".join(m.keys().map(func(x): return "%d %s" % [m[x], x]))]
		if s.status == "bau" and crew_now(s) <= 1:
			var free: Array = sim.personnel.employed(cid).filter(func(x): return x.role != "owner" and not s.crew.has(x.id) and int(x.vehicle_id) < 0)
			if not free.is_empty():
				return "Baustelle %s: mehr Leute bauen schneller – Firma {aktion: {action: \"bauleute\", baustelle: \"%s\", worker_ids: [\"%s\"]}}." % [s.id, s.id, free[0].id]
			if not sim.personnel.available().is_empty():
				return "Baustelle %s geht langsam (nur du baust) – Mitarbeiter anwerben: Firma {aktion: {action: \"recruit_worker\", worker_id: \"%s\"}}." % [s.id, sim.personnel.available()[0].id]
	if open.is_empty():
		return "Wohnraum bauen – erst mit Wohnungen ziehen Menschen per Schiff zu: Firma {aktion: {action: \"haus_bauen\", typ: \"einfamilienhaus\"}} (oder doppelhaus, mehrfamilienhaus)."
	return ""


func to_dict() -> Dictionary:
	return {"sites": sites, "next": _next}


func from_dict(d: Dictionary) -> void:
	sites = d.get("sites", {})
	_next = int(d.get("next", 1))
	for s in sites.values():
		for item in s.need:
			s.need[item] = int(s.need[item])
