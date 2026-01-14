extends Node3D

@export var game: MafiaGame
@export var ui: MarginContainer
@export var player_scene: PackedScene
@export var openai: OpenAI

@export_category("Markers")
@export var town_square: Marker3D
@export var doctor_spawn: Marker3D
@export var sheriff_spawn: Marker3D
@export var mafia_spawn: Marker3D

@export_category("Cameras")
@export var town_camera: Camera3D
@export var doctor_camera: Camera3D
@export var sheriff_camera: Camera3D
@export var mafia_camera: Camera3D

var player_map: Dictionary[Player, Node3D]
var clone_map: Dictionary[Player, Node3D]
const PLAYER_DISTANCE_FROM_CENTER: int = 2

signal tts_done

func _ready() -> void:
	Debug.debug(self, "Connecting signals...")
	
	game.day_started.connect(_on_day_started)
	game.game_ended.connect(_on_game_ended)
	game.night_started.connect(_on_night_started)
	game.player_killed.connect(_on_player_killed)
	game.player_spoke.connect(_on_player_spoke)
	game.player_thinking.connect(_on_player_thinking)
	game.player_voted.connect(_on_player_voted)
	game.players_created.connect(_on_players_created)
	game.scene_changed.connect(_on_scene_changed)
	
	Debug.debug(self, "Starting game...")
	game.run_game()

func _on_players_created(players: Array[Player]) -> void:
	var mafia: int = players.filter(func (player: Player) -> bool: return player.role == MafiaGame.Role.MAFIA).size()
	var mafia_index: int = 0
	
	for i in range(players.size()):
		var instance: Node3D = player_scene.instantiate()
		var angle: float = 2 * PI / players.size() * i
		var offset: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, angle) * PLAYER_DISTANCE_FROM_CENTER
		
		$Players.add_child(instance)
		instance.global_position = town_square.global_position + offset
		instance.look_at(town_square.global_position)
		
		var data: Dictionary = players[i].extra_config
		instance.set_face(data.face)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(data.body_colour)
		instance.set_body(material)
		instance.set_text(players[i])
		
		player_map[players[i]] = instance
		
		if players[i].role == MafiaGame.Role.TOWN:
			continue
		
		var clone: Node3D = player_scene.instantiate()
		clone_map[players[i]] = clone
		$Players.add_child(clone)
		clone.set_face(data.face)
		clone.set_body(material)
		clone.set_text(players[i])
		
		match players[i].role:
			MafiaGame.Role.DOCTOR:
				clone.global_position = doctor_spawn.global_position
				clone.scale = Vector3.ONE * 0.6
				clone.rotation_degrees.y = 45
		
			MafiaGame.Role.SHERIFF:
				clone.global_position = sheriff_spawn.global_position
				clone.scale = Vector3.ONE * 0.6
				clone.rotation_degrees.y = 270
			
			MafiaGame.Role.MAFIA:
				angle = 2 * PI / mafia * mafia_index
				offset = Vector3.FORWARD.rotated(Vector3.UP, angle) * 0.8
				clone.global_position = mafia_spawn.global_position + offset
				clone.look_at(mafia_camera.global_position)
				clone.global_rotation.z = 0
				clone.global_rotation.x = 0
				
				mafia_index += 1
	
	game.signal_handled.emit()

func _on_player_killed(player: Player) -> void:
	player_map[player].hide()
	
	game.signal_handled.emit()

func _on_day_started(day: int, players_left: Array[Player]) -> void:
	$WorldEnvironment.environment = load("res://assets/resources/day_environment.tres")
	$NightSun.hide()
	$DaySun.show()
	for lamp in $Town/Lamps.get_children():
		lamp.off()
	
	game.signal_handled.emit()

func _on_night_started(day: int) -> void:
	$WorldEnvironment.environment = load("res://assets/resources/night_environment.tres")
	$DaySun.hide()
	$NightSun.show()
	for lamp in $Town/Lamps.get_children():
		lamp.on()
	
	game.signal_handled.emit()

func _on_scene_changed(scene_name: String, day: int) -> void:
	var camera_map: Dictionary[String, Camera3D] = {
		"town_square": town_camera,
		"doctor_office": doctor_camera,
		"sheriff_office": sheriff_camera,
		"mafia_hideout": mafia_camera
	}
	if scene_name in camera_map:
		for camera in camera_map.values():
			camera.current = false
		
		camera_map[scene_name].current = true
	
	game.signal_handled.emit()

func _on_player_thinking(player: Player, context: String) -> void:
	ui.show_text("")
	
	match context:
		"mafia_discussion":
			mafia_camera.position = Vector3(0, 0, 0.2)
			var old: Vector3 = mafia_camera.global_rotation
			mafia_camera.look_at(clone_map[player].global_position)
			mafia_camera.global_rotation = Vector3(old.x, mafia_camera.global_rotation.y, old.z)
			var backwards: Vector3 = -mafia_camera.basis.x
			mafia_camera.global_position += backwards * 0.6
			
		"town_discussion", "voting":
			var old: Vector3 = town_camera.global_rotation
			town_camera.look_at(player_map[player].global_position)
			var pointed: float = town_camera.global_rotation.y
			town_camera.global_rotation = old
			
			var tween: Tween = town_camera.create_tween()
			tween.set_ease(Tween.EASE_IN)
			tween.tween_property(town_camera, "global_rotation", Vector3(old.x, pointed, old.z), 0.2)
	
	game.signal_handled.emit()

func _on_player_spoke(player: Player, message: String, context: String) -> void:
	message = message.strip_edges()
	var chunks: Array = ui.get_chunks(message)
	Debug.debug(self, "Speech chunks:", chunks)
	var tts_results: Dictionary = {}
	var generate_speech: Callable = (func (chunk): tts_results[chunk] = await openai.tts("gpt-4o-mini-tts", chunk, "alloy"); if chunks.size() == tts_results.size(): tts_done.emit())
	
	for chunk in chunks:
		generate_speech.call(chunk)
	
	Debug.info(self, "Creating TTS clips...")
	await tts_done
	
	for text in chunks:
		ui.show_text(text)
		await ui.play_sound(tts_results[text])
		ui.show_text("")
	
	game.signal_handled.emit()

func _on_game_ended(winner: String) -> void:
	game.signal_handled.emit()

func _on_player_voted(player: Player, target: String, vote_type: String) -> void:
	game.signal_handled.emit()
