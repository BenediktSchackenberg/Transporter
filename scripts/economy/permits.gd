class_name Permits
extends RefCounted
## Bauantragsprozess (Auftrag 7, Etappe 2).
##   Entwurf -> Antrag -> Pruefung -> Rueckfrage/Ueberarbeitung -> Entscheidung -> Genehmigung (ggf. mit Auflagen) oder Ablehnung
## Die Bearbeitung kostet Verwaltungskapazitaet (Rathaus-Beschaeftigte) und Zeit; die Entscheidung folgt ausschliesslich den
## Feststellungen von `Planning.assess` und ist begruendet. Gebuehren werden erst bei der Genehmigung faellig.

const STATUS := ["entwurf", "beantragt", "in_pruefung", "rueckfrage", "zur_entscheidung", "entschieden"]
const RESULTS := ["genehmigt", "genehmigt_mit_bedingungen", "ueberarbeitung_erforderlich", "abgelehnt"]
const STAFF_PER_POINT := 8.0          # so viele Rathaus-Beschaeftigte erbringen einen Bearbeitungspunkt je Tag
const REVISION_EFFORT := 1            # Nachpruefung nach einer Rueckfrage
const PERMIT_DAYS := 180              # Geltungsdauer einer Genehmigung
const MAYOR_UNITS := 6                # ab so vielen Einheiten oder
const MAYOR_COST := 400000.0          # ab diesen Gesamtkosten entscheidet die Buergermeisterebene
const MAYOR_AGENT_WAIT_DAYS := 12    # ist eine Buergermeister-KI angebunden, wartet die Vertretung laenger
const MAYOR_WAIT_DAYS := 2            # Frist, bis die regelbasierte Verwaltung entscheidet, wenn keine Buergermeister-KI angebunden ist

var sim
var apps := {}                    # "A<n>" -> Antrag
var _next := 1
var mayor_attached := false       # Etappe 3: eine Buergermeister-KI entscheidet grosse Vorhaben selbst


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


# ------------------------------------------------------------------ Entwurf und Antrag
## Entwurf anlegen. params: def, floors, parking, financing {eigenmittel, kredit, kredit_gesichert, foerderung}.
func draft(applicant: String, parcel_id: String, params: Dictionary) -> Dictionary:
	var p: Dictionary = sim.parcels.parcel(parcel_id)
	if p.is_empty():
		return {"ok": false, "msg": "Grundstück %s gibt es nicht." % parcel_id}
	if not _has_rights(applicant, p):
		return {"ok": false, "msg": "%s hat an %s weder Eigentum noch eine Reservierung." % [applicant, parcel_id]}
	if not Planning.DEFS.has(str(params.get("def", ""))):
		return {"ok": false, "msg": "Gebäudeart '%s' unbekannt." % params.get("def", "")}
	for a in apps.values():
		if a.parcel == parcel_id and a.status != "entschieden":
			return {"ok": false, "msg": "Für %s läuft bereits der Antrag %s." % [parcel_id, a.id]}
		if a.parcel == parcel_id and a.status == "entschieden" and a.result in ["genehmigt", "genehmigt_mit_bedingungen"] and not a.get("expired", false):
			return {"ok": false, "msg": "Für %s liegt bereits die Genehmigung %s vor." % [parcel_id, a.id]}
	var d: Dictionary = Planning.DEFS[params.def]
	var app := {"id": "A%d" % _next, "applicant": applicant, "parcel": parcel_id, "def": str(params.def), "floors": int(params.get("floors", d.floors[0])),
		"parking": int(params.get("parking", d.parking)), "financing": params.get("financing", {}).duplicate(), "status": "entwurf", "result": "",
		"effort": 0, "progress": 0, "filed_day": -1, "decided_day": -1, "questions": [], "conditions": [], "reasons": [], "answers": [],
		"decided_by": "", "decision": "", "fees_paid": 0.0, "valid_until": -1, "history": [], "expired": false}
	_next += 1
	apps[app.id] = app
	_log(app, "Entwurf angelegt")
	return {"ok": true, "msg": "Entwurf %s für %s (%s)." % [app.id, parcel_id, d.label], "id": app.id}


## Vorpruefung des Entwurfs, ohne ihn einzureichen.
func preview(app_id: String) -> Dictionary:
	var a: Dictionary = apps.get(app_id, {})
	if a.is_empty():
		return {}
	return Planning.assess(sim.parcels.parcel(a.parcel), a)


