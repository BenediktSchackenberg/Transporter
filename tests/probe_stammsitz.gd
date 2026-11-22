extends SceneTree
## Aktuellen Spielstand auf finanzierbare Stammsitz-Ausbauoptionen prüfen.
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	for name in ["Greta", "Viktor"]:
		var b: Dictionary = s.eko.beings[name]
		var cid: int = s.eko.active_firm(b)
		var cash: float = s.company(cid).ledger.cash
		print("%s: privat %.0f EUR, Firma %.0f EUR" % [name, float(b.geld), cash])
		for option in s.eko.estates.decision_options(name):
			print("  %s Feld %d: %.0f EUR, finanzierbar %s" % [option.art, int(option.feld), float(option.kosten), cash >= float(option.kosten) + 5000.0])
		var options: Array = s.eko.estates.decision_options(name).filter(func(x): return cash >= float(x.kosten) + 5000.0)
		if not options.is_empty():
			var option: Dictionary = options[0]
			var result: Dictionary = s.eko.input(name, "Bauwerk", {"art": option.art, "feld": option.feld,
				"material": option.material, "hoehe": option.hoehe, "zahlung": "firma"})
			var project: Dictionary = (s.eko.estates.estates[name].bauten as Array).back()
			s.eko.estates.tick(1.0)
			print("  Probe auf Spielstand-Kopie: Auftrag %s, Blöcke nach 1 s %d, Privatgeld %.0f EUR" % [
				result.ok, int(project.placed), float(b.geld)])
	quit()
