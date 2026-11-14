class_name VehicleWorks
extends RefCounted
## Auftrag 24: Stadtwerkstaetten und Fahrzeugwerk.
##  - Wartung nach Kilometerstand: alle SERVICE_KM faehrt ein freies Firmenfahrzeug mit Fahrer selbst in die Stadtwerkstatt
##    (Kfz-Werkstatt KW-01 je Stadt, Nutzfahrzeug-Werkstatt KW-02 fuer schwere Lkw). Ueberfaellige Fahrzeuge verschleissen schneller.
##    Die Firma zahlt Teile und Arbeitsstunden an die Stadtkasse; die Stadt kauft die Teile von ausserhalb (X0).
##  - Fahrzeugwerk FZ-01 der einwohnerstaerksten Stadt: der Buergermeister (Sprachmodell oder Regeln) entwirft Modelle
##    (Klasse, Name, Farbe, Form, Nutzlast, Motor, Qualitaet, Preis). Die Engine rechnet daraus Werte und Kosten; Konstrukteure
##    entwickeln, Bandmonteure bauen am Montageband (Karosserie, Lack, Montage, Endkontrolle), Autoverkaeufer bieten die Nutzfahrzeuge
##    auf dem Automarkt an (Angebote wie bei den Autohaeusern) und verkaufen Pkw an Buerger mit Erspartem.
## Personal und Loehne laufen ueber Municipal (fixer Stellenplan); Material zahlt die Stadtkasse an X0, Erloese gehen an sie zurueck.

const TICK_MIN := 2                  # Spielminuten (ein Spieltag = GameCalendar.day_game_min = 120 Spielminuten = 24 Stunden)
const SERVICE_KM := 500.0
const SERVICE := {"pkw": {"min": 12.0, "teile": 140.0, "stunden": 1.5}, "lkw": {"min": 20.0, "teile": 420.0, "stunden": 3.0}}   # min = Spielminuten
const LABOUR_RATE := 68.0            # EUR je Werkstattstunde
const SERVICE_BOOST := 25.0          # Zustandspunkte durch die Wartung
const LINE_SLOTS := 4                # Fahrzeuge gleichzeitig am Band
const STOCK_MAX := 8                 # unverkaufte Fahrzeuge auf dem Werkshof: darueber steht das Band
const STOCK_PER_MODEL := 3           # je Modell hoechstens so viele auf Hof und Band (ein Ladenhueter blockiert die anderen nicht)
const MAX_SERIES := 4                # gleichzeitig gebaute Modelle; das aelteste laeuft aus
const DEV_DAYS := 3                  # Entwicklungszeit mit Konstrukteur (ohne: doppelt)
const DEV_COST := 15000.0
const DESIGN_GAP_DAYS := 5           # Regelvorschlag hoechstens alle 5 Tage
const LABOUR_COST_H := 24.0          # Lohn und Gemeinkosten je Montagestunde (Selbstkosten)
const SHIFT := [6.0, 22.0]           # Zwei Schichten
const PKW_BUY_RATE := 0.03           # Anteil der kaufkraeftigen Buerger ohne Auto, die je Tag zuschlagen
const SUPPLIER_LIMIT := 150000.0     # Zulieferer liefern auf Rechnung bis zu dieser Summe (Zahlungsziel SUPPLIER_DAYS oder beim Verkauf)
const SUPPLIER_DAYS := 20
const PKW_DOWN := 0.2                # Werksfinanzierung: Anzahlung, Rest in Tagesraten ueber PKW_TERM_DAYS
const PKW_TERM_DAYS := 720              # Loehne sind im Spiel klein (60 h je Monat): Kleinwagen ~6 000 EUR, lange Laufzeit
const PKW_RATE_SHARE := 0.4          # Rate hoechstens dieser Anteil vom Nettotageslohn
const STAGES := [["karosserie", 0.25, "Karosseriebau"], ["lack", 0.45, "Lackiererei"], ["montage", 0.85, "Montage"], ["endkontrolle", 1.0, "Endkontrolle"]]

const KLASSEN := {
	"pkw": {"label": "Pkw", "base": "", "cap": [4, 7], "material": 3500.0, "stunden": 30.0, "kunden": "buerger"},
	"transporter": {"label": "Transporter", "base": "transporter", "cap": [8, 24], "stunden": 45.0, "kunden": "firmen"},
	"lkw": {"label": "Lkw", "base": "truck", "cap": [28, 56], "stunden": 90.0, "kunden": "firmen"},
	"sattelzug": {"label": "Sattelzug", "base": "semi", "cap": [60, 100], "stunden": 140.0, "kunden": "firmen"},
}
const LEISTUNG := {"sparsam": {"tempo": 0.92, "verbrauch": 0.85, "kosten": 1.05}, "ausgewogen": {"tempo": 1.0, "verbrauch": 1.0, "kosten": 1.0},
	"kraftvoll": {"tempo": 1.1, "verbrauch": 1.2, "kosten": 1.12}}