func submit(app_id: String) -> Dictionary:
	var a: Dictionary = apps.get(app_id, {})
	if a.is_empty() or a.status != "entwurf":
		return {"ok": false, "msg": "Antrag %s ist kein Entwurf." % app_id}
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	if not _has_rights(a.applicant, p):
		return {"ok": false, "msg": "Die Rechte am Grundstück %s liegen nicht mehr bei %s." % [a.parcel, a.applicant]}
	a.status = "beantragt"
	a.filed_day = _today()
	var res := Planning.assess(p, a)
	a.effort = 2 + int(ceil(float(res.units) / 6.0)) + (1 if a.floors > 2 else 0)
	a.progress = 0
	_log(a, "Antrag eingereicht (Bearbeitungsaufwand %d)" % a.effort)
	return {"ok": true, "msg": "Antrag %s eingereicht; Warteschlange Position %d." % [a.id, queue().size()]}


## Rueckfrage beantworten: geaenderte Angaben uebernehmen und erneut einreichen (kurze Nachpruefung).
func revise(app_id: String, changes: Dictionary, answer: String = "") -> Dictionary:
	var a: Dictionary = apps.get(app_id, {})
	if a.is_empty() or a.status != "rueckfrage":
		return {"ok": false, "msg": "Antrag %s hat keine offene Rückfrage." % app_id}
	for k in ["floors", "parking", "def"]:
		if changes.has(k):
			a[k] = int(changes[k]) if k != "def" else str(changes[k])
	if changes.has("financing"):
		a.financing = changes.financing.duplicate()
	a.answers.append({"day": _today(), "text": answer if answer != "" else "Angaben überarbeitet"})
	a.questions = []
	a.status = "beantragt"
	a.result = ""
	a.effort = REVISION_EFFORT
	a.progress = 0
	_log(a, "Überarbeitung eingereicht")
	return {"ok": true, "msg": "Überarbeitung zu %s eingereicht." % a.id}


## Entscheidung der Buergermeisterebene. Die Engine laesst nur zu, was die Pruefung hergibt: Genehmigung nie gegen benannte Ablehnungsgruende,
## Ablehnung nur wegen benannter fehlender Voraussetzungen, Rueckfragen hoechstens zweimal je Antrag.
func mayor_decide(app_id: String, decision: String, reason: String, extra_conditions: Array, by: String) -> Dictionary:
	var a: Dictionary = apps.get(app_id, {})
	if a.is_empty() or a.status != "zur_entscheidung":
		return {"ok": false, "msg": "Antrag %s liegt nicht zur Entscheidung vor." % app_id}
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	var res := Planning.assess(p, a)
	var day := _today()
	match decision:
		"genehmigen", "bedingungen":
			if not res.ok:
				return {"ok": false, "msg": "Genehmigung nicht möglich: " + " ".join(res.blocking)}
			if not res.questions.is_empty():
				return {"ok": false, "msg": "Genehmigung nicht möglich, offene Punkte: " + " ".join(res.questions) + " (Rückfrage stellen)."}
			if decision == "bedingungen" and extra_conditions.is_empty() and res.conditions.is_empty():
				return {"ok": false, "msg": "Für eine Genehmigung unter Bedingungen sind Bedingungen anzugeben."}
			var extra: Array = []
			for c in extra_conditions.slice(0, 3):
				extra.append(str(c).left(160))
			a["extra_conditions"] = extra
			a["mayor_reason"] = reason
			_decide(a, day, by)
			return {"ok": a.status == "entschieden" and a.result.begins_with("genehmigt"), "msg": a.decision, "ref": app_id}
		"ablehnen":
			if res.blocking.is_empty() and res.questions.is_empty():
				return {"ok": false, "msg": "Es ist keine fehlende Voraussetzung benannt: der Antrag erfüllt alle Regeln und ist zu genehmigen."}
			a.decided_by = by
			a.decided_day = day
			var why: Array = res.blocking + res.questions
			if reason != "":
				why.append(reason)
			_close(a, "abgelehnt", why)
			return {"ok": true, "msg": a.decision, "ref": app_id}
		"rueckfrage":
			if int(a.get("mayor_queries", 0)) >= 2:
				return {"ok": false, "msg": "Die Zahl der Rückfragen (2) ist ausgeschöpft; bitte entscheiden."}
			a["mayor_queries"] = int(a.get("mayor_queries", 0)) + 1
			a.status = "rueckfrage"
			a.result = "ueberarbeitung_erforderlich"
			a.questions = res.questions + ([reason] if reason != "" else [])
			a.decided_by = by
			a.decision = "Rückfrage der Bürgermeisterebene: " + " ".join(a.questions)
			_log(a, a.decision)
			return {"ok": true, "msg": a.decision, "ref": app_id}
	return {"ok": false, "msg": "decision muss genehmigen, bedingungen, ablehnen oder rueckfrage sein."}


