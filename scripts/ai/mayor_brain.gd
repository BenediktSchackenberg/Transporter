class_name MayorBrain
extends RefCounted
## Regelbasierte Buergermeister-Entscheidung (Standard ohne Sprachmodell und Ersatzmodus bei API-Stoerung). Arbeitet nur mit der
## Beobachtung aus `Mayor.indicators()` und den Aktionen aus `Mayor.SCHEMA` – wie ein Sprachmodell. Die Partei bestimmt die Schwellen.

const MAX_ACTIONS := 4


static func decide(ind: Dictionary) -> Dictionary:
	var actions: Array = []
	var notes: Array = []
	var party := str(ind.buergermeister.partei)
	var housing: Dictionary = ind.wohnen
	var stock := maxf(1.0, float(housing.bestand_einheiten))
	var waiting := int(housing.wohnungssuchende_haushalte)
	# 1) Bauantraege der Buergermeisterebene nach den benannten Voraussetzungen entscheiden
	for d in ind.bauantraege.zur_entscheidung_details:
		if actions.size() >= MAX_ACTIONS:
			break
		if bool(d.vorpruefung_ok) and d.offene_punkte.is_empty():
			var cond: Array = d.auflagen
			actions.append({"action": "decide_application", "application_id": d.id, "decision": "bedingungen" if not cond.is_empty() else "genehmigen",
				"reason": "Alle Voraussetzungen erfüllt (%s, %d Einheiten)%s." % [d.art, int(d.einheiten), ", Erschließung als Auflage" if not cond.is_empty() else ""]})
			notes.append("Antrag %s genehmigt" % d.id)
		elif not d.ablehnungsgruende.is_empty():
			actions.append({"action": "decide_application", "application_id": d.id, "decision": "ablehnen", "reason": "Nicht genehmigungsfähig: " + " ".join(d.ablehnungsgruende)})
			notes.append("Antrag %s abgelehnt" % d.id)
		elif int(d.rueckfragen_bisher) < 2:
			actions.append({"action": "decide_application", "application_id": d.id, "decision": "rueckfrage", "reason": "Offene Punkte: " + " ".join(d.offene_punkte)})
		else:
			actions.append({"action": "decide_application", "application_id": d.id, "decision": "ablehnen", "reason": "Offene Punkte trotz Rückfragen nicht behoben: " + " ".join(d.offene_punkte)})
	# 1b) Beschaffungsvorschlaege des Stadtlagers: kritische Ware und bezahlbare Vorschlaege genehmigen, zu teure ablehnen
	for pv in ind.stadtlager.vorschlaege:
		if actions.size() >= MAX_ACTIONS:
			break
		var project := str(pv.projekt if pv.has("projekt") else "")
		var afford := float(pv.geschaetzte_kosten) <= float(ind.haushalt.verfuegbar)
		# Material eines laufenden oeffentlichen Projekts wird aus dem bereits reservierten Projektbudget bezahlt
		# (Kassenverfuegbarkeit egal): Ablehnung hier wuerde das Projekt unbefristet stilllegen.
		if project != "":
			actions.append({"action": "approve_procurement", "order_id": pv.id, "reason": "%s für Projekt %s: %s; gedeckt aus dem reservierten Projektbudget, nicht von der Restkasse." % [pv.artikel, project, pv.grund]})
			notes.append("Projektbeschaffung %s genehmigt" % pv.id)
		elif afford and (int(pv.kritikalitaet) >= 2 or str(party) != "haushalt"):
			actions.append({"action": "approve_procurement", "order_id": pv.id, "reason": "%s: %s; Kosten %s im Budget (verfügbar %s)." % [pv.artikel, pv.grund, Catalog.money(float(pv.geschaetzte_kosten)), Catalog.money(float(ind.haushalt.verfuegbar))]})
			notes.append("Beschaffung %s genehmigt" % pv.id)
		elif not afford:
			actions.append({"action": "reject_procurement", "order_id": pv.id, "reason": "Budget reicht nicht (%s nötig, %s verfügbar); später erneut prüfen." % [Catalog.money(float(pv.geschaetzte_kosten)), Catalog.money(float(ind.haushalt.verfuegbar))]})
	# 1c) Zentrallager ausbauen: wiederkehrend wartende Lkw -> Rampe, Rueckstau im Wareneingang -> Personal bzw. Stapler
	var sl: Dictionary = ind.stadtlager
	if actions.size() < MAX_ACTIONS:
		if int(sl.lkw_wartezeiten_letzte_10_tage) >= 3 and int(sl.rampen) < CityDepot.MAX_RAMPS and float(ind.haushalt.verfuegbar) > CityDepot.RAMP_COST * 2.0:
			actions.append({"action": "expand_depot", "kind": "ramp", "reason": "Lkw mussten an %d der letzten 10 Tage auf eine freie Rampe warten (Rampen: %d)." % [int(sl.lkw_wartezeiten_letzte_10_tage), int(sl.rampen)]})
		elif int(sl.rueckstau_wareneingang_einheiten) > 2 * maxi(int(sl.kapazitaet_wareneingang_je_tag), 1) and float(ind.haushalt.verfuegbar) > 30000.0:
			var kind := "forklift" if int(sl.gabelstapler) < 2 else "staff"
			actions.append({"action": "expand_depot", "kind": kind, "reason": "Rückstau im Wareneingang: %d Einheiten bei %d je Tag Kapazität." % [int(sl.rueckstau_wareneingang_einheiten), int(sl.kapazitaet_wareneingang_je_tag)]})
	# 1d) Wiederkehrende Engpaesse (an mehreren Tagen ueberfuellt) entlasten: Kreuzung -> Ampelsteuerung, Strecke -> Ausbau
	for sp in ind.verkehr.get("engpaesse", []):
		if actions.size() >= MAX_ACTIONS:
			break
		if not bool(sp.wiederkehrend) or str(sp.massnahme) != "":
			continue
		var kind_t := "ampel" if bool(sp.kreuzung) else ("ladezone" if bool(sp.get("neben_gebaeude", false)) else "ausbau")
		if float(ind.haushalt.verfuegbar) > float(TrafficFlow.MEASURES[kind_t].cost) * 2.0:
			actions.append({"action": "improve_traffic", "kind": kind_t, "x": int(sp.x), "y": int(sp.y),
				"reason": "Engpass auf (%d,%d) an %d Tagen überfüllt, %d Fahrzeugsekunden verloren." % [int(sp.x), int(sp.y), int(sp.tage_mit_stau), int(sp.verlorene_fahrzeugsekunden)]})
			break
	# 1e) Rathaus: lange Antragswarteschlange bei ausgelastetem Bauamt -> Stellen ausschreiben (nur mit Reserve in der Kasse)
	var th: Dictionary = ind.get("rathaus", {})
	if actions.size() < MAX_ACTIONS and not th.is_empty() and int(th.offene_stellen) == 0 and int(th.soll_gesamt) < int(th.grenzen.max_gesamt) - 2 \
			and int(ind.bauantraege.warteschlange) > 6.0 * maxf(1.0, float(ind.bauantraege.kapazitaet_je_tag)) and float(ind.haushalt.verfuegbar) > 60000.0:
		actions.append({"action": "hire_staff", "abteilung": "bauamt", "anzahl": 2,
			"reason": "%d Anträge in der Warteschlange bei %.1f Bearbeitungspunkten je Tag; das Bauamt wird verstärkt." % [int(ind.bauantraege.warteschlange), float(ind.bauantraege.kapazitaet_je_tag)]})
		notes.append("Bauamt verstärkt")
	# 1f) Pruefdienst: nur bei sichtbaren Auffaelligkeiten (schlechte Fahrzeuge, erschoepfte Beschaeftigte), hoechstens eine Pruefung je Runde
	var insp: Dictionary = ind.get("pruefungen", {})
	if actions.size() < MAX_ACTIONS and int(insp.get("frei_diesen_monat", 0)) > 0:
		for f in insp.firmen:
			if bool(f.gesperrt) or (int(f.tage_seit_pruefung) >= 0 and int(f.tage_seit_pruefung) < 30):
				continue   # Regel: dieselbe Firma hoechstens alle 30 Tage
			if float(f.fahrzeugzustand_mittel) < 50.0:
				actions.append({"action": "order_inspection", "firma": int(f.firma), "art": "fahrzeuge", "reason": "Fahrzeuge von %s im Mittel nur %.0f %% Zustand." % [f.name, float(f.fahrzeugzustand_mittel)]})
				break
			if int(f.erschoepfte_beschaeftigte) >= 2:
				actions.append({"action": "order_inspection", "firma": int(f.firma), "art": "arbeitssicherheit", "reason": "%d erschöpfte Beschäftigte bei %s im Einsatz." % [int(f.erschoepfte_beschaeftigte), f.name]})
				break
	# 1g) Staedtischer Auftragspool: musste der Stadtfuhrpark oft einspringen, Verguetung anheben (bei vielen Faellen Rahmenvertrag mit der
	#     zuverlaessigsten Firma); laeuft alles, Verguetung schrittweise zurueck auf 1,0
	var tp: Dictionary = ind.stadtlager.get("transportpool", {})
	if actions.size() < MAX_ACTIONS and not tp.is_empty() and tp.vergabe == "ausschreibung" and int(tp.tage_seit_aenderung) >= 10:
		var fb := int(tp.stadtfuhrpark_einsaetze_30_tage)
		var price := float(tp.preisfaktor)
		var best: Dictionary = {}
		for f in tp.firmen:
			if float(f.ruf) >= 60.0 and float(f.anteil_30_tage) < 0.4 and int(f.erledigt) >= 5 and (best.is_empty() or float(f.puenktlich_quote) > float(best.puenktlich_quote)):
				best = f
		if fb >= 4 and not best.is_empty() and float(best.puenktlich_quote) >= 0.8:
			actions.append({"action": "set_city_freight", "vergabe": "rahmenvertrag", "firma": int(best.firma), "tage": 20, "preisfaktor": price,
				"reason": "Stadtfuhrpark musste %d-mal einspringen; %s ist zu %.0f %% pünktlich (Ruf %.0f)." % [fb, best.name, float(best.puenktlich_quote) * 100.0, float(best.ruf)]})
		elif fb >= 2 and price < 1.3 - 0.001:
			actions.append({"action": "set_city_freight", "vergabe": "ausschreibung", "preisfaktor": minf(1.3, price + 0.1), "reason": "Stadtfuhrpark musste %d-mal einspringen; Vergütung wird angehoben." % fb})
		elif fb == 0 and price > 1.0 + 0.001:
			actions.append({"action": "set_city_freight", "vergabe": "ausschreibung", "preisfaktor": maxf(1.0, price - 0.1), "reason": "Alle Stadtaufträge wurden übernommen; Vergütung wird gesenkt."})
	# 1h) Strassenwartung: Abschnitte unter 45 % -> freie eigene Bautrupps, sonst Baufirma bei genug Mitteln (hoechstens zwei je Runde)
	var st: Dictionary = ind.get("strassen", {})
	if not st.is_empty():
		var crews_free := int(st.bautrupps_frei)
		var firms_free := int(st.baufirmen_frei)
		var cash := float(ind.haushalt.verfuegbar)
		var given := 0
		for w in st.schlechteste:
			if actions.size() >= MAX_ACTIONS or given >= 2 or float(w.zustand) >= 45.0:
				break
			if crews_free > 0 and cash > float(st.kosten.eigen) * 2.0:
				actions.append({"action": "repair_road", "abschnitt": w.abschnitt, "ausfuehrung": "eigen", "reason": "Abschnitt %s nur noch %.0f %%; Bautrupp der Straßenmeisterei frei." % [w.abschnitt, float(w.zustand)]})
				crews_free -= 1
				cash -= float(st.kosten.eigen)
			elif firms_free > 0 and float(w.zustand) < 30.0 and cash > float(st.kosten.firma) * 3.0:
				actions.append({"action": "repair_road", "abschnitt": w.abschnitt, "ausfuehrung": "firma", "reason": "Abschnitt %s nur noch %.0f %%, alle eigenen Trupps im Einsatz; Baufirma beauftragt." % [w.abschnitt, float(w.zustand)]})
				firms_free -= 1
				cash -= float(st.kosten.firma)
			else:
				break
			given += 1
	# 1h1) Strom: Netz ueber 85 % ausgelastet oder Betriebe abgeschaltet -> ausbauen (nur mit Reserve)
	var pw: Dictionary = ind.get("strom", {})
	if actions.size() < MAX_ACTIONS and not pw.is_empty() and not bool(pw.ausbau_laeuft) and (float(pw.auslastung) > 0.85 or int(pw.abgeschaltete_betriebe) > 0) 			and float(ind.haushalt.verfuegbar) > float(pw.ausbau.kosten) * 1.5:
		actions.append({"action": "expand_power", "reason": "Stromnetz zu %.0f %% ausgelastet, %d Betriebe ohne Strom." % [float(pw.auslastung) * 100.0, int(pw.abgeschaltete_betriebe)]})
	# 1h1-) Hafen: Einfuhren stauen sich ueber mehr als eine Schiffsladung -> naechste Stufe, wenn die Kasse das 1,5-fache traegt
	var hf: Dictionary = ind.get("hafen", {})
	if actions.size() < MAX_ACTIONS and not hf.is_empty() and not bool(hf.ausbau_laeuft) and not hf.ausbau.is_empty() 			and float(hf.rueckstau_schiffsladungen) > 1.0 and float(ind.haushalt.verfuegbar) > float(hf.ausbau.kosten) * 1.5:
		actions.append({"action": "expand_harbor", "reason": "Einfuhren für %.1f Schiffsladungen warten am Hafen; %s schafft %d statt %d Einheiten je Schiff." % [float(hf.rueckstau_schiffsladungen), hf.ausbau.ziel, int(hf.ausbau.ladung), int(hf.ladung_je_schiff)]})
	# 1h1a) Bergbau: Abbauantraege genehmigen (Arbeitsplaetze, Export, Abgabe); Abgabe nach Partei
	var mb: Dictionary = ind.get("bergbau", {})
	for ap in mb.get("abbauantraege", []):
		if actions.size() >= MAX_ACTIONS:
			break
		var pct := 12.0 if party == "haushalt" else (6.0 if party == "wachstum" else 8.0)
		actions.append({"action": "decide_mining", "grundstueck": ap.grundstueck, "decision": "genehmigen", "abgabe_prozent": pct,
			"reason": "%s auf %s bringt Arbeitsplätze und Exporte; Förderabgabe %d %% für die Stadtkasse." % [Production.item_name(str(ap.rohstoff)), ap.grundstueck, int(pct)]})
	# 1h1b) Erschliessung (Ersatz fuer die KI): Antraege genehmigen, wenn die Stadt ihren Anteil tragen kann; Auftrag direkt an eine freie
	# Unternehmer-Baufirma (die Stadt gibt den Unternehmen Arbeit), sonst Ausschreibung. Eigene Bruecke nur bei Wohnungsnot.
	var er: Dictionary = ind.get("erschliessung", {})
	if not er.is_empty():
		var free_firm := -1
		for f in er.baufirmen:
			if str(f.status) == "aktiv" and int(f.auslastung) < int(f.kapazitaet):
				free_firm = int(f.firma)
				break
		var cash_left := float(ind.haushalt.verfuegbar)
		for ap in er.antraege:
			if actions.size() >= MAX_ACTIONS:
				break
			if cash_left >= float(ap.anteil_stadt) * 1.5:
				var act := {"action": "decide_access", "antrag": ap.id, "decision": "genehmigen", "vergabe": "ausschreibung",
					"reason": "%s erschließt %s (%s); die Stadt trägt %s für Brücken und gewinnt eine neue Zufahrt." % [ap.name, ap.grundstueck, ap.art, Catalog.money(float(ap.anteil_stadt))]}
				if free_firm >= 0:
					act.vergabe = "direkt"
					act.firma = free_firm
					act.reason += " Bauauftrag direkt an eine ortsansässige Baufirma."
				actions.append(act)
				cash_left -= float(ap.anteil_stadt)
			else:
				actions.append({"action": "decide_access", "antrag": ap.id, "decision": "ablehnen", "reason": "Stadtkasse kann den Anteil von %s derzeit nicht tragen." % Catalog.money(float(ap.anteil_stadt))})
		var mine: int = er.laufend.filter(func(j): return int(j.unternehmen) < 0).size()
		if actions.size() < MAX_ACTIONS and mine == 0 and not er.vorschlaege.is_empty() and party != "haushalt" and waiting > 0 and int(ind.versorgung.davon_voll_erschlossen) < 3:
			var bv: Dictionary = er.vorschlaege[0]
			if cash_left > float(bv.kosten) * 3.0:
				var act2 := {"action": "build_bridge", "grundstueck": bv.grundstueck, "reason": "%d Haushalte suchen Wohnraum, diesseits kaum erschlossenes Bauland; %s zu %s (%s, etwa %d Tage)." % [waiting,
					bv.art, bv.grundstueck, Catalog.money(float(bv.kosten)), int(bv.tage)]}
				if free_firm >= 0:
					act2.vergabe = "direkt"
					act2.firma = free_firm
				actions.append(act2)
	# 1h2) Rivalitaet: heftigsten Streit (ab 60) schlichten, sonst Dauer-Eskalierer (3+ Vorfaelle in 7 Tagen) verwarnen
	var rv: Dictionary = ind.get("rivalitaet", {})
	if actions.size() < MAX_ACTIONS and not rv.is_empty():
		var done := false
		for p in rv.paare:
			if int(p.spannung) >= 60 and not bool(p.stillhalteabkommen):
				actions.append({"action": "mediate_rivalry", "firma_a": int(p.firmen[0]), "firma_b": int(p.firmen[1]), "tage": 7,
					"reason": "Streit zwischen %s und %s auf Stufe %s (Spannung %d)." % [p.namen[0], p.namen[1], p.stufe, int(p.spannung)]})
				done = true
				break
		if not done:
			for f in rv.get("verursacher", []):
				if int(f.eskalationen_7_tage) >= 3 and not bool(f.verwarnt):
					actions.append({"action": "warn_company", "firma": int(f.firma), "reason": "%s hat in 7 Tagen %d-mal eskaliert." % [f.name, int(f.eskalationen_7_tage)]})
					break
	# 1i) Polizei: viele unaufgeklaerte Diebstaehle -> zwei Stellen mehr (nur mit Reserve)
	var sg: Dictionary = ind.get("sicherheit_gesundheit", {})
	if actions.size() < MAX_ACTIONS and not sg.is_empty() and int(sg.get("gesucht", 0)) >= 6 and float(ind.haushalt.verfuegbar) > 80000.0 			and int(ind.arbeit.offene_stellen_nach_arbeitgeber.get("polizei", 0)) == 0:
		actions.append({"action": "set_public_staff", "bereich": "polizei", "aenderung": 2, "reason": "%d Tatverdächtige auf freiem Fuß bei %d Polizeikräften." % [int(sg.gesucht), int(sg.polizei_personal)]})
	# 1j) Weiterbildung foerdern, solange viele lange Arbeitslose und offene Stellen da sind; Foerderung beenden, wenn das Geld knapp wird
	var bm: Dictionary = ind.get("bevoelkerungsmodell", {})
	if actions.size() < MAX_ACTIONS and not bm.is_empty():
		var support := int(bm.get("weiterbildung_foerderung_prozent", 0))
		var jobless_share := 1.0 - float(ind.arbeit.quote)
		if support == 0 and jobless_share > 0.12 and int(ind.arbeit.offene_stellen) > 10 and float(ind.haushalt.verfuegbar) > 100000.0:
			actions.append({"action": "support_training", "foerderung_prozent": 50, "reason": "%.0f %% ohne Arbeit bei %d offenen Stellen; Weiterbildung öffnet Fachkraftstellen." % [jobless_share * 100.0, int(ind.arbeit.offene_stellen)]})
		elif support > 0 and (float(ind.haushalt.verfuegbar) < 40000.0 or jobless_share < 0.07):
			actions.append({"action": "support_training", "foerderung_prozent": 0, "reason": "Förderung beendet (Kasse %s, Arbeitslosenanteil %.0f %%)." % [Catalog.money(float(ind.haushalt.verfuegbar)), jobless_share * 100.0]})
	# 1k) Stadtmarketing bei Leerstand und offenen Stellen, wenn keine Kampagne laeuft
	var bv: Dictionary = ind.bevoelkerung
	if actions.size() < MAX_ACTIONS and int(bv.get("monat", 0)) > int(bv.get("stadtmarketing_bis_monat", -1)) and float(housing.leerstand) > 0.06 \
			and int(ind.arbeit.offene_stellen) > 20 and float(ind.haushalt.verfuegbar) > 80000.0:
		actions.append({"action": "city_marketing", "budget": 10000.0, "reason": "Leerstand %.1f %% und %d offene Stellen: Zuzug werben." % [float(housing.leerstand) * 100.0, int(ind.arbeit.offene_stellen)]})
	# 1l) Hof-Bauantraege der Firmen: Kran mit Laermschutz-Auflage, sonst genehmigen
	for hp in ind.get("hof_bauantraege", []):
		if actions.size() >= MAX_ACTIONS:
			break
		if hp.status == "zur_entscheidung":
			var cond: bool = hp.typ == "kran"
			actions.append({"action": "decide_yard_permit", "antrag": hp.id, "decision": "auflagen" if cond else "genehmigen",
				"reason": "Lärmschutz zum Wohngebiet" if cond else "%s fügt sich in das Gewerbegebiet ein." % hp.gebaeude})
	# 2) Bedarf bestimmen (Schwellen je Partei)
	var need := waiting > 0
	match party:
		"haushalt":
			need = float(waiting) / stock > 0.02
		"soziales":
			need = waiting > 0 or float(housing.mietindex) > 105.0
	var budget := float(ind.haushalt.verfuegbar)
	var plans: Array = ind.plaene
	# 3) beschlossene Quartiere: Grundstuecke zur Vergabe freigeben
	for pl in plans:
		if actions.size() >= MAX_ACTIONS:
			break
		if pl.status == "beschlossen" and not pl.ids_zur_entwicklung.is_empty():
			actions.append({"action": "offer_parcels", "parcel_ids": pl.ids_zur_entwicklung, "price_factor": 0.9 if party == "soziales" else 1.0,
				"reason": "Quartier %s ist beschlossen; Wohnungssuchende: %d." % [pl.name, waiting]})
	# 4) Erschliessung der Quartiere, Ausschreibung beschlossener Projekte
	for prj in ind.projekte:
		if actions.size() >= MAX_ACTIONS:
			break
		if prj.status == "beschlossen":
			actions.append({"action": "tender", "project_id": prj.id, "reason": "Projekt ist beschlossen und finanziert (%s)." % Catalog.money(float(prj.kosten))})
	# 5) neues Quartier, wenn Bedarf besteht und kein offenes Angebot vorhanden ist
	var open_plans := plans.filter(func(p): return p.status == "beschlossen" and not p.ids_zur_entwicklung.is_empty()).size()
	if need and open_plans == 0 and actions.size() < MAX_ACTIONS and not ind.entwicklungsvorschlaege.is_empty() and plans.size() < 8:
		var c: Dictionary = ind.entwicklungsvorschlaege[0]
		actions.append({"action": "designate_quarter", "name": "Quartier %d (%s)" % [plans.size() + 1, str(c.zone).capitalize()], "parcel_ids": c.grundstuecke, "zone": c.zone,
			"reason": "%d wohnungssuchende Haushalte, Leerstand %.1f %%, Mietindex %.0f; nächstgelegener Vorschlag mit %d erschlossenen Grundstücken." % [waiting, float(housing.leerstand) * 100.0, float(housing.mietindex), int(c.davon_voll_erschlossen)]})
	# 5b) Flaechenplanung: fehlt eine Zone deutlich (Richtwert -5 Punkte), den Umwidmungsvorschlag ausweisen (hoechstens ein offenes Quartier)
	var fp: Dictionary = ind.get("flaechenplanung", {})
	if open_plans == 0 and actions.size() < MAX_ACTIONS and not fp.is_empty() and not fp.umwidmung_vorschlaege.is_empty() and plans.size() < 12 			and not actions.any(func(x): return x.action == "designate_quarter"):
		var rz: Dictionary = fp.umwidmung_vorschlaege[0]
		var zi: Dictionary = fp.zonen[rz.zone]
		actions.append({"action": "designate_quarter", "name": "%s %d" % [Parcels.ZONES[rz.zone].label, plans.size() + 1], "parcel_ids": rz.grundstuecke, "zone": rz.zone,
			"reason": "%s nur %.0f %% der Fläche (Richtwert %.0f %%): mehr Geschäfte, Arbeitsplätze und Steuern; Lage %d Felder vom Rathaus." % [Parcels.ZONES[rz.zone].label,
				float(zi.anteil) * 100.0, float(zi.richtwert) * 100.0, int(rz.entfernung_rathaus)]})
	# 6) Erschliessung planen fuer beschlossene Quartiere ohne Projekt
	for pl in plans:
		if actions.size() >= MAX_ACTIONS:
			break
		if pl.status == "beschlossen" and budget > 20000.0 and ind.projekte.filter(func(p): return pl.ids_zur_entwicklung.any(func(id): return id in p.grundstuecke)).is_empty() and not pl.ids_zur_entwicklung.is_empty():
			actions.append({"action": "plan_infrastructure", "parcel_ids": pl.ids_zur_entwicklung, "reason": "Quartier %s braucht Anschlüsse; verfügbare Mittel %s." % [pl.name, Catalog.money(budget)]})
	if actions.is_empty():
		actions.append({"action": "wait"})
	var summary := "Lage: %d wohnungssuchende Haushalte, Leerstand %.1f %%, Beschäftigung %.0f %%, %d Anträge zur Entscheidung. %s" % [waiting, float(housing.leerstand) * 100.0,
		float(ind.arbeit.quote) * 100.0, ind.bauantraege.zur_entscheidung.size(), ("Maßnahmen: " + ", ".join(actions.map(func(a): return a.action))) if actions[0].action != "wait" else "Keine Maßnahme nötig."]
	return {"summary": summary, "actions": actions.slice(0, MAX_ACTIONS), "memory": "; ".join(notes)}
