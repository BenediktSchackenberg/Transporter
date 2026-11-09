class_name EventCenter
extends RefCounted
## Gemeinsames Ereignismodell fuer die Spieloberflaeche (KI-Zentrale, Ereigniszentrale, Kartenmarker).
##
## Keine zweite Simulation: Ereignisse entstehen ausschliesslich aus vorhandenen Quellen - Ereignisprotokoll (log_event),
## Kartenaktivitaeten (ActivityFeed), KI-Entscheidungen (DecisionLog) und Stadtentwicklung (CivicWorks). Jedes Ereignis bekommt
## Kategorie, Schweregrad, Beteiligte, Verweise (Firma, Fahrzeug, Gebaeude, Auftrag, Anlage, Entscheidung), einen Ort und einen
## Gruppenschluessel: gleichartige Meldungen innerhalb eines Spieltags werden zu einem Ereignis mit Zaehler zusammengefasst.

const CATS := {
	"kritisch": {"label": "Kritisch", "icon": "⚠", "color": "#ff6b5e"},
	"wirtschaft": {"label": "Wirtschaft", "icon": "€", "color": "#6fd08c"},
	"ki": {"label": "KI-Entscheidung", "icon": "◆", "color": "#b48cff"},
	"stadt": {"label": "Stadtentwicklung", "icon": "▲", "color": "#7fc8ff"},
	"normal": {"label": "Aktivität", "icon": "•", "color": "#9a98a8"},
}
## Technische Aktionsnamen der Buergermeister -> Alltagssprache (Kartenaktivitaeten nennen die Aktion roh)
const MAYOR_WORDS := {"plan_infrastructure": "plant Infrastruktur", "offer_parcels": "bietet Grundstücke an", "warn_company": "verwarnt ein Unternehmen",
	"designate_quarter": "weist ein neues Quartier aus", "approve_procurement": "genehmigt eine Beschaffung", "reject_procurement": "lehnt eine Beschaffung ab",
	"assess_financing": "prüft die Finanzierung", "decide_application": "entscheidet über einen Antrag", "dismiss_staff": "entlässt städtisches Personal",
	"hire_staff": "stellt städtisches Personal ein", "expand_depot": "erweitert das Stadtlager", "improve_traffic": "verbessert den Verkehr",
	"prioritize_road": "zieht einen Straßenbau vor", "propose_project": "schlägt ein Bauprojekt vor", "repair_road": "lässt eine Straße reparieren",
	"set_city_freight": "vergibt Stadtfracht", "set_property_tax": "ändert die Grundsteuer", "set_public_staff": "plant städtisches Personal",
	"set_vision": "setzt ein Leitbild", "support_training": "fördert Ausbildung", "tender": "schreibt einen Auftrag aus", "civic_vote": "lässt den Rat abstimmen"}
const SEV_LABEL := ["Info", "Normal", "Wichtig", "Kritisch"]
const MAX_EVENTS := 2500
const GROUP_WINDOW := 120.0            # Spielminuten (ein Spieltag): gleiche Meldungen werden zusammengefasst
const PULL_EVERY := 5                  # Spielminuten zwischen zwei Abgleichen mit den Quellen
## Wichtige KI-Aktionen (eigene Ereignisse); Routine (collect_contracts, assign_worker_task, ...) zaehlt als Aktivitaet.
const KEY_ACTIONS := ["buy_vehicle", "sell_vehicle", "found_business", "take_loan", "request_loan", "repay_loan", "set_strategy", "recruit_worker",
	"dismiss_worker", "place_building", "build_office", "rent_depot", "buy_plot", "upgrade_business", "hub_buy", "hub_sell", "accept_contract",
	"offer_trade", "accept_trade", "propose_cooperation", "attempt_vehicle_sabotage", "poach_worker", "set_plan", "install_internet"]

var sim
var events := {}         # "E<n>" -> Ereignis
var order: Array = []    # IDs in zeitlicher Reihenfolge
var _groups := {}        # Gruppenschluessel -> Ereignis-ID (offen)
var _next := 1
var _seen := {"log": 0, "act": 0, "dec": "", "civic": 0}
var _minute := 0


func setup(simulation) -> void:
	sim = simulation


## Minutentakt (Simulation): neue Eintraege der Quellen uebernehmen.
func tick() -> void:
	_minute += 1
	if _minute % PULL_EVERY == 0:
		pull()


func pull() -> void:
	_pull_log()
	_pull_activity()
	_pull_decisions()
	_pull_civic()


