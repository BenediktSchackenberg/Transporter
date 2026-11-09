class_name OpenAIAdapter
extends LLMAdapter
## Adapter fuer OpenAI-kompatible Chat-APIs (POST {base_url}/chat/completions).
## Funktioniert z. B. mit OpenAI, OpenRouter, Mistral, Groq, Together, LM Studio, Ollama (/v1).
## Kompatibilitaet: Lehnt ein Server einen Parameter mit HTTP 400 ab, wird die Anfrage ohne diesen Parameter
## (bzw. mit max_completion_tokens statt max_tokens) wiederholt und das gemerkt.
## Profil "ionos" (IONOS AI Model Hub, z. B. Qwen): Herstellerparameter, kein response_format, laengeres Timeout.

const IONOS_BASE_URL := "https://openai.inference.de-txl.ionos.com/v1"
const IONOS_MODEL := "Qwen/Qwen3.8-27B"
const IONOS_PARAMS := {"temperature": 1.0, "top_p": 0.95, "reasoning_effort": "medium", "presence_penalty": 1.5,
	"frequency_penalty": 0}

var http: HTTPRequest
var _req_id := -1
var _sent_at := 0          # Ticks (ms) der laufenden Anfrage, fuer die eigene Zeitgrenze
## IONOS/Qwen denkt oft laenger als 45 s. Partie 09.11.: beim Abbruch nach 50 s stand das ganze Spiel, weil
## HTTPRequest.cancel_request() bei use_threads auf das Ende des HTTP-Threads wartet (wait_to_finish), der in der
## TLS-Verbindung haengt. Deshalb: nie blockierend abbrechen - die Anfrage wird verlassen und laeuft im Hintergrund aus.
const IONOS_MIN_TIMEOUT := 180.0
## Qwen denkt vor jeder Antwort 3500-6000 Tokens (reasoning_tokens); mit 2000 blieb die Antwort leer (Partie 09.11., Viktor/Bodo).
const IONOS_MIN_TOKENS := 8000
var _messages: Array = []
var _compat := {}          # "drop:<parameter>" oder "max_completion_tokens"
var _compat_retries := 0


func _ready() -> void:
	http = _new_http()
	set_process(true)


func _new_http() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.use_threads = true
	h.timeout = 0.0   # Godots eigene Zeitgrenze bricht blockierend ab; die Zeitgrenze fuehrt _process (nicht blockierend)
	add_child(h)
	h.request_completed.connect(_on_completed.bind(h))
	return h


## Laufende Anfrage verlassen statt abbrechen: der Knoten bleibt, bis sein Thread von selbst fertig ist, dann wird er entsorgt.
func _abandon() -> void:
	if http != null and http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http.set_meta("verlassen", true)
		http = _new_http()


func timeout_s() -> float:
	var t := float(config.get("timeout", 45.0))
	return maxf(t, IONOS_MIN_TIMEOUT) if config.get("provider", "") == "ionos" else t


func _process(_delta: float) -> void:
	if _req_id >= 0 and _sent_at > 0 and (Time.get_ticks_msec() - _sent_at) / 1000.0 > timeout_s():
		_abandon()
		_finish({"ok": false, "error": "Zeitüberschreitung (%d s)" % int(timeout_s())})


func display_name() -> String:
	return "OpenAI-kompatibel"


func send(req_id: int, messages: Array) -> void:
	_req_id = req_id
	_messages = messages
	_compat_retries = 0
	_post()


func cancel() -> void:
	_abandon()
	_req_id = -1
	_sent_at = 0


