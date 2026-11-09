class_name DecisionText
extends RefCounted
## Verstaendliche Darstellung von KI-Entscheidungen aus dem Entscheidungsprotokoll (DecisionLog) - nur aus gespeicherten Fakten:
## Ziel und Kurzbegruendung des Modells (falls angegeben), Lage zum Entscheidungszeitpunkt (Momentaufnahme), Pruefung der Engine,
## tatsaechliche Ausfuehrung und gemessene Folgen. Fehlende Angaben werden als unbekannt ausgewiesen, nie erfunden.

## Aktion -> [Ueberschrift (mit %s = Name), Absicht (allgemeiner Zweck der Aktion, keine Behauptung ueber das Modell), moegliche Risiken]
const ACTIONS := {
	"buy_vehicle": ["%s kauft ein Fahrzeug", "mehr Transportkapazität", "Der Kauf bindet Geld; laufende Fahrzeugkosten (Treibstoff, Reparaturen, Abschreibung) steigen."],
	"sell_vehicle": ["%s verkauft ein Fahrzeug", "Geld freisetzen oder Kosten senken", "Weniger Kapazität für Aufträge."],
	"accept_contract": ["%s nimmt einen Transportauftrag an", "Umsatz durch einen Auftrag", "Wird die Frist verpasst, drohen Vertragsstrafe und Rufverlust."],
	"assign_transport": ["%s plant eine Lieferung ein", "einen angenommenen Auftrag ausführen", "Das Fahrzeug ist für die Dauer der Fahrt gebunden."],
	"assign_worker_task": ["%s verteilt eine Aufgabe", "Personal sinnvoll einsetzen", "Eine falsch verteilte Aufgabe bindet Personal."],
	"collect_contracts": ["%s sucht neue Aufträge", "mehr Auftragsangebote kennen", "Kostet Zeit der Figur."],
	"recruit_worker": ["%s stellt jemanden ein", "Personal für Fahrzeuge oder Betriebe", "Lohnkosten steigen dauerhaft."],
	"dismiss_worker": ["%s entlässt eine Kraft", "Lohnkosten senken", "Fehlt die Kraft später, bleiben Fahrzeuge stehen."],
	"take_loan": ["%s nimmt einen Kredit auf", "Liquidität für Investitionen", "Zinsen und Tilgung belasten künftige Monate."],
	"request_loan": ["%s beantragt einen Bankkredit", "Liquidität für Investitionen", "Zinsen und Tilgung belasten künftige Monate."],
	"repay_loan": ["%s tilgt einen Kredit", "Schulden und Zinsen senken", "Weniger Bargeld als Reserve."],
	"found_business": ["%s gründet einen Betrieb", "ein zweites Standbein neben dem Transport", "Hohe Anfangsinvestition; der Betrieb braucht Personal und Rohstoffe."],
	"place_building": ["%s baut auf dem Betriebshof", "den Hof erweitern (Stellplätze, Büro, Lager)", "Baukosten; Nutzen erst nach Fertigstellung."],
	"set_strategy": ["%s ändert die Unternehmensstrategie", "eine neue Linie für künftige Entscheidungen", "Ein Strategiewechsel wirkt erst über mehrere Tage."],
	"set_plan": ["%s legt einen Plan fest", "mehrere Schritte nacheinander umsetzen", "Pläne binden Geld und Personal über Tage."],
	"execute_plan_step": ["%s führt einen Planschritt aus", "den aktuellen Plan voranbringen", "Kosten des Planschritts."],
	"buy_supplies": ["%s kauft Betriebsmittel", "Treibstoff oder Ersatzteile vorrätig haben", "Geld ist im Vorrat gebunden."],
	"schedule_refueling": ["%s legt eine Nachtank-Regel fest", "Treibstoff automatisch nachbestellen", "Regel bestellt auch bei hohen Preisen."],
	"repair_vehicle": ["%s lässt ein Fahrzeug reparieren", "Pannen vermeiden", "Werkstattkosten, Fahrzeug fällt kurz aus."],
	"hub_buy": ["%s kauft im Großlager", "Ware für Betrieb oder Weiterverkauf", "Ware muss mit eigenem Fahrzeug abgeholt werden."],
	"hub_sell": ["%s verkauft an das Großlager", "Lagerbestand zu Geld machen", "Bezahlt wird erst bei Anlieferung."],
	"offer_trade": ["%s macht einem Konkurrenten ein Angebot", "Zusammenarbeit oder Weitergabe eines Auftrags", "Der Partner kann ablehnen."],
	"accept_trade": ["%s nimmt ein Angebot an", "ein Geschäft mit einem anderen Unternehmen", "Verpflichtung gegenüber dem Partner."],
	"send_message": ["%s schreibt einer anderen Firma", "Absprache oder Verhandlung", "–"],
	"move_to": ["%s schickt die Figur los", "einen Ort aufsuchen (Händler, Arbeitsamt, Kunde)", "Die Figur ist unterwegs."],
	"install_internet": ["%s richtet Internet ein", "Aufträge direkt im Büro sammeln", "Monatliche Kosten."],
	"upgrade_business": ["%s baut einen Betrieb aus", "mehr Leistung des Betriebs", "Investition; Ausbau dauert Tage."],
	"quote_transport_help": ["%s bietet einer anderen Firma Transporthilfe an", "freie Fahrzeuge auslasten", "Eigene Aufträge könnten warten müssen."],
	"request_transport_help": ["%s bittet eine andere Firma um Transporthilfe", "einen Auftrag trotz Engpass erfüllen", "Ein Teil des Erlöses geht an den Partner."],
	"assign_vehicle": ["%s teilt ein Fahrzeug einem Auftrag zu", "einen Auftrag ausführen", "Das Fahrzeug ist für die Fahrt gebunden."],
	"plan_tour": ["%s plant eine Sammeltour", "mehrere Aufträge in einer Fahrt erledigen", "Verzögert sich ein Stopp, wird die ganze Tour später."],
	"clear_tour": ["%s löst eine geplante Tour auf", "Fahrzeug neu einplanen", "–"],
	"update_plan_step": ["%s passt einen Planschritt an", "den Plan an die Lage anpassen", "–"],
	"cancel_plan": ["%s verwirft den aktuellen Plan", "neu planen", "Bereits ausgegebenes Geld ist gebunden."],
	"start_experiment": ["%s probiert eine neue Vorgehensweise aus", "herausfinden, was besser funktioniert", "Das Experiment kann Geld kosten."],
	"end_experiment": ["%s wertet ein Experiment aus", "aus Erfahrung lernen", "–"],
	"remember": ["%s merkt sich etwas", "Erfahrung für spätere Entscheidungen", "–"],
	"forget": ["%s verwirft eine Notiz", "veraltetes Wissen löschen", "–"],
	"move_vehicle": ["%s stellt ein Fahrzeug um", "Fahrzeug näher an künftige Aufträge bringen", "Leerfahrt kostet Treibstoff."],
	"build_office": ["%s baut ein Büro", "Verwaltung und mehr Aufträge gleichzeitig", "Baukosten und laufende Bürokosten."],
	"upgrade_office": ["%s baut das Büro aus", "mehr Aufträge gleichzeitig bearbeiten", "Investition; höhere laufende Kosten."],
	"rent_depot": ["%s mietet ein Depot", "mehr Stellplätze und ein zweiter Standort", "Monatliche Miete."],
	"cancel_depot": ["%s kündigt ein Depot", "Mietkosten sparen", "Weniger Stellplätze."],
	"bid_auction": ["%s bietet bei einer Versteigerung", "Grundstück oder Fahrzeug günstig erwerben", "Ein Gebot bindet Geld; andere können überbieten."],
	"buy_material": ["%s kauft Baumaterial", "Material für eine Baustelle liefern", "Ware muss abgeholt und verkauft werden."],
	"sell_material": ["%s verkauft Material", "Lager zu Geld machen", "–"],
	"bau_lieferung": ["%s übernimmt eine Baustofflieferung", "Umsatz mit Baustellenlogistik", "Frist der Baustelle."],
	"change_company_form": ["%s ändert die Rechtsform", "Haftung oder Kreditwürdigkeit verbessern", "Gebühren und Mindestkapital."],
	"deposit_money": ["%s legt Geld an", "Zinsen auf Überschüsse", "Geld ist nicht sofort verfügbar."],
	"withdraw_deposit": ["%s löst eine Geldanlage auf", "Liquidität erhöhen", "Zinsen entfallen."],
	"counter_offer": ["%s macht ein Gegenangebot", "bessere Bedingungen aushandeln", "Der Partner kann abbrechen."],
	"reject_trade": ["%s lehnt ein Angebot ab", "unvorteilhaftes Geschäft vermeiden", "–"],
	"propose_cooperation": ["%s schlägt eine Kooperation vor", "Zusammenarbeit mit einer anderen Firma", "Der Partner kann ablehnen; Absprachen binden."],
	"offer_cooperation": ["%s bietet eine Kooperation an", "Zusammenarbeit mit einer anderen Firma", "Der Partner kann ablehnen."],
	"poach_customer": ["%s wirbt einen Kunden ab", "Marktanteil gewinnen", "Ärger mit der Konkurrenz."],
	"report_rival": ["%s meldet einen Konkurrenten", "Regelverstöße anzeigen", "Falsche Anzeigen schaden dem Ruf."],
	"book_air_cargo": ["%s bucht Luftfracht", "eiligen Auftrag schnell erfüllen", "Teuer."],
	"explore_deposit": ["%s lässt nach Rohstoffen suchen", "ein Bergwerk vorbereiten", "Probebohrungen kosten Geld und finden evtl. nichts."],
	"request_mining": ["%s beantragt ein Abbaurecht", "Rohstoffe selbst fördern", "Gebühren; Genehmigung durch die Stadt."],
	"build_access": ["%s lässt eine Zufahrt bauen", "Grundstück an die Straße anschließen", "Baukosten."],
	"buy_property": ["%s kauft eine Immobilie", "Mieteinnahmen oder Standort", "Hohe Investition, Unterhalt."],
	"sell_property": ["%s verkauft eine Immobilie", "Geld freisetzen", "Einnahmen entfallen."],
	"buy_it_service": ["%s bucht einen IT-Dienst", "Verwaltung beschleunigen", "Monatliche Kosten."],
	"set_business_price": ["%s ändert einen Verkaufspreis", "mehr Umsatz oder Marge", "Zu hohe Preise vertreiben Kundschaft."],
	"set_hotel_price": ["%s ändert den Hotelpreis", "Auslastung oder Marge verbessern", "Zu hohe Preise vertreiben Gäste."],
	"set_venue_price": ["%s ändert einen Eintrittspreis", "Auslastung oder Marge verbessern", "Zu hohe Preise vertreiben Gäste."],
	"close_business": ["%s schließt einen Betrieb", "Verluste beenden", "Personal wird frei, Investition verloren."],
	"assign_staff": ["%s teilt Personal einem Betrieb zu", "Betrieb am Laufen halten", "Fehlt an anderer Stelle."],
	"block_road": ["%s lässt eine Straße sperren", "Konkurrenz behindern", "Strafen und Rufverlust möglich."],
	"buy_security": ["%s bucht Wachschutz", "Schutz vor Sabotage", "Laufende Kosten."],
	"set_insurance": ["%s ändert die Versicherung", "Risiken absichern", "Prämien."],
	"attempt_sabotage": ["%s versucht eine Sabotage", "Konkurrenz schwächen", "Wird es entdeckt: Strafe und Rufverlust."],
	"wait": ["%s wartet ab", "keine sinnvolle Aktion verfügbar", "–"],
}
const ORIGIN := {"api": "KI-Modell (API)", "plan": "Planschritt der KI", "fallback": "Regelbasierter Ersatzmodus", "foreman": "Vorarbeiter-Routine",
	"auto": "Simulation", "spectator": "Zuschauer", "world": "Stadt"}
