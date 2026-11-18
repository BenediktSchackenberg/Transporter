extends SceneTree
## Auftrag 8: Viertel-Strassennetz beschliessen und sofort abnehmen (am Spielstand) – Strassen, Platz, Bauland, Standortwahl danach.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for k in s.towns.count():
		if not s.town_plan.has(k):
			continue
		var M: Mayor = s.towns.mayor(k)
		for v in s.town_plan.of(k).viertel:
			var r: Dictionary = M.execute({"action": "viertel_erschliessen", "viertel": v.id, "reason": "Probe"})
			if not r.has("project"):
				continue
			var prj: Dictionary = M.projects[r.project]
			var roads0: int = s.city.road_count
			var plots0: int = (s.settlements.get(str(k), {}).get("plots", []) as Array).size()
			s.construction._finish_district(M, prj)
			print("%s %s (%s): %s | Strassen +%d, Grundstuecke +%d, Status %s" % [s.towns.name_of(k), v.id, v.rolle, str(prj.reason).left(120), s.city.road_count - roads0,
				(s.settlements.get(str(k), {}).get("plots", []) as Array).size() - plots0, v.status])
		for req in [{"w": 5, "h": 4, "art": "wohnen", "label": "Einfamilienhaus"}, {"w": 4, "h": 3, "art": "laerm", "label": "Betriebshof Abfallwirtschaft"}]:
			var ch: Dictionary = s.sites.choose(k, req)
			print("   danach %s: %s" % [req.label, str(ch.get("begruendung", ch.get("msg", ""))).left(260)])
	quit()
