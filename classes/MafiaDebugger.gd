class_name MafiaDebugger extends Node

@export var game: MafiaGame

func _ready():
	game.scene_changed.connect(_on_scene_changed)
	game.night_started.connect(_on_night_started)
	game.day_started.connect(_on_day_started)
	game.game_ended.connect(_on_game_ended)
	game.player_spoke.connect(_on_player_spoke)
	game.player_voted.connect(_on_player_voted)
	game.player_killed.connect(_on_player_killed)

func _on_scene_changed(scene_name: String, day: int):
	var scene_display = {
		"mafia_hideout": "MAFIA HIDEOUT",
		"sheriff_office": "SHERIFF'S OFFICE",
		"doctor_office": "DOCTOR'S OFFICE",
		"town_square": "TOWN SQUARE"
	}
	Debug.info(self, "\n")
	Debug.info(self, "===", scene_display.get(scene_name, scene_name.to_upper()) + " - Day %d" % day, "===")

func _on_night_started(day: int):
	Debug.info(self, "\n")
	Debug.info(self, "NIGHT %d BEGINS" % day)
	Debug.info(self, "=".repeat(20))

func _on_day_started(day: int, players: Array[Player]):
	var role_display = {
		MafiaGame.Role.TOWN:    "TOWN   ",
		MafiaGame.Role.MAFIA:   "MAFIA  ",
		MafiaGame.Role.SHERIFF: "SHERIFF",
		MafiaGame.Role.DOCTOR:  "DOCTOR "
	}
	Debug.info(self, "\nDAY %d BEGINS" % day)
	Debug.info(self, "Players:")
	
	players.sort_custom(func (a: Player, b: Player) -> bool: return a.role > b.role)
	for player in players:
		Debug.info(self, "  - %s%s %s %s)%s" % [
			"" if player.alive else "[s]",
			role_display[player.role],
			player.name.substr(0, 20).rpad(20),
			"(Alive" if player.alive else " (Dead",
			"" if player.alive else "[/s]"
		])

func _on_game_ended(winner: String):
	Debug.info(self, "\n\n === Game Over ===\n%s WINS!" % winner)

func _on_player_spoke(player: Player, message: String, context: String):
	var context_prefix = {
		"mafia_discussion": "[MAFIA]",
		"sheriff_investigation": "[SHERIFF]",
		"doctor_save": "[DOCTOR]",
		"town_discussion": "[DISCUSSION]",
		"voting": "[VOTING]"
	}
	
	var prefix = context_prefix.get(context, "[UNKNOWN]")
	Debug.info(self, "%s %s: %s" % [prefix, player.name, message])

func _on_player_voted(player: Player, target: String, vote_type: String):
	var vote_emoji = {
		"kill": "🔪",
		"investigate": "🔍",
		"save": "💊",
		"town_discussion": "🗳️"
	}
	
	var emoji = vote_emoji.get(vote_type, "❓")
	Debug.info(self, "  %s %s voted for: %s" % [emoji, player.name, target])

func _on_player_killed(player: Player):
	Debug.info(self, "\n")
	Debug.info(self, "%s HAS BEEN ELIMINATED" % player.name.to_upper())
	Debug.info(self, "   Their role was: %s" % MafiaPrompts.ROLE_NAMES[player.role])
