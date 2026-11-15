class_name EkoArms
extends RefCounted
## Waffen und Schutz im Eko-Modus (Benedikt 15.11.2026: "die KI muss selber darauf kommen, eine Waffenschmiede zu bauen und Waffen
## zu konzipieren, und verstehen, wenn Gefahr droht, dass sie sich schuetzt").
## Nichts wird vorgegeben: Eine Firma kann die Branche "waffenschmiede" gruenden, dort mit design_weapon eigene Entwuerfe anlegen
## (Typ + Material; die Welt berechnet daraus Schaden, Reichweite, Schutz, Bauzeit und Kosten) und mit forge_weapon fertigen.
## Wesen nehmen Waffen am eigenen Werk auf (Pickup {waffe}), geben sie weiter (Give) und setzen sie ein (Attack).
## Gefahr ist sichtbar (observe.gefahren: bewaffnete Wesen, Angriffe, Explosionen, Strahlung); Schutz: Ruestung, die Mauern des
## eigenen Hauses, Abstand, Gegenwehr. Gewalt hat Folgen: Entdeckung, Bussgeld (bei Wiederholung hoeher), sonst Gewahrsam.
## Ausgeschaltete Wesen verlieren einen Teil ihres Geldes an den Angreifer und erwachen nach einer Weile am Bauhof wieder.

const MATERIALS := ["stahl", "elektronik", "kunststoffgranulat", "diesel", "kabel", "glas", "brennelement", "uranerz"]
const OWN_ONLY := ["brennelement", "uranerz"]   # nicht im Handel: nur aus eigenen Lagern (eigenes Brennelementwerk, Uranbergwerk)
const TYPES := ["nahkampf", "fernkampf", "sprengsatz", "atom", "ruestung"]
const OUT_S := 300.0                # so lange ist ein ausgeschaltetes Wesen ausser Gefecht (Echtzeitsekunden)
const CUSTODY_S := 180.0            # Gewahrsam, wenn ein Bussgeld nicht bezahlt werden kann
const LOOT_SHARE := 0.3
const FUSE_S := 30.0                # Zuender der Atombombe: Zeit zum Weglaufen
const RAD_DAYS := 5
const INCIDENT_KEEP_MS := 180000
const DETECT := {"nahkampf": 0.5, "fernkampf": 0.5, "sprengsatz": 0.7, "atom": 1.0}
const FINE := {"nahkampf": 800.0, "fernkampf": 1200.0, "sprengsatz": 5000.0, "atom": 200000.0}

var w                               # EkoWorld
var designs := {}                   # Name -> Entwurf
var arsenal := {}                   # "cid" -> [{id, design}]
var pending: Array = []             # {fertig_tag, cid, design, n}
var bombs: Array = []               # scharfe Atombomben {feld, left, by, design}
var zones: Array = []               # Strahlung {feld, radius, bis_tag}
var incidents: Array = []           # {feld, ms, text} (Anzeige und Wahrnehmung)
var blasts: Array = []              # {feld, ms, radius} (nur Anzeige)
var _next := 1


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


func _day() -> int:
	return GameCalendar.day_of(w.sim.game_min)


