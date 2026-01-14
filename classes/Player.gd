class_name Player

var name: String
var role: MafiaGame.Role
var alive: bool = true
var messages: Array[Dictionary]
var extra_config: Dictionary
var api_config: Dictionary[StringName, Variant]

func _init(model: StringName, name: String, client: OpenAI) -> void:
	self.name = name
	self.role = MafiaGame.Role.TOWN
	self.api_config.model = model
	self.api_config.client = client

func generate() -> String:
	var client: OpenAI = self.api_config.client
	if not client:
		Debug.critical(self, "OpenAI client not configured for player %s!" % self.name)
		return ""
	
	var response: Dictionary = await client.completion(self.api_config.model, self.messages)
	var choice = response.get("choices", [null])[0]
	if choice:
		var message = choice.get("message", {})
		var content = message.get("content", null)
		if content:
			return content.strip_edges()
		else:
			Debug.error(self, "Model %s returned no content, regenerating." % self.name)
			return (await generate()).strip_edges()
	else:
		Debug.error("Model %s returned no content, regenerating." % self.name)
		return (await generate()).strip_edges()