const QUALITAET := {"einfach": {"wear": 1.25, "kosten": 0.85, "stunden": 0.85}, "solide": {"wear": 1.0, "kosten": 1.0, "stunden": 1.0},
	"premium": {"wear": 0.8, "kosten": 1.3, "stunden": 1.25}}
const FORMEN := ["kantig", "rund", "keil"]
const FARBEN := {"rot": "c8322b", "blau": "2f5fb3", "gruen": "3f8a4a", "gelb": "e8b830", "weiss": "eeeeea", "schwarz": "2a2c30",
	"silber": "b8bcc2", "orange": "e07a2a", "tuerkis": "2aa8a8", "violett": "7a4ab0", "braun": "7a5232", "grau": "70757c", "creme": "e8dcb8"}
const NAMES := {"pkw": ["Spatz", "Komet", "Lerche", "Fuchs", "Libelle"], "transporter": ["Kurier", "Pony", "Biber", "Lastesel"],
	"lkw": ["Atlas", "Hüne", "Bär", "Brummi"], "sattelzug": ["Titan", "Mammut", "Koloss", "Fernweh"]}

var sim
var designs := {}        # "D<n>" -> Entwurf (siehe design())
var line: Array = []     # Montageband: {design, serial, need_h, done_h}
var hof: Array = []      # fertige, unverkaufte Fahrzeuge: {design, serial, day, offer}
var stats := {"gebaut": 0, "verkauft_firmen": 0, "verkauft_buerger": 0, "umsatz": 0.0, "material": 0.0, "entwicklung": 0.0,
	"wartungen": 0, "wartung_erloes": 0.0, "raten": 0.0, "ausfall": 0.0}
var sales: Array = []    # letzte Verkaeufe {day, design, an, preis}
var loans: Array = []    # Werksfinanzierung der Pkw: {person, rest, rate, design}
var tried := {}          # Standortsuche: "Stadt|Code" -> Tag
var serial := 1
var dev_open := 0.0      # gestundete Entwicklungskosten (Konstruktionsbuero, aus Verkaeufen bezahlt)
var _next := 1
var last_design_day := -99


func setup(simulation) -> void:
	sim = simulation
	Catalog.custom_models.clear()   # gehoert zur laufenden Partie (Laden registriert die Entwuerfe neu)
	if sim.municipal.enabled():
		sim.day_changed.connect(on_day)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Standorte
func facility(code: String, k: int = -1) -> Dictionary:
	for f in sim.municipal.facilities.values():
		if str(f.code) == code and f.status == "in_betrieb" and (k < 0 or int(f.town) == k):
			return f
	return {}


func plant() -> Dictionary:
	return facility("FZ-01")


func plant_town() -> int:
	var f := plant()
	return int(f.town) if not f.is_empty() else -1


## Kfz-Werkstatt je Stadt, eine Nutzfahrzeug-Werkstatt und das Fahrzeugwerk in der einwohnerstaerksten Stadt mit Bauplatz.
## Fehlt ein Bauplatz, wird nach 10 Tagen erneut gesucht.
func ensure_sites() -> void:
	var order: Array = sim.towns.list.map(func(t): return int(t.id))
	order.sort_custom(func(a, b): return sim.citizens.population_of(a) > sim.citizens.population_of(b))
	var day := _today()
	for k in order:
		_try(k, "KW-01", day)
	for code in ["KW-02", "FZ-01"]:
		if not facility(code).is_empty():
			continue
		for k in order:
			if _try(k, code, day):
				break


func _try(k: int, code: String, day: int) -> bool:
	if not facility(code, k).is_empty():
		return true
	var key := "%d|%s" % [k, code]
	if tried.has(key) and day - int(tried[key]) < 10:
		return false
	tried[key] = day
	var f: Dictionary = sim.municipal._place(k, code, "rand")   # Gewerbe am Stadtrand: die Plaetze nahe dem Rathaus bleiben den Diensten
	return not f.is_empty()


func on_day(day: int) -> void:
	ensure_sites()
	for d in designs.values():
		if d.status == "entwicklung" and day >= int(d.ready_day):
			d.status = "serie"
			_retire_old()
			_news("%s: Serienstart %s (%s)" % [plant().get("name", "Fahrzeugwerk"), d.name, KLASSEN[d.klasse].label], "Konstruktion abgeschlossen")
	_sell_pkw(day)
	_collect_rates()
	for e in hof:
		if day - int(e.day) >= SUPPLIER_DAYS:
			_settle(e)


# ------------------------------------------------------------------ Wartung
static func kind_of(model: String) -> String:
	return "lkw" if bool(Catalog.model(model).get("heavy", false)) else "pkw"