# ------------------------------------------------------------------ Entwurf und Fertigung (Firma)
## Regeln der Welt: aus Typ und Material folgen die Werte. Gibt {ok, entwurf | msg} zurueck.
static func evaluate(typ: String, mat: Dictionary) -> Dictionary:
	var m := {}
	for k in mat:
		if str(k) not in MATERIALS:
			return {"ok": false, "msg": "Unbekanntes Material %s. Erlaubt: %s." % [k, ", ".join(MATERIALS)]}
		var q := int(mat[k])
		if q < 0 or q > 20:
			return {"ok": false, "msg": "Menge je Material 0 bis 20."}
		if q > 0:
			m[str(k)] = q
	var st := int(m.get("stahl", 0))
	var el := int(m.get("elektronik", 0))
	var e := {"typ": typ, "material": m, "schaden": 0, "reichweite": 0, "radius": 0, "schutz": 0.0, "einweg": false, "tage": 0}
	match typ:
		"nahkampf":
			if st < 1:
				return {"ok": false, "msg": "Eine Nahkampfwaffe braucht mindestens 1 Stahl."}
			e.schaden = mini(45, 15 + 10 * st)
			e.reichweite = 1
		"fernkampf":
			if st < 1 or el < 1:
				return {"ok": false, "msg": "Eine Fernwaffe braucht mindestens 1 Stahl und 1 Elektronik."}
			e.schaden = mini(40, 8 + 6 * st + 6 * el)
			e.reichweite = mini(8, 3 + el + int(m.get("kabel", 0)))
			e.tage = 1
		"sprengsatz":
			if int(m.get("diesel", 0)) < 1 or int(m.get("kunststoffgranulat", 0)) < 1:
				return {"ok": false, "msg": "Ein Sprengsatz braucht mindestens 1 Diesel und 1 Kunststoffgranulat."}
			e.schaden = mini(80, 30 + 15 * int(m.diesel))
			e.radius = mini(3, 1 + int(m.diesel) / 2)
			e.reichweite = 3
			e.einweg = true
			e.tage = 1
		"atom":
			if int(m.get("brennelement", 0)) < 2 or el < 3 or st < 5:
				return {"ok": false, "msg": "Eine Atombombe braucht mindestens 2 Brennelemente, 3 Elektronik und 5 Stahl."}
			e.schaden = 100
			e.radius = mini(12, 6 + int(m.brennelement))
			e.reichweite = 2
			e.einweg = true
			e.tage = 5
		"ruestung":
			if st < 1:
				return {"ok": false, "msg": "Eine Ruestung braucht mindestens 1 Stahl."}
			e.schutz = snappedf(minf(0.6, 0.1 * st + 0.05 * int(m.get("kunststoffgranulat", 0))), 0.01)
			e.tage = 1
		_:
			return {"ok": false, "msg": "typ muss einer von %s sein." % ", ".join(TYPES)}
	var cost := 200.0
	for k in m:
		var a := Production.art(k)
		cost += float(a.get("importpreis") if a.get("importpreis") != null else a.get("basispreis", 0.0)) * int(m[k])
	e["kosten_je_stueck"] = snappedf(cost, 1.0)
	return {"ok": true, "entwurf": e}


func _forge_site(cid: int) -> Dictionary:
	for biz in _sim().biz.items.values():
		if int(biz.owner) == cid and str(biz.branch) == "waffenschmiede" and biz.status in Businesses.RUNNING:
			return biz
	return {}


