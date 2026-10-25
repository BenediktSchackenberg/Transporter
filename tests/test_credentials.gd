extends SceneTree
## Manueller Test der Windows-Anmeldeinformationsverwaltung (Dummy-Schluessel, wird wieder geloescht).
func _initialize() -> void:
	var secret := "dummy-secret-%d" % (randi() % 100000)
	var ok_save := CredentialStore.save_key("selftest", secret)
	var back := CredentialStore.read_key("selftest")
	CredentialStore.delete_key("selftest")
	var after := CredentialStore.read_key("selftest")
	print("gespeichert=", ok_save, " gelesen_gleich=", back == secret, " nach_loeschen_leer=", after == "")
	quit(0 if ok_save and back == secret and after == "" else 1)
