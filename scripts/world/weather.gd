class_name Weather
extends RefCounted
## Oeffentlicher Wetterstand fuer alle Unternehmen (Standort Mainz). Reine Logik ohne Netzwerk:
## Der WeatherService liefert Antworten, hier werden sie geprueft, eingeordnet und aufgezeichnet.
## Drei Zeitachsen bleiben getrennt: reale Wetterzeit (obs_time/fetched_unix), aktive Partiedauer und beschleunigte
## Spielzeit. Der Wetterstand aendert sich NUR durch reale Abrufe (oder die Wiederholung); die Beschleunigung der
## Spielwelt erzeugt keine Wetteraenderungen. Ohne Daten gilt ein gekennzeichnetes simuliertes Ersatzwetter.

const LOCATION := {"name": "Mainz", "admin": "Rheinland-Pfalz", "country": "DE", "lat": 49.98185, "lon": 8.28008,
	"tz": "Europe/Berlin"}
const UPDATE_INTERVAL_S := 900.0     # reale Sekunden zwischen zwei Abrufen
const STALE_AFTER_S := 2400.0        # nach 40 min ohne Erfolg: veraltet
const OFFLINE_AFTER_S := 7200.0      # nach 2 h ohne Erfolg: offline (Daten nur noch als Hinweis)

## Spielparameter (Schwellenwerte). Wetter allein loest keinen Schaden aus; die Werte steuern nur Wahrscheinlichkeiten.
const PARAMS := {
	"rain_mm_h": 0.5, "heavy_rain_mm_h": 4.0, "gust_strong_kmh": 60.0, "heat_c": 28.0, "cold_c": 3.0,
	"ice_c": 1.0, "fog_visibility": 0.7,
	"drive_rain": 0.92, "drive_heavy_rain": 0.80, "drive_snow": 0.80, "drive_ice": 0.70, "drive_fog": 0.90, "drive_wind": 0.95,
	"loading_rain": 1.25, "loading_heavy_rain": 1.5, "loading_wind": 1.2, "loading_snow": 1.3,
	"build_rain": 0.7, "build_heavy_rain": 0.4, "build_wind": 0.5, "build_snow": 0.5,
	"breakdown_cold": 1.5, "breakdown_heat": 1.3, "breakdown_ice": 1.8,
	"covered_rain_relief": 0.85,     # Anteil der Regen-Ladeverzoegerung, der unter Dach entfaellt
}

const CODE_TEXT := {0: "klar", 1: "überwiegend klar", 2: "wolkig", 3: "bedeckt", 45: "Nebel", 48: "Reifnebel",
	51: "leichter Nieselregen", 53: "Nieselregen", 55: "starker Nieselregen", 56: "gefrierender Nieselregen", 57: "gefrierender Nieselregen",
	61: "leichter Regen", 63: "Regen", 65: "starker Regen", 66: "gefrierender Regen", 67: "gefrierender Regen",
	71: "leichter Schneefall", 73: "Schneefall", 75: "starker Schneefall", 77: "Schneegriesel",
	80: "leichte Schauer", 81: "Schauer", 82: "heftige Schauer", 85: "Schneeschauer", 86: "starke Schneeschauer",
	95: "Gewitter", 96: "Gewitter mit Hagel", 99: "Gewitter mit Hagel"}

var cur := {}                # aktueller Stand (siehe parse_forecast)
var params := PARAMS.duplicate()
var fetched_unix := 0.0      # reale Zeit des letzten erfolgreichen Abrufs
var last_error := ""
var sim_until := 120.0       # nur Ersatzwetter: Spielminute des naechsten simulierten Wechsels
var hold_simulation := false # Live-Modus: kein Ersatzwetter, solange noch auf die ersten echten Daten gewartet wird
var log: Array = []          # Aufzeichnung: [{minute, state}] (Grundlage fuer Wiederholungen)
var replay: Array = []       # abzuspielende Aufzeichnung (leer = Live-/Ersatzbetrieb)
var _replay_pos := 0


func _init() -> void:
	cur = _fallback_state("klar", 0, 12.0, 0.0, 10.0, 20.0, 20, true)