## Verschleiss-Faktor: ab SERVICE_KM steigt er linear bis x2 bei doppelter Laufleistung.
static func wear_factor(v) -> float:
	return 1.0 + clampf((float(v.service_km) - SERVICE_KM) / SERVICE_KM, 0.0, 1.0)


func shop_for(v) -> Dictionary:
	var want := "KW-02" if kind_of(v.model) == "lkw" else "KW-01"
	var best := {}
	var best_d := INF
	for code in [want, "KW-01" if want == "KW-02" else "KW-02"]:
		for f in sim.municipal.facilities.values():
			if str(f.code) != code or f.status != "in_betrieb":
				continue
			var b: Dictionary = sim.city.building(int(f.building))
			if b.is_empty():
				continue
			var dd: float = Vector2(v.tile()).distance_to(Vector2(b.road))
			if dd < best_d:
				best_d = dd
				best = f
		if not best.is_empty():
			return best
	return best


## Faellige Fahrzeuge (frei, mit Fahrer, ohne Ladung und Stopps) fahren zur Wartung.
func _send_due() -> void:
	for v in sim.vehicles.values():
		if v.service_km < SERVICE_KM or v.service_fid != "" or v.state != "idle" or not v.stops.is_empty() or not v.load.is_empty():
			continue
		if v.contract_id != "" or not v.queue.is_empty() or v.operator >= 0 or sim.driver_of(v) == null:
			continue
		send_to_service(v)


func send_to_service(v) -> Dictionary:
	var f := shop_for(v)
	if f.is_empty():
		return {"ok": false, "msg": "Keine Stadtwerkstatt in Betrieb."}
	var b: Dictionary = sim.city.building(int(f.building))
	v.service_fid = str(f.id)
	if not sim.route(v, b.road, "to_workshop"):
		v.service_fid = ""
		return {"ok": false, "msg": "Kein Weg zur %s." % f.name}
	sim.notify(v.owner, "%s fährt zur Wartung in die %s (%d km seit der letzten Wartung)." % [v.display_name(), f.name, int(v.service_km)])
	return {"ok": true, "msg": "#%d fährt zur Wartung (%s)." % [v.id, f.name]}


func in_service(fid: String) -> Array:
	return sim.vehicles.values().filter(func(x): return x.service_fid == fid and x.state == "repairing")


## Ankunft: auf die Hebebuehne; Dauer nach Fahrzeugart, Besetzung und Warteschlange (capacity = Hebebuehnen).
func begin_service(v) -> void:
	var f: Dictionary = sim.municipal.facilities.get(v.service_fid, {})
	var sv: Dictionary = SERVICE[kind_of(v.model)]
	var ahead := in_service(v.service_fid).size()
	var mech: int = sim.municipal.staff_count(v.service_fid, "mechaniker") if not f.is_empty() else 0
	v.state = "repairing"
	v.timer = float(sv.min) * (3.0 if mech <= 0 else 1.0) * (1.0 + float(ahead / maxi(1, int(f.get("capacity", 1)))))


func finish_service(v) -> void:
	var f: Dictionary = sim.municipal.facilities.get(v.service_fid, {})
	var sv: Dictionary = SERVICE[kind_of(v.model)]
	var fee := float(sv.teile) + float(sv.stunden) * LABOUR_RATE
	var c = sim.companies[v.owner]
	if not f.is_empty():
		var acct := Towns.account_of(int(f.town))
		c.ledger.book("repairs", -fee, true, "Wartung %s (%d km)" % [v.display_name(), int(v.service_km)], sim.game_min, acct)
		sim.economy.transfer(acct, "X0", float(sv.teile))   # Ersatzteile, Oel und Filter von ausserhalb
		f["wartungen"] = int(f.get("wartungen", 0)) + 1
		stats.wartungen = int(stats.wartungen) + 1
		stats.wartung_erloes = float(stats.wartung_erloes) + fee - float(sv.teile)
	v.condition = minf(100.0, v.condition + SERVICE_BOOST)
	v.service_km = 0.0
	v.service_fid = ""
	v.state = "idle"
	v.idle_since = sim.game_min
	sim.notify(v.owner, "%s gewartet (%s)." % [v.display_name(), Catalog.money(fee)])


