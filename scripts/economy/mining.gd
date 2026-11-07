class_name Mining
extends RefCounted
## Bergwerk-Story (Benedikt, 06.11.2026): Erkundung, Abbaurecht und Foerderabgabe. Ablauf fuer ein Unternehmen:
##   1. Probebohrung (explore_deposit): kostet EXPLORE_COST, dauert EXPLORE_DAYS, Bohrturm sichtbar; danach sind Menge und Qualitaet
##      bekannt (vorher nur eine unsichere Schaetzung).
##   2. Abbauantrag (request_mining): der Buergermeister entscheidet (decide_mining) mit einer Foerderabgabe von 3-15 % des
##      Rohstoffwerts an die Stadtkasse; ohne Entscheidung genehmigt das Bauamt nach PERMIT_DAYS Tagen mit DEFAULT_ROYALTY.
##   3. Zufahrt (build_access), falls die Lagerstaette keinen Strassenanschluss hat.
##   4. Gruendung (found_business bergwerk): Grundstueck wird gekauft, ein Bautrupp baut das Bergwerk (Construction.works).
## next_step() nennt jeder Firma den naechsten Schritt je Rohstoff (Beobachtung "bergbau").

const EXPLORE_COST := 6000.0
const EXPLORE_DAYS := 2
const PERMIT_DAYS := 3
const DEFAULT_ROYALTY := 0.08
const ROYALTY_MIN := 0.03
const ROYALTY_MAX := 0.15

var sim
var enabled := true                 # Tests mit direkter Bergwerksgruendung schalten die Regeln ab
var explored := {}                  # Grundstueck -> {by, day}
var drillings := {}                 # Grundstueck -> {cid, done}
var permits := {}                   # Grundstueck -> {cid, status (antrag|genehmigt|abgelehnt), abgabe, day, reason, decision}
var royalty_total := 0.0
var royalty_month := 0.0


func setup(simulation) -> void:
	sim = simulation


# ------------------------------------------------------------------ Schaetzung und Erkundung
## Oeffentliche Sicht auf eine Lagerstaette: nach der Erkundung die echten Werte, vorher eine Schaetzung (Faktor 0,6-1,4).
func estimate(pid: String) -> Dictionary:
	var d: Dictionary = sim.prod.deposit_of(pid)
	if d.is_empty():
		return {}
	if explored.has(pid) or not enabled:
		return {"art": d.art, "menge": int(d.menge), "qualitaet": float(d.qualitaet), "erkundet": true}
	var h := absi(hash([sim.city.seed_value, pid, "schaetzung"]))
	var f := 0.6 + float(h % 81) / 100.0
	var g := 0.8 + float((h / 97) % 41) / 100.0
	return {"art": d.art, "menge_geschaetzt": int(round(float(d.menge) * f / 100.0)) * 100, "qualitaet_geschaetzt": snappedf(clampf(float(d.qualitaet) * g, 0.4, 1.0), 0.05),
		"erkundet": false, "hinweis": "Schätzung, unsicher ±40 %; Probebohrung (explore_deposit) klärt"}


func explore(cid: int, pid: String) -> Dictionary:
	if sim.prod.deposit_of(pid).is_empty():
		return {"ok": false, "msg": "Auf %s ist keine Lagerstätte." % pid}
	if explored.has(pid):
		return {"ok": false, "msg": "%s ist schon erkundet: %s" % [pid, _result_text(pid)]}
	if drillings.has(pid):
		return {"ok": false, "msg": "Auf %s wird schon gebohrt." % pid}
	var c: Company = sim.company(cid)
	if c.ledger.cash < EXPLORE_COST:
		return {"ok": false, "msg": "Probebohrung kostet %s." % Catalog.money(EXPLORE_COST)}
	c.ledger.book("property_costs", -EXPLORE_COST, true, "Probebohrung %s" % pid, sim.game_min, "S0")
	drillings[pid] = {"cid": cid, "done": GameCalendar.day_of(sim.game_min) + EXPLORE_DAYS}
	var art := item_label(pid)
	sim.log_event("%s lässt auf %s eine Probebohrung niederbringen (%s vermutet, %d Tage)." % [c.company_name, pid, art, EXPLORE_DAYS], "info", cid)
	sim.activity.add("unternehmen", cid, "bau", "Probebohrung auf %s" % pid, "%s vermutet" % art, _cell(pid))
	return {"ok": true, "msg": "Probebohrung auf %s beauftragt (%s, Ergebnis in %d Tagen)." % [pid, Catalog.money(EXPLORE_COST), EXPLORE_DAYS], "ref": pid}


