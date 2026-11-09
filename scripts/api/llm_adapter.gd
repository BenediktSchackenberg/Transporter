class_name LLMAdapter
extends Node
## Schnittstelle fuer Modell-Anbieter. Neue Anbieter erben hiervon und implementieren send()/cancel().
## send() muss sofort zurueckkehren (asynchron) und spaeter genau einmal completed emittieren:
##   result = {ok: bool, content: String, error: String, retry_after: float, usage: {prompt_tokens, completion_tokens, total_tokens}}

signal completed(req_id: int, result: Dictionary)

var config := {}           # base_url, model, api_key, temperature, timeout, max_tokens_per_request
var observation := {}      # nur fuer den Demo-Adapter (eigene Beobachtung des Spielers)


func send(_req_id: int, _messages: Array) -> void:
	push_error("LLMAdapter.send nicht implementiert")


func cancel() -> void:
	pass


func display_name() -> String:
	return "Basis"


## Wartezeit auf eine Antwort in Sekunden (der Wachhund der Firmen-KI bricht danach ab).
func timeout_s() -> float:
	return float(config.get("timeout", 45.0))


static func create(provider: String) -> LLMAdapter:
	match provider:
		"ollama":
			return OllamaAdapter.new()
		"openai", "ionos":
			return OpenAIAdapter.new()
		"anthropic":
			return AnthropicAdapter.new()
		"demo":
			return DemoAdapter.new()
	push_error("Unbekannter Anbieter: " + provider)
	return DemoAdapter.new()