# ------------------------------------------------------------------ Entwuerfe
## Werte und Kosten eines Entwurfs (reine Rechnung, auch fuer die Vorschau in der Beobachtung).
static func compute(a: Dictionary) -> Dictionary:
	var klasse := str(a.get("klasse", "")).to_lower()
	if not KLASSEN.has(klasse):
		return {"error": "klasse: %s" % " | ".join(KLASSEN.keys())}
	var kl: Dictionary = KLASSEN[klasse]
	var lei := str(a.get("leistung", "ausgewogen")).to_lower()
	var qua := str(a.get("qualitaet", "solide")).to_lower()
	if not LEISTUNG.has(lei):
		lei = "ausgewogen"
	if not QUALITAET.has(qua):
		qua = "solide"
	var L: Dictionary = LEISTUNG[lei]
	var Q: Dictionary = QUALITAET[qua]
	var lo := int(kl.cap[0])
	var hi := int(kl.cap[1])
	var cap := clampi(int(a.get("nutzlast", (lo + hi) / 2)) if a.get("nutzlast") != null else (lo + hi) / 2, lo, hi)
	var refr := bool(a.get("kuehlung", false)) and klasse in ["transporter", "lkw"]
	var out := {"klasse": klasse, "leistung": lei, "qualitaet": qua, "capacity": cap, "refrigerated": refr, "base": str(kl.base)}
	var material: float
	if klasse == "pkw":
		material = float(kl.material) * float(L.kosten) * float(Q.kosten) * (1.0 + 0.06 * float(cap - lo))
		out.merge({"speed": 0.0, "cost_per_tile": 0.0, "wear": 0.0, "heavy": false})
	else:
		var base: Dictionary = Catalog.VEHICLE_MODELS[kl.base]
		var ratio := float(cap) / float(base.capacity)
		out.speed = snappedf(float(base.speed) * float(L.tempo) * clampf(1.0 - 0.15 * (ratio - 1.0), 0.8, 1.1), 0.01)
		out.cost_per_tile = snappedf(float(base.cost_per_tile) * sqrt(ratio) * float(L.verbrauch), 0.01)
		out.wear = snappedf(float(base.wear) * float(Q.wear), 0.0001)
		out.heavy = bool(base.heavy)
		material = float(base.price) * 0.55 * pow(ratio, 0.7) * float(L.kosten) * float(Q.kosten) * (1.25 if refr else 1.0)
	var hours := float(kl.stunden) * float(Q.stunden)
	var cost := material + hours * LABOUR_COST_H
	var price := cost * 1.35
	if a.get("preis") != null and float(a.preis) > 0.0:
		price = float(a.preis)
	out.material = roundf(material)
	out.hours = snappedf(hours, 0.1)
	out.selbstkosten = roundf(cost)
	out.price = roundf(clampf(price, cost, cost * 2.2) / 50.0) * 50.0
	return out


static func color_of(name: String, fallback: String) -> String:
	var n := name.strip_edges().to_lower().replace("ü", "ue").replace("#", "")
	if FARBEN.has(n):
		return str(FARBEN[n])
	if n.length() == 6 and n.is_valid_hex_number():
		return n
	return fallback


## Buergermeister-Aktion fahrzeug_entwerfen: nur die Traegerstadt des Werks; kostet DEV_COST - bar aus dem Haushalt, sonst stundet das
## Konstruktionsbuero (im Kreditrahmen der Zulieferer) und wird aus den naechsten Verkaeufen bezahlt.
func design(k: int, a: Dictionary, by: String) -> Dictionary:
	var f := plant()
	if f.is_empty():
		return {"ok": false, "msg": "Kein Fahrzeugwerk in Betrieb."}
	if int(f.town) != k:
		return {"ok": false, "msg": "Das Fahrzeugwerk gehört %s." % sim.towns.name_of(int(f.town))}
	var c := compute(a)
	if c.has("error"):
		return {"ok": false, "msg": str(c.error)}
	var M: Mayor = sim.towns.mayor(k)
	var dev_cash := M.available_budget() >= DEV_COST
	if not dev_cash and supplier_open() + DEV_COST > SUPPLIER_LIMIT:
		return {"ok": false, "msg": "Entwicklung kostet %s: Haushalt verfügbar %s, Kreditrahmen von Zulieferern und Konstruktionsbüro ausgeschöpft (%s offen) – erst verkaufen." % [
			Catalog.money(DEV_COST), Catalog.money(M.available_budget()), Catalog.money(supplier_open())]}
	var name := str(a.get("name", "")).strip_edges().left(28)
	if name == "":
		name = "%s %s" % [sim.towns.name_of(k), KLASSEN[c.klasse].label]
	if designs.values().any(func(d): return str(d.name) == name):
		return {"ok": false, "msg": "Ein Modell %s gibt es schon." % name}
	if dev_cash:
		_pay_dev(k, DEV_COST)   # Prototyp, Pruefstand, Zulassung
	else:
		dev_open += DEV_COST
	var form := str(a.get("form", "kantig")).to_lower()
	var day := _today()
	var eng: int = sim.municipal.staff_count(str(f.id), "ingenieur")
	var d := {"id": "D%d" % _next, "name": name, "by": by, "town": k, "day": day, "status": "entwicklung",
		"ready_day": day + DEV_DAYS * (1 if eng > 0 else 2), "farbe": color_of(str(a.get("farbe", "")), "c8322b"),
		"akzent": color_of(str(a.get("akzent", "")), "eeeeea"), "form": form if form in FORMEN else "kantig",
		"reason": str(a.get("reason", "")).left(160), "gebaut": 0, "verkauft": 0}
	d.merge(c)
	_next += 1
	designs[d.id] = d
	last_design_day = day
	_register(d)
	_news("%s entwirft %s: %s, %s, Nutzlast %d, %s" % [by, d.name, KLASSEN[d.klasse].label, d.form, int(d.capacity), Catalog.money(float(d.price))],
		str(d.reason) if str(d.reason) != "" else "neues Modell")
	return {"ok": true, "msg": "%s (%s) in Entwicklung bis Tag %d: Nutzlast %d, Tempo %.2f, Verbrauch %.2f/Feld, Selbstkosten %s, Preis %s." % [
		d.name, d.id, int(d.ready_day), int(d.capacity), float(d.speed), float(d.cost_per_tile), Catalog.money(float(d.selbstkosten)), Catalog.money(float(d.price))]}


