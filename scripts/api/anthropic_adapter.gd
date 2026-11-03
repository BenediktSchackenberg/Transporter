class_name AnthropicAdapter
extends LLMAdapter
## Adapter fuer die Claude Messages API (POST {base_url}/messages).
## Unterschiede zum OpenAI-Format: Schluessel im Header `x-api-key`, Pflichtheader `anthropic-version`,
## Systemprompt als eigenes Feld, Antwort als Liste von Inhaltsbloecken. Der Schluessel steht nur im Header
## und wird nie protokolliert (Fehlertexte laufen durch ApiLog.redact).
## Neue Modelle (Sonnet 5.5, Haiku 5.5, Opus 5.5): kein `temperature`, Denkbloecke zaehlen auf max_tokens,
## Ablehnungen kommen als stop_reason "refusal".

const DEFAULT_BASE_URL := "https://api.anthropic.com/v1"
const DEFAULT_MODEL := "claude-sonnet-5-5"
const API_VERSION := "2023-06-01"
const MIN_OUTPUT_TOKENS := 4000     # Denkanteil und Antwort teilen sich max_tokens

var http: HTTPRequest
var _req_id := -1


func _ready() -> void:
	http = HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request_completed.connect(_on_completed)


func display_name() -> String:
	return "Claude (Anthropic)"


func send(req_id: int, messages: Array) -> void:
	_req_id = req_id
	var url := str(config.get("base_url", DEFAULT_BASE_URL)).strip_edges().trim_suffix("/") + "/messages"
	var headers := PackedStringArray(["Content-Type: application/json", "anthropic-version: " + API_VERSION,
		"x-api-key: " + str(config.get("api_key", ""))])
	http.timeout = maxf(float(config.get("timeout", 60.0)), 30.0)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(build_body(messages)))
	if err != OK:
		_finish({"ok": false, "error": "Anfrage konnte nicht gestartet werden (Fehler %d). URL prüfen." % err})


func cancel() -> void:
	if http:
		http.cancel_request()
	_req_id = -1


## Anfragekoerper aus der Nachrichtenliste im Chat-Format (system/user/assistant); oeffentlich fuer Tests.
func build_body(messages: Array) -> Dictionary:
	var system_parts: Array = []
	var turns: Array = []
	for m in messages:
		var role := str(m.get("role", "user"))
		var text := str(m.get("content", ""))
		if role == "system":
			system_parts.append(text)
			continue
		if role != "assistant":
			role = "user"
		if not turns.is_empty() and turns[turns.size() - 1].role == role:
			turns[turns.size() - 1].content += "\n\n" + text     # die API verlangt abwechselnde Rollen
		else:
			turns.append({"role": role, "content": text})
	if turns.is_empty() or turns[0].role != "user":
		turns.push_front({"role": "user", "content": "(Beginn)"})
	var model := str(config.get("model", DEFAULT_MODEL))
	var body := {"model": model, "max_tokens": maxi(int(config.get("max_tokens_per_request", 0)), MIN_OUTPUT_TOKENS), "messages": turns}
	if not system_parts.is_empty():
		body["system"] = "\n\n".join(system_parts)
	if model.contains("-5-") or model.contains("fable") or model.contains("opus-5") or model.contains("sonnet-5"):
		body["output_config"] = {"effort": str(config.get("effort", "medium"))}   # Standard waere "high": fuer seltene Rollenentscheidungen unnoetig teuer
	return body


## Wertet eine HTTP-Antwort aus (oeffentlich fuer Tests): {ok, content, usage} oder {ok:false, error, retry_after}.
static func parse_response(code: int, text: String, retry_after_header: String = "") -> Dictionary:
	if code == 429 or code == 529:
		var retry := maxf(1.0, retry_after_header.to_float()) if retry_after_header != "" else 20.0
		return {"ok": false, "error": ("Rate Limit (HTTP 429)" if code == 429 else "API überlastet (HTTP 529)"), "retry_after": retry}
	var data = JSON.parse_string(text)
	if code < 200 or code >= 300:
		var msg := text.left(200)
		if data is Dictionary and data.get("error") is Dictionary:
			msg = str(data.error.get("message", "")).left(200)
		return {"ok": false, "error": "HTTP %d: %s" % [code, msg]}
	if not data is Dictionary or not data.get("content") is Array:
		return {"ok": false, "error": "Unerwartetes Antwortformat der API"}
	if str(data.get("stop_reason", "")) == "refusal":
		return {"ok": false, "error": "Das Modell hat die Anfrage abgelehnt (refusal)."}
	var out := ""
	for block in data.content:     # Denkbloecke und Werkzeugaufrufe ueberspringen, nur Text zaehlt
		if block is Dictionary and str(block.get("type", "")) == "text":
			out += str(block.get("text", ""))
	var u: Dictionary = data.get("usage", {}) if data.get("usage") is Dictionary else {}
	var pt := int(u.get("input_tokens", 0))
	var ct := int(u.get("output_tokens", 0))
	return {"ok": true, "content": out, "usage": {"prompt_tokens": pt, "completion_tokens": ct, "total_tokens": pt + ct}}


func _on_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _req_id < 0:
		return   # abgebrochen
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := {HTTPRequest.RESULT_TIMEOUT: "Zeitüberschreitung", HTTPRequest.RESULT_CANT_CONNECT: "Keine Verbindung",
			HTTPRequest.RESULT_CANT_RESOLVE: "Host nicht gefunden", HTTPRequest.RESULT_CONNECTION_ERROR: "Verbindungsabbruch",
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS-Fehler", HTTPRequest.RESULT_NO_RESPONSE: "Keine Antwort"}
		_finish({"ok": false, "error": reason.get(result, "Netzwerkfehler %d" % result)})
		return
	var retry_h := ""
	for h in headers:
		if h.to_lower().begins_with("retry-after:"):
			retry_h = h.split(":", true, 1)[1].strip_edges()
	_finish(parse_response(code, body.get_string_from_utf8(), retry_h))


func _finish(r: Dictionary) -> void:
	var id := _req_id
	_req_id = -1
	r["error"] = ApiLog.redact(str(r.get("error", "")))
	completed.emit(id, r)