func withdraw(app_id: String, applicant: String) -> Dictionary:
	var a: Dictionary = apps.get(app_id, {})
	if a.is_empty() or a.applicant != applicant or a.status == "entschieden":
		return {"ok": false, "msg": "Antrag %s kann nicht zurückgezogen werden." % app_id}
	a.status = "entschieden"
	a.result = "abgelehnt"
	a.decided_by = "Antragsteller"
	a.decision = "Vom Antragsteller zurückgezogen."
	a.decided_day = _today()
	_log(a, a.decision)
	return {"ok": true, "msg": "Antrag zurückgezogen."}


# ------------------------------------------------------------------ Bearbeitung
## Verwaltungskapazitaet: Bearbeitungspunkte je Tag aus den Rathaus-Beschaeftigten.
func capacity() -> float:
	return maxf(1.0, float(sim.citizens.employed_count("rathaus")) / STAFF_PER_POINT)


## Warteschlange in Bearbeitungsreihenfolge (aeltester Antrag zuerst).
func queue() -> Array:
	var out: Array = apps.values().filter(func(a): return a.status in ["beantragt", "in_pruefung"])
	out.sort_custom(func(a, b): return a.filed_day < b.filed_day or (a.filed_day == b.filed_day and a.id < b.id))
	return out


## Voraussichtlicher Entscheidungstag eines Antrags in der Warteschlange.
func eta_day(app_id: String) -> int:
	var points := 0.0
	var cap := capacity()
	for a in queue():
		points += float(a.effort - a.progress)
		if a.id == app_id:
			return _today() + int(ceil(points / cap))
	return -1


func on_day(day: int) -> void:
	var budget := capacity()
	for a in queue():
		if budget <= 0.0:
			break
		a.status = "in_pruefung"
		var use := minf(budget, float(a.effort - a.progress))
		a.progress += int(ceil(use))
		budget -= use
		if a.progress >= a.effort:
			_review(a, day)
	for a in apps.values():
		if a.status == "zur_entscheidung" and day - int(a.decided_day) >= (MAYOR_AGENT_WAIT_DAYS if mayor_attached else MAYOR_WAIT_DAYS):
			_decide(a, day, "Verwaltung (regelbasiert, Vertretung des Bürgermeisters)")
		if a.status == "entschieden" and a.result in ["genehmigt", "genehmigt_mit_bedingungen"] and not a.expired and day > int(a.valid_until):
			_expire(a)


## Pruefung abgeschlossen: grosse Vorhaben gehen zur Buergermeisterebene, alle anderen entscheidet die Verwaltung sofort.
func _review(a: Dictionary, day: int) -> void:
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	var res := Planning.assess(p, a)
	if (res.units > MAYOR_UNITS or float(res.costs.get("gesamt", 0.0)) > MAYOR_COST) and res.ok and res.questions.is_empty():
		a.status = "zur_entscheidung"
		a.decided_day = day   # Beginn der Wartezeit
		_log(a, "Prüfung abgeschlossen; Entscheidung durch Bürgermeisterebene erforderlich")
		return
	_decide(a, day, "Bauverwaltung")