func _register(d: Dictionary) -> void:
	if str(d.klasse) == "pkw":
		return   # Pkw gehen an Buerger, nicht in Firmenflotten
	Catalog.custom_models[d.id] = {"name": d.name, "price": float(d.price), "capacity": int(d.capacity), "speed": float(d.speed),
		"cost_per_tile": float(d.cost_per_tile), "wear": float(d.wear), "refrigerated": bool(d.refrigerated), "heavy": bool(d.heavy), "base": str(d.base)}


func _retire_old() -> void:
	var series: Array = designs.values().filter(func(d): return d.status == "serie")
	series.sort_custom(func(a, b): return int(a.day) < int(b.day))
	while series.size() > MAX_SERIES:
		var old: Dictionary = series.pop_front()
		old.status = "auslauf"


# ------------------------------------------------------------------ Montageband
func tick(now: float) -> void:
	if not sim.municipal.enabled():
		return
	_send_due()
	var f := plant()
	if f.is_empty():
		return
	var h := GameCalendar.hour_of(now)
	var fid := str(f.id)
	if h >= SHIFT[0] and h < SHIFT[1] and not line.is_empty():
		var hours := float(sim.municipal.staff_count(fid, "monteur")) * float(TICK_MIN) * 24.0 / GameCalendar.day_game_min
		var each := hours / float(line.size())
		for u in line:
			u.done_h = minf(float(u.need_h), float(u.done_h) + each)
		for u in line.duplicate():
			if float(u.done_h) >= float(u.need_h):
				line.erase(u)
				_finish(u)
	if h >= SHIFT[0] and h < SHIFT[1]:
		_start_units(f)
	_list_offers(f)


func _start_units(f: Dictionary) -> void:
	var M: Mayor = sim.towns.mayor(int(f.town))
	while line.size() < LINE_SLOTS and line.size() + hof.size() < STOCK_MAX:
		var d := _next_design()
		if d.is_empty():
			return
		# Stahl, Motor, Achsen, Glas von Zulieferern: bar aus dem Haushalt, sonst auf Rechnung (Kreditrahmen der Zulieferer)
		var cash_ok := M.available_budget() >= float(d.material)
		if not cash_ok and supplier_open() + float(d.material) > SUPPLIER_LIMIT:
			f["hinweis"] = "Band steht: Zulieferer liefern erst nach Bezahlung offener Rechnungen (%s offen)" % Catalog.money(supplier_open())
			return
		f.erase("hinweis")
		var u := {"design": d.id, "serial": serial, "need_h": float(d.hours), "done_h": 0.0, "unpaid": 0.0 if cash_ok else float(d.material)}
		if cash_ok:
			_pay_material(int(f.town), float(d.material))
		line.append(u)
		serial += 1


func supplier_open() -> float:
	var x := dev_open
	for e in line + hof:
		x += float(e.get("unpaid", 0.0))
	return x


func _pay_material(k: int, amount: float) -> void:
	sim.economy.transfer(Towns.account_of(k), "X0", amount)
	stats.material = float(stats.material) + amount


func _pay_dev(k: int, amount: float) -> void:
	sim.economy.transfer(Towns.account_of(k), "S0", amount)
	stats.entwicklung = float(stats.entwicklung) + amount


## Offene Zuliefererrechnung eines Fahrzeugs begleichen (beim Verkauf oder nach SUPPLIER_DAYS); beim Verkauf (sale > 0) geht ausserdem
## ein Drittel des Erloeses an gestundete Entwicklungskosten.
func _settle(e: Dictionary, sale: float = 0.0) -> void:
	var k := plant_town() if plant_town() >= 0 else 0
	if float(e.get("unpaid", 0.0)) > 0.0:
		_pay_material(k, float(e.unpaid))
		e.unpaid = 0.0
	if sale > 0.0 and dev_open > 0.0:
		var x := minf(dev_open, sale / 3.0)
		_pay_dev(k, x)
		dev_open -= x


