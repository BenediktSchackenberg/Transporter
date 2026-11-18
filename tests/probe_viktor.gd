extends SceneTree
## Messung 18.11.: was sieht Viktor bei Kies-Kauf und Inspect BS1?
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var s := Simulation.from_dict(d.sim if d.has("sim") else d)
	var E: EkoWorld = s.eko
	print("Inspect: ", E.input("Viktor", "Inspect", {"target_id": "BS1"}).msg)
	print("Kies:    ", E.input("Viktor", "Firma", {"aktion": {"action": "hub_buy", "item": "kies", "qty": 20}}).msg)
	quit()
