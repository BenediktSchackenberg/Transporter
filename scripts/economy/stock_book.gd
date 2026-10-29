class_name StockBook
extends RefCounted
## Warenbestand mit Eigentuemer und tatsaechlichem Standort (docs/ECONOMY.md Abschnitt 9).
##
## Ein Posten ("Lot") hat Artikel, Menge, Eigentuemer ("T0", "C<n>", "X0"), Standort (Gebaeude-ID) und Herkunft.
## Ware entsteht nur durch add() (Import, Produktion, Rueckbau) und verschwindet nur durch consume() (Verbrauch, Export).
## move() aendert Eigentuemer und/oder Standort, nie die Menge. Jede Bewegung wird mit Grund protokolliert.

var lots := {}          # "P<n>" -> {id, item, qty, owner, loc, source, state}   (state: ok | pruefung | gesperrt)
var reservations := {}  # Referenz -> {item, qty, owner, loc}: reservierte Menge ist fuer andere Verkaeufe, Verbrauch und Transporte gesperrt
var log: Array = []     # letzte Bewegungen [{t, item, qty, von, nach, grund}]
var created := {}       # Artikel -> insgesamt entstanden (Import, Produktion, Rueckbau)
var consumed := {}      # Artikel -> insgesamt verbraucht (Verbrauch, Export)
var _next := 1


func qty(item: String, owner: String, loc: int = -2) -> int:
	var n := 0
	for l in lots.values():
		if l.item == item and l.owner == owner and (loc == -2 or l.loc == loc):
			n += int(l.qty)
	return n


## Menge im Zustand `state` (z. B. "ok" = freigegebene Ware; "pruefung" = noch im Wareneingang).
func qty_state(item: String, owner: String, loc: int, state: String) -> int:
	var n := 0
	for l in lots.values():
		if l.item == item and l.owner == owner and (loc == -2 or l.loc == loc) and l.get("state", "ok") == state:
			n += int(l.qty)
	return n


func reserved(item: String, owner: String, loc: int = -2) -> int:
	var n := 0
	for r in reservations.values():
		if r.item == item and r.owner == owner and (loc == -2 or r.loc == loc):
			n += int(r.qty)
	return n


## Frei verfuegbar = freigegebene Menge (Zustand ok) minus Reservierungen.
func available(item: String, owner: String, loc: int = -2) -> int:
	return maxi(0, qty_state(item, owner, loc, "ok") - reserved(item, owner, loc))


## Menge fuer einen Auftrag reservieren (nur freie Ware; eine Referenz einmal). Gibt false zurueck, wenn nicht genug frei ist.
func reserve(ref: String, item: String, amount: int, owner: String, loc: int) -> bool:
	if amount <= 0 or reservations.has(ref) or available(item, owner, loc) < amount:
		return false
	reservations[ref] = {"item": item, "qty": amount, "owner": owner, "loc": loc}
	return true


func release(ref: String) -> void:
	reservations.erase(ref)


## Reservierte Menge verbrauchen / verschieben (die Reservierung endet damit). Gibt die tatsaechliche Menge zurueck.
func consume_reserved(ref: String, reason: String, now: float = 0.0) -> int:
	var r: Dictionary = reservations.get(ref, {})
	if r.is_empty():
		return 0
	reservations.erase(ref)
	return consume(r.item, int(r.qty), r.owner, int(r.loc), reason, now)


func move_reserved(ref: String, to_owner: String, to_loc: int, reason: String, now: float = 0.0, to_state: String = "ok") -> int:
	var r: Dictionary = reservations.get(ref, {})
	if r.is_empty():
		return 0
	reservations.erase(ref)
	return move(r.item, int(r.qty), r.owner, int(r.loc), to_owner, to_loc, reason, now, to_state)


## Zustand eines Teils des Bestands aendern (z. B. Wareneingang pruefung -> ok). Gibt die geaenderte Menge zurueck.
func set_state(item: String, amount: int, owner: String, loc: int, from_state: String, to_state: String) -> int:
	var left := amount
	var changed := 0
	for id in lots.keys():
		var l: Dictionary = lots[id]
		if left <= 0:
			break
		if l.item == item and l.owner == owner and l.loc == loc and l.get("state", "ok") == from_state:
			var take := mini(left, int(l.qty))
			l.qty = int(l.qty) - take
			left -= take
			changed += take
			var src: String = l.source
			if int(l.qty) <= 0:
				lots.erase(id)
			_merge(item, take, owner, loc, src, to_state)
	return changed


func total(item: String) -> int:
	var n := 0
	for l in lots.values():
		if l.item == item:
			n += int(l.qty)
	return n


