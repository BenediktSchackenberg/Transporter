# Episodisches Gedächtnis

Was passiert ist, wird als eine JSON-Zeile je Ereignis an `EPISODIC_MEMORY.jsonl` angehängt. Alte Zeilen nie ändern oder löschen.

Format je Zeile:

```json
{"zeit": "Spielzeit aus /observe", "wo": [x, y], "was": "kurz, was ich getan oder erlebt habe", "warum": "optional", "gefuehl": "optional"}
```

Notiere Anfänge und Abschlüsse von Vorhaben, Überraschungen, Fehlschläge und Begegnungen – nicht jeden einzelnen Schritt.
