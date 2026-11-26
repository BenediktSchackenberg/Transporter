class_name Founders
extends RefCounted
## Zusaetzliche Unternehmer aus wirtschaftlichen Chancen (Auftrag 17, Abschnitt 12). Neue Companies mit eigener Identitaet, Heimatstadt,
## Konto, Gedaechtnis und (in der Sitzung) eigenem Regel-Controller. Das Firmenregister bleibt append-only: neue ID = naechster Index,
## keine ID wird wiederverwendet; die Startspieler (IDs 0..n-1) behalten ihre Profile.
##
## Alle CHECK_DAYS Tage je Stadt: Chancen erkennen (Lieferengpass einer Vorstufe, fehlende Baeckerei/fehlendes Restaurant bei
## ausreichender Einwohnerzahl, Bauvorhaben ohne freien Bautrupp). Eine Chance muss bei STREAK aufeinanderfolgenden Pruefungen bestehen
## (laenger unbefriedigte Nachfrage). Dann Pruefung: Gruenderquote (aktive Unternehmen mit Heimat in der Stadt < MAX_PER_TOWN),
## Abklingzeit der Stadt, Standort (freies Grundstueck mit Strassen- und Stromanschluss in der Stadt), Personal (Arbeitslose bzw.
## Bewerber), Finanzierung (Einlage aus dem Kapitalgeberpool I0, kein neues Geld). Scheitert eine Pruefung, wird der Grund protokolliert.

signal company_founded(cid: int)

const CHECK_DAYS := 5
const STREAK := 3
const MAX_PER_TOWN := 5              # ursprunglicher Unternehmer + bis zu vier Gruender (konfigurierbar ueber max_per_town)
const COOLDOWN_DAYS := 12
const WILD_COOLDOWN_DAYS := 2        # Wildnis: Laeden einer jungen Stadt nacheinander, nicht im 12-Tage-Takt
const WILD_MAX_PER_TOWN := 8
const CAPITAL := 60000.0
const CAPITAL_BY_BRANCH := {"bergwerk": 120000.0, "stahlwerk": 150000.0, "kokerei": 110000.0}
const POP_PER_FIRM := 40.0           # Standard fuer pop_per_firm: neue Gruender erst ab so vielen Einwohnern je bestehendem Unternehmen (Messung 14.11.: 10 Firmen
                                      # auf ~200 Einwohner, alle im Minus)
const POP_PER_SHOP := 15.0         # Benedikt 25.11. ("Leben und Gewerbe"): je Stadt ein Laden/Betrieb je so vielen Einwohnern
const SHOPS := {"baeckerei": 15, "kneipe": 20, "restaurant": 25, "metzgerei": 30}   # Mindesteinwohner der Stadt je Ladenbranche
const MINING_FROM_DAY := 5           # Bergbau frueh: die Kette Bohrung -> Abbaurecht -> Zufahrt -> Bergwerk -> Stahl braucht Wochen
const INDUSTRY := ["bergwerk", "stahlwerk", "elektrostahlwerk", "kokerei"]   # regionale Aufgaben: ohne Abklingzeit der Stadt, sofort statt nach STREAK Pruefungen
const FOCUS_BRANCHES := ["bergwerk"] # mehrstufige Gruendung (Probebohrung, Abbaurecht, Zufahrt): die Regel-KI geht die Schritte selbst
const FIRST := ["Jana", "Tom", "Aylin", "Malte", "Greta", "Kemal", "Ronja", "Lars", "Mira", "Nils", "Selin", "Arne"]
const LAST := ["Brückner", "Seidel", "Kaya", "Wendt", "Lorenz", "Ahrens", "Petersen", "Yilmaz", "Haas", "Voss", "Engel", "Kruse"]
const WORDS := ["Werke", "& Partner", "Betriebe", "Handel", "Gruppe"]

