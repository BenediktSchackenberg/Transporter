extends SceneTree
## Trainingsliga (kein Pass/Fail, keine Modellaufrufe): vergleicht die Strategieprofile der Regel-KI in reproduzierbaren Partien.
##   Godot_console.exe --headless --path . -s tests/train_strategies.gd -- --seeds=21,22,23 --days=30 --personality=wachstum
## Jede Partie hat vier Plaetze (konservativ, wachstum, effizient, lernend); die Plaetze rotieren (Arena.compare), alle Firmen bekommen
## gleiches Startkapital, gleiche Karte und gleiches Aktionsbudget. Ein Profil gilt nur als bewaehrt, wenn es in mindestens zwei Dritteln
## der Karten (Seeds) den hoechsten mittleren Gewinn hat. Ergebnis: Ausgabe und user://strategy_training.json (aendert config/strategies.json nicht).

const PROFILES := ["konservativ", "wachstum", "effizient", "lernend"]


func _initialize() -> void:
	var seeds: Array = [21, 22, 23]
	var days := 30.0
	var personality := "wachstum"
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--seeds="):
			seeds = Array(s.trim_prefix("--seeds=").split(",")).map(func(x): return int(x))
		elif s.begins_with("--days="):
			days = float(s.trim_prefix("--days="))
		elif s.begins_with("--personality="):
			personality = s.trim_prefix("--personality=")
	GameCalendar.configure(60.0)
	var per_seed: Array = []
	var wins := {}
	var total := {}
	for sd in seeds:
		var spec := {"seed": sd, "map": 128, "steps": int(days * 600.0), "brains": [personality, personality, personality, personality],
			"strategies": PROFILES, "events": []}
		var res: Dictionary = Arena.compare(spec)
		var best := ""
		var best_profit := -INF
		for row in res.summary:
			print("Seed %d  %-10s Gewinn %9.0f  Vermoegen %9.0f  Rang %.2f  Siege %d" % [sd, row.strategie, row.gewinn, row.vermoegen, row.rang, row.siege])
			if float(row.gewinn) > best_profit:
				best_profit = float(row.gewinn)
				best = str(row.strategie)
			total[row.strategie] = float(total.get(row.strategie, 0.0)) + float(row.gewinn) / float(seeds.size())
		wins[best] = int(wins.get(best, 0)) + 1
		per_seed.append({"seed": sd, "summary": res.summary})
	var needed := ceili(float(seeds.size()) * 2.0 / 3.0)
	var adopted := ""
	for id in wins:
		if int(wins[id]) >= needed and id != "lernend":
			adopted = id
	print("Siege je Profil: ", wins, "  mittlerer Gewinn: ", total)
	print("Bewaehrt (mind. %d von %d Karten): %s" % [needed, seeds.size(), adopted if adopted != "" else "kein Profil"])
	var f := FileAccess.open("user://strategy_training.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"days": days, "personality": personality, "seeds": seeds, "wins": wins, "mean_profit": total, "adopted": adopted, "per_seed": per_seed}, "\t"))
		f.close()
	quit()
