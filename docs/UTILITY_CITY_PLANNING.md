# Versorgung als Stadtentscheidung

Die Bürgermeister-KI plant Strom, Frischwasser und Abwasser zusammen mit neuen Vierteln. Die vorhandene Startversorgung bleibt funktionsfähig; für neue Städte und neue Straßen entstehen echte Bauvorhaben. Alte Spielstände mit bereits gebautem Netz behalten ihre Trassen. Alte Spielstände ohne gespeicherte Leitungsdaten übernehmen ihre bestehenden Straßen einmalig als Grundversorgung.

## Strom

Das Kernkraftwerk hat ein eigenes 4×4-Modell. Das Startgebiet besitzt eine vorhandene Leitung; weitere Städte bekommen zunächst nur den begrenzten Notstrom. `PowerNet.connection_options` bietet der KI bis zu drei Trassen mit Standort des Umspannwerks, Länge, Konflikten, Kosten und Bauzeit. `stromtrasse_bauen` schreibt die gewählte Trasse mit Material und Baufirma aus. Bei Abnahme entsteht die sichtbare Leitung. Ein zweiter Weg kann eine Stadt vor dem Ausfall einer einzelnen Trasse schützen. `stromstoerung_priorisieren` bezahlt zusätzliche Netzkräfte; der Netztrupp muss weiter zur Schadstelle fahren.

Das örtliche Stromnetz folgt verbundenen Straßen vom Umspannwerk. Betriebe auf abgetrennten Parzellen können keinen Strom beziehen. Kommunale Einrichtungen verlieren bei fehlender Versorgung einen Teil ihrer wirksamen Leistung.

## Frischwasser und Kanal

`WaterSupply.mains` speichert beide Netze getrennt. Bestehende Startstraßen sind angeschlossen; neue Straßen erhalten Leitungen erst nach `versorgungsleitung_bauen`. Die KI wählt geprüfte, mit dem bestehenden Netz verbundene Bauabschnitte. Frischwasser benötigt Druck vom Wasserwerk oder Hochbehälter. Betriebe ohne Kanalanschluss werden angehalten; bei Haushalten wird nicht abgeführtes Abwasser erfasst und die Stadt belastet. `kommunal_bauen` akzeptiert für neue Wasserwerke, Hochbehälter und Kläranlagen ein geprüftes Grundstück aus `versorgungsanlagen_standorte`.

## Sicht auf der Karte

`UtilityNetworkView` zeichnet farbige Ortsnetze, Ventile, Schächte, Baustellen, Rohrbrüche und animierte Zustände der Anlagen. Die Hochspannungsansicht zeigt die gewählte Trasse bereits während des Baus. **V** schaltet zwischen allen Netzen, Strom, Frischwasser, Kanal und nur den Anlagen um. Wasserwerk, Hochbehälter und Kläranlage besitzen zusätzliche Betriebsdetails; das Kernkraftwerk nutzt eine eigene Grafik.

Ausfälle wirken weiter auf Pumpen, Betriebe, Bahn und Verkehr. Fehlende Anschlüsse und längere Versorgungslücken mindern jetzt auch die Zufriedenheit der Bewohner und die Leistungsfähigkeit kommunaler Dienste.