var sim
var enabled := true
var pop_per_firm := POP_PER_FIRM   # 0 = ohne Marktgroessen-Pruefung (Mechanik-Tests)
var max_per_town := MAX_PER_TOWN
var streaks := {}                    # "Stadt|Branche" -> aufeinanderfolgende Pruefungen mit dieser Chance
var last_found := {}                 # Stadt -> Tag der letzten Gruendung
var history: Array = []              # {tag, stadt, firma, branche, anlass, kapital}
var refusals: Array = []             # {tag, stadt, branche, grund}
var topups := {}                     # Firma -> Nachschuss des Kapitalgebers fuer das Gruendungsziel (hoechstens einmal)
const START_FLOOR := 10000.0
const START_TOPUP := 30000.0
const START_EVERY_DAYS := 5        # Bergwerk blockiert (Kasse leer): Kapitalgeber helfen bei jeder Gruenderpruefung (zuerst, vor neuen Laeden)
const WILD_DAILY_INFLOW := 4000.0
## 26.11.: viermal wurde eine Kneipe gegruendet (zweimal je Stadt), keine trug sich (Voss Werke: 756 EUR Umsatz gegen 26.700 EUR Lohn
## und Miete); jede kostete den Kapitalgeberpool 35.000 EUR. Nach dem Scheitern eines Ladens dieser Branche in der Stadt so lange keine Neugruendung.
const FAILED_RETRY_DAYS := 60
const TOPUP_TARGET := 55000.0        # Bargeld fuer Bergwerksgruendung (Gebaeude 30.000) plus Betriebsreserve


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


func on_day(day: int) -> void:
	# 26.11.: Versicherung und Sicherheitsdienst (je 750 EUR/Tag) aus der Zeit vor der Gruendersperre liefen weiter, kuendigen
	# konnten Gruenderfirmen sie nicht (nicht in FOUNDER_ACTIONS) – rund die Haelfte der laufenden Kosten der Engel-Firmen
	for c in sim.companies:
		if c.is_active() and sim.executor.founder_only(c.id):
			c.insurance = false
			c.security_level = 0
	if enabled and sim.wildnis:
		# 25.11.: Aufbauphase – Kapitalgeber taeglich statt monatlich (25.000 EUR/Monat liessen I0 tagelang leer; Bergwerk und Laeden
		# blieben ohne Anlaufkapital)
		var room := maxf(0.0, Insolvency.WILD_INVESTOR_CAP - float(sim.economy.accounts.get("I0", 0.0)))
		if room > 0.0:
			sim.economy.transfer("X0", "I0", minf(WILD_DAILY_INFLOW, room))
	if not enabled or not sim.towns.is_region() or day % CHECK_DAYS != 0:
		return
	_topup_focus(day)
	var seen := {}
	for chance in opportunities():
		var key := "%d|%s" % [int(chance.stadt), chance.branche]
		seen[key] = true
		streaks[key] = int(streaks.get(key, 0)) + 1
		if int(streaks[key]) >= STREAK or str(chance.branche) in INDUSTRY:
			var r := try_found(int(chance.stadt), str(chance.branche), str(chance.anlass))
			streaks[key] = 0 if r.ok else int(streaks[key])
	for key in streaks.keys():
		if not seen.has(key):
			streaks.erase(key)   # Chance verschwunden: kurzer Engpass begruendet keine Gruendung


