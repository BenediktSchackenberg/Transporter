class_name ApiLog
extends RefCounted
## Protokolliert API-Anfragen/-Antworten und ausgefuehrte Aktionen als JSON-Lines (user://logs/).
## Bekannte Schluessel werden vor dem Schreiben geschwaerzt; Header werden nie protokolliert.

static var _secrets: Array[String] = []
var path := ""


static func register_secret(s: String) -> void:
	if s.length() >= 6 and s not in _secrets:
		_secrets.append(s)


static func redact(text: String) -> String:
	for s in _secrets:
		text = text.replace(s, "***")
	return text


func open(match_id: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	path = "user://logs/match_%s.jsonl" % match_id


func write(entry: Dictionary) -> void:
	if path == "":
		return
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(redact(JSON.stringify(entry)))
	f.close()
