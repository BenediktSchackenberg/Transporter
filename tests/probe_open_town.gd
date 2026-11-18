extends SceneTree
## Messung 18.11.: wird Viktors haengendes Buergeramt (100 %, passt nicht) jetzt fertig?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var site: Dictionary = s.eko.homes.sites.get("BS1", {})
	print("vorher: ", site.get("status"), " ", site.get("blockiert", ""), " Stadt bereit ", s.town_ready(1))
	s.eko.homes.tick(1.0)
	print("nachher: ", site.get("status"), " Stadt bereit ", s.town_ready(1), " Rathaus ", s.city.towns[1].get("town_hall", -1))
	quit()