## Nachfinanzierung: Hat eine Gruenderfirma alle Vorstufen ihres Ziels geschafft (Bergbau: Abbaurecht und Zufahrt) und fehlt nur
## noch Geld fuer den Betrieb, schiesst der Kapitalgeberpool I0 einmal nach (Einlage, kein Kredit - die Banken verlangen ein
## Fahrzeug als Pfand, das eine Bergbaufirma nicht hat). Geld kommt aus I0, entsteht also nicht neu.
func _topup_focus(day: int) -> void:
	for c in sim.companies:
		if c.focus != "bergwerk" or c.status in ["geschlossen", "verwertung"]:
			continue
		var mine: Array = sim.biz.items.values().filter(func(b): return int(b.owner) == c.id and b.branch == c.focus)
		if not mine.is_empty() and str(mine[0].status) == "geschlossen" and c.is_active():
			# 25.11.: die Rueckzugsregel hatte das Bergwerk der Engel Gruppe geschlossen (stossweiser Absatz) – wieder in Betrieb nehmen
			sim.biz.set_status(str(mine[0].id), "blockiert", "Kapitalgeber: Bergwerk wieder in Betrieb genommen")
			sim.log_event("%s nimmt das Bergwerk %s wieder in Betrieb." % [c.company_name, str(mine[0].get("name", mine[0].id))], "good", c.id)
		if not mine.is_empty():
			# 25.11.: Bergwerk steht, aber die Kasse ist leer (Engel Gruppe: 2.016 EUR, Strom und Personal nicht bezahlbar) –
			# einmal Anlaufkapital bis zur ersten Foerderung
			var key := "%d:anlauf" % c.id
			var last_day := int(topups.get("%d:anlauf_tag" % c.id, -1000))
			if day - last_day < START_EVERY_DAYS or c.ledger.cash >= START_FLOOR or str(mine[0].status) not in ["blockiert", "betriebsbereit"]:
				continue
			var add := minf(START_TOPUP, float(sim.economy.accounts.get("I0", 0.0)))
			if add > 1000.0:
				c.ledger.inject(add)
				topups[key] = float(topups.get(key, 0.0)) + add
				topups["%d:anlauf_tag" % c.id] = day
				sim.log_event("Kapitalgeber geben %s %s Anlaufkapital für das Bergwerk (Personal, Strom bis zur ersten Förderung)." % [c.company_name, Catalog.money(add)], "good", c.id)
			continue
		if topups.has(c.id):
			continue
		var ready := false
		for art in ["eisenerz", "kohle", "kalkstein", "rohmaterial", "naturstein"]:
			if str(sim.mining.next_step(c.id, art).get("schritt", "")) == "gruenden":
				ready = true
				break
		var gap: float = TOPUP_TARGET - c.ledger.cash
		if not ready or gap <= 1000.0:
			continue
		gap = minf(gap, float(sim.economy.accounts.get("I0", 0.0)))
		if gap <= 1000.0:
			continue
		c.ledger.inject(gap)
		topups[c.id] = gap
		sim.log_event("Kapitalgeber schießen %s für %s nach: Abbaurecht und Zufahrt stehen, das Bergwerk kann gebaut werden." % [Catalog.money(gap), c.company_name], "good", c.id)


## Fuer die Beobachtung der Firmen: dieselben Chancen, je Spielstunde nur einmal berechnet (kostet in der Region 40 ms,
## Beobachtung und Hofrunde fragen sie mehrmals je Stunde ab - Partie 09.11.: Ruckler). Die Gruendungspruefung (on_day) rechnet frisch.
var _opp_cache := {"slot": -1, "out": []}
func opportunities_cached() -> Array:
	var slot := int(sim.game_min / 60.0)
	if int(_opp_cache.slot) != slot:
		_opp_cache = {"slot": slot, "out": opportunities()}
	return _opp_cache.out


## Erkannte Chancen je Stadt: [{stadt, branche, anlass}].
func opportunities() -> Array:
	var out: Array = []
	var T: Towns = sim.towns
	var running: Array = sim.biz.items.values().filter(func(b): return b.status in Businesses.RUNNING or b.status == "im_bau")
	for k in T.count():
		var pop: int = sim.citizens.population_of(k)
		var in_town := running.filter(func(b): return T.of_building(int(b.site)) == k)
		if sim.wildnis and not sim.town_ready(k):
			continue
		for br in SHOPS:
			var min_pop: int = int(SHOPS[br]) if sim.wildnis else (80 if br == "metzgerei" else 40)
			if (sim.wildnis or br != "kneipe") and pop >= min_pop and not in_town.any(func(b): return b.branch == br):
				out.append({"stadt": k, "branche": br, "anlass": "Keine %s in %s bei %d Einwohnern" % [Businesses.branches()[br].label, T.name_of(k), pop]})
		# Vorstufe fehlt: Betriebe dieser Stadt warten auf eine Ware, die niemand in der Region herstellt
		for b in in_town:
			var item := str(b.get("waiting_for", ""))
			if item != "" and Production.UPSTREAM.has(item) and not running.any(func(x): return x.branch == Production.UPSTREAM[item]):
				out.append({"stadt": k, "branche": str(Production.UPSTREAM[item]), "anlass": "%s wartet auf %s, kein Hersteller in der Region" % [b.name, Production.item_name(item)]})
		# Rohstoffe: noch kein Bergwerk in der Region und eine Lagerstaette ist frei -> Bergbau (Ausfuhr ueber den Hafen, spaeter Industrie)
		if k == _mining_town() and GameCalendar.day_of(sim.game_min) >= MINING_FROM_DAY and not running.any(func(b): return b.branch == "bergwerk") \
				and not sim.companies.any(func(c): return c.focus == "bergwerk" and c.status not in ["geschlossen", "verwertung"]):
			var dep := _free_deposit()
			if not dep.is_empty():
				out.append({"stadt": k, "branche": "bergwerk", "anlass": "Lagerstätte %s (%s) ungenutzt – Bergbau mit Zufahrt in die Berge" % [dep.grundstueck, Production.item_name(str(dep.art))]})
		# Weiterverarbeitung: Erz wird gefoerdert, aber kein Stahlwerk in der Region -> Industrie
		# (schon sobald ein Eisenerz-Abbaurecht genehmigt ist: Bergwerk und Stahlwerk entstehen parallel)
		var ore_ready: bool = running.any(func(b): return b.branch == "bergwerk" and str(b.get("deposit", {}).get("art", "")) == "eisenerz") \
				or sim.mining.permits.keys().any(func(pid): return sim.mining.permits[pid].status == "genehmigt" and str(sim.prod.deposit_of(str(pid)).get("art", "")) == "eisenerz")
		if k == _mining_town() and ore_ready and not running.any(func(b): return b.branch in ["stahlwerk", "elektrostahlwerk"]):
			out.append({"stadt": k, "branche": "stahlwerk", "anlass": "Eisenerz-Abbau genehmigt bzw. in Förderung, aber kein Stahlwerk in der Region – parallel zum Bergwerk bauen"})
		# Bauvorhaben ohne Baufirma vor Ort
		var waiting: int = sim.construction.works.values().filter(func(w): return w.status == "laufend" and str(w.waiting).contains("Bautrupp") and T.of_building(int(w.building)) == k).size()
		var today := GameCalendar.day_of(sim.game_min)
		waiting += sim.construction.projects.values().filter(func(p): return p.status in ["erschliessung", "im_bau"] and int(p.get("start", 0)) > today + 10 and T.of_parcel(str(p.parcel)) == k).size()
		if waiting >= 2 and not in_town.any(func(b): return b.branch == "baufirma"):
			out.append({"stadt": k, "branche": "baufirma", "anlass": "%d Bauvorhaben in %s warten auf einen Bautrupp bzw. Baubeginn" % [waiting, T.name_of(k)]})
	return out