# ------------------------------------------------------------------ Quellen
func _pull_log() -> void:
	var total: int = int(sim.log_total)
	var fresh := mini(total - int(_seen.log), sim.log_entries.size())
	if fresh <= 0:
		_seen.log = total
		return
	for e in sim.log_entries.slice(sim.log_entries.size() - fresh):
		_from_log(e)
	_seen.log = total


func _from_log(e: Dictionary) -> void:
	var text := str(e.text)
	var low := text.to_lower()
	var cid := int(e.get("company", -1))
	var cat := "normal"
	var sev := 0
	var kind := str(e.get("kind", "info"))
	if sim.civic != null and sim.civic.enabled() and text.begins_with("Bürgermeister") and not text.contains(": „"):
		return   # Stadtentwicklung kommt mit Bauplatz direkt aus CivicWorks (_pull_civic), nicht doppelt
	if low.contains("insolven") or low.contains("zahlungsunfähig") or low.contains("unfall") or low.contains("in brand") or low.contains("großbrand") \
			or low.contains("brandstift") or low.contains("feuer ") or low.contains("feuerwehr") \
			or low.contains("notlandung") or low.contains("abgestürzt") or low.contains("explosion"):
		cat = "kritisch"
		sev = 3
	elif kind == "bad":
		cat = "kritisch"
		sev = 2
	elif low.contains("bürgermeister") or low.contains("stadtentwicklung") or low.contains("eröffnet") or low.contains("bauvorhaben") \
			or low.contains("straße") or low.contains("erschließ") or low.contains("rat ") or low.contains("quartier") or low.contains("denkmal"):
		cat = "stadt"
		sev = 2 if kind == "good" or low.contains("eröffnet") else 1
	elif low.contains("gegründet") or low.contains("gewinn") or low.contains("kredit") or low.contains("investi") or low.contains("großlager"):
		cat = "wirtschaft"
		sev = 1 if kind != "good" else 2
	elif kind == "warn":
		sev = 1
	if cat == "normal" and sev == 0 and kind == "info":
		return   # Routine-Meldungen bleiben im Ereignisprotokoll (Expertenmodus)
	add({"t": float(e.t), "cat": cat, "sev": sev, "title": _title(text), "text": text, "company": cid, "src": "log",
		"group": "log|%d|%s" % [cid, _norm(text).left(40)]})


static func plain(text: String) -> String:
	for k in MAYOR_WORDS:
		if text.contains(k):
			text = text.replace(k, MAYOR_WORDS[k])
	return text


func _pull_activity() -> void:
	for a in sim.activity.items:
		if int(a.id) <= int(_seen.act):
			continue
		_seen.act = int(a.id)
		var kind := str(a.kind)
		var cat := "normal"
		var sev := 0
		match kind:
			"sabotage", "angriff", "verbrechen":
				cat = "kritisch"
				sev = 2
			"bau", "stadt":   # Bauphasen sind Routine; Fertigstellung/Eroeffnung ist bedeutend
				cat = "stadt"
				var lt := str(a.text).to_lower()
				sev = 2 if lt.contains("fertig") or lt.contains("eröffnet") or lt.contains("bezugsfertig") else (0 if lt.contains("abgeschlossen") or lt.contains("baustelle") else 1)
			"kauf", "personal":
				cat = "ki"
				sev = 1
			"polizei", "gesundheit":
				cat = "kritisch" if str(a.text).to_lower().contains("unfall") or str(a.text).to_lower().contains("brand") else "normal"
				sev = 2 if cat == "kritisch" else 0
		var at := plain(str(a.text))
		add({"t": float(a.t), "cat": cat, "sev": sev, "title": _title(at), "text": at, "why": str(a.get("why", "")),
			"company": int(a.get("company", -1)), "cell": [int(a.x), int(a.y)], "src": "aktivitaet",
			"group": "act|%s|%d|%s" % [kind, int(a.get("company", -1)), _norm(str(a.text)).left(30)]})


