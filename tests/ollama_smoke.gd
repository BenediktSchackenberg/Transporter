extends SceneTree
## Optionaler Integrationstest: lokaler Docker-Stack und Qwen-Modell muessen laufen.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var players: Array = []
	for i in 2:
		players.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i,
			"color": Catalog.COMPANY_COLORS[i], "avatar_style": i,
			"personality": Catalog.PERSONALITIES.keys()[i]})
	var sim := Simulation.new()
	sim.setup(4242, players, 128, 0.5)
	var controller := AgentController.new()
	controller.sim = sim
	controller.cid = 0
	controller.config = {"provider": "ollama"}
	var messages := [{"role": "system", "content": controller.system_prompt()},
		{"role": "user", "content": controller.user_prompt(
			ObservationBuilder.build(sim, 0, [], 0.0, 30.0))}]
	var adapter := OllamaAdapter.new()
	root.add_child(adapter)
	adapter.config = {"base_url": OllamaAdapter.DEFAULT_BASE_URL, "model": OllamaAdapter.DEFAULT_MODEL,
		"max_tokens_per_request": 900, "timeout": 90.0}
	var replies: Array = []
	adapter.completed.connect(func(_id: int, result: Dictionary): replies.append(result))
	adapter.send(1, messages)
	var deadline := Time.get_ticks_msec() + 95000
	while replies.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if replies.is_empty() or not replies[0].get("ok", false):
		printerr("Ollama-Anfrage fehlgeschlagen: ", replies[0].get("error", "Timeout") if not replies.is_empty() else "Timeout")
		quit(1)
		return
	var parsed := AgentController.parse_response(str(replies[0].content))
	if not parsed.ok or parsed.actions.is_empty() or int(replies[0].usage.prompt_tokens) < 5000:
		printerr("Ollama-Spielantwort ungültig oder Prompt abgeschnitten: ", parsed.error if not parsed.ok else str(replies[0].usage))
		quit(1)
		return
	print("PASS: Ollama verarbeitet vollständigen Spiel-Prompt und liefert Aktionen; Token: ", replies[0].usage.total_tokens)
	quit()
