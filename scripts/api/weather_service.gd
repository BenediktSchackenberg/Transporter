class_name WeatherService
extends Node
## Holt das Wetter fuer Mainz asynchron (Open-Meteo, ohne Schluessel) und gibt es an Weather weiter.
## Austauschbar: Wer eine andere Quelle will, ersetzt build_url()/parse_forecast(). Bei Fehlern bleibt der letzte
## Stand erhalten; sein Alter ist ueber Weather.status() sichtbar. Alle Unternehmen sehen denselben Stand.

signal updated
signal failed(message: String)

const FORECAST_URL := "https://api.open-meteo.com/v1/forecast"
const GEOCODE_URL := "https://geocoding-api.open-meteo.com/v1/search"
const LOCATION_PATH := "user://weather_location.json"
const TIMEOUT_S := 12.0

var sim: Simulation
var base_url := FORECAST_URL        # fuer Tests/Mock-Server ueberschreibbar
var geocode_url := GEOCODE_URL
var location := Weather.LOCATION.duplicate()
var enabled := true
var location_path := LOCATION_PATH   # Tests leiten auf eine Wegwerfdatei um
var http: HTTPRequest
var _busy := false
var _geocoding := false
var _since_fetch := 0.0
var _started := false
var _waited := 0.0                  # reale Sekunden ohne erste Daten
const WAIT_FOR_FIRST_DATA_S := 10.0


func setup(simulation: Simulation) -> void:
	sim = simulation
	sim.wx.hold_simulation = true   # bis zu den ersten Live-Daten (oder Fehler/Zeitueberschreitung) kein erfundenes Wetter
	_load_location()


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_completed)


func _process(delta: float) -> void:
	if not enabled or sim == null or sim.finished:
		return
	_since_fetch += delta
	if sim.wx.hold_simulation:
		_waited += delta
		if _waited > WAIT_FOR_FIRST_DATA_S:
			sim.wx.hold_simulation = false   # keine Daten in Sicht: gekennzeichnetes Ersatzwetter uebernimmt
	if not _started or _since_fetch >= Weather.UPDATE_INTERVAL_S:
		_started = true
		_since_fetch = 0.0
		refresh()


func has_saved_location() -> bool:
	return FileAccess.file_exists(location_path)


func refresh() -> void:
	if _busy or http == null:
		return
	_busy = true
	if not has_saved_location():
		_geocoding = true
		var q := "?name=Mainz&count=10&language=de&format=json"
		_start(geocode_url + q)
	else:
		_geocoding = false
		_start(build_url())


func build_url() -> String:
	var cur := "temperature_2m,apparent_temperature,is_day,precipitation,rain,showers,snowfall,weather_code,cloud_cover,wind_speed_10m,wind_gusts_10m"
	var hourly := "temperature_2m,precipitation_probability,precipitation,weather_code,wind_gusts_10m"
	return "%s?latitude=%s&longitude=%s&current=%s&hourly=%s&forecast_hours=6&timezone=%s&wind_speed_unit=kmh&precipitation_unit=mm" % [
		base_url, str(location.lat), str(location.lon), cur, hourly, str(location.tz).uri_encode()]


func _start(url: String) -> void:
	var err := http.request(url)
	if err != OK:
		_busy = false
		_fail("Anfrage nicht startbar (Fehler %d)" % err)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Keine Verbindung zum Wetterdienst (%d)" % result)
		return
	if code < 200 or code >= 300:
		_fail("Wetterdienst antwortete mit HTTP %d" % code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if _geocoding:
		_geocoding = false
		if _pick_location(data):
			_save_location()
			refresh()   # sofort das Wetter fuer den gespeicherten Standort holen
		else:
			_fail("Standort Mainz (Rheinland-Pfalz) nicht gefunden – verwende Standardkoordinaten")
			_save_location()   # Standardkoordinaten dauerhaft speichern, damit nicht bei jedem Abruf neu gesucht wird
			refresh()
		return
	var state: Dictionary = sim.wx.parse_forecast(data)
	if state.is_empty():
		_fail("Unerwartetes Antwortformat des Wetterdienstes")
		return
	sim.apply_weather(state, Time.get_unix_time_from_system())
	updated.emit()


func _fail(msg: String) -> void:
	sim.wx.hold_simulation = false   # Abruf gescheitert: Ersatzwetter darf (gekennzeichnet) einspringen
	sim.wx.mark_failed(msg)
	failed.emit(msg)


## Waehlt aus den Treffern Mainz in Rheinland-Pfalz (nicht Mainz in Bayern).
func _pick_location(data) -> bool:
	if not data is Dictionary or not data.get("results") is Array:
		return false
	for r in data.results:
		if str(r.get("name", "")) == "Mainz" and str(r.get("country_code", "")) == "DE" and str(r.get("admin1", "")) == "Rheinland-Pfalz":
			location = {"name": "Mainz", "admin": "Rheinland-Pfalz", "country": "DE", "lat": float(r.latitude),
				"lon": float(r.longitude), "tz": "Europe/Berlin"}
			return true
	return false


func _load_location() -> void:
	if FileAccess.file_exists(location_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(location_path))
		if d is Dictionary and d.has("lat") and d.has("lon"):
			location = d


func _save_location() -> void:
	var f := FileAccess.open(location_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(location))