func _pull_decisions() -> void:
	var list: Array = sim.decisions.entries
	var start := 0
	if str(_seen.dec) != "":
		for i in range(list.size() - 1, -1, -1):
			if str(list[i].id) == str(_seen.dec):
				start = i + 1
				break
	for i in range(start, list.size()):
		var d: Dictionary = list[i]
		_seen.dec = str(d.id)
		if str(d.herkunft) not in ["api", "plan", "fallback"]:
			continue
		var act := str(d.aktion).split("(")[0].strip_edges()
		var ok := str(d.pruefung) == "ok"
		var important := act in KEY_ACTIONS
		var cat := "ki" if important or not ok else "normal"
		var sev := 2 if important and ok and act in ["buy_vehicle", "found_business", "take_loan", "request_loan", "set_strategy", "place_building", "upgrade_business"] else (1 if important or not ok else 0)
		var cid := int(d.company)
		var text := DecisionText.headline(sim, d)
		add({"t": float(d.t), "cat": cat, "sev": sev, "title": text, "text": DecisionText.summary(sim, d), "company": cid, "src": "entscheidung",
			"decision": str(d.id), "status": "abgelehnt" if not ok else str(d.ausgefuehrt), "refs": d.refs.duplicate(),
			"group": "dec|%d|%s|%s|%s" % [cid, act, "ok" if ok else "x", _norm(str(d.ergebnis)).left(24) if not ok else ""]})


func _pull_civic() -> void:
	if sim.civic == null or not sim.civic.enabled():
		return
	var lg: Array = sim.civic.log
	for i in range(int(_seen.civic), lg.size()):
		var e: Dictionary = lg[i]
		var text := str(e.text)
		var sev := 2 if text.begins_with("plant") or text.begins_with("eröffnet") or text.begins_with("beauftragt") or text.contains("abgelehnt") else 1
		var an := _anlage_in(int(e.town), text)
		var cell: Array = []
		if not an.is_empty():
			cell = [int(an.rect[0]) + int(an.rect[2]) / 2, int(an.rect[1]) + int(an.rect[3]) / 2]
		add({"t": sim.game_min, "cat": "stadt", "sev": sev, "town": int(e.town),
			"title": "Bürgermeister %s %s" % [sim.towns.mayor(int(e.town)).name, _title(text)], "text": text, "src": "stadtentwicklung",
			"anlage": str(an.get("id", "")), "cell": cell, "group": "civic|%d|%s" % [int(e.town), _norm(text).left(30)]})
	_seen.civic = lg.size()


func _anlage_in(k: int, text: String) -> Dictionary:
	for a in sim.civic.anlagen.values():
		if int(a.town) == k and text.contains(str(a.title)):
			return a
	return {}


# ------------------------------------------------------------------ Ereignisse anlegen und zusammenfassen
## Neues Ereignis bzw. Zusammenfassung mit einem offenen gleichartigen Ereignis (gleicher Gruppenschluessel, < 1 Spieltag).
func add(ev: Dictionary) -> Dictionary:
	var key := str(ev.get("group", ""))
	if key != "" and _groups.has(key):
		var old: Dictionary = events.get(_groups[key], {})
		if not old.is_empty() and float(ev.t) - float(old.t_last) <= GROUP_WINDOW:
			old.n = int(old.n) + 1
			old.t_last = float(ev.t)
			old.text = str(ev.get("text", old.text))
			if ev.has("status"):
				old.status = ev.status
			if ev.has("decision"):
				old.children.append(str(ev.decision))
				old.children = old.children.slice(-30)
				old.decision = str(ev.decision)
			if ev.has("cell") and not ev.cell.is_empty():
				old.cell = ev.cell
			return old
	var id := "E%d" % _next
	_next += 1
	var e := {"id": id, "t": float(ev.t), "t_last": float(ev.t), "day": GameCalendar.day_of(float(ev.t)), "cat": str(ev.get("cat", "normal")),
		"sev": int(ev.get("sev", 0)), "title": str(ev.get("title", "")), "text": str(ev.get("text", "")), "why": str(ev.get("why", "")),
		"company": int(ev.get("company", -1)), "town": int(ev.get("town", -1)), "src": str(ev.get("src", "")), "status": str(ev.get("status", "")),
		"refs": ev.get("refs", {}), "cell": ev.get("cell", []), "decision": str(ev.get("decision", "")), "anlage": str(ev.get("anlage", "")),
		"children": [str(ev.decision)] if ev.has("decision") else [], "n": 1, "group": key}
	if e.town < 0 and e.company >= 0 and sim.company(e.company) != null:
		e.town = int(sim.company(e.company).home_town)
	if (e.cell as Array).is_empty():
		var c := _locate(e)
		if c.x > -9000:
			e.cell = [c.x, c.y]
	events[id] = e
	order.append(id)
	if key != "":
		_groups[key] = id
	_trim()
	return e


