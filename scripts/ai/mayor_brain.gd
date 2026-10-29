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
		var afford := float(pv.geschaetzte_kosten) <= float(ind.haushalt.verfuegbar)
		if afford and (int(pv.kritikalitaet) >= 2 or str(party) != "haushalt"):
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