## Naechstes Modell: das Serienmodell mit dem wenigsten Bestand (Hof + Band) im Verhaeltnis zu den Verkaeufen.
func _next_design() -> Dictionary:
	var best := {}
	var best_score := INF
	for d in designs.values():
		if d.status != "serie":
			continue
		var stock := hof.filter(func(x): return x.design == d.id).size() + line.filter(func(x): return x.design == d.id).size()
		var score := float(stock) - 0.2 * float(d.verkauft)
		if stock < STOCK_PER_MODEL and score < best_score:
			best_score = score
			best = d
	return best


func _finish(u: Dictionary) -> void:
	var d: Dictionary = designs.get(str(u.design), {})
	if d.is_empty():
		return
	d.gebaut = int(d.gebaut) + 1
	stats.gebaut = int(stats.gebaut) + 1
	hof.append({"design": d.id, "serial": int(u.serial), "day": _today(), "offer": "", "unpaid": float(u.get("unpaid", 0.0))})


## Autoverkaeufer stellen fertige Nutzfahrzeuge auf den Automarkt (je Verkaeufer bis zu 3 Angebote).
func _list_offers(f: Dictionary) -> void:
	var sellers: int = sim.municipal.staff_count(str(f.id), "autohaendler")
	var listed := hof.filter(func(x): return str(x.offer) != "").size()
	for e in hof:
		if listed >= sellers * 3:
			return
		var d: Dictionary = designs.get(str(e.design), {})
		if str(e.offer) != "" or d.is_empty() or str(d.klasse) == "pkw":
			continue
		var R = sim.resources
		var o := {"id": "F%d" % R.next_offer, "dealer": int(f.building), "model": d.id, "status": "verfügbar", "condition": 100,
			"price": float(d.price), "acct": Towns.account_of(int(f.town)), "werk": str(f.id)}
		R.next_offer += 1
		R.offers[o.id] = o
		e.offer = o.id
		listed += 1


func on_offer_sold(offer: Dictionary, cid: int) -> void:
	for e in hof:
		if str(e.offer) == str(offer.id):
			_settle(e, float(offer.price))
			hof.erase(e)
			break
	var d: Dictionary = designs.get(str(offer.model), {})
	if not d.is_empty():
		d.verkauft = int(d.verkauft) + 1
	stats.verkauft_firmen = int(stats.verkauft_firmen) + 1
	stats.umsatz = float(stats.umsatz) + float(offer.price)
	_sale(str(offer.model), sim.companies[cid].company_name, float(offer.price))


static func net_day(p: Dictionary) -> float:
	return float(p.get("wage", 0.0)) * Citizens.HOURS_PER_MONTH / float(GameCalendar.DAYS_PER_MONTH) * (1.0 - PublicSector.INCOME_TAX - PublicSector.SOCIAL_RATE)


## Kaeufer: Buerger ohne Auto mit Arbeit, Anzahlung plus 300 EUR auf dem Konto und tragbarer Rate (Werksfinanzierung).
func _can_buy(p: Dictionary, price: float) -> bool:
	if str(p.get("auto", "")) != "" or str(p.get("employer", "")) == "":
		return false
	return float(p.balance) >= price * PKW_DOWN + 300.0 and price * (1.0 - PKW_DOWN) / float(PKW_TERM_DAYS) <= net_day(p) * PKW_RATE_SHARE


## Tagesraten an die Stadtkasse; wer weggezogen ist, faellt aus (Abschreibung).
func _collect_rates() -> void:
	if loans.is_empty():
		return
	var f := plant()
	var acct := Towns.account_of(int(f.town)) if not f.is_empty() else "P0"
	var idx: Dictionary = sim.population.person_index()
	for l in loans.duplicate():
		var p: Dictionary = idx.get(int(l.person), {})
		if p.is_empty():
			stats.ausfall = float(stats.ausfall) + float(l.rest)
			loans.erase(l)
			continue
		var paid: float = sim.population.pay_out(acct, [[p, minf(float(l.rate), float(l.rest))]])
		l.rest = float(l.rest) - paid
		stats.raten = float(stats.raten) + paid
		if float(l.rest) <= 0.01:
			loans.erase(l)


