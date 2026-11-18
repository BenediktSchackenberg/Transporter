extends SceneTree
## Messung 18.11.: was bauen die Unternehmer in der Wildnis, woran haengen Baustellen (Material, Genehmigung, Arbeit)?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var E: EkoWorld = s.eko
	print("Spielzeit ", Catalog.game_minutes_to_text(s.game_min))
	for k in s.city.towns.size():
		var st: Dictionary = s.settlements.get(str(k), {})
		var link: Dictionary = E.settle.road_link(k)
		print("Ort %d %s: Buergeramt %s, Strassenfelder %d, Baugrundstuecke %d, Anbindung %s %s" % [k, s.towns.name_of(k), s.town_ready(k),
			(st.get("roads", []) as Array).size(), (st.get("plots", []) as Array).size(), link.get("verbunden"), str(link.get("von", ""))])
	for c in s.companies:
		var sites: Array = E.homes.sites.values().filter(func(x): return int(x.cid) == c.id)
		var line := ""
		for x in sites:
			var miss: Dictionary = E.homes.missing(x) if x.status == "material" else {}
			line += "\n    %s %s %s %d%%%s%s" % [x.id, x.typ, x.status, int(100.0 * float(x.progress) / maxf(1.0, float(x.work))), (" fehlt " + str(miss)) if not miss.is_empty() else "", (" " + str(x.get("blockiert", ""))) if x.has("blockiert") else ""]
		print("%s (Kasse %d, Stamm %s): %d Baustellen%s" % [c.company_name, int(c.ledger.cash), E.estates.estates.has(E.firm_being(c.id)), sites.size(), line])
	var biz := s.biz.items.values()
	print("Betriebe: ", biz.map(func(b): return "%s %s %s" % [b.get("owner"), b.get("branche", b.get("kind", "")), b.get("status", "")]))
	quit()
