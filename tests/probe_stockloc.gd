extends SceneTree
## Messung 18.11.: wo liegt gekaufte Ware der Firma 0 und wo sucht die Baustelle?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var c = s.companies[0]
	print("depots ", c.depots, " _depot ", s.eko.homes._depot(0))
	for it in ["installation", "holz", "ziegel", "beton", "glas"]:
		var where := {}
		for site in c.depots:
			where[site] = s.stock.available(it, "C0", int(site))
		print(it, " je Standort ", where, " gesamt(-2) ", s.stock.available(it, "C0", -2))
	var k: Contract = s.contracts.get("A253")
	if k != null:
		print("A253 ", k.status, " pickup ", k.pickup, " dropoff ", k.dropoff, " ", s.city.building(k.dropoff).get("name", ""))
	for e in s.stock.log:
		if str(e.item) in ["installation", "holz", "glas"] and (str(e.get("von", "")).contains("C0") or str(e.get("nach", "")).contains("C0")):
			print("  log ", e)
	for l in s.stock.lots.values():
		if str(l.owner) == "C0" and str(l.item) in ["installation", "holz", "glas"]:
			print("  lot ", l)
	quit()
