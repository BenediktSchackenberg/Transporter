extends SceneTree
## Messung: was liegt an einem Feld (Gebaeude, Boden, Auftraege mit diesem Ort)?
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var d = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var c := Vector2i(int(a[1]), int(a[2]))
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var q := c + Vector2i(dx, dy)
			var bid: int = s.city.building_at[s.city.idx(q)]
			if bid >= 0:
				print("Gebaeude ", bid, " ", s.city.building(bid).name, " bei ", q)
				break
	for v in s.vehicles.values():
		var k: Contract = s.contracts.get(v.contract_id)
		print("Lkw ", v.id, " Auftrag ", v.contract_id, " ", k.label if k != null else "-", " pickup ", s.city.building(k.pickup).get("name", "") if k != null else "", " -> ", s.city.building(k.dropoff).get("name", "") if k != null else "", " Stopps ", v.stops.size())
	quit()