# ------------------------------------------------------------------ Antwort pruefen
## Wandelt eine Open-Meteo-Antwort in einen Wetterstand. Leeres Dictionary = Antwort unbrauchbar.
func parse_forecast(data) -> Dictionary:
	if not data is Dictionary or not data.get("current") is Dictionary:
		return {}
	var c: Dictionary = data.current
	for key in ["temperature_2m", "weather_code", "wind_speed_10m", "time"]:
		if not c.has(key) or c[key] == null:
			return {}
	var interval := clampf(float(c.get("interval", 900.0)), 60.0, 3600.0)
	# current.precipitation ist die Summe ueber das Messintervall (meist 900 s), nicht je Stunde.
	var mm_interval := maxf(0.0, float(c.get("precipitation", 0.0)))
	var code := int(c.weather_code)
	var out := {"source": "open-meteo", "temp": float(c.temperature_2m), "feels": float(c.get("apparent_temperature", c.temperature_2m)),
		"code": code, "cond": condition_of(code), "text": CODE_TEXT.get(code, "unbekannt"),
		"precip_mm": mm_interval, "interval_s": interval, "precip_mm_h": minf(mm_interval * 3600.0 / interval, 100.0),
		"snow_cm": maxf(0.0, float(c.get("snowfall", 0.0))), "wind": float(c.wind_speed_10m),
		"gust": float(c.get("wind_gusts_10m", c.wind_speed_10m)), "cloud": int(c.get("cloud_cover", 0)),
		"is_day": int(c.get("is_day", 1)) == 1, "obs_time": str(c.time), "forecast": []}
	var h = data.get("hourly")
	if h is Dictionary and h.get("time") is Array:
		for i in mini(h.time.size(), 6):
			var hc := int(_at(h, "weather_code", i, 0))
			out.forecast.append({"time": str(h.time[i]), "temp": float(_at(h, "temperature_2m", i, out.temp)),
				"pop": int(_at(h, "precipitation_probability", i, 0)), "precip_mm_h": float(_at(h, "precipitation", i, 0.0)),
				"gust": float(_at(h, "wind_gusts_10m", i, 0.0)), "cond": condition_of(hc), "text": CODE_TEXT.get(hc, "")})
	return out


static func _at(h: Dictionary, key: String, i: int, fallback):
	var a = h.get(key)
	if a is Array and i < a.size() and a[i] != null:
		return a[i]
	return fallback


## Spielzustand aus dem WMO-Code (Niederschlagsmenge kommt getrennt dazu).
static func condition_of(code: int) -> String:
	if code in [95, 96, 99]:
		return "Gewitter"
	if code in [71, 73, 75, 77, 85, 86]:
		return "Schnee"
	if code in [45, 48]:
		return "Nebel"
	if code in [65, 82, 67]:
		return "Starkregen"
	if code in [51, 53, 55, 56, 57, 61, 63, 66, 80, 81]:
		return "Regen"
	if code == 3:
		return "bewölkt"
	if code == 2:
		return "wolkig"
	return "klar"


## Uebernimmt einen neuen Stand (Live-Abruf oder Wiederholung) und zeichnet ihn auf.
func apply(state: Dictionary, minute: int, now_unix: float = 0.0, record: bool = true) -> void:
	cur = state
	if state.get("source", "") == "open-meteo":
		fetched_unix = now_unix
		last_error = ""
	if record:
		log.append({"minute": minute, "state": state.duplicate(true)})


func mark_failed(msg: String) -> void:
	last_error = msg


## Wiederholung: spielt aufgezeichnete Staende zur aufgezeichneten Spielminute ab.
func replay_tick(minute: int) -> void:
	while _replay_pos < replay.size() and int(replay[_replay_pos].minute) <= minute:
		var st: Dictionary = replay[_replay_pos].state.duplicate(true)
		st["source"] = "wiederholung"
		cur = st
		_replay_pos += 1


func start_replay(recorded: Array) -> void:
	replay = recorded.duplicate(true)
	_replay_pos = 0
	if not replay.is_empty():
		replay_tick(int(replay[0].minute))


# ------------------------------------------------------------------ Ersatzwetter
func _fallback_state(cond: String, code: int, temp: float, mm_h: float, wind: float, gust: float, cloud: int, day: bool) -> Dictionary:
	return {"source": "simuliert", "temp": temp, "feels": temp, "code": code, "cond": cond, "text": CODE_TEXT.get(code, cond),
		"precip_mm": mm_h * 0.25, "interval_s": 900.0, "precip_mm_h": mm_h, "snow_cm": 0.0, "wind": wind, "gust": gust,
		"cloud": cloud, "is_day": day, "obs_time": "", "forecast": []}


## Simuliertes Ersatzwetter, solange keine echten Daten vorliegen. Wechselt nur in der Spielzeit und ist als simuliert markiert.
func simulate(game_min: float, rng: RandomNumberGenerator) -> void:
	if hold_simulation or cur.get("source", "") != "simuliert" or game_min < sim_until:
		return
	var r := rng.randf()
	if r < 0.25:
		cur = _fallback_state("Regen", 61, 11.0, rng.randf_range(0.6, 3.0), 18.0, 34.0, 90, true)
	elif r < 0.30:
		cur = _fallback_state("Starkregen", 65, 11.0, rng.randf_range(4.5, 8.0), 28.0, 55.0, 100, true)
	elif r < 0.55:
		cur = _fallback_state("bewölkt", 3, 14.0, 0.0, 12.0, 22.0, 100, true)
	else:
		cur = _fallback_state("klar", 0, 16.0, 0.0, 8.0, 15.0, 15, true)
	sim_until = game_min + rng.randf_range(120.0, 300.0)


# ------------------------------------------------------------------ Einordnung
func p(key: String) -> float:
	return float(params[key])


func is_heavy_rain() -> bool:
	return cur.cond in ["Starkregen", "Gewitter"] or float(cur.precip_mm_h) >= p("heavy_rain_mm_h")


func is_rain() -> bool:
	return is_heavy_rain() or cur.cond == "Regen" or float(cur.precip_mm_h) >= p("rain_mm_h")


