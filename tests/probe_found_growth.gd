extends SceneTree
## Benedikt 18.11.: Gruendung -> Startpaket (Kern-Strassennetz) und Bautraeger in der Wildnis (am Spielstand, Buergeraemter fertiggestellt).
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for sid in s.eko.homes.sites:
		var st: Dictionary = s.eko.homes.sites[sid]
		if str(st.typ) == "buergeramt" and str(st.status) in ["bau", "material"]:
			st.status = "bau"
			st.progress = float(st.work)
	s.eko.homes.tick(1.0)
	for k in s.towns.count():
		var M: Mayor = s.towns.mayor(k)
		print("%s: gegruendet %s, Plan %s, Kernprojekt %s" % [s.towns.name_of(k), s.town_ready(k), s.town_plan.of(k).get("label", "-"),
			M.projects.values().filter(func(p): return p.has("road_plan")).map(func(p): return "%s %s %d Felder %s" % [p.id, p.status, (p.road_plan as Array).size(), p.reason.left(60)])])
	var day0 := GameCalendar.day_of(s.game_min)
	var steps := int(GameCalendar.day_seconds / 0.1) * 16
	for i in steps:
		s.step(0.1)
	for k in s.towns.count():
		var apps: Array = s.permits.apps.values().filter(func(a): return str(a.applicant) == Construction.DEVELOPER and s.towns.of_parcel(str(a.parcel)) == k)
		var prs: Array = s.construction.projects.values().filter(func(p): return s.towns.of_parcel(str(p.parcel)) == k)
		print("%s nach 16 Tagen: Bautraeger-Antraege %d (%s), Bauprojekte %d (%s), Entscheidungen: %s" % [s.towns.name_of(k), apps.size(), ", ".join(apps.map(func(a): return "%s %s %s" % [a.def, a.parcel, a.status])),
			prs.size(), ", ".join(prs.map(func(p): return p.status)), (s.town_plan.of(k).get("entscheidungen", []) as Array).slice(-2).map(func(e): return str(e.begruendung).left(140))])
	for k in s.towns.count():
		var Mk: Mayor = s.towns.mayor(k)
		var r: Dictionary = s.sites.rank(k, {"w": 5, "h": 4, "art": "wohnen", "label": "Einfamilienhaus"})
		var cand: Array = s.parcels.search({"zone": "wohnen", "min_area": 12, "utilities": "teilweise", "limit": 2000, "town": k})
		print("  %s: wartend %d, Leerstand %.2f, gueltige Plaetze %d, ohne Strasse %d, Gruenzug %d, zu klein %d, Suche wohnen/teilweise %d, Bautraeger-Kasse %.0f" % [s.towns.name_of(k), Mk.waiting, Mk.vacancy(), (r.list as Array).size(), (r.ohne_strasse as Array).size(), r.gruen, r.zu_klein, cand.size(), s.construction.available_funds(Construction.DEVELOPER)])
	for k in s.towns.count():
		var r2: Dictionary = s.sites.rank(k, {"w": 4, "h": 2, "art": "wohnen", "label": "Doppelhaus"})
		for c in (r2.list as Array).slice(0, 2):
			var pp: Dictionary = s.parcels.parcel(str(c.parcel))
			for def_id in ["doppelhaus", "einfamilienhaus"]:
				var chk := Planning.assess(pp, {"def": def_id, "floors": int(Planning.DEFS[def_id].floors[0]), "parking": int(Planning.DEFS[def_id].parking), "financing": {"eigenmittel": 1.0e9}})
				print("   %s %s %s Zone %s Flaeche %d utilities %s: ok %s blocking %s questions %s" % [s.towns.name_of(k), c.parcel, def_id, pp.zone, int(pp.area), s.parcels.utility_level(pp), chk.ok, chk.blocking, chk.questions])
		print("   Siedlungsgrundstuecke %d, P-Strassen %s" % [(s.settlements.get(str(k), {}).get("plots", []) as Array).size(), s.towns.mayor(k).projects.values().filter(func(p): return p.has("road_cells")).map(func(p): return (p.road_cells as Array).size())])
	var C: Construction = s.construction
	print("   Region ", s.towns.is_region(), " neubeginn ", s.neubeginn, " wildnis ", s.wildnis, " Tag ", GameCalendar.day_of(s.game_min))
	for k in s.towns.count():
		var running := 0
		for pr in C.projects.values():
			if pr.client == Construction.DEVELOPER and pr.status in ["angebote", "erschliessung", "im_bau", "pruefung", "wartet_anschluss"] and s.towns.of_parcel(str(pr.parcel)) == k:
				running += 1
		var open_apps: Array = s.permits.apps.values().filter(func(a): return a.applicant == Construction.DEVELOPER and s.towns.of_parcel(str(a.parcel)) == k and a.status != "entschieden")
		print("   Stadt %d: laufend %d, offene Antraege %d %s, waiting %d vacancy %.2f, units %d" % [k, running, open_apps.size(), open_apps.map(func(a): return "%s %s %s" % [a.id, a.status, a.parcel]), s.towns.mayor(k).waiting, s.towns.mayor(k).vacancy(), s.towns.mayor(k).town_units().size()])
		var n0: int = s.permits.apps.size()
		var r1: bool = C._developer_once(k)
		print("   _developer_once(%d) -> %s, neue Antraege %d, supply %s commerce %s" % [k, r1, s.permits.apps.size() - n0, "-", "-"])
		var free: Array = s.parcels.search({"zone": "wohnen", "min_area": 12, "utilities": "teilweise", "limit": 2000, "town": k})
		var ordered: Array = s.sites.order_parcels(k, free, {"w": 4, "h": 2, "art": "wohnen", "floors": 1, "label": "Doppelhaus"}, true)
		print("   geordnet %d von %d: %s" % [ordered.size(), free.size(), ordered.slice(0, 3).map(func(p): return p.id)])
		var n1: int = s.permits.apps.size()
		print("   _developer_try doppelhaus -> ", C._developer_try(free, "doppelhaus"), " neue Antraege ", s.permits.apps.size() - n1)
	for k in s.towns.count():
		var M: Mayor = s.towns.mayor(k)
		for p in M.projects.values().filter(func(p): return p.has("road_plan")):
			var e: Dictionary = s.construction.public.get(p.id, {})
			print("  %s %s: %s, Rest %s, wartet %s" % [s.towns.name_of(k), p.id, p.status, e.get("days_left", "-"), e.get("waiting", "")])
	quit()