func add(item: String, amount: int, owner: String, loc: int, source: String, now: float = 0.0, state: String = "ok") -> String:
	assert(amount > 0)
	var id := "P%d" % _next
	_next += 1
	lots[id] = {"id": id, "item": item, "qty": amount, "owner": owner, "loc": loc, "source": source, "state": state}
	created[item] = int(created.get(item, 0)) + amount
	_note(now, item, amount, "-", "%s@%d" % [owner, loc], source)
	return id


## Menge aus Posten (Eigentuemer, Standort) entnehmen und vernichten. Gibt die tatsaechlich entnommene Menge zurueck (nie mehr als vorhanden).
func consume(item: String, amount: int, owner: String, loc: int, reason: String, now: float = 0.0) -> int:
	var left := _free_limit(item, amount, owner, loc)
	for id in lots.keys():
		var l: Dictionary = lots[id]
		if left <= 0:
			break
		if l.item == item and l.owner == owner and (loc == -2 or l.loc == loc):
			var take := mini(left, int(l.qty))
			l.qty = int(l.qty) - take
			left -= take
			if int(l.qty) <= 0:
				lots.erase(id)
	var done := amount - left
	if done > 0:
		consumed[item] = int(consumed.get(item, 0)) + done
		_note(now, item, done, "%s@%d" % [owner, loc], "-", reason)
	return done


## Menge von (Eigentuemer, Standort) nach (neuer Eigentuemer, neuer Standort) verschieben. Gibt die verschobene Menge zurueck.
func move(item: String, amount: int, owner: String, loc: int, to_owner: String, to_loc: int, reason: String, now: float = 0.0, to_state: String = "ok") -> int:
	var left := _free_limit(item, amount, owner, loc)
	var moved := 0
	for id in lots.keys():
		var l: Dictionary = lots[id]
		if left <= 0:
			break
		if l.item == item and l.owner == owner and (loc == -2 or l.loc == loc):
			var take := mini(left, int(l.qty))
			var src: String = l.source
			l.qty = int(l.qty) - take
			left -= take
			moved += take
			if int(l.qty) <= 0:
				lots.erase(id)
			_merge(item, take, to_owner, to_loc, src, to_state)
	if moved > 0:
		_note(now, item, moved, "%s@%d" % [owner, loc], "%s@%d" % [to_owner, to_loc], reason)
	return moved


## Reservierte Ware darf ohne ihre Referenz weder verbraucht noch verkauft noch verschoben werden.
func _free_limit(item: String, amount: int, owner: String, loc: int) -> int:
	if reservations.is_empty():
		return amount
	return mini(amount, maxi(0, qty(item, owner, loc) - reserved(item, owner, loc)))


func _merge(item: String, amount: int, owner: String, loc: int, source: String, state: String = "ok") -> void:
	for l in lots.values():
		if l.item == item and l.owner == owner and l.loc == loc and l.source == source and l.get("state", "ok") == state:
			l.qty = int(l.qty) + amount
			return
	var id := "P%d" % _next
	_next += 1
	lots[id] = {"id": id, "item": item, "qty": amount, "owner": owner, "loc": loc, "source": source, "state": state}


func _note(t: float, item: String, amount: int, from_s: String, to_s: String, reason: String) -> void:
	log.append({"t": t, "item": item, "qty": amount, "von": from_s, "nach": to_s, "grund": reason})
	if log.size() > 200:
		log.pop_front()


## Kontrollsumme: entstanden - verbraucht == vorhandener Bestand (je Artikel). Soll 0 sein.
func balance_error() -> int:
	var err := 0
	var items := {}
	for k in created:
		items[k] = true
	for k in consumed:
		items[k] = true
	for l in lots.values():
		items[l.item] = true
	for it in items:
		err += absi(int(created.get(it, 0)) - int(consumed.get(it, 0)) - total(it))
	return err


func of_owner(owner: String) -> Array:
	return lots.values().filter(func(l): return l.owner == owner)


func to_dict() -> Dictionary:
	return {"lots": lots, "log": log.slice(-60), "created": created, "consumed": consumed, "next": _next, "reservations": reservations}


func from_dict(d: Dictionary) -> void:
	lots = {}
	for id in d.get("lots", {}):
		var l: Dictionary = d.lots[id]
		l.qty = int(l.qty)
		l.loc = int(l.loc)
		lots[id] = l
	reservations = d.get("reservations", {})
	for r in reservations.values():
		r.qty = int(r.qty)
		r.loc = int(r.loc)
	log = d.get("log", [])
	created = {}
	consumed = {}
	for k in d.get("created", {}):
		created[k] = int(d.created[k])
	for k in d.get("consumed", {}):
		consumed[k] = int(d.consumed[k])
	_next = int(d.get("next", 1))