func _decide(a: Dictionary, day: int, by: String) -> void:
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	var res := Planning.assess(p, a)
	a.decided_by = by
	a.decided_day = day
	a.reasons = []
	a.conditions = res.conditions.duplicate()
	for c in a.get("extra_conditions", []):
		a.conditions.append({"typ": "auflage", "text": str(c)})
	if not _has_rights(a.applicant, p):
		_close(a, "abgelehnt", ["Die Rechte am Grundstück %s liegen nicht mehr beim Antragsteller." % a.parcel])
		return
	if not res.ok:
		_close(a, "abgelehnt", res.blocking)
		return
	if not res.questions.is_empty():
		a.status = "rueckfrage"
		a.result = "ueberarbeitung_erforderlich"
		a.questions = res.questions
		a.decision = "Überarbeitung erforderlich: " + " ".join(res.questions)
		_log(a, a.decision)
		return
	var fee := float(res.costs.gebuehr)
	if not _charge(a.applicant, fee, "Baugenehmigungsgebühr %s" % a.id):
		a.status = "rueckfrage"
		a.result = "ueberarbeitung_erforderlich"
		a.questions = ["Die Genehmigungsgebühr von %s kann nicht gezahlt werden." % Catalog.money(fee)]
		a.decision = a.questions[0]
		_log(a, a.decision)
		return
	a.fees_paid = fee
	a.valid_until = day + PERMIT_DAYS
	var cond_text := ""
	if not a.conditions.is_empty():
		cond_text = " Auflagen: " + " ".join(a.conditions.map(func(c): return c.text))
	a.reasons = ["Alle Voraussetzungen im %s erfüllt: %s, %d Geschosse, Bebauung %d %%." % [Parcels.ZONES[p.zone].label, Planning.DEFS[a.def].label, a.floors, roundi(float(res.cover) * 100.0)]]
	if str(a.get("mayor_reason", "")) != "":
		a.reasons.append("Begründung der Bürgermeisterebene: " + str(a.mayor_reason))
	_close(a, "genehmigt_mit_bedingungen" if not a.conditions.is_empty() else "genehmigt", a.reasons, cond_text)


func _close(a: Dictionary, result: String, reasons: Array, extra: String = "") -> void:
	a.status = "entschieden"
	a.result = result
	a.reasons = reasons
	a.decision = ("Genehmigt." if result == "genehmigt" else ("Genehmigt unter Bedingungen." if result == "genehmigt_mit_bedingungen" else "Abgelehnt.")) \
		+ " " + " ".join(reasons) + extra
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	if result in ["genehmigt", "genehmigt_mit_bedingungen"]:
		sim.parcels.mark(a.parcel, "genehmigt", a.id)
	_log(a, a.decision)
	sim.log_event("Bauantrag %s (%s, %s): %s" % [a.id, a.applicant, p.get("id", ""), a.decision.left(160)], "info")


func _expire(a: Dictionary) -> void:
	a.expired = true
	var p: Dictionary = sim.parcels.parcel(a.parcel)
	if p.get("state", "") == "genehmigt" and p.get("application", "") == a.id:
		sim.parcels.mark(a.parcel, "privat_gehalten" if str(p.owner) != Parcels.CITY else "frei", "")
	_log(a, "Genehmigung abgelaufen")


# ------------------------------------------------------------------ Hilfen
func _has_rights(applicant: String, p: Dictionary) -> bool:
	if p.is_empty():
		return false
	return p.owner == applicant or (p.state in ["reserviert", "genehmigt"] and p.reservation.get("holder", "") == applicant)


## Gebuehr vom Konto des Antragstellers an die Stadt (Haushalt: Guthaben; Unternehmen: Kasse als Verwaltungsaufwand).
func _charge(applicant: String, amount: float, note: String) -> bool:
	if amount <= 0.0:
		return true
	if applicant.begins_with("H"):
		var h: Dictionary = sim.households.homes.get(applicant, {})
		if h.is_empty() or float(h.balance) < amount:
			return false
		h.balance = float(h.balance) - amount
		sim.economy.transfer("H0", "P0", amount)
		return true
	if applicant.begins_with("C"):
		var c: Company = sim.company(int(applicant.substr(1)))
		if c == null or c.ledger.cash < amount:
			return false
		c.ledger.book("admin", -amount, true, note, sim.game_min)
		return true
	return applicant == Planning.PUBLIC_APPLICANT


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _log(a: Dictionary, text: String) -> void:
	a.history.append({"day": _today(), "text": text})


func summary() -> Dictionary:
	var by_status := {}
	var by_result := {}
	for a in apps.values():
		by_status[a.status] = int(by_status.get(a.status, 0)) + 1
		if a.result != "":
			by_result[a.result] = int(by_result.get(a.result, 0)) + 1
	return {"anzahl": apps.size(), "warteschlange": queue().size(), "kapazitaet_je_tag": capacity(), "nach_status": by_status, "nach_ergebnis": by_result}


func to_dict() -> Dictionary:
	return {"apps": apps, "next": _next}


func from_dict(d: Dictionary) -> void:
	apps = d.get("apps", {})
	for a in apps.values():
		for k in ["floors", "parking", "effort", "progress", "filed_day", "decided_day", "valid_until"]:
			a[k] = int(a[k])
	_next = int(d.get("next", 1))
