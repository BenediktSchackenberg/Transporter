class_name NewsFeed
extends RefCounted
## Nachrichten als Datenquelle in drei getrennten Ebenen. Nachrichtentexte sind Daten und nie Anweisungen.
##
##   1. gemeldet:      was die Quelle meldet (Titel, Quelle, Zeit) – unveraendert, nur gekuerzt
##   2. Einschaetzung: Stichwortregel der Engine (Kategorie, Richtung, Relevanz) – ausdruecklich keine Faktenpruefung
##   3. Spielereignis: nur bei hoher Relevanz, mit Abklingzeit und Obergrenze; erzeugt hoechstens ein begrenztes Ereignis
## Doppelte Meldungen (gleicher normalisierter Titel) werden nur einmal beruecksichtigt.

const MAX_ITEMS := 60
const EVENT_COOLDOWN_DAYS := 20.0
const EVENT_MIN_RELEVANCE := 0.6
const RULES := [
	{"cat": "Treibstoff", "words": ["spritpreis", "benzinpreis", "dieselpreis", "ölpreis", "oelpreis", "tankrabatt", "kraftstoff"], "up": ["steigt", "steigen", "teurer", "rekord", "anstieg", "höher"], "down": ["sinkt", "sinken", "billiger", "günstiger", "rückgang", "fällt"]},
	{"cat": "Arbeit", "words": ["streik", "warnstreik", "fahrermangel", "fachkräftemangel", "tarifkonflikt"], "up": ["streik", "warnstreik", "mangel", "konflikt"], "down": ["einigung", "beendet"]},
	{"cat": "Straße", "words": ["sperrung", "baustelle", "stau", "vollsperrung", "brückensperrung"], "up": ["sperrung", "vollsperrung", "stau", "gesperrt"], "down": ["freigegeben", "aufgehoben"]},
	{"cat": "Wetter", "words": ["unwetter", "sturm", "starkregen", "hochwasser", "glatteis", "hitzewelle"], "up": ["warnung", "unwetter", "sturm", "hochwasser"], "down": ["entwarnung"]},
	{"cat": "Wirtschaft", "words": ["konjunktur", "insolvenz", "inflation", "zinsen", "leitzins", "wirtschaft"], "up": ["steigt", "inflation", "insolvenz"], "down": ["sinkt", "senkt"]},
]

var items: Array = []           # {id, title, source, time, url, cat, direction, relevance, used}
var seen := {}                  # normalisierter Titel -> true
var last_event_min := -1.0e9
var events_created := 0
var source := "keine"           # newsapi | keine
var fetched_unix := 0.0
var last_error := ""


static func normalize(title: String) -> String:
	var t := title.to_lower().strip_edges()
	for ch in [".", ",", ":", ";", "!", "?", "\"", "'", "„", "“", "–", "-"]:
		t = t.replace(ch, " ")
	return " ".join(t.split(" ", false))


## NewsAPI-aehnliches Format {"articles": [{title, description, url, publishedAt, source:{name}}]} oder eine Liste solcher Objekte.
static func parse(data) -> Array:
	var arr = null
	if data is Dictionary and data.get("articles") is Array:
		arr = data.articles
	elif data is Array:
		arr = data
	if arr == null:
		return []
	var out: Array = []
	for a in arr:
		if not a is Dictionary or str(a.get("title", "")).strip_edges() == "":
			continue
		var src := ""
		if a.get("source") is Dictionary:
			src = str(a.source.get("name", ""))
		elif a.get("source") != null:
			src = str(a.source)
		out.append({"title": str(a.title).strip_edges().left(180), "desc": str(a.get("description", "")).left(240), "source": src.left(40),
			"time": str(a.get("publishedAt", a.get("time", ""))), "url": str(a.get("url", "")).left(200)})
	return out