## Haeufige Ablehnungen der Engine -> [Ueberschrift, Ursache (Muster im Text), Verbesserung]
const REJECTS := [
	["nicht rechtzeitig machbar", "Auftrag lässt sich nicht fristgerecht erledigen", "Die voraussichtliche Lieferzeit überschreitet die Frist.", "Mehr oder passendere Fahrzeuge, kürzere Wege, bessere Disposition."],
	["nicht (mehr) verfügbar", "Auftrag war schon vergeben", "Ein anderes Unternehmen war schneller oder das Angebot ist abgelaufen.", "Schneller entscheiden; Aufträge in der Nähe bevorzugen."],
	["bereits verkauft", "Fahrzeugangebot war schon weg", "Das Fahrzeug wurde inzwischen verkauft.", "Ein anderes Angebot wählen."],
	["Stellplätze belegt", "Kein Stellplatz für ein weiteres Fahrzeug", "Alle Stellplätze des Hofs sind belegt.", "Stellplätze oder Halle bauen oder ein Depot anmieten."],
	["fehlt für", "Angabe fehlte in der Entscheidung", "Der KI fehlte eine nötige Angabe (z. B. welcher Auftrag).", "–"],
	["Bargeld", "Nicht genug Geld", "Das verfügbare Bargeld reicht nicht.", "Erst Einnahmen erzielen oder einen Kredit aufnehmen."],
	["kein Platz mit Straßenzugang", "Kein geeigneter Bauplatz", "Auf dem gewählten Grundstück passt das Gebäude nicht an eine Straße.", "Ein vorgeschlagenes Grundstück wählen."],
	["Leute ohne Fahrzeug", "Einstellung gesperrt", "Es gibt schon mehr Personal als Fahrzeuge.", "Erst Fahrzeuge kaufen oder Betriebe gründen."],
	["Besuche geplant", "Figur ist ausgelastet", "Die Figur hat schon mehrere Wege vor sich.", "Abwarten, bis die Besuche erledigt sind."],
	["Preisangebot wird bereits verhandelt", "Es läuft schon eine Verhandlung", "Ein früheres Preisangebot ist noch nicht entschieden.", "Die Antwort auf das laufende Angebot abwarten."],
	["kein Fahrer", "Kein Fahrer verfügbar", "Für das Fahrzeug ist niemand eingeteilt.", "Fahrer einstellen oder zuweisen."],
]