## Stadt, von der aus Bergbau und Industrie entstehen: die einwohnerstaerkste mit freiem Gruenderplatz (Arbeitskraefte, Hafen);
## Bergbau ist eine regionale Aufgabe, nicht an die groesste Stadt gebunden.
func _mining_town() -> int:
	var best := -1
	for k in sim.towns.count():
		if active_home(k) >= max_per_town or (sim.wildnis and not sim.town_ready(k)):
			continue
		if best < 0 or sim.citizens.population_of(k) > sim.citizens.population_of(best):
			best = k
	return best


## Freie Lagerstaette (Eisenerz bevorzugt), auf der noch niemand bohrt oder abbaut.
func _free_deposit() -> Dictionary:
	for art in ["eisenerz", "kohle", "kalkstein", "rohmaterial", "naturstein"]:
		for pid in sim.prod.deposit_parcels():
			var d: Dictionary = sim.prod.deposit_of(str(pid))
			if d.is_empty() or str(d.art) != art or sim.mining.drillings.has(pid) or sim.mining.permits.has(pid):
				continue
			var p: Dictionary = sim.parcels.parcel(str(pid))
			if not p.is_empty() and p.state == "frei" and Towns.is_public(str(p.owner)):
				return {"grundstueck": str(pid), "art": art}
	return {}


func active_home(town: int) -> int:
	return sim.companies.filter(func(c): return int(c.home_town) == town and c.status not in ["geschlossen", "verwertung"]).size()


func _refuse(town: int, branch: String, why: String) -> Dictionary:
	refusals.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": town, "branche": branch, "grund": why})
	if refusals.size() > 40:
		refusals.pop_front()
	return {"ok": false, "msg": "Keine Gründung (%s, %s): %s" % [sim.towns.name_of(town), branch, why]}


