@icon("res://assets/openai.svg")
class_name OpenAI extends Node
@export var api_key: String = ""
@export var base_url: String = "https://api.openai.com/v1"

func _post(endpoint: String, headers: PackedStringArray, payload: Variant) -> Dictionary:
	var request: HTTPRequest = HTTPRequest.new()
	add_child(request)
	
	var error: Error = request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		Debug.error(self, "Failed to request endpoint:", error_string(error))
		return { "error": error, "error_type": "creation_error" }
	
	var data: Array = await request.request_completed
	if data[0] != HTTPRequest.RESULT_SUCCESS:
		Debug.error(self, "Failed to request endpoint, error code", data[0])
		return { "error": data[0], "error_type": "client_error" }
	
	var response_code: int = data[1]
	if response_code < 200 || response_code >= 300:
		Debug.error(self, "Server sent back non-OK response code: HTTP", response_code)
		return { "error": data[3].get_string_from_utf8(), "error_type": "http_error" }
	
	var content_type: Array = ["application/json"]
	for header in data[2]:
		if header.to_lower().begins_with("content-type:"):
			var type_data: String = header.split(":", false, 1)[1].strip_edges()
			content_type = Array(type_data.split(";")).filter(func(item): return item.strip_edges())
	
	var response
	if "application/json" in content_type:
		var json = JSON.new()
		error = json.parse(data[3].get_string_from_utf8())
		if error != OK:
			Debug.error("Failed to parse response JSON at line", json.get_error_line(), ":", json.get_error_message())
			return { "error": json.get_error_message(), "error_type": "parse_error" }
		response = json.get_data()
	else:
		response = data[3]
	
	return {
		"code": response_code,
		"headers": data[2],
		"content": response,
	}

func completion(model: StringName, messages: Array[Dictionary]) -> Dictionary:
	var response: Dictionary = await _post(base_url.path_join("chat/completions"), [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	], {
		"model": model,
		"messages": messages
	})
	
	if "error" in response:
		return {}
	
	return response.content

func responses(model: StringName, input: String, conversation: String = ""):
	var response: Dictionary = await _post(base_url.path_join("responses"), [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	], {
		"model": model,
		"input": input,
		"conversation": conversation
	})
	
	if "error" in response:
		return {}
	return response.content

func tts(model: StringName, text: String, voice: StringName) -> AudioStreamMP3:
	var response: Dictionary = await _post(base_url.path_join("audio/speech"), [
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	], {
		"model": model,
		"input": text,
		"voice": voice
	})
	
	if "error" in response:
		return null
	
	return AudioStreamMP3.load_from_buffer(response.content)