func is_snow() -> bool:
	return cur.cond == "Schnee" or (float(cur.snow_cm) > 0.0 and float(cur.temp) <= 1.0)


func is_strong_wind() -> bool:
	return float(cur.gust) >= p("gust_strong_kmh")


func is_hot() -> bool:
	return float(cur.temp) >= p("heat_c")


func is_cold() -> bool:
	return float(cur.temp) <= p("cold_c")


func is_fog() -> bool:
	return cur.cond == "Nebel"


## Glaette braucht Frost UND Feuchtigkeit (Niederschlag, Nebel, Schnee); trockene Kaelte allein vereist nichts.
func is_icy() -> bool:
	return float(cur.temp) <= p("ice_c") and (is_rain() or is_snow() or is_fog())


## Fahrgeschwindigkeit (Faktor), Verladedauer im Freien (Faktor >= 1), Bautempo (Faktor <= 1), Pannenrisiko (Faktor).
func drive_factor() -> float:
	var f := 1.0
	if is_heavy_rain():
		f = minf(f, p("drive_heavy_rain"))
	elif is_rain():
		f = minf(f, p("drive_rain"))
	if is_snow():
		f = minf(f, p("drive_snow"))
	if is_icy():
		f = minf(f, p("drive_ice"))
	if is_fog():
		f = minf(f, p("drive_fog"))
	if is_strong_wind():
		f = minf(f, p("drive_wind"))
	return f


func loading_factor(covered: bool) -> float:
	var rain := 1.0
	if is_heavy_rain():
		rain = p("loading_heavy_rain")
	elif is_rain():
		rain = p("loading_rain")
	if covered:
		rain = 1.0 + (rain - 1.0) * (1.0 - p("covered_rain_relief"))   # Dach hilft gegen Regen, nicht gegen Sturm
	var f := rain
	if is_strong_wind():
		f = maxf(f, p("loading_wind"))
	if is_snow():
		f = maxf(f, p("loading_snow"))
	return f


func build_factor() -> float:
	var f := 1.0
	if is_heavy_rain():
		f = minf(f, p("build_heavy_rain"))
	elif is_rain():
		f = minf(f, p("build_rain"))
	if is_strong_wind():
		f = minf(f, p("build_wind"))
	if is_snow():
		f = minf(f, p("build_snow"))
	return f


func breakdown_factor(maintained: bool) -> float:
	var f := 1.0
	if is_cold():
		f = maxf(f, p("breakdown_cold"))
	if is_hot():
		f = maxf(f, p("breakdown_heat"))
	if is_icy():
		f = maxf(f, p("breakdown_ice"))
	return 1.0 + (f - 1.0) * (0.5 if maintained else 1.0)   # gewartete Fahrzeuge verkraften Extremwetter besser


## Nachfrageeffekte je Warenart (Faktor auf Auftragsgenerierung/-verguetung).
func demand_factors() -> Dictionary:
	var d := {}
	if is_hot():
		d["getraenke"] = 1.5
		d["lebensmittel"] = 1.2
	if is_cold() or is_snow():
		d["baustoffe"] = 1.2   # Wintermaterial, Frostschutz
		d["maschinenteile"] = 1.15
	if is_heavy_rain():
		d["baustoffe"] = maxf(d.get("baustoffe", 1.0), 1.3)   # Abdichten, Ersatzlieferungen
		d["pakete"] = 1.15
	if is_strong_wind():
		d["baustoffe"] = maxf(d.get("baustoffe", 1.0), 1.25)   # Sicherungs- und Reparaturbedarf
	return d


# ------------------------------------------------------------------ Anzeige
## aktuell | veraltet | offline | simuliert | wiederholung
func status(now_unix: float) -> String:
	var src: String = cur.get("source", "simuliert")
	if src != "open-meteo":
		return src
	var age := now_unix - fetched_unix
	if age > OFFLINE_AFTER_S:
		return "offline"
	if age > STALE_AFTER_S:
		return "veraltet"
	return "aktuell"


static func icon_of(cur_state: Dictionary) -> String:
	match cur_state.get("cond", "klar"):
		"Gewitter": return "gewitter"
		"Starkregen", "Regen": return "regen"
		"Schnee": return "schnee"
		"Nebel": return "nebel"
		"bewölkt", "wolkig": return "wolke"
	return "sonne" if cur_state.get("is_day", true) else "mond"


func headline() -> String:
	return "%s, %.0f °C, %s" % [cur.text, float(cur.temp), "Tag" if cur.is_day else "Nacht"]


func to_dict() -> Dictionary:
	return {"cur": cur, "fetched_unix": fetched_unix, "sim_until": sim_until, "log": log, "last_error": last_error}


func from_dict(d: Dictionary) -> void:
	if d.get("cur") is Dictionary and not d.cur.is_empty():
		cur = d.cur
	fetched_unix = float(d.get("fetched_unix", 0.0))
	sim_until = float(d.get("sim_until", 0.0))
	log = d.get("log", [])
	last_error = str(d.get("last_error", ""))