## Gruendungsversuch. Prueft Quote, Abklingzeit, Standort, Personal, Finanzierung; legt dann die Company an und gruendet den Betrieb.
func try_found(town: int, branch: String, reason: String) -> Dictionary:
	var day := GameCalendar.day_of(sim.game_min)
	# 25.11. (Wildnis, Ziel "Leben und Gewerbe"): jede Stadt ist ein eigener Markt – mehr Gruender je Stadt, kurze Abklingzeit, und
	# die regionale Marktsaettigung zaehlt nicht (die Baeckerei in Sonnenbucht sperrte die erste Baeckerei in Liorklippe).
	var quota := maxi(max_per_town, WILD_MAX_PER_TOWN) if sim.wildnis else max_per_town
	var cooldown := WILD_COOLDOWN_DAYS if sim.wildnis else COOLDOWN_DAYS
	if active_home(town) >= quota:
		return _refuse(town, branch, "Gründerquote erreicht (%d aktive Unternehmen mit Heimat %s)" % [active_home(town), sim.towns.name_of(town)])
	if branch not in INDUSTRY and last_found.has(town) and day - int(last_found[town]) < cooldown:
		return _refuse(town, branch, "Abklingzeit nach der letzten Gründung (bis Tag %d)" % (int(last_found[town]) + cooldown))
	var spec: Dictionary = Businesses.branches().get(branch, {})
	if spec.is_empty():
		return _refuse(town, branch, "unbekannte Branche")
	var via: Dictionary = sim.retail.counter_viable(branch)
	if not bool(via.ok) and sim.wildnis and str(via.msg).begins_with("Markt gesättigt"):
		via = {"ok": true}
	if not bool(via.ok):
		return _refuse(town, branch, str(via.msg).left(120))
	if SHOPS.has(branch):
		for b in sim.biz.items.values():
			var closed_day := GameCalendar.day_of(float(b.since))
			if str(b.branch) == branch and str(b.status) == "geschlossen" and sim.towns.of_building(int(b.site)) == town and day - closed_day < FAILED_RETRY_DAYS:
				return _refuse(town, branch, "%s in %s erst an Tag %d gescheitert – neuer Versuch frühestens ab Tag %d" % [Businesses.branches()[branch].label, sim.towns.name_of(town), closed_day, closed_day + FAILED_RETRY_DAYS])
	# 25.11.: Marktgroesse je Stadt (Einwohner der Stadt gegen ihre Betriebe) statt Region gegen alle Firmen – mit zwei KI-Unternehmern
	# und 50 Einwohnern entstand sonst nie ein Laden. Bergbau und Industrie sind regionale Aufgaben ohne Marktpruefung.
	var firms: int = sim.companies.filter(func(x): return x.status not in ["geschlossen", "verwertung"]).size()
	if not sim.wildnis and (branch not in INDUSTRY or sim.neubeginn) and float(sim.citizens.population()) < pop_per_firm * float(firms + 1):
		return _refuse(town, branch, "Markt zu klein: %d Einwohner für %d Unternehmen (eine Gründung je %d Einwohner)" % [sim.citizens.population(), firms + 1, int(pop_per_firm)])
	if sim.wildnis and branch not in INDUSTRY and pop_per_firm > 0.0:
		var town_pop: int = sim.citizens.population_of(town)
		var shops: int = sim.biz.items.values().filter(func(b): return SHOPS.has(str(b.branch)) and str(b.status) != "geschlossen" and sim.towns.of_building(int(b.site)) == town).size()   # nur Laeden: Felder und Muehle leben nicht von der Laufkundschaft der Stadt
		var per: float = minf(pop_per_firm, POP_PER_SHOP)
		if float(town_pop) < per * float(shops + 1):
			return _refuse(town, branch, "Markt zu klein: %d Einwohner in %s für %d Betriebe (einer je %d Einwohner)" % [town_pop, sim.towns.name_of(town), shops + 1, int(per)])
	var bsize: Array = CityGenerator.TYPES[str(spec.get("gebaeude", "farm"))]
	var min_area: int = int(spec.feld.min_flaeche) if spec.has("feld") else int(bsize[1]) * int(bsize[2]) + 4
	var site_ok: bool = branch in FOCUS_BRANCHES or sim.parcels.search({"min_area": min_area, "town": town, "limit": 400}).any(func(p): return bool(sim.parcels.utilities_of(p).strasse))
	if branch == "bergwerk" and _free_deposit().is_empty():
		return _refuse(town, branch, "keine freie Lagerstätte")
	if not site_ok:
		return _refuse(town, branch, "kein freies erschlossenes Grundstück (mind. %d Felder)" % min_area)
	var staff_need: int = int(spec.get("personal_min", 1)) + (0 if sim.wildnis else 1)
	if not (sim.wildnis and branch in INDUSTRY) and sim.citizens.unemployed_total() + sim.citizens.applicants() < staff_need:
		return _refuse(town, branch, "kein Personal am Arbeitsmarkt")   # Industrie: Fachkraefte ziehen fuer die Stelle zu (Zuzug)
	var need := float(CAPITAL_BY_BRANCH.get(branch, CAPITAL))
	if sim.wildnis and SHOPS.has(branch):
		# 25.11.: kleine Laeden brauchen keine 60.000 EUR (Kaya/Engel hatten nach dem Aufbau noch 23.000-30.000 EUR) – der Pool I0 reichte
		# sonst fuer keine zweite Gruendung
		need = maxf(2.5 * float(spec.get("ausstattung", 0.0)), 35000.0)
	if float(sim.economy.accounts.get("I0", 0.0)) < need:
		return _refuse(town, branch, "Kapitalgeber ohne Mittel (I0 %s, nötig %s)" % [Catalog.money(float(sim.economy.accounts.get("I0", 0.0))), Catalog.money(need)])
	var c := _create(town, reason, need)
	if branch in FOCUS_BRANCHES:
		# mehrstufig: Ziel setzen, Hauptsitz im Ort (Rathaus-Nachbarschaft folgt mit dem ersten Betrieb); die Regel-KI bohrt, beantragt,
		# laesst die Zufahrt bauen und gruendet dann das Bergwerk
		c.focus = branch
		c.personality = "wachstum"
		c.depots.append(int(sim.towns.get_t(town).town_hall))   # vorlaeufiger Sitz: Buero im Rathaus der Heimatstadt
		sim.personnel.start_staff_small(c.id)
		if branch not in INDUSTRY:
			last_found[town] = day
		history.append({"tag": day, "stadt": town, "firma": c.id, "branche": branch, "anlass": reason, "kapital": need})
		sim.log_event("Neue Bergbaufirma in %s: %s (%s) – Anlass: %s. Einlage %s vom Kapitalgeberpool; nächste Schritte: Probebohrung, Abbaurecht, Zufahrt, Bergwerk." % [
			sim.towns.name_of(town), c.player_name, c.company_name, reason, Catalog.money(need)], "good", c.id)
		company_founded.emit(c.id)
		return {"ok": true, "msg": "%s gegründet (Firma %d, Ziel Bergbau)." % [c.company_name, c.id], "ref": c.id}
	var act := {"action": "found_business", "branche": branch, "stadt": str(town), "reason": reason}
	var hints: Array = sim.prod.site_hints(branch, 1) if branch in INDUSTRY else []
	if not hints.is_empty():
		act["standort"] = str(hints[0].grundstueck)   # Regel-Gruender: Standort mit den geringsten Zutatenkosten (Naehe zur Quelle)
		act.erase("stadt")
	var r: Dictionary = sim.executor.execute(c.id, act)
	if not r.get("ok", false):
		# Gruendung des Betriebs gescheitert: Firma bleibt mit ihrer Einlage bestehen (kein Rueckbau von IDs), Grund protokolliert
		_refuse(town, branch, "Betrieb nicht gegründet: %s" % str(r.get("msg", "")).left(120))
		if c.depots.is_empty():
			# ohne Sitz brach die Figur jedes Bild mit depots[0] ab (22 841 Fehler im 8-Stunden-Lauf): Buero im Rathaus der Heimatstadt
			c.depots.append(int(sim.towns.get_t(town).town_hall))
			sim.personnel.start_staff_small(c.id)
	else:
		var b: Dictionary = sim.biz.get_b(str(r.ref))
		if c.depots.is_empty() and not b.is_empty():
			c.depots.append(int(b.site))   # Hauptsitz am ersten Betrieb
		if not c.depots.is_empty():
			sim.personnel.start_staff_small(c.id)   # zwei Allrounder am Hauptsitz, wie beim Startunternehmer
	if branch not in INDUSTRY:
		last_found[town] = day
	history.append({"tag": day, "stadt": town, "firma": c.id, "branche": branch, "anlass": reason, "kapital": need})
	sim.log_event("Neue Unternehmerin/neuer Unternehmer in %s: %s (%s) gründet %s – Anlass: %s. Einlage %s vom Kapitalgeberpool." % [sim.towns.name_of(town),
		c.player_name, c.company_name, spec.get("label", branch), reason, Catalog.money(need)], "good", c.id)
	company_founded.emit(c.id)
	return {"ok": true, "msg": "%s gegründet (Firma %d)." % [c.company_name, c.id], "ref": c.id}