static func _name(sim, d: Dictionary) -> String:
	var c = sim.company(int(d.company))
	return c.player_name if c != null else "Unbekannt"


static func action_of(d: Dictionary) -> String:
	return str(d.aktion).split("(")[0].strip_edges()


## Kurzname einer Aktion ohne Firmenname (aus der Ueberschrift), sonst der technische Name lesbar gemacht.
static func _act_label(act: String) -> String:
	if ACTIONS.has(act):
		return str(ACTIONS[act][0]).replace("%s ", "")
	return act.replace("_", " ")


static func headline(sim, d: Dictionary) -> String:
	var act := action_of(d)
	var spec: Array = ACTIONS.get(act, ["%s: " + act.replace("_", " "), "", ""])
	var head: String = str(spec[0]) % _name(sim, d) if str(spec[0]).contains("%s") else str(spec[0])
	if str(d.pruefung) != "ok":
		var rj := reject_info(str(d.ergebnis))
		return "%s – abgelehnt: %s" % [head, rj.title] if not rj.is_empty() else "%s – abgelehnt" % head
	return head


## Ein Satz fuer Ereigniskarten: Ergebnis der Engine in Alltagssprache (ohne IDs am Anfang).
static func summary(sim, d: Dictionary) -> String:
	if str(d.pruefung) != "ok":
		var rj := reject_info(str(d.ergebnis))
		if not rj.is_empty():
			return "%s Folge: nicht ausgeführt." % rj.ursache
		return "Nicht ausgeführt: %s" % str(d.ergebnis).left(140)
	var why := str(d.begruendung).strip_edges()
	return "%s%s" % [str(d.ergebnis).left(150), (" – Begründung der KI: „%s“" % why.left(120)) if why != "" else ""]


