extends SceneTree
## Vergleichsmodus (kein Pass/Fail): spielt Strategien gegeneinander, rotiert die Startpositionen und schreibt die Kennzahlen als CSV.
##   Godot_console.exe --headless --path . -s tests/arena_compare.gd -- --seed=21 --days=3 --brains=kostenoptimierer,wachstum --out=user://arena.csv [--closure]
## --closure loest am zweiten Spieltag eine Strassensperrung an der Zufahrt von Unternehmen 0 aus.


func _initialize() -> void:
	var seed_value := 21
	var days := 3.0
	var brains: Array = ["kostenoptimierer", "wachstum"]
	var out := "user://arena.csv"
	var closure := false
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seed="):
			seed_value = int(s.trim_prefix("--seed="))
		elif s.begins_with("--days="):
			days = float(s.trim_prefix("--days="))
		elif s.begins_with("--brains="):
			brains = s.trim_prefix("--brains=").split(",")
		elif s.begins_with("--out="):
			out = s.trim_prefix("--out=")
		elif s == "--closure":
			closure = true
	GameCalendar.configure(60.0)
	var spec := {"seed": seed_value, "map": 128, "steps": int(days * 600.0), "brains": brains, "events": []}
	if closure:
		spec.events.append({"step": 600, "typ": "strassensperre", "params": {"cell": "depot0"}, "duration": 600.0})
	var res := Arena.compare(spec)
	for row in res.summary:
		print("%s: Läufe %d, Gewinn %.0f, Vermögen %.0f, mittlerer Rang %.2f, Siege %d" % [row.strategie, row.laeufe, row.gewinn, row.vermoegen, row.rang, row.siege])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(Arena.to_csv(res.rows))
	f.close()
	print("CSV: ", ProjectSettings.globalize_path(out))
	quit()