## Gruendung durch ein freies Wesen (Eko-Modus): eigene Ersparnisse (Konto Y0) plus Einlage des Kapitalgeberpools I0.
## Sitz vorlaeufig im Rathaus der Heimatstadt, zwei Allrounder wie beim Startunternehmer. Das Signal company_founded sendet der
## Aufrufer, nachdem er die Firma dem Wesen zugeordnet hat (damit die Sitzung den Controller als "eko" anlegt).
func create_for_being(town: int, player: String, firm: String, own: float, investor: float) -> Company:
	var c := _create(town, "Gründung durch %s (eigene Ersparnisse und Kapitalgeber)" % player, investor)
	c.player_name = player
	c.company_name = firm
	c.personality = "netzwerker"
	sim.economy.transfer("Y0", "I0", own)   # Ersparnisse des Wesens als Einlage (ueber den Kapitalgeberpool in die Firma)
	c.ledger.inject(own)
	c.depots.append(int(sim.towns.get_t(town).town_hall))
	sim.personnel.start_staff_small(c.id)
	history.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": town, "firma": c.id, "branche": "transport", "anlass": "Wesen %s" % player, "kapital": own + investor})
	return c


## Neue Company am Ende des Registers (eigene ID, eigenes Konto "C<id>", Einlage aus I0, eigenes Gedaechtnis, Figur und Personal).
func _create(town: int, reason: String, capital: float = CAPITAL) -> Company:
	var cid: int = sim.companies.size()
	var r := RandomNumberGenerator.new()
	r.seed = hash([sim.city.seed_value, cid, "gruender"])
	var c := Company.new()
	c.id = cid
	c.player_name = "%s %s" % [FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]]
	c.company_name = "%s %s" % [c.player_name.split(" ")[1], WORDS[r.randi() % WORDS.size()]]
	c.color = Catalog.COMPANY_COLORS[cid % Catalog.COMPANY_COLORS.size()].lightened(0.15 * float(cid / Catalog.COMPANY_COLORS.size()))
	c.avatar_style = cid % 4
	c.personality = Catalog.PERSONALITIES.keys()[r.randi() % Catalog.PERSONALITIES.size()]
	c.form = "einzel"
	c.founded_min = sim.game_min
	c.home_town = town
	c.ledger = Ledger.new(0.0)
	sim.companies.append(c)
	sim.economy.attach(c.ledger, "C%d" % cid)
	c.ledger.public_acct = Towns.account_of(town)
	c.ledger.inject(capital)   # Einlage aus dem Kapitalgeberpool (I0 -> Firma), kein neues Geld
	c.ledger.book("admin", -float(CompanyForms.FORMS[c.form].found_cost), true, "Gründung " + CompanyForms.name_of(c.form), sim.game_min)
	for k in sim.contracts:
		if sim.contracts[k].status == "open":
			c.known[k] = true
	var a := Avatar.new()
	a.owner = cid
	var hall: int = int(sim.towns.get_t(town).town_hall)
	a.pos = sim.city.tile_center(sim.city.building(hall).walk if hall >= 0 else sim.towns.get_t(town).center)
	sim.avatars[cid] = a
	sim.action_results[cid] = []
	sim._fuel[cid] = 0.0
	sim.memory.books[cid] = {"events": [], "experiences": [], "next": 1}
	sim.personnel.seen[cid] = {}
	c.ledger.sample(sim.game_min)
	c.add_key_event("Gegründet in %s: %s" % [sim.towns.name_of(town), reason.left(80)], sim.game_min)
	return c


func summary() -> Dictionary:
	return {"max_je_stadt": max_per_town, "gruendungen": history.slice(-10), "abgelehnt": refusals.slice(-6),
		"chancen": streaks.keys().map(func(k): return {"chance": k, "pruefungen": int(streaks[k])})}


func to_dict() -> Dictionary:
	return {"streaks": streaks.duplicate(), "last_found": last_found.duplicate(), "history": history.duplicate(true), "refusals": refusals.duplicate(true), "max": max_per_town, "topups": topups.duplicate()}


func from_dict(d: Dictionary) -> void:
	streaks = d.get("streaks", {})
	topups = {}
	for k in d.get("topups", {}):
		topups[int(k)] = float(d.topups[k])
	last_found = {}
	for k in d.get("last_found", {}):
		last_found[int(k)] = int(d.last_found[k])
	history = d.get("history", [])
	refusals = d.get("refusals", [])
	max_per_town = int(d.get("max", MAX_PER_TOWN))