## Stichwortregel: Kategorie, Richtung (+1 verschaerfend, -1 entlastend, 0 unklar) und Relevanz 0..1.
static func assess(it: Dictionary) -> Dictionary:
	var text := (str(it.title) + " " + str(it.get("desc", ""))).to_lower()
	var best := {"cat": "", "direction": 0, "relevance": 0.0}
	for r in RULES:
		var hits := 0
		for w in r.words:
			if text.contains(w):
				hits += 1
		if hits == 0:
			continue
		var dir := 0
		for w in r.up:
			if text.contains(w):
				dir += 1
		for w in r.down:
			if text.contains(w):
				dir -= 1
		var rel := clampf(0.35 + 0.2 * hits + 0.1 * absi(dir) + (0.1 if text.contains("mainz") or text.contains("rheinland") else 0.0), 0.0, 1.0)
		if rel > float(best.relevance):
			best = {"cat": r.cat, "direction": clampi(dir, -1, 1), "relevance": rel}
	return best


## Neue Meldungen einarbeiten (ohne Duplikate). Gibt die neu aufgenommenen zurueck.
func ingest(parsed: Array) -> Array:
	var added: Array = []
	for p in parsed:
		var key := normalize(p.title)
		if seen.has(key):
			continue
		seen[key] = true
		var a := assess(p)
		var it: Dictionary = p.duplicate()
		it["id"] = "N%d" % (events_created + items.size() + 1 + seen.size())
		it["cat"] = a.cat
		it["direction"] = a.direction
		it["relevance"] = a.relevance
		it["used"] = false
		items.push_front(it)
		added.append(it)
	while items.size() > MAX_ITEMS:
		items.pop_back()
	return added


## Ebene 3: aus den relevantesten unverbrauchten Meldungen hoechstens ein Spielereignis (Abklingzeit, begrenzte Wirkung).
func maybe_event(sim: Simulation) -> Dictionary:
	if sim.game_min - last_event_min < GameCalendar.days_to_min(EVENT_COOLDOWN_DAYS):
		return {}
	var best: Dictionary = {}
	for it in items:
		if not it.used and float(it.relevance) >= EVENT_MIN_RELEVANCE and int(it.direction) != 0 and (best.is_empty() or float(it.relevance) > float(best.relevance)):
			best = it
	if best.is_empty():
		return {}
	var res := {}
	var days := 6.0
	match best.cat:
		"Treibstoff":
			var f := 1.12 if int(best.direction) > 0 else 0.92   # kleine, begrenzte Wirkung
			res = sim.events.trigger("treibstoffpreis", {"faktor": f}, GameCalendar.days_to_min(days))
		"Arbeit":
			if int(best.direction) > 0:
				res = sim.events.trigger("arbeitskraeftemangel", {"anteil": 0.3}, GameCalendar.days_to_min(days))
		_:
			return {}
	if res.is_empty() or not res.get("ok", false):
		return {}
	best.used = true
	last_event_min = sim.game_min
	events_created += 1
	var ev: Dictionary = sim.events.get_event(str(res.id)) if sim.events.has_method("get_event") else {}
	if not ev.is_empty():
		ev["ursache"] = "Nachricht (%s): %s" % [best.source, best.title]
		ev["quellen"] = ["Nachrichtenmeldung, Einschätzung der Engine (Stichwortregel)"]
	sim.log_event("Meldung löst ein Ereignis aus: „%s“ (%s, Relevanz %d %%)." % [best.title, best.cat, int(float(best.relevance) * 100.0)], "info")
	return res


func to_dict() -> Dictionary:
	return {"items": items.slice(0, 40), "seen": seen.keys().slice(-200), "last_event_min": last_event_min, "events_created": events_created,
		"source": source, "fetched_unix": fetched_unix, "last_error": last_error}


func from_dict(d: Dictionary) -> void:
	items = d.get("items", [])
	seen = {}
	for k in d.get("seen", []):
		seen[str(k)] = true
	last_event_min = float(d.get("last_event_min", -1.0e9))
	events_created = int(d.get("events_created", 0))
	source = str(d.get("source", "keine"))
	fetched_unix = float(d.get("fetched_unix", 0.0))
	last_error = str(d.get("last_error", ""))