func _result_text(pid: String) -> String:
	var d: Dictionary = sim.prod.deposit_of(pid)
	return "%d Einheiten %s, Qualität %d %%" % [int(d.menge), Production.item_name(str(d.art)), int(float(d.qualitaet) * 100.0)]


func item_label(pid: String) -> String:
	return Production.item_name(str(sim.prod.deposit_of(pid).get("art", "")))


# ------------------------------------------------------------------ Abbaurecht
func request(cid: int, pid: String, reason: String) -> Dictionary:
	if not explored.has(pid):
		return {"ok": false, "msg": "%s ist nicht erkundet: zuerst Probebohrung (explore_deposit)." % pid}
	var p: Dictionary = permits.get(pid, {})
	if not p.is_empty() and p.status in ["antrag", "genehmigt"]:
		return {"ok": false, "msg": "Für %s liegt schon ein Abbauantrag bzw. -recht vor (%s, Firma %d)." % [pid, p.status, int(p.cid)]}
	var parcel: Dictionary = sim.parcels.parcel(pid)
	if parcel.is_empty() or parcel.owner != Parcels.CITY:
		return {"ok": false, "msg": "%s gehört nicht mehr der Stadt." % pid}
	permits[pid] = {"cid": cid, "status": "antrag", "abgabe": DEFAULT_ROYALTY, "day": GameCalendar.day_of(sim.game_min), "reason": reason.left(200), "decision": ""}
	var c: Company = sim.company(cid)
	sim.log_event("%s beantragt das Abbaurecht für %s (%s). Der Bürgermeister entscheidet über Genehmigung und Förderabgabe." % [c.company_name, pid, _result_text(pid)], "info", cid)
	sim.activity.add("unternehmen", cid, "bau", "Abbauantrag für %s" % pid, reason, _cell(pid))
	return {"ok": true, "msg": "Abbauantrag für %s gestellt; Entscheidung spätestens in %d Tagen." % [pid, PERMIT_DAYS], "ref": pid}


func decide(pid: String, approve: bool, pct: float, reason: String, by: String) -> Dictionary:
	var p: Dictionary = permits.get(pid, {})
	if p.is_empty() or p.status != "antrag":
		return {"ok": false, "msg": "Kein offener Abbauantrag für %s." % pid}
	var c: Company = sim.company(int(p.cid))
	p.decision = "%s: %s" % [by, reason.left(200)]
	if not approve:
		p.status = "abgelehnt"
		sim.log_event("%s lehnt den Abbauantrag von %s für %s ab: %s" % [by, c.company_name, pid, reason], "warn", int(p.cid))
		return {"ok": true, "msg": "Abbauantrag %s abgelehnt." % pid, "ref": pid}
	p.status = "genehmigt"
	p.abgabe = clampf(pct, ROYALTY_MIN, ROYALTY_MAX)
	sim.log_event("%s genehmigt %s den Abbau auf %s, Förderabgabe %d %% an die Stadt." % [by, c.company_name, pid, int(round(float(p.abgabe) * 100.0))], "good", int(p.cid))
	sim.activity.add("buergermeister", -1, "stadt", "Abbaurecht %s für %s" % [pid, c.company_name], "Förderabgabe %d %%" % int(round(float(p.abgabe) * 100.0)), _cell(pid))
	return {"ok": true, "msg": "Abbau auf %s genehmigt (Förderabgabe %d %%)." % [pid, int(round(float(p.abgabe) * 100.0))], "ref": pid}


## Grundstueck mit Abbaurecht der Firma fuer einen Rohstoff ("" = keins).
func permitted_for(cid: int, kind: String) -> String:
	for pid in permits:
		var p: Dictionary = permits[pid]
		if int(p.cid) == cid and p.status == "genehmigt" and (kind == "" or str(sim.prod.deposit_of(pid).get("art", "")) == kind):
			if sim.parcels.parcel(pid).get("owner", "") == Parcels.CITY:
				return pid
	return ""


