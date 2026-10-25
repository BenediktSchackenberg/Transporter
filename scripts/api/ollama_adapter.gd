class_name OllamaAdapter
extends LLMAdapter
## Lokales Ollama ueber die native Chat-API. Denkmodus aus: kurze Spielentscheidungen
## liefern direkt Aktions-JSON statt das Tokenbudget mit Gedankengaengen zu verbrauchen.

const DEFAULT_BASE_URL := "http://127.0.0.1:11435"
const DEFAULT_MODEL := "qwen3.5:9b-q4_K_M"
## Der lokale Spiel-Prompt ist auf die Transportentscheidung verdichtet. Dieses
## Fenster deckt auch spätere Partien ab und spart KV-Speicher gegenüber 24k.
const CONTEXT_TOKENS := 12288
const RESPONSE_SCHEMA := {
	"type": "object",
	"properties": {
		"summary": {"type": "string", "maxLength": 240},
		"actions": {"type": "array", "minItems": 1, "maxItems": 6,
			"items": {"type": "object", "properties": {"action": {"type": "string"}},
				"required": ["action"], "additionalProperties": true}},
		"goal": {"type": "string", "maxLength": 120},
		"memory": {"type": "string", "maxLength": 400},
		"plan": {"type": "object"},
		"erfahrungen": {"type": "array", "items": {"type": "object"}, "maxItems": 3}
	},
	"required": ["summary", "actions"],
	"additionalProperties": false
}

var http: HTTPRequest
var _req_id := -1


func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_completed)


func display_name() -> String:
	return "Ollama lokal"


func send(req_id: int, messages: Array) -> void:
	_req_id = req_id
	http.timeout = maxf(float(config.get("timeout", 90.0)), 90.0)
	var url := str(config.get("base_url", DEFAULT_BASE_URL)).strip_edges().trim_suffix("/") + "/api/chat"
	var err := http.request(url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(build_body(messages)))
	if err != OK:
		_finish({"ok": false, "error": "Ollama-Anfrage konnte nicht gestartet werden (Fehler %d)." % err})


func cancel() -> void:
	if http:
		http.cancel_request()
	_req_id = -1


func build_body(messages: Array) -> Dictionary:
	return {"model": str(config.get("model", DEFAULT_MODEL)), "messages": messages,
		"stream": false, "think": false, "format": RESPONSE_SCHEMA,
		"options": {"temperature": float(config.get("temperature", 0.2)),
			"num_ctx": maxi(int(config.get("num_ctx", CONTEXT_TOKENS)), CONTEXT_TOKENS),
			"num_predict": int(config.get("max_tokens_per_request", 900))}}


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _req_id < 0:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := {HTTPRequest.RESULT_TIMEOUT: "Zeitüberschreitung", HTTPRequest.RESULT_CANT_CONNECT: "Keine Verbindung",
			HTTPRequest.RESULT_CANT_RESOLVE: "Host nicht gefunden", HTTPRequest.RESULT_CONNECTION_ERROR: "Verbindungsabbruch"}
		_finish({"ok": false, "error": reason.get(result, "Netzwerkfehler %d" % result)})
		return
	if code < 200 or code >= 300:
		_finish({"ok": false, "error": "Ollama HTTP %d: %s" % [code, body.get_string_from_utf8().left(200)]})
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("message", {}) is Dictionary:
		_finish({"ok": false, "error": "Unerwartetes Ollama-Antwortformat"})
		return
	var content = data.message.get("content", "")
	if not content is String or content.is_empty():
		_finish({"ok": false, "error": "Ollama lieferte kein Aktions-JSON"})
		return
	var prompt_tokens := int(data.get("prompt_eval_count", 0))
	var answer_tokens := int(data.get("eval_count", 0))
	_finish({"ok": true, "content": content,
		"usage": {"prompt_tokens": prompt_tokens, "completion_tokens": answer_tokens,
			"total_tokens": prompt_tokens + answer_tokens}})


func _finish(r: Dictionary) -> void:
	var id := _req_id
	_req_id = -1
	r["error"] = ApiLog.redact(str(r.get("error", "")))
	completed.emit(id, r)