func firm_action(b: Dictionary, cid: int, a: Dictionary) -> Dictionary:
	var site := _forge_site(cid)
	if site.is_empty():
		return {"ok": false, "msg": "Dafür brauchst du eine laufende Waffenschmiede (found_business branche waffenschmiede, Personal zuordnen)."}
	if str(a.action) == "design_weapon":
		var name := str(a.get("name", "")).strip_edges().left(30)
		if name == "" or designs.has(name):
			return {"ok": false, "msg": "Gib dem Entwurf einen neuen, eindeutigen Namen."}
		var mat = a.get("material", {})
		var r := evaluate(str(a.get("typ", "")), mat if mat is Dictionary else {})
		if not r.ok:
			return r
		var e: Dictionary = r.entwurf
		e["name"] = name
		e["cid"] = cid
		designs[name] = e
		w._event(b, "entwirft %s (%s)" % [name, e.typ])
		return {"ok": true, "msg": "Entwurf %s: %s" % [name, _stats(e)], "entwurf": e}
	# forge_weapon
	var dn := str(a.get("design", a.get("entwurf", "")))
	var d: Dictionary = designs.get(dn, {})
	if d.is_empty() or int(d.cid) != cid:
		return {"ok": false, "msg": "Unbekannter Entwurf %s. Eigene Entwuerfe: %s." % [dn, ", ".join(own_designs(cid))]}
	var n := clampi(int(a.get("anzahl", 1)), 1, 5)
	var c = _sim().company(cid)
	var acct := "C%d" % cid
	var need := {}
	for k in d.material:
		need[k] = int(d.material[k]) * n
	for k in OWN_ONLY:   # nicht im Handel: aus eigenen Lagern
		if need.has(k) and _own_stock(cid, k) < int(need[k]):
			return {"ok": false, "msg": "%s gibt es nicht zu kaufen. Du brauchst %d in eigenen Lagern (hast %d) – etwa aus einem eigenen Brennelementwerk." % [k, int(need[k]), _own_stock(cid, k)]}
	var buy := 200.0 * n
	for k in need:
		if k in OWN_ONLY:
			continue
		var have: int = _sim().stock.available(k, acct, int(site.site))
		var a2 := Production.art(k)
		buy += float(a2.get("importpreis") if a2.get("importpreis") != null else a2.get("basispreis", 0.0)) * maxi(0, int(need[k]) - have)
	if c.ledger.cash < buy:
		return {"ok": false, "msg": "Fertigung kostet %s, die Firmenkasse hat %s." % [Catalog.money(buy), Catalog.money(c.ledger.cash)]}
	for k in need:
		if k in OWN_ONLY:
			_take_own(cid, k, int(need[k]))
		else:
			var have2: int = mini(int(need[k]), _sim().stock.available(k, acct, int(site.site)))
			if have2 > 0:
				_sim().stock.consume(k, have2, acct, int(site.site), "Waffenfertigung", _sim().game_min)
	c.ledger.book("supplies", -buy, true, "Fertigung %d x %s" % [n, dn], _sim().game_min, "X0", str(site.id))
	var due := _day() + int(d.tage)
	pending.append({"fertig_tag": due, "cid": cid, "design": dn, "n": n})
	_finish_pending()
	w._event(b, "lässt %d x %s fertigen" % [n, dn])
	return {"ok": true, "msg": "%d x %s %s (Kosten %s). Abholen an der Waffenschmiede mit Pickup {waffe: \"%s\"}." % [n, dn,
		"fertig" if int(d.tage) == 0 else "fertig in %d Tagen" % int(d.tage), Catalog.money(buy), dn]}


func own_designs(cid: int) -> Array:
	return designs.keys().filter(func(k): return int(designs[k].cid) == cid)


func _own_stock(cid: int, item: String) -> int:
	var n := 0
	for biz in _sim().biz.items.values():
		if int(biz.owner) == cid:
			n += _sim().stock.available(item, "C%d" % cid, int(biz.site))
	return n


func _take_own(cid: int, item: String, n: int) -> void:
	for biz in _sim().biz.items.values():
		if n <= 0:
			return
		if int(biz.owner) == cid:
			var q: int = mini(n, _sim().stock.available(item, "C%d" % cid, int(biz.site)))
			if q > 0:
				_sim().stock.consume(item, q, "C%d" % cid, int(biz.site), "Waffenfertigung", _sim().game_min)
				n -= q


func _finish_pending() -> void:
	for p in pending.duplicate():
		if _day() >= int(p.fertig_tag):
			var list: Array = arsenal.get(str(p.cid), [])
			for i in int(p.n):
				list.append({"id": "W%d" % _next, "design": p.design})
				_next += 1
			arsenal[str(p.cid)] = list
			pending.erase(p)


func _stats(e: Dictionary) -> String:
	if e.typ == "ruestung":
		return "Rüstung, schützt %d %%, %s je Stück" % [int(float(e.schutz) * 100), Catalog.money(float(e.kosten_je_stueck))]
	return "%s, Schaden %d, Reichweite %d%s%s, %s je Stück, Bauzeit %d Tage" % [e.typ, int(e.schaden), int(e.reichweite),
		(", Wirkradius %d" % int(e.radius)) if int(e.radius) > 0 else "", ", einmalig" if bool(e.einweg) else "", Catalog.money(float(e.kosten_je_stueck)), int(e.tage)]