## Baut den Anfragekoerper (oeffentlich fuer Tests).
func build_body(messages: Array) -> Dictionary:
	var ionos: bool = config.get("provider", "") == "ionos"
	var body := {"model": config.get("model", ""), "messages": messages}
	var max_tok := maxi(int(config.get("max_tokens_per_request", 700)), IONOS_MIN_TOKENS if ionos else 0)
	if _compat.has("max_completion_tokens"):
		body["max_completion_tokens"] = max_tok
	else:
		body["max_tokens"] = max_tok
	if ionos:
		body.merge(IONOS_PARAMS)   # JSON-Format wird ueber den Systemprompt verlangt
	else:
		body["temperature"] = float(config.get("temperature", 0.7))
		body["response_format"] = {"type": "json_object"}
	for k in _compat:
		if k.begins_with("drop:"):
			body.erase(k.trim_prefix("drop:"))
	return body


func _post() -> void:
	_abandon()   # noch belegter Knoten (verlassene Anfrage): neuen nehmen
	_sent_at = Time.get_ticks_msec()
	var body := build_body(_messages)
	var url := str(config.get("base_url", "")).strip_edges().trim_suffix("/") + "/chat/completions"
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := str(config.get("api_key", ""))
	if key != "":
		headers.append("Authorization: Bearer " + key)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_finish({"ok": false, "error": "Anfrage konnte nicht gestartet werden (Fehler %d). URL prüfen." % err})


func _on_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, from: HTTPRequest = null) -> void:
	if from != null and from.has_meta("verlassen"):
		from.queue_free()   # verlassene Anfrage ist von selbst fertig geworden
		return
	if _req_id < 0:
		return   # abgebrochen
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := {HTTPRequest.RESULT_TIMEOUT: "Zeitüberschreitung", HTTPRequest.RESULT_CANT_CONNECT: "Keine Verbindung",
			HTTPRequest.RESULT_CANT_RESOLVE: "Host nicht gefunden", HTTPRequest.RESULT_CONNECTION_ERROR: "Verbindungsabbruch",
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS-Fehler", HTTPRequest.RESULT_NO_RESPONSE: "Keine Antwort"}
		_finish({"ok": false, "error": reason.get(result, "Netzwerkfehler %d" % result)})
		return
	if code == 400 and _compat_retries < 5:
		var low := text.to_lower()
		var changed := false
		if low.contains("max_tokens") and not _compat.has("max_completion_tokens"):
			_compat["max_completion_tokens"] = true
			changed = true
		else:
			for param in ["response_format", "reasoning_effort", "presence_penalty", "frequency_penalty", "top_p", "temperature"]:
				if low.contains(param) and not _compat.has("drop:" + param):
					_compat["drop:" + param] = true
					changed = true
					break
		if changed:
			_compat_retries += 1
			_post()
			return
	if code == 429:
		var retry := 20.0
		for h in headers:
			if h.to_lower().begins_with("retry-after:"):
				retry = maxf(1.0, h.split(":", true, 1)[1].strip_edges().to_float())
		_finish({"ok": false, "error": "Rate Limit (HTTP 429)", "retry_after": retry})
		return
	if code < 200 or code >= 300:
		_finish({"ok": false, "error": "HTTP %d: %s" % [code, _error_message(text)]})
		return
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.has("choices") or data.choices.is_empty():
		_finish({"ok": false, "error": "Unerwartetes Antwortformat der API"})
		return
	var msg: Dictionary = data.choices[0].get("message", {})
	var content = msg.get("content", "")
	if (not content is String or str(content).strip_edges() == "") and str(data.choices[0].get("finish_reason", "")) == "length":
		_finish({"ok": false, "error": "Antwort abgeschnitten – Denkbudget erschöpft (max_tokens_per_request erhöhen)", "usage": data.get("usage", {})})
		return
	_finish({"ok": true, "content": content if content is String else "", "usage": data.get("usage", {})})


func _error_message(text: String) -> String:
	var data = JSON.parse_string(text)
	if data is Dictionary and data.get("error") is Dictionary:
		return str(data.error.get("message", "")).left(200)
	return text.left(200)


func _finish(r: Dictionary) -> void:
	var id := _req_id
	_req_id = -1
	_sent_at = 0
	r["error"] = ApiLog.redact(str(r.get("error", "")))
	completed.emit(id, r)
