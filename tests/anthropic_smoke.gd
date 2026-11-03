extends SceneTree
## Durchlauf des AnthropicAdapters gegen einen Testserver (kein echter Schluessel noetig):
##   Godot_console.exe --headless --path . -s tests/anthropic_smoke.gd -- --url=http://127.0.0.1:8099/v1
## Fuer die echte API: --url=https://api.anthropic.com/v1 --key-env=ANTHROPIC_API_KEY (der Schluessel wird nie ausgegeben).


func _initialize() -> void:
	var url := "http://127.0.0.1:8099/v1"
	var key := "TEST_KEY"
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--url="):
			url = str(a).trim_prefix("--url=")
		elif str(a).begins_with("--key-env="):
			key = OS.get_environment(str(a).trim_prefix("--key-env="))
	var ad := AnthropicAdapter.new()
	ad.config = {"base_url": url, "model": "claude-haiku-5-5", "api_key": key, "timeout": 60.0, "max_tokens_per_request": 600}
	root.add_child(ad)
	ad.completed.connect(func(id, r):
		print("Antwort ", id, ": ok=", r.ok, " inhalt=", str(r.get("content", "")).left(120), " fehler=", r.get("error", ""), " nutzung=", r.get("usage", {}))
		quit())
	await process_frame   # _ready des Adapters abwarten
	ad.send(1, [{"role": "system", "content": "Antworte nur mit JSON."}, {"role": "user", "content": "Gib {\"ok\": true} zurueck."}])
