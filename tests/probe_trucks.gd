extends SceneTree
## Messung 18.11.: Lkw der Unternehmer (Zustand, Ziel, Auftrag) und offene Abholungen am Grosslager.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for v in s.vehicles.values():
		var k: Contract = s.contracts.get(v.contract_id)
		print("Lkw %d (%s) Firma %d: Zustand %s, Feld %s, Ziel %s, Auftrag %s %s, Ladung %s, Kraftstoff %.0f, kaputt-Grund %s" % [v.id, v.model, v.owner, v.state, v.tile(), v.goal, v.contract_id,
			(k.status + " " + k.label) if k != null else "-", str(s.logistics.load_total(v)), s.companies[v.owner].fuel, v.get("broken_reason") if "broken_reason" in v else "-"])
	for c in s.companies:
		var mine: Array = s.contracts.values().filter(func(k): return k.owner == c.id or k.exclusive_for == c.id)
		var st := {}
		for k in mine:
			st[k.status] = int(st.get(k.status, 0)) + 1
		print(c.company_name, " Aufträge: ", st, " Hub-Abholungen offen: ", s.hub.pending_pickups(c.id).size() if s.hub.has_method("pending_pickups") else "?")
	quit()