## Pkw: Buerger kaufen beim Autoverkaeufer (Anzahlung, Rest in Raten), hoechstens 2 je Verkaeufer und Tag.
func _sell_pkw(_day: int) -> void:
	var f := plant()
	if f.is_empty():
		return
	var sellers: int = sim.municipal.staff_count(str(f.id), "autohaendler")
	var budget := sellers * 2
	for e in hof.duplicate():
		if budget <= 0:
			return
		var d: Dictionary = designs.get(str(e.design), {})
		if d.is_empty() or str(d.klasse) != "pkw":
			continue
		var price := float(d.price)
		var buyers: Array = sim.citizens.people.filter(func(p): return _can_buy(p, price))
		if buyers.is_empty() or sim.rng.randf() > minf(1.0, float(buyers.size()) * PKW_BUY_RATE):
			continue
		var p: Dictionary = buyers[sim.rng.randi() % buyers.size()]
		var down := price * PKW_DOWN
		var paid: float = sim.population.pay_out(Towns.account_of(int(f.town)), [[p, down]])
		if paid + 0.01 < down:
			continue
		p["auto"] = d.id
		loans.append({"person": int(p.id), "rest": price - down, "rate": (price - down) / float(PKW_TERM_DAYS), "design": d.id})
		_settle(e, price)
		hof.erase(e)
		budget -= 1
		d.verkauft = int(d.verkauft) + 1
		stats.verkauft_buerger = int(stats.verkauft_buerger) + 1
		stats.umsatz = float(stats.umsatz) + price
		_sale(str(d.id), str(p.get("name", "Bürger")), price)


func _sale(did: String, who: String, price: float) -> void:
	sales.append({"day": _today(), "design": did, "an": who, "preis": price})
	if sales.size() > 40:
		sales.pop_front()
	var d: Dictionary = designs.get(did, {})
	_news("Autohaus: %s verkauft an %s (%s)" % [d.get("name", did), who, Catalog.money(price)], "Verkauf", "kauf")


func _news(text: String, why: String, kind: String = "stadt") -> void:
	var f := plant()
	var cell := Vector2i.ZERO
	if not f.is_empty():
		cell = Vector2i(int(f.cell[0]), int(f.cell[1]))
	sim.activity.add("stadt", -1, kind, text, why, cell)


## Station am Band (fuer Anzeige und Beobachtung): Index in STAGES.
static func stage_of(u: Dictionary) -> int:
	var p := float(u.done_h) / maxf(0.01, float(u.need_h))
	for i in STAGES.size():
		if p < float(STAGES[i][1]):
			return i
	return STAGES.size() - 1


# ------------------------------------------------------------------ Beobachtung des Buergermeisters
func mayor_obs(k: int) -> Dictionary:
	var f := plant()
	if f.is_empty():
		return {}
	if int(f.town) != k:
		return {"werk_in": sim.towns.name_of(int(f.town))}
	var fid := str(f.id)
	var models: Array = []
	for d in designs.values():
		models.append({"id": d.id, "name": d.name, "klasse": d.klasse, "status": d.status, "nutzlast": d.capacity, "tempo": d.speed,
			"verbrauch_feld": d.cost_per_tile, "verschleiss": d.wear, "preis": d.price, "selbstkosten": d.selbstkosten,
			"gebaut": d.gebaut, "verkauft": d.verkauft, "auf_hof": hof.filter(func(x): return x.design == d.id).size(), "farbe": d.farbe, "form": d.form})
	var market := {}
	for o in sim.resources.offers.values():
		if o.has("werk"):
			continue
		var bm := str(o.model)
		if o.status == "verfügbar":
			market[bm] = minf(float(market.get(bm, INF)), float(o.price))
	var out := {"werk": f.name, "personal": {"bandmonteure": sim.municipal.staff_count(fid, "monteur"), "konstrukteure": sim.municipal.staff_count(fid, "ingenieur"),
			"autoverkaeufer": sim.municipal.staff_count(fid, "autohaendler")},
		"band": line.map(func(u): return {"modell": designs.get(str(u.design), {}).get("name", ""), "station": STAGES[stage_of(u)][2],
			"fortschritt": snappedf(float(u.done_h) / maxf(0.01, float(u.need_h)), 0.01)}),
		"hof_unverkauft": hof.size(), "zulieferer_offen": snappedf(supplier_open(), 1.0), "hinweis": str(f.get("hinweis", "")), "modelle": models, "statistik": stats.duplicate(),
		"haendlerpreise_neu_ab": market, "letzte_verkaeufe": sales.slice(-5),
		"pkw_finanzierung": {"laufend": loans.size(), "offen": snappedf(loans.reduce(func(acc, l): return acc + float(l.rest), 0.0), 1.0),
			"kaufkraeftige_buerger_ohne_auto": sim.citizens.people.filter(func(p): return _can_buy(p, 6000.0)).size()},
		"regeln": "Pkw: 20 %% Anzahlung, Rest in Tagesraten über %d Tage (Rate höchstens 40 %% vom Nettolohn) – günstige Pkw finden mehr Käufer. Entwurf kostet %s und %d Tage Entwicklung; Material zahlt die Stadtkasse je Fahrzeug, Erlös fließt zurück. Klassen: pkw (Bürger kaufen) | transporter | lkw | sattelzug (Firmen kaufen auf dem Automarkt). Mehr Nutzlast = teurer und langsamer; kraftvoll = schneller, mehr Verbrauch; premium = weniger Verschleiß, teurer. Höchstens %d Serienmodelle." % [PKW_TERM_DAYS, Catalog.money(DEV_COST), DEV_DAYS, MAX_SERIES]}
	out["vorschlag"] = _suggest(k)
	return out