## Darf die Firma auf dieser Lagerstaette ein Bergwerk gruenden?
func check_found(cid: int, pid: String) -> Dictionary:
	if not enabled:
		return {"ok": true}
	if not explored.has(pid):
		return {"ok": false, "msg": "Lagerstätte %s ist nicht erkundet: zuerst Probebohrung (explore_deposit, %s, %d Tage)." % [pid, Catalog.money(EXPLORE_COST), EXPLORE_DAYS]}
	var p: Dictionary = permits.get(pid, {})
	if p.is_empty() or int(p.cid) != cid or p.status != "genehmigt":
		return {"ok": false, "msg": "Kein Abbaurecht für %s: Abbauantrag stellen (request_mining); der Bürgermeister entscheidet." % pid}
	return {"ok": true}


## Foerderabgabe je Foerdertag an die Stadtkasse (Anteil am Rohstoffwert).
func royalty(b: Dictionary, item: String, q: int) -> void:
	var p: Dictionary = permits.get(str(b.get("parcel", "")), {})
	var pct: float = float(p.get("abgabe", DEFAULT_ROYALTY)) if not p.is_empty() else (DEFAULT_ROYALTY if enabled else 0.0)
	if pct <= 0.0 or q <= 0:
		return
	var amount := snappedf(float(q) * float(sim.prod.art(item).get("basispreis", 5.0)) * pct, 0.01)
	sim.company(int(b.owner)).ledger.book("property_costs", -amount, true, "Förderabgabe %s" % b.id, sim.game_min, Towns.account_of(sim.towns.of_parcel(str(b.get("parcel", "")))), b.id)
	royalty_total += amount
	royalty_month += amount


# ------------------------------------------------------------------ Tageslauf
func on_day(day: int) -> void:
	for pid in drillings.keys():
		var d: Dictionary = drillings[pid]
		if day >= int(d.done):
			drillings.erase(pid)
			explored[pid] = {"by": int(d.cid), "day": day}
			sim.log_event("Probebohrung auf %s abgeschlossen: %s." % [pid, _result_text(pid)], "good", int(d.cid))
			sim.activity.add("unternehmen", int(d.cid), "bau", "Bohrergebnis %s" % pid, _result_text(pid), _cell(pid))
	for pid in permits:
		var p: Dictionary = permits[pid]
		if p.status == "antrag" and day - int(p.day) >= PERMIT_DAYS:
			decide(pid, true, DEFAULT_ROYALTY, "Frist abgelaufen, Bauamt genehmigt mit Regelabgabe", "Bauamt")


func on_month() -> void:
	royalty_month = 0.0


# ------------------------------------------------------------------ Naechster Schritt (KI)
## Je Rohstoff der naechste Schritt fuer die Firma: erkunden | abbauantrag | warten | zufahrt | gruenden, mit Grundstueck und Kosten.
func next_step(cid: int, kind: String) -> Dictionary:
	if sim.prod._deposits.is_empty():
		sim.prod.deposit_of("x")
	var best := {}
	var best_rank := -1
	var best_score := -1.0
	for pid in sim.prod._deposits:
		var d: Dictionary = sim.prod.deposit_of(pid)
		var p: Dictionary = sim.parcels.parcel(pid)
		if str(d.art) != kind or int(d.menge) <= 0 or p.is_empty() or p.owner != Parcels.CITY:
			continue
		var pm: Dictionary = permits.get(pid, {})
		if not pm.is_empty() and int(pm.cid) != cid and pm.status in ["antrag", "genehmigt"]:
			continue   # gehoert einem anderen
		if not pm.is_empty() and pm.status == "abgelehnt" and int(pm.cid) == cid:
			continue
		var road: bool = bool(sim.parcels.utilities_of(p).strasse)
		var step := "erkunden"
		var rank := 0
		if not enabled:
			step = "gruenden" if road else "zufahrt"
			rank = 4 if road else 3
		elif drillings.has(pid) or (pm.get("status", "") == "antrag"):
			step = "warten"
			rank = 2
		elif explored.has(pid) and pm.get("status", "") == "genehmigt":
			step = "gruenden" if road else "zufahrt"
			rank = 4 if road else 3
		elif explored.has(pid):
			step = "abbauantrag"
			rank = 1
		if step == "zufahrt" and sim.access.jobs.values().any(func(j): return j.parcel == pid and j.status in ["antrag", "im_bau"]):
			step = "warten"
		var e := estimate(pid)
		var score := float(e.get("menge", e.get("menge_geschaetzt", 0))) * float(e.get("qualitaet", e.get("qualitaet_geschaetzt", 0.5))) * (1.0 if road else 0.6)
		if rank > best_rank or (rank == best_rank and score > best_score):
			best_rank = rank
			best_score = score
			best = {"grundstueck": pid, "schritt": step, "lagerstaette": e, "strasse": road}
	if best.is_empty():
		return {}
	match str(best.schritt):
		"erkunden":
			best["kosten"] = int(EXPLORE_COST)
		"zufahrt":
			var pl: Dictionary = sim.access.plan(str(best.grundstueck))
			best["kosten"] = int(pl.get("kosten", 0)) if pl.get("ok", false) else -1
	return best


