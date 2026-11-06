extends SceneTree
## Messung: Groesse der KI-Beobachtung je Schluessel (Zeichen/4 ~ Token). Godot_console.exe --headless --path . -s tests/probe_obs_size.gd
func _initialize() -> void:
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, ps, 128, 0.5)
	var obs := ObservationBuilder.build(s, 0, [], 0.0, 10.0)
	var rows: Array = []
	for k in obs:
		rows.append([JSON.stringify(obs[k]).length() / 4, k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 25):
		print("%5d  %s" % r)
	print("gesamt ~", JSON.stringify(obs).length() / 4)
	quit()