## Regelvorschlag (MayorBrain nutzt ihn direkt): fehlt eine Klasse in Serie oder Entwicklung, ein Modell dafuer entwerfen.
func _suggest(k: int) -> Dictionary:
	if _today() - last_design_day < DESIGN_GAP_DAYS:
		return {}
	if sim.towns.mayor(k).available_budget() < DEV_COST and supplier_open() + DEV_COST > SUPPLIER_LIMIT:
		return {}   # erst verkaufen
	var have := {}
	for d in designs.values():
		if d.status in ["entwicklung", "serie"]:
			have[str(d.klasse)] = true
	for kl in ["transporter", "lkw", "pkw", "sattelzug"]:
		if have.has(kl):
			continue
		var names: Array = NAMES[kl]
		var town: String = sim.towns.name_of(k)
		var h := absi(hash([town, kl, designs.size()]))
		var colors: Array = FARBEN.keys()
		return {"action": "fahrzeug_entwerfen", "klasse": kl, "name": "%s %s" % [town, names[h % names.size()]], "farbe": colors[h % colors.size()],
			"akzent": "weiss", "form": FORMEN[h % FORMEN.size()], "leistung": "sparsam" if kl in ["transporter", "pkw"] else "ausgewogen",
			"qualitaet": "solide", "reason": "Im Werk fehlt noch ein %s – die Händler verlangen mehr." % KLASSEN[kl].label}
	return {}


# ------------------------------------------------------------------ Anzeige
## Infotext beim Anklicken: Werk (Personal, Band, Modelle, Verkauf) oder Werkstatt (Hebebuehnen, Wartungen); "" fuer andere Gebaeude.
func panel_text(building_id: int) -> String:
	var f := {}
	for x in sim.municipal.facilities.values():
		if int(x.building) == building_id and str(x.code) in ["FZ-01", "KW-01", "KW-02"]:
			f = x
	if f.is_empty():
		return ""
	var M = sim.municipal
	var fid := str(f.id)
	if str(f.code) != "FZ-01":
		var busy := in_service(fid)
		return "%s – Wartung alle %d km
Mechaniker: %d · Hebebühnen: %d · in Arbeit: %s
Wartungen bisher: %d (Teile + %d EUR/Stunde)" % [f.name, int(SERVICE_KM),
			M.staff_count(fid, "mechaniker"), int(f.capacity), ", ".join(busy.map(func(v): return v.display_name())) if not busy.is_empty() else "–",
			int(f.get("wartungen", 0)), int(LABOUR_RATE)]
	var lines: Array = ["%s – Träger %s" % [f.name, sim.towns.name_of(int(f.town))],
		"Personal: %d Bandmonteure · %d Konstrukteure · %d Autoverkäufer" % [M.staff_count(fid, "monteur"), M.staff_count(fid, "ingenieur"), M.staff_count(fid, "autohaendler")]]
	for u in line:
		var d: Dictionary = designs.get(str(u.design), {})
		lines.append("Band: %s – %s (%d %%)" % [d.get("name", "?"), STAGES[stage_of(u)][2], int(100.0 * float(u.done_h) / maxf(0.01, float(u.need_h)))])
	lines.append("Werkshof: %d unverkauft · gebaut %d · verkauft %d an Firmen, %d an Bürger" % [hof.size(), int(stats.gebaut), int(stats.verkauft_firmen), int(stats.verkauft_buerger)])
	for d in designs.values():
		lines.append("• %s (%s, %s, %s): Nutzlast %d · %s · %s – gebaut %d, verkauft %d" % [d.name, KLASSEN[d.klasse].label, d.form, d.status,
			int(d.capacity), Catalog.money(float(d.price)), str(d.by), int(d.gebaut), int(d.verkauft)])
	if str(f.get("hinweis", "")) != "":
		lines.append("⚠ " + str(f.hinweis))
	return "
".join(lines)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	return {"designs": designs, "line": line, "hof": hof, "stats": stats, "sales": sales, "loans": loans, "tried": tried, "serial": serial, "next": _next, "dev_open": dev_open,
		"last_design_day": last_design_day}


func from_dict(d: Dictionary) -> void:
	designs = d.get("designs", {})
	line = d.get("line", [])
	hof = d.get("hof", [])
	stats.merge(d.get("stats", {}), true)
	sales = d.get("sales", [])
	loans = d.get("loans", [])
	tried = d.get("tried", {})
	serial = int(d.get("serial", 1))
	dev_open = float(d.get("dev_open", 0.0))
	_next = int(d.get("next", 1))
	last_design_day = int(d.get("last_design_day", -99))
	for x in designs.values():
		x.capacity = int(x.capacity)
		_register(x)
