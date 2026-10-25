class_name DemoAdapter
extends LLMAdapter
## DEMO-MODUS: simuliert Modellantworten lokal (keine echte KI, kein Internet).
## Erzeugt aus der eigenen Beobachtung des Spielers per RuleBrain eine JSON-Antwort und schickt sie
## nach kuenstlicher Latenz durch denselben Parser wie echte Antworten. Optional mit Fehler-Injektion
## (ungueltiges JSON, Rate Limit, ausbleibende Antwort), um die Robustheit sichtbar zu machen.

var rng := RandomNumberGenerator.new()
var personality := "kostenoptimierer"
var fault_rate := 0.0
var _timer: SceneTreeTimer
var _req_id := -1


func display_name() -> String:
	return "DEMO (simuliert)"


func send(req_id: int, _messages: Array) -> void:
	_req_id = req_id
	var r := rng.randf()
	if r < fault_rate * 0.3:
		return   # Antwort bleibt aus -> Zeitueberschreitung im Controller
	var delay := rng.randf_range(0.6, 2.2)
	_timer = get_tree().create_timer(delay, true, false, true)
	_timer.timeout.connect(_respond.bind(req_id, r))


func cancel() -> void:
	_req_id = -1


func _respond(req_id: int, r: float) -> void:
	if req_id != _req_id:
		return
	_req_id = -1
	if r < fault_rate * 0.65:
		completed.emit(req_id, {"ok": true, "content": "Ich überlege noch … {\"actions\": [kaputt", "usage": {"total_tokens": 40}})
		return
	if r < fault_rate:
		completed.emit(req_id, {"ok": false, "error": "Rate Limit (HTTP 429, simuliert)", "retry_after": 3.0})
		return
	var d := RuleBrain.decide(observation, personality, rng)
	var content := JSON.stringify(d)
	completed.emit(req_id, {"ok": true, "content": content,
		"usage": {"prompt_tokens": 1200, "completion_tokens": content.length() / 4, "total_tokens": 1200 + content.length() / 4}})
