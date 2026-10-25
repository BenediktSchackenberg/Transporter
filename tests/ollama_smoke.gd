extends SceneTree
## Optionaler Integrationstest: lokaler Docker-Stack und Qwen-Modell muessen laufen.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var adapter := OllamaAdapter.new()
	root.add_child(adapter)
	adapter.config = {"base_url": OllamaAdapter.DEFAULT_BASE_URL, "model": OllamaAdapter.DEFAULT_MODEL,
		"max_tokens_per_request": 300, "timeout": 90.0}
	var replies: Array = []
	adapter.completed.connect(func(_id: int, result: Dictionary): replies.append(result))
	adapter.send(1, [{"role": "system", "content": "Antworte nur als JSON-Objekt mit summary und actions."},
		{"role": "user", "content": "Gib eine kurze deutsche Zusammenfassung und eine wait-Aktion zurück."}])
	var deadline := Time.get_ticks_msec() + 95000
	while replies.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if replies.is_empty() or not replies[0].get("ok", false):
		printerr("Ollama-Anfrage fehlgeschlagen: ", replies[0].get("error", "Timeout") if not replies.is_empty() else "Timeout")
		quit(1)
		return
	var parsed := AgentController.parse_response(str(replies[0].content))
	if not parsed.ok:
		printerr("Ollama-Aktions-JSON ungültig: ", parsed.error)
		quit(1)
		return
	print("PASS: Ollama lokal liefert gültiges Aktions-JSON; Token: ", replies[0].usage.total_tokens)
	quit()
