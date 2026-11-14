extends SceneTree
## Weite Arbeitswege der Buerger-KI finden: Wohnung, Arbeitsplatz, Orte. Godot_console.exe --headless --path . -s tests/probe_commute.gd
func _initialize() -> void:
	var s := Simulation.new()
	s.world_mode = "region"
	var ps: Array = []
	for i in 2:
		ps.append({"player_name": "P%d" % i, "company_name": "F%d" % i, "color": Color.RED, "avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, ps, Catalog.MAP_SIZE, 0.5)
	var B: CitizenBrain = s.citizens.brain
	var far := 0
	for p in s.citizens.people:
		var d := B._commute(p)
		if d > 120.0:
			far += 1
			if far <= 6:
				var unit: Dictionary = s.housing.units.get(str(p.home), {})
				var hb: Dictionary = s.city.building(int(unit.building))
				var w := B._workplace(p, B._town_of(p, int(unit.building)))
				var wb: Dictionary = s.city.building(w)
				print("%d Felder: %s (%s) wohnt %s [Ort %d, %d/%d] arbeitet %s [Ort %d, %d/%d]" % [int(d), p.name, p.employer, hb.name, s.towns.of_building(int(hb.id)), hb.x, hb.y, wb.name, s.towns.of_building(w), wb.x, wb.y])
	print("weit: %d von %d" % [far, s.citizens.people.size()])
	quit()
