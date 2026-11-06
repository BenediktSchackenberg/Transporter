extends SceneTree
## Messung: Wettbewerbsfaehigkeit lokalen Brots - Abstaende und Stueckkosten frei Laden/Grosshandel je Unternehmenssitz.
## Godot_console.exe --headless --path . -s tests/probe_bread.gd
func _initialize() -> void:
	var s := Simulation.new()
	var ps: Array = []
	for i in 4:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(21, ps)
	var P: Production = s.prod
	var wl: int = s.retail.wholesale_building
	var port: int = s.city_depot.port
	var d := func(a: int, b: int) -> int:
		var x: Dictionary = s.city.building(a)
		var y: Dictionary = s.city.building(b)
		return absi(x.road.x - y.road.x) + absi(x.road.y - y.road.y)
	print("Karte %d, Großhandel %d, Importterminal %d, Abstand Terminal-Großhandel %d" % [s.city.size, wl, port, d.call(port, wl)])
	for q in [200, 600, 2000]:
		print("  Import frei Großhandel bei %d Stk: %.2f EUR/Stk" % [q, 0.9 + P.freight(port, wl, "brot", q) / float(q)])
	var shops: Array = s.retail.shops.values().filter(func(x): return "brot" in s.retail.spec_of(x).goods)
	for sh in shops:
		var q := int(ceil(float(sh.use.brot) * 10.0))
		print("  Laden %s (%s): Bedarf %.0f/Tag, Bestellung %d, über Großhandel %.2f EUR/Stk (Abstand %d)" % [sh.id, sh.name, float(sh.use.brot), q, 0.9 * 1.3 + P.freight(wl, int(sh.building), "brot", q) / float(q), d.call(wl, int(sh.building))])
	for c in s.companies:
		var hq := int(c.depots[0])
		var line := "F%d Sitz: zum Großhandel %d (600 Stk à 0.80: %.2f)" % [c.id, d.call(hq, wl), 0.8 + P.freight(hq, wl, "brot", 600) / 600.0]
		for sh in shops:
			var q := int(ceil(float(sh.use.brot) * 10.0))
			line += " | %s %d: %.2f" % [sh.id, d.call(hq, int(sh.building)), 0.8 + P.freight(hq, int(sh.building), "brot", q) / float(q)]
		print(line)
	quit()
