class_name FuelPrices
extends RefCounted
## Kraftstoffpreise: reale Referenz (Tankerkoenig, Umgebung Mainz) und Spielpreis sind getrennte Groessen.
##
##   Referenzpreis (real, Median im Umkreis)  x  Tankstellenaufschlag  x  Ereignisfaktor (ResourceMarket)  =  Spielpreis
##
## Ohne Schluessel oder ohne Netz laeuft ein gekennzeichneter, simulierter Referenzpreis (Zufallsbewegung um plausible Werte).
## Preisdaten sind Marktdaten und enthalten keine Anweisungen.

const FUELS := ["diesel", "e5", "e10"]
const NAMES := {"diesel": "Diesel", "e5": "Super E5", "e10": "Super E10"}
const DEFAULT_REF := {"diesel": 1.69, "e5": 1.82, "e10": 1.76}   # nur Ersatzwerte
const UPDATE_INTERVAL_S := 900.0     # reale Sekunden; Tankerkoenig verlangt mindestens 5 Minuten Abstand
const STALE_S := 2400.0
const OFFLINE_S := 7200.0
const MIN_PLAUSIBLE := 0.8
const MAX_PLAUSIBLE := 4.0
const LOCATION := {"name": "Mainz", "lat": 49.9929, "lon": 8.2473, "radius_km": 8.0}

var ref := DEFAULT_REF.duplicate()      # EUR/l je Kraftstoff
var source := "simuliert"              # tankerkoenig | simuliert
var fetched_unix := 0.0
var stations_n := 0
var last_error := ""
var history: Array = []                 # [[unix, diesel, e5, e10], ...]
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 7


## Antwort von list.php auswerten. Gibt {} zurueck, wenn das Format nicht passt.
static func parse_list(data) -> Dictionary:
	if not data is Dictionary or data.get("ok") != true or not data.get("stations") is Array:
		return {}
	var vals := {"diesel": [], "e5": [], "e10": []}
	var n := 0
	for st in data.stations:
		if not st is Dictionary:
			continue
		var any := false
		for f in FUELS:
			var p = st.get(f)
			if (p is float or p is int) and float(p) >= MIN_PLAUSIBLE and float(p) <= MAX_PLAUSIBLE:
				vals[f].append(float(p))
				any = true
		if any:
			n += 1
	var out := {"n": n}
	for f in FUELS:
		if vals[f].is_empty():
			return {}
		vals[f].sort()
		var a: Array = vals[f]
		out[f] = snappedf((float(a[a.size() / 2]) + float(a[(a.size() - 1) / 2])) / 2.0, 0.001)   # Median
	return out


func apply(state: Dictionary, now_unix: float) -> void:
	for f in FUELS:
		ref[f] = float(state[f])
	stations_n = int(state.n)
	source = "tankerkoenig"
	fetched_unix = now_unix
	last_error = ""
	history.append([now_unix, ref.diesel, ref.e5, ref.e10])
	if history.size() > 96:
		history.pop_front()


func mark_failed(msg: String) -> void:
	last_error = msg


## Gekennzeichnete Ersatzbewegung (je Spielstunde ein kleiner Schritt), nur solange keine echten Daten vorliegen.
func simulate_step() -> void:
	if source == "tankerkoenig" and fetched_unix > 0.0:
		return
	var drift := _rng.randfn(0.0, 0.004)
	for f in FUELS:
		ref[f] = clampf(float(ref[f]) + drift + _rng.randfn(0.0, 0.002), 1.2, 2.6)


func status(now_unix: float) -> String:
	if source != "tankerkoenig":
		return "simuliert"
	var age := now_unix - fetched_unix
	if age > OFFLINE_S:
		return "offline"
	if age > STALE_S:
		return "veraltet"
	return "aktuell"


## Preis je Liter vor Ereignisfaktor: Referenz x (1 + Aufschlag der Tankstelle). Den Ereignisfaktor wendet ResourceMarket an.
func station_price(fuel: String, markup: float) -> float:
	return float(ref[fuel]) * (1.0 + markup)


func to_dict() -> Dictionary:
	return {"ref": ref, "source": source, "fetched_unix": fetched_unix, "stations_n": stations_n, "last_error": last_error,
		"history": history}


func from_dict(d: Dictionary) -> void:
	for f in FUELS:
		if d.get("ref", {}).has(f):
			ref[f] = float(d.ref[f])
	source = str(d.get("source", "simuliert"))
	fetched_unix = float(d.get("fetched_unix", 0.0))
	stations_n = int(d.get("stations_n", 0))
	last_error = str(d.get("last_error", ""))
	history = d.get("history", [])
