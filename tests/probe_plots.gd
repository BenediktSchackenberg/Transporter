extends SceneTree
## Messung 18.11.: Zustand des Baulands an den Siedlungsstrassen.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for key in s.settlements:
		var st: Dictionary = s.settlements[key]
		var stats := {}
		for pl in st.get("plots", []):
			var r := Rect2i(int(pl[0]), int(pl[1]), int(pl[2]), int(pl[3]))
			var p: Dictionary = s.parcels.at_cell(r.position + Vector2i(1, 1))
			var tag := "kein Grundstück" if p.is_empty() else "%s/%s/%s" % [p.state, p.zone, "Strasse" if s.civic._touches_road(r) else "ohne Strasse"]
			if not p.is_empty() and p.state == "frei":
				tag += " frei-Flaeche %s" % str(s.civic._cells_free(r))
			stats[tag] = int(stats.get(tag, 0)) + 1
			if not p.is_empty() and p.state == "frei" and s.civic._touches_road(r):
				var k := int(key)
				var pr := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
				print("   %s owner %s town_of_owner %d public %s buildable %s dist %.0f rect %s plotrect %s fit3x2 %s viertel %s" % [p.id, p.owner, Towns.town_of_owner(str(p.owner)), Towns.is_public(str(p.owner)), s.parcels.is_buildable(p),
					Vector2(pr.get_center()).distance_to(Vector2(s.sites._kern(k))), pr, r, s.sites._fit(pr, 3, 2), s.town_plan.district_at(k, pr.get_center()).get("rolle", "-")])
		print("Siedlung %s: %d Grundstuecke, Strassen %d: %s" % [key, (st.get("plots", []) as Array).size(), (st.get("roads", []) as Array).size(), stats])
	quit()