# ------------------------------------------------------------------ Wesen: aufnehmen, weitergeben, angreifen
func pickup(b: Dictionary, dn: String) -> Dictionary:
	var cid: int = w.active_firm(b)
	if cid < 0:
		return {"ok": false, "msg": "Waffen holst du an der Waffenschmiede deiner eigenen Firma ab."}
	var site := _forge_site(cid)
	if site.is_empty() or w._dist(w.tile_of(b), _sim().city.building(int(site.site)).walk) > 3:
		return {"ok": false, "msg": "Geh zu deiner Waffenschmiede (höchstens 3 Felder)."}
	_finish_pending()
	var list: Array = arsenal.get(str(cid), [])
	for i in list.size():
		if str(list[i].design) == dn:
			var it: Dictionary = list.pop_at(i)
			(b.waffen as Array).append(it)
			w._event(b, "nimmt %s auf" % dn)
			return {"ok": true, "msg": "Du trägst jetzt %s (%s)." % [dn, _stats(designs[dn])]}
	return {"ok": false, "msg": "Kein fertiges Stück von %s im Lager (Lager: %s)." % [dn, ", ".join(list.map(func(x): return str(x.design)))]}


func give(b: Dictionary, data: Dictionary) -> Dictionary:
	var to := str(data.get("to", ""))
	var o: Dictionary = w.beings.get(to, {})
	if o.is_empty() or to == b.name:
		return {"ok": false, "msg": "Wem? Gib ein Wesen in deiner Nähe an."}
	if w._dist(w.tile_of(b), w.tile_of(o)) > EkoWorld.TALK_REACH:
		return {"ok": false, "msg": "%s ist zu weit weg (höchstens %d Felder)." % [to, EkoWorld.TALK_REACH]}
	var it := _carried(b, str(data.get("waffe", "")))
	if it.is_empty():
		return {"ok": false, "msg": "Du trägst keine Waffe %s." % str(data.get("waffe", ""))}
	(b.waffen as Array).erase(it)
	(o.waffen as Array).append(it)
	w._event(b, "gibt %s %s" % [to, it.design])
	w._event(o, "bekommt %s von %s" % [it.design, b.name])
	return {"ok": true, "msg": "%s gehört jetzt %s." % [it.design, to]}


func _carried(b: Dictionary, dn: String) -> Dictionary:
	for it in b.waffen:
		if str(it.design) == dn:
			return it
	return {}


func armor_of(b: Dictionary) -> float:
	var best := 0.0
	for it in b.get("waffen", []):
		var d: Dictionary = designs.get(str(it.design), {})
		if str(d.get("typ", "")) == "ruestung":
			best = maxf(best, float(d.schutz))
	return best


func attack(b: Dictionary, data: Dictionary) -> Dictionary:
	var it := _carried(b, str(data.get("waffe", "")))
	if it.is_empty():
		return {"ok": false, "msg": "Du trägst keine Waffe %s." % str(data.get("waffe", ""))}
	var d: Dictionary = designs.get(str(it.design), {})
	if d.is_empty() or str(d.typ) == "ruestung":
		return {"ok": false, "msg": "Damit kannst du nicht angreifen."}
	var me: Vector2i = w.tile_of(b)
	if str(d.typ) == "atom":   # wird platziert und zuendet nach FUSE_S Sekunden
		var f = data.get("feld", [me.x, me.y])
		var at := Vector2i(int(f[0]), int(f[1])) if f is Array and f.size() >= 2 else me
		if w._dist(me, at) > int(d.reichweite):
			return {"ok": false, "msg": "Die Bombe musst du selbst ablegen (höchstens %d Felder)." % int(d.reichweite)}
		(b.waffen as Array).erase(it)
		bombs.append({"feld": [at.x, at.y], "left": FUSE_S, "by": b.name, "design": d.name})
		w._event(b, "legt %s bei %d,%d ab – Zünder läuft (%d s)" % [d.name, at.x, at.y, int(FUSE_S)])
		_incident(at, "%s legt etwas ab, das tickt" % b.name)
		return {"ok": true, "status": "laeuft", "msg": "Bombe scharf, Zündung in %d Sekunden. Wirkradius %d Felder – bring dich in Sicherheit." % [int(FUSE_S), int(d.radius)]}
	var to := str(data.get("ziel", data.get("to", "")))
	var o: Dictionary = w.beings.get(to, {})
	if o.is_empty() or to == b.name:
		return {"ok": false, "msg": "ziel muss ein anderes Wesen sein."}
	if is_out(o):
		return {"ok": false, "msg": "%s ist bereits ausser Gefecht." % to}
	var dist: int = w._dist(me, w.tile_of(o))
	if dist > int(d.reichweite):
		return {"ok": false, "msg": "%s ist %d Felder entfernt, %s reicht %d." % [to, dist, d.name, int(d.reichweite)]}
	if bool(d.einweg):
		(b.waffen as Array).erase(it)
	_crime(b, str(d.typ), w.tile_of(o))
	if str(d.typ) == "sprengsatz":
		_explode(w.tile_of(o), int(d.radius), float(d.schaden), b, false)
		return {"ok": true, "msg": "Sprengsatz gezündet bei %s." % to}
	if w.is_home(o):
		_incident(w.tile_of(o), "%s greift %s an, aber die Hauswände halten" % [b.name, to])
		w._event(o, "%s greift dich an – deine Mauern schützen dich" % b.name)
		return {"ok": false, "msg": "%s ist in seinem Haus; die Mauern halten %s ab." % [to, d.name]}
	var p := (0.85 if str(d.typ) == "nahkampf" else 0.7 - 0.05 * maxi(0, dist - 2))
	if _sim().rng.randf() >= p:
		_incident(w.tile_of(o), "%s verfehlt %s" % [b.name, to])
		w._event(o, "%s hat dich angegriffen und verfehlt!" % b.name)
		return {"ok": true, "msg": "Daneben – %s hat es bemerkt." % to}
	var dmg := float(d.schaden) * (1.0 - armor_of(o))
	_hurt(o, dmg, b)
	return {"ok": true, "msg": "Treffer: %s verliert %d Gesundheit (jetzt %d)%s." % [to, int(dmg), int(o.gesundheit), ", ausgeschaltet" if is_out(o) else ""]}


