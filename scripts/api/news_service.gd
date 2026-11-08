class_name NewsService
extends Node
## Holt Nachrichten asynchron (NewsAPI-kompatibler Endpunkt). Schluessel aus NEWS_API_KEY oder dem Windows-Tresor (Slot "news").
## Ohne Schluessel passiert nichts (Quelle "keine"). Der Schluessel wird nie protokolliert oder gespeichert.

signal updated(added: int)
signal failed(message: String)

const URL := "https://newsapi.org/v2/everything"
const QUERY := "Mainz OR Spritpreis OR Dieselpreis OR Streik OR Sperrung OR Unwetter"
const KEY_SLOT := "news"
const UPDATE_INTERVAL_S := 1800.0
const TIMEOUT_S := 12.0

var sim: Simulation
var base_url := URL
var enabled := true
var http: HTTPRequest
var _key := ""
var _busy := false
var _since := 0.0
var _started := false


func setup(simulation: Simulation, key: String = "") -> void:
	sim = simulation
	_key = key if key != "" else _find_key()
	ApiLog.register_secret(_key)


static func _find_key() -> String:
	var env := OS.get_environment("NEWS_API_KEY")
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
	_since += delta
	if not _started or _since >= UPDATE_INTERVAL_S:
		_started = true
		_since = 0.0
		refresh()


func build_url() -> String:
	return "%s?q=%s&language=de&sortBy=publishedAt&pageSize=20&apiKey=%s" % [base_url, QUERY.uri_encode(), _key]


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
		_fail("Keine Verbindung zum Nachrichtendienst (%d)" % result)
		return
	if code < 200 or code >= 300:
		_fail("Nachrichtendienst antwortete mit HTTP %d" % code)
		return
	handle_body(body.get_string_from_utf8())


## Antwort verarbeiten (auch fuer Tests mit aufgezeichneten Antworten).
func handle_body(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail("Ungueltiges JSON des Nachrichtendienstes")
		return false
	var data = json.data
	if not (data is Array or (data is Dictionary and data.get("articles") is Array)):
		_fail("Unerwartetes Antwortformat des Nachrichtendienstes")
		return false
	var parsed := NewsFeed.parse(data)
	var added := sim.news.ingest(parsed)
	sim.news.source = "newsapi"
	sim.news.fetched_unix = Time.get_unix_time_from_system()
	sim.news.last_error = ""
	sim.news.maybe_event(sim)
	updated.emit(added.size())
	return true


func _fail(msg: String) -> void:
	sim.news.last_error = msg.replace(_key, "***") if _key != "" else msg
	failed.emit(msg)