## Beobachtung der Unternehmer: naechster Schritt je Rohstoff.
func steps_for(cid: int) -> Dictionary:
	var out := {}
	for k in Production.DEPOSIT_KINDS:
		var s := next_step(cid, k)
		if s.is_empty():
			continue
		# knapp fuer die Beobachtung (Tokenbudget): erkundete Werte stehen in produktion_markt, Schaetzung nur vor der Bohrung
		var e := {"schritt": s.schritt, "grundstueck": s.get("grundstueck", "")}
		if s.has("kosten"):
			e["kosten"] = s.kosten
		if s.has("lagerstaette") and not bool(s.lagerstaette.get("erkundet", true)):
			e["schaetzung"] = {"menge": s.lagerstaette.get("menge_geschaetzt", 0), "qualitaet": s.lagerstaette.get("qualitaet_geschaetzt", 0)}
		if s.has("grund"):
			e["grund"] = s.grund
		out[k] = e
	return out


# ------------------------------------------------------------------ Buergermeister
func pending() -> Array:
	var out: Array = []
	for pid in permits:
		var p: Dictionary = permits[pid]
		if p.status == "antrag":
			var e := estimate(pid)
			out.append({"grundstueck": pid, "firma": int(p.cid), "name": sim.company(int(p.cid)).company_name, "rohstoff": e.art, "menge": int(e.get("menge", 0)),
				"qualitaet": float(e.get("qualitaet", 0.0)), "wert_je_einheit": float(sim.prod.art(str(e.art)).get("basispreis", 0.0)), "eingereicht_tag": int(p.day),
				"begruendung": str(p.reason)})
	return out


func summary() -> Dictionary:
	var mines: Array = sim.biz.items.values().filter(func(b): return b.branch == "bergwerk" and b.status not in ["geschlossen"])
	return {"abbauantraege": pending(), "bergwerke": mines.map(func(b): return {"id": b.id, "status": b.status, "firma": int(b.owner), "grundstueck": str(b.get("parcel", ""))}),
		"probebohrungen": drillings.keys(), "foerderabgabe_gesamt": int(royalty_total), "foerderabgabe_monat": int(royalty_month),
		"hinweis": "Abgabe 3–15 % des Rohstoffwerts: höher bringt mehr Steuern, zu hoch macht den Abbau unrentabel."}


func _cell(pid: String) -> Vector2i:
	var p: Dictionary = sim.parcels.parcel(pid)
	return Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2) if not p.is_empty() else Vector2i.ZERO


func to_dict() -> Dictionary:
	return {"explored": explored.duplicate(true), "drillings": drillings.duplicate(true), "permits": permits.duplicate(true), "royalty_total": royalty_total, "royalty_month": royalty_month}


func from_dict(d: Dictionary) -> void:
	explored = d.get("explored", {})
	drillings = d.get("drillings", {})
	permits = d.get("permits", {})
	royalty_total = float(d.get("royalty_total", 0.0))
	royalty_month = float(d.get("royalty_month", 0.0))