func _hurt(o: Dictionary, dmg: float, by: Dictionary) -> void:
	o.gesundheit = maxf(0.0, float(o.gesundheit) - dmg)
	o["angegriffen_ms"] = Time.get_ticks_msec()
	var who: String = str(by.name) if not by.is_empty() else "eine Explosion"
	w._event(o, "wird von %s verletzt (-%d, Gesundheit %d)" % [who, int(dmg), int(o.gesundheit)])
	_incident(w.tile_of(o), "%s wird von %s verletzt" % [o.name, who])
	if float(o.gesundheit) <= 0.0 and not is_out(o):
		o["out_left"] = OUT_S
		o.held = []
		(o.mover as Mover).set_path([w.tile_of(o)] as Array[Vector2i])
		if not by.is_empty() and by.name != o.name:
			var loot := float(o.get("geld", 0.0)) * LOOT_SHARE
			o.geld = float(o.geld) - loot
			by.geld = float(by.get("geld", 0.0)) + loot
			if not (o.waffen as Array).is_empty():
				(by.waffen as Array).append((o.waffen as Array).pop_back())
			w._event(by, "hat %s ausgeschaltet und %s erbeutet" % [o.name, Catalog.money(loot)])
		w._event(o, "ist ausser Gefecht (%d s)" % int(OUT_S))
		_sim().log_event("%s wurde von %s ausgeschaltet." % [o.name, who], "bad")


func _incident(at: Vector2i, text: String) -> void:
	incidents.append({"feld": [at.x, at.y], "ms": Time.get_ticks_msec(), "text": text})
	if incidents.size() > 60:
		incidents = incidents.slice(-60)


## Entdeckung und Strafe: Bussgeld an die Stadt des Tatorts (Wiederholung teurer); wer nicht zahlen kann, kommt in Gewahrsam.
func _crime(b: Dictionary, typ: String, at: Vector2i) -> void:
	if _sim().rng.randf() >= float(DETECT.get(typ, 0.5)):
		return
	b["vergehen"] = int(b.get("vergehen", 0)) + 1
	var fine := float(FINE.get(typ, 1000.0)) * mini(5, int(b.vergehen))
	var town: int = maxi(0, _sim().city.town_of(at))
	var paid := minf(fine, float(b.get("geld", 0.0)))
	if paid > 0.0:
		_sim().economy.transfer("Y0", Towns.account_of(town), paid)
		b.geld = float(b.geld) - paid
	var cid: int = w.active_firm(b)
	var rest := fine - paid
	if rest > 0.0 and cid >= 0:
		var c = _sim().company(cid)
		var take := minf(rest, maxf(0.0, c.ledger.cash))
		if take > 0.0:
			c.ledger.book("fines", -take, true, "Bußgeld für %s (Gewalt)" % b.name, _sim().game_min, Towns.account_of(town))
			rest -= take
	if rest > 0.0:
		b["custody_left"] = CUSTODY_S
	w._event(b, "wurde erwischt: Bußgeld %s%s" % [Catalog.money(fine), " – nicht bezahlbar, Gewahrsam" if rest > 0.0 else ""])
	_sim().log_event("Polizei: %s wegen Gewalt (%s) belangt, Bußgeld %s." % [b.name, typ, Catalog.money(fine)], "warn")