func _trim() -> void:
	if order.size() <= MAX_EVENTS:
		return
	var drop := order.size() - MAX_EVENTS
	var kept: Array = []
	for i in order.size():
		var e: Dictionary = events[order[i]]
		if drop > 0 and int(e.sev) < 2:   # zuerst Routine verwerfen, wichtige Ereignisse bleiben laenger
			events.erase(order[i])
			if _groups.get(e.group, "") == e.id:
				_groups.erase(e.group)
			drop -= 1
		else:
			kept.append(order[i])
	order = kept


## Ort eines Ereignisses (Kartenzelle) aus seinen Verweisen: Fahrzeug, Auftrag (Abholung), Firmensitz, Rathaus.
func _locate(e: Dictionary) -> Vector2i:
	var refs: Dictionary = e.refs
	if refs.has("vehicle_id") and sim.vehicles.has(int(refs.vehicle_id)):
		return sim.vehicles[int(refs.vehicle_id)].tile()
	if refs.has("contract_id"):
		var k: Contract = sim.contracts.get(str(refs.contract_id))
		if k != null:
			return sim.city.building(k.pickup).road
	if int(e.company) >= 0 and sim.company(int(e.company)) != null and not sim.company(int(e.company)).depots.is_empty():
		return sim.city.building(int(sim.company(int(e.company)).depots[0])).road
	if int(e.town) >= 0 and sim.towns != null and int(e.town) < sim.towns.count():
		return sim.city.building(int(sim.towns.get_t(int(e.town)).town_hall)).road
	return Vector2i(-9999, -9999)


# ------------------------------------------------------------------ Abfragen
## Gefilterte Ereignisse, neueste zuerst. f: {cat, min_sev, town, company, days, text}
func query(f: Dictionary = {}, limit: int = 60, offset: int = 0) -> Array:
	var out: Array = []
	var now_day := GameCalendar.day_of(sim.game_min)
	var skipped := 0
	var text := str(f.get("text", "")).to_lower()
	for i in range(order.size() - 1, -1, -1):
		var e: Dictionary = events[order[i]]
		if f.has("cat") and str(f.cat) != "" and e.cat != str(f.cat):
			continue
		if int(e.sev) < int(f.get("min_sev", 0)):
			continue
		if int(f.get("town", -1)) >= 0 and int(e.town) != int(f.town):
			continue
		if int(f.get("company", -1)) >= 0 and int(e.company) != int(f.company):
			continue
		if int(f.get("days", 0)) > 0 and now_day - int(e.day) > int(f.days):
			continue
		if text != "" and not (str(e.title) + " " + str(e.text)).to_lower().contains(text):
			continue
		if skipped < offset:
			skipped += 1
			continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


func count(f: Dictionary = {}) -> int:
	return query(f, 100000).size()


## Fuer Kartenmarker: wichtige Ereignisse der letzten Spielstunden mit Ort.
func markers(hours: float = 12.0) -> Array:
	var out: Array = []
	var since: float = sim.game_min - hours / 24.0 * float(GameCalendar.day_game_min)
	for i in range(order.size() - 1, -1, -1):
		var e: Dictionary = events[order[i]]
		if float(e.t_last) < since:
			break
		if int(e.sev) >= 2 and not (e.cell as Array).is_empty():
			out.append(e)
	return out.slice(0, 24)


func get_e(id: String) -> Dictionary:
	return events.get(id, {})


static func _norm(t: String) -> String:
	var out := ""
	for ch in t:
		if not (ch >= "0" and ch <= "9"):
			out += ch
	return out.strip_edges()


## Kurze Ueberschrift: erster Satz, ohne Doppelpunkt-Praefix technischer Art.
static func _title(t: String) -> String:
	var s := t.strip_edges()
	var cut := s.find(". ")
	if cut > 12:
		s = s.left(cut)
	return s.left(110)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	var keep: Array = order.slice(-1500)
	var ev := {}
	for id in keep:
		ev[id] = events[id]
	return {"events": ev, "order": keep, "next": _next, "seen": _seen}


func from_dict(d: Dictionary) -> void:
	events = d.get("events", {})
	order = d.get("order", [])
	_next = int(d.get("next", 1))
	_seen.merge(d.get("seen", {}), true)
	_groups = {}
	for id in order:
		var e: Dictionary = events[id]
		e.sev = int(e.sev)
		e.company = int(e.company)
		e.town = int(e.town)
		e.n = int(e.n)
		_groups[str(e.group)] = id