static func reject_info(msg: String) -> Dictionary:
	for r in REJECTS:
		if msg.contains(str(r[0])):
			return {"title": str(r[1]), "ursache": str(r[2]), "verbesserung": str(r[3])}
	return {}


## Vollstaendige Erklaerung fuer "Warum?": Abschnitte mit Herkunft der Angaben.
static func explain(sim, d: Dictionary) -> Dictionary:
	var act := action_of(d)
	var spec: Array = ACTIONS.get(act, ["", "", ""])
	var name := _name(sim, d)
	var ok := str(d.pruefung) == "ok"
	var lage: Dictionary = d.get("lage", {})
	var facts: Array = []
	if not lage.is_empty():
		facts.append("Bargeld %s, Schulden %s" % [Catalog.money(float(lage.get("bargeld", 0))), Catalog.money(float(lage.get("schulden", 0)))])
		facts.append("%d Fahrzeuge (%d ohne Auftrag), %d laufende Aufträge von höchstens %d" % [int(lage.get("fahrzeuge", 0)), int(lage.get("frei", 0)),
			int(lage.get("auftraege", 0)), int(lage.get("kapazitaet", 0))])
		facts.append("%d Beschäftigte, Ruf %.0f" % [int(lage.get("personal", 0)), float(lage.get("ruf", 0))])
	for w in d.get("wahrgenommen", []):
		facts.append("Meldung zuvor: %s" % str(w))
	var rj := reject_info(str(d.ergebnis)) if not ok else {}
	var folgen: String = str(sim.decisions.consequences(d)) if ok else ""
	if ok and folgen.strip_edges() == "":
		folgen = "Noch keine messbaren Folgen (z. B. Besuch oder Fahrt läuft noch)."
	var steps := [
		["Vorgeschlagen", "%s: %s" % [ORIGIN.get(str(d.herkunft), str(d.herkunft)), _act_label(act)], true, false],
		["Geprüft", "Regeln der Engine eingehalten" if ok else "abgelehnt: %s" % (rj.get("ursache", str(d.ergebnis).left(120))), ok, false],
		["Angenommen", "ja" if ok else "nein", ok, false],
		["Ausgeführt", str(d.ausgefuehrt), ok and str(d.ausgefuehrt) == "ausgeführt", ok and str(d.ausgefuehrt) != "ausgeführt"],
		["Ergebnis", folgen if ok else "keine Wirkung", ok and not folgen.begins_with("Noch keine"), ok and folgen.begins_with("Noch keine")],
	]
	return {
		"titel": headline(sim, d),
		"wer": "%s (%s)" % [name, sim.company(int(d.company)).company_name if sim.company(int(d.company)) != null else ""],
		"wann": Catalog.game_minutes_to_text(float(d.t)),
		"herkunft": ORIGIN.get(str(d.herkunft), str(d.herkunft)),
		"ziel": str(d.ziel) if str(d.ziel) != "" else "Nicht angegeben – die KI hat für diese Runde kein Ziel genannt.",
		"zweck": str(spec[1]) if str(spec[1]) != "" else "",
		"begruendung": str(d.begruendung) if str(d.begruendung) != "" else "Nicht angegeben – Gründe sind nicht bekannt (Regel-Ersatzmodus oder keine Begründung im Modell).",
		"lage": facts,
		"entscheidung": str(d.ergebnis) if ok else "%s wollte: %s" % [name, _act_label(act)],
		"ablauf": steps,
		"folgen": folgen if ok else ("Keine – die Aktion wurde nicht ausgeführt. " + (("Verbesserung: " + str(rj.verbesserung)) if not rj.is_empty() else "")),
		"risiken": str(spec[2]) if ok and str(spec[2]) != "" else "–",
		"technik": {"aktion": str(d.aktion), "pruefung": str(d.pruefung), "meldung": str(d.ergebnis), "verweise": d.get("refs", {}), "id": str(d.id), "schluessel": str(d.get("key", ""))},
	}