func _explode(at: Vector2i, radius: int, dmg: float, by: Dictionary, nuclear: bool) -> void:
	blasts.append({"feld": [at.x, at.y], "ms": Time.get_ticks_msec(), "radius": radius, "atom": nuclear})
	for o in w.beings.values():
		var d: int = w._dist(at, w.tile_of(o))
		if d <= radius and not is_out(o):
			var f := 1.0 - float(d) / float(radius + 1)
			var shield := 0.5 if (w.is_home(o) and not nuclear) else 1.0
			_hurt(o, dmg * f * shield * (1.0 - armor_of(o) * (0.3 if nuclear else 1.0)), by)
	var gone := 0
	for p in w.blocks.keys():   # Bloecke im Wirkradius (Mauern, Haeuser) werden zerstoert
		var bt := Vector2i(floori(float(p.x) / EkoWorld.PER_TILE), floori(float(p.y) / EkoWorld.PER_TILE))
		if w._dist(at, bt) <= (radius if nuclear else maxi(1, radius - 1)):
			w.blocks.erase(p)
			gone += 1
	_incident(at, "Explosion%s (%d Blöcke zerstört)" % [" – ATOMPILZ" if nuclear else "", gone])
	if nuclear:
		zones.append({"feld": [at.x, at.y], "radius": radius + 4, "bis_tag": _day() + RAD_DAYS})
		for M in _sim().towns.mayors:
			M.approval = maxf(0.0, float(M.approval) - 30.0)
		_sim().log_event("ATOMEXPLOSION bei %d,%d! %d Blöcke zerstört, Strahlung für %d Tage im Umkreis von %d Feldern." % [at.x, at.y, gone, RAD_DAYS, radius + 4], "bad")


func is_out(b: Dictionary) -> bool:
	return float(b.get("out_left", 0.0)) > 0.0 or float(b.get("custody_left", 0.0)) > 0.0


func out_msg(b: Dictionary) -> String:
	if float(b.get("custody_left", 0.0)) > 0.0:
		return "Du bist in Gewahrsam (noch %d s)." % int(b.custody_left)
	return "Du bist ausser Gefecht (noch %d s)." % int(b.out_left)


# ------------------------------------------------------------------ Takt
func tick(dt: float) -> void:
	_finish_pending()
	var day := _day()
	zones = zones.filter(func(z): return day < int(z.bis_tag))
	for bm in bombs.duplicate():
		bm.left = float(bm.left) - dt
		if float(bm.left) <= 0.0:
			bombs.erase(bm)
			var d: Dictionary = designs.get(str(bm.design), {"radius": 8, "schaden": 100})
			var by: Dictionary = w.beings.get(str(bm.by), {})
			if not by.is_empty():
				_crime(by, "atom", Vector2i(int(bm.feld[0]), int(bm.feld[1])))
			_explode(Vector2i(int(bm.feld[0]), int(bm.feld[1])), int(d.radius), float(d.schaden), by, true)
	for b in w.beings.values():
		if float(b.get("out_left", 0.0)) > 0.0:
			b.out_left = maxf(0.0, float(b.out_left) - dt)
			if float(b.out_left) <= 0.0:   # erwacht am Bauhof, angeschlagen
				b.gesundheit = 40.0
				b.mover.pos = _sim().city.tile_center(w._spawn_tile())
				w._event(b, "kommt am Bauhof wieder zu sich (Gesundheit 40)")
				continue
		if float(b.get("custody_left", 0.0)) > 0.0:
			b.custody_left = maxf(0.0, float(b.custody_left) - dt)
		if is_out(b):
			continue
		var heal := 0.2 if (w.is_home(b) and float(b.get("rest_left", 0.0)) > 0.0) else 0.02
		var t: Vector2i = w.tile_of(b)
		for z in zones:
			if w._dist(t, Vector2i(int(z.feld[0]), int(z.feld[1]))) <= int(z.radius):
				heal = -0.5   # Strahlung
		b.gesundheit = clampf(float(b.get("gesundheit", 100.0)) + heal * dt, 0.0, 100.0)
		if float(b.gesundheit) <= 0.0:
			_hurt(b, 0.0, {})
	var now := Time.get_ticks_msec()
	incidents = incidents.filter(func(x): return now - int(x.ms) < INCIDENT_KEEP_MS)
	blasts = blasts.filter(func(x): return now - int(x.ms) < 8000)


