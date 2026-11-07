extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var seed_value := 4242
	var count := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
	var gen := CornerRegionGenerator.new(count)
	var cd := gen.generate(seed_value, 512)
	print(JSON.stringify({"ok": gen.report.ok, "errors": gen.report.get("fehler", []), "towns": cd.towns.map(func(t): return {"corner": t.ecke, "center": t.center, "airport": t.has("airport"), "start_plot": t.get("start_plot", -1)}), "roads": cd.region_roads}))
	quit(0 if gen.report.ok else 1)
