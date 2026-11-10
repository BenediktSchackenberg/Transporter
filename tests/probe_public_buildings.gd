extends SceneTree
## Auftrag 20, Bestandsaufnahme: welche oeffentlichen Gebaeude (Rolle/Typ) hat jede Stadt der Region beim Start?
## Aufruf: Godot --headless --path . -s tests/probe_public_buildings.gd


func _init() -> void:
	var s := Simulation.new()
	s.world_mode = "region"
	s.start_profile = "unternehmer"
	var pl: Array = []
	for i in 4:
		pl.append({"player_name": "Spieler%d" % i, "company_name": "Firma%d" % i, "color": Catalog.COMPANY_COLORS[i],
			"avatar_style": i, "personality": Catalog.PERSONALITIES.keys()[i]})
	s.setup(4242, pl, Catalog.MAP_SIZE, 0.5)
	for t in s.towns.list:
		var roles := {}
		for b in s.city.buildings:
			if s.towns.of_building(int(b.id)) != int(t.id):
				continue
			var key := "%s/%s" % [b.role, b.type]
			roles[key] = int(roles.get(key, 0)) + 1
		print("Stadt %d %s charakter=%s: %s" % [t.id, t.name, t.get("charakter", ""), str(roles)])
	quit()