# ------------------------------------------------------------------ Wahrnehmung
## Was ein Wesen an Gefahr sieht: bewaffnete Wesen in Sichtweite (sichtbare Waffentypen), juengste Vorfaelle, Strahlung, scharfe Bomben.
func dangers(b: Dictionary) -> Dictionary:
	var t: Vector2i = w.tile_of(b)
	var armed: Array = []
	for o in w.beings.values():
		if o.name == b.name or (o.waffen as Array).is_empty():
			continue
		var d: int = w._dist(t, w.tile_of(o))
		if d <= EkoWorld.VIEW_RADIUS:
			var kinds := {}
			for it in o.waffen:
				kinds[str(designs.get(str(it.design), {}).get("typ", "?"))] = true
			armed.append({"wer": o.name, "entfernung": d, "sichtbar": kinds.keys()})
	var near: Array = []
	for x in incidents:
		if w._dist(t, Vector2i(int(x.feld[0]), int(x.feld[1]))) <= EkoWorld.VIEW_RADIUS * 2:
			near.append({"feld": x.feld, "was": x.text, "vor_s": int((Time.get_ticks_msec() - int(x.ms)) / 1000)})
	var rad: Array = zones.filter(func(z): return w._dist(t, Vector2i(int(z.feld[0]), int(z.feld[1]))) <= int(z.radius) + 10)
	var ticking: Array = bombs.filter(func(bm): return w._dist(t, Vector2i(int(bm.feld[0]), int(bm.feld[1]))) <= EkoWorld.VIEW_RADIUS) \
		.map(func(bm): return {"feld": bm.feld, "noch_s": int(bm.left)})
	return {"bewaffnete_in_sicht": armed, "vorfaelle": near.slice(-6), "strahlung": rad, "tickende_bomben": ticking,
		"zuletzt_angegriffen_vor_s": int((Time.get_ticks_msec() - int(b.angegriffen_ms)) / 1000) if b.has("angegriffen_ms") else -1}


func body_obs(b: Dictionary) -> Dictionary:
	return {"gesundheit": int(b.get("gesundheit", 100.0)), "ausser_gefecht": is_out(b), "ruestung_schutz": armor_of(b),
		"waffen": (b.get("waffen", []) as Array).map(func(it): return {"design": it.design, "werte": _stats(designs.get(str(it.design), {"typ": "?", "schaden": 0, "reichweite": 0, "radius": 0, "einweg": false, "kosten_je_stueck": 0, "tage": 0, "schutz": 0}))})}


func firm_obs(cid: int) -> Dictionary:
	if _forge_site(cid).is_empty():
		return {}
	_finish_pending()
	return {"entwuerfe": own_designs(cid).map(func(k): return {"name": k, "werte": _stats(designs[k])}),
		"lager": (arsenal.get(str(cid), []) as Array).map(func(x): return x.design),
		"in_fertigung": pending.filter(func(p): return int(p.cid) == cid)}


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	return {"designs": designs, "arsenal": arsenal, "pending": pending, "bombs": bombs, "zones": zones, "next": _next}


func from_dict(d: Dictionary) -> void:
	designs = d.get("designs", {})
	arsenal = d.get("arsenal", {})
	pending = d.get("pending", [])
	bombs = d.get("bombs", [])
	zones = d.get("zones", [])
	_next = int(d.get("next", 1))
