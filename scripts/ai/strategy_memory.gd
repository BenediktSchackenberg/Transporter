class_name StrategyMemory
extends RefCounted
## Bewertete Strategieerfahrungen je Unternehmen (Etappe 2 des Lernsystems).
## Messwerte stammen ausschliesslich aus der Engine (StrategyEvaluator). Vermutungen des Modells stehen getrennt in `notes` und zaehlen nie als Beleg.
## Ein Eintrag gilt erst ab MIN_CONTRACTS abgeschlossenen Auftraegen als belastbar; die Aussage gilt nur fuer die gespeicherte Situation.

const MIN_CONTRACTS := 8
const MAX_RECORDS := 60
const MAX_NOTES := 20

var records := {}     # cid -> [ {strategy, day_from, day_to, value, contracts, ...} ]
var notes := {}       # cid -> [ {t, text, art: "vermutung"} ]


func add(cid: int, rec: Dictionary) -> void:
	var list: Array = records.get(cid, [])
	list.append(rec)
	if list.size() > MAX_RECORDS:
		list.pop_front()
	records[cid] = list


func add_note(cid: int, day: int, text: String) -> void:
	var list: Array = notes.get(cid, [])
	list.append({"tag": day, "text": text.left(240), "art": "vermutung"})
	if list.size() > MAX_NOTES:
		list.pop_front()
	notes[cid] = list


## Zusammenfassung einer Strategie: Mittelwert des Strategiewerts (Gewinn je Spieltag, ggf. mit Risikoabzug) ueber alle Bewertungszeitraeume.
func aggregate(cid: int, strategy: String) -> Dictionary:
	var n := 0
	var sum := 0.0
	var contracts := 0
	var last := {}
	for r in records.get(cid, []):
		if r.strategy != strategy:
			continue
		n += 1
		sum += float(r.value)
		contracts += int(r.contracts)
		last = r
	var confidence := "keine Daten"
	if n > 0:
		confidence = "unsicher" if contracts < MIN_CONTRACTS else ("vorlaeufig" if n < 2 else "bestaetigt")
	return {"zeitraeume": n, "mittelwert": snappedf(sum / float(n), 0.01) if n > 0 else 0.0, "auftraege": contracts, "vertrauen": confidence, "zuletzt": last}


func to_dict() -> Dictionary:
	var rec := {}
	for cid in records:
		rec[str(cid)] = records[cid]
	var nt := {}
	for cid in notes:
		nt[str(cid)] = notes[cid]
	return {"records": rec, "notes": nt}


func from_dict(d: Dictionary) -> void:
	records.clear()
	notes.clear()
	for k in d.get("records", {}):
		records[int(k)] = d.records[k]
	for k in d.get("notes", {}):
		notes[int(k)] = d.notes[k]
