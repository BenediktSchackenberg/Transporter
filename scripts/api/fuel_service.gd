class_name FuelService
extends Node
## Holt die Referenzpreise fuer Diesel, E5 und E10 im Umkreis von Mainz (Tankerkoenig, Creative-Commons-Schnittstelle) asynchron.
## Der Schluessel stammt aus der Umgebungsvariable TANKERKOENIG_API_KEY oder dem Windows-Tresor (Slot "tankerkoenig").
## Er wird nie protokolliert, gespeichert oder in Fehlermeldungen ausgegeben. Ohne Schluessel oder bei Fehlern bleibt der letzte
## Stand erhalten bzw. laeuft der gekennzeichnete simulierte Referenzpreis (FuelPrices.status()).

signal updated
signal failed(message: String)

const LIST_URL := "https://creativecommons.tankerkoenig.de/json/list.php"
const KEY_SLOT := "tankerkoenig"
const TIMEOUT_S := 12.0

var sim: Simulation
var base_url := LIST_URL            # fuer Tests/Mock-Server ueberschreibbar
var enabled := true
var http: HTTPRequest
var _key := ""
var _busy := false
var _since_fetch := 0.0
var _started := false


func setup(simulation: Simulation, key: String = "") -> void:
	sim = simulation
	_key = key if key != "" else _find_key()
	ApiLog.register_secret(_key)


static func _find_key() -> String:
	var env := OS.get_environment("TANKERKOENIG_API_KEY")
	if env != "":
		return env
	return CredentialStore.read_key(KEY_SLOT) if CredentialStore.available() else ""


func has_key() -> bool:
	return _key != ""


func _ready() -> void:
	http = HTTPRequest.new()
	http.timeout = TIMEOUT_S
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_completed)


func _process(delta: float) -> void:
	if not enabled or sim == null or sim.finished or _key == "":
		return
	_since_fetch += delta
	if not _started or _since_fetch >= FuelPrices.UPDATE_INTERVAL_S:
		_started = true
		_since_fetch = 0.0
		refresh()


func build_url() -> String:
	var loc: Dictionary = FuelPrices.LOCATION
	return "%s?lat=%s&lng=%s&rad=%s&sort=dist&type=all&apikey=%s" % [base_url, str(loc.lat), str(loc.lon), str(loc.radius_km), _key]


func refresh() -> void:
	if _busy or http == null or _key == "":
		return
	_busy = true
	var err := http.request(build_url())
	if err != OK:
		_busy = false
		_fail("Anfrage nicht startbar (Fehler %d)" % err)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Keine Verbindung zum Preisdienst (%d)" % result)
		return
	if code < 200 or code >= 300:
		_fail("Preisdienst antwortete mit HTTP %d" % code)
		return
	handle_body(body.get_string_from_utf8())


## Antwort verarbeiten (auch fuer Tests mit aufgezeichneten Antworten).
func handle_body(text: String) -> bool:
	var state := FuelPrices.parse_list(JSON.parse_string(text))
	if state.is_empty():
		_fail("Unerwartetes Antwortformat des Preisdienstes")
		return false
	sim.fuel.apply(state, Time.get_unix_time_from_system())
	updated.emit()
	return true


func _fail(msg: String) -> void:
	sim.fuel.mark_failed(msg.replace(_key, "***") if _key != "" else msg)
	failed.emit(msg)
