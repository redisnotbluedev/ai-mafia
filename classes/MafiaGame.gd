class_name MafiaGame extends Node

@warning_ignore_start("unused_signal")
# Scene/Phase signals
signal scene_changed(scene_name: String, day: int)  # "mafia_hideout", "doctor_office", "sheriff_jail", "town_square"
signal night_started(day: int)
signal day_started(day: int, players_left: Array[Player])
signal game_ended(winner: String)

# Player action signals
signal player_thinking(player: Player, context: String) # context tells which scene/action
signal player_spoke(player: Player, message: String, context: String)
signal player_voted(player: Player, target: String, vote_type: String)
signal player_killed(player: Player)  # Covers both elimination AND night kills
signal players_created(players: Array[Player])
@warning_ignore_restore("unused_signal")

# Emitted when the callback finishes
signal signal_handled

enum Role {
	TOWN,
	MAFIA,
	SHERIFF,
	DOCTOR
}

@export var openai_client: OpenAI
var players: Array[Player]
var day_number: int = 0
var killed_player: Player              # Killed player this round
const DISCUSSION_MAX_MENTION_DEPTH = 4 # Max amount of times to follow mentions before picking a new speaker

func emit(sig: StringName, ...data):
	Debug.debug(self, "Emitting", sig + ",", "connections:", Signal(self, sig).get_connections().size())
	Signal(self, sig).emit.bindv(data).call_deferred()
	Debug.debug(self, "Signal", sig, "emitted")
	if Signal(self, sig).has_connections():
		await signal_handled
	Debug.debug(self, "Signal", sig, "handled")

func run_game():
	setup_players()
	
	while not is_game_over():
		await run_night_phase()
		if is_game_over(): break
		day_number += 1
		await run_day_phase()
		if is_game_over(): break
	
	var winner := "town" if get_alive_players().filter(func(p): return p.role == Role.MAFIA).is_empty() else "mafia"
	await emit(&"game_ended", winner)

func is_game_over() -> bool:
	var alive := get_alive_players()
	var m := alive.filter(func(p): return p.role == Role.MAFIA).size()
	var t := alive.size() - m
	return m <= 0 or m >= t

func get_alive_players() -> Array[Player]:
	return players.filter(func (player: Player): return player.alive)

func get_discussion_max_rounds(player_count: int) -> int:
	var t: float = clamp((player_count - 2.0) / 8.0, 0.0, 1.0)
	var smooth_t: float = t * t * (3.0 - 2.0 * t)
	return round(lerpf(3.0, 10.0, smooth_t))

func setup_players():
	var models: Array = MafiaPrompts.get_models()
	for model in models:
		var player: Player = Player.new(model.model, model.name, openai_client)
		player.extra_config = model
		players.append(player)
	
	var player_distribution = players.duplicate()
	player_distribution.shuffle()
	
	for player in players:
		if player in player_distribution.slice(0, 2):
			player.role = Role.MAFIA
		elif player == player_distribution[2]:
			player.role = Role.SHERIFF
		elif player == player_distribution[3]:
			player.role = Role.DOCTOR
		else:
			player.role = Role.TOWN
		
		player.messages.append({"role": "system", "content": MafiaPrompts.BASE_SYSTEM_PROMPT % [
			player.name,
			MafiaPrompts.ROLE_INFO[player.role].replace(
				"[MAFIA_NAMES]",
				MafiaPrompts.get_mafia_members(players)
			)
		]})
	
	await emit(&"players_created", players)

func run_night_phase():
	await emit(&"night_started", day_number)
	
	await emit(&"scene_changed", "mafia_hideout", day_number)
	await mafia_discussion()
	var kill = await get_mafia_decision()
	
	await emit(&"scene_changed", "sheriff_office", day_number)
	await get_sheriff_investigation()
	
	await emit(&"scene_changed", "doctor_office", day_number)
	var save = await get_doctor_decision()
	
	killed_player = kill
	if kill != save:
		kill.alive = false
		await emit(&"player_killed", kill)

func run_day_phase():
	await emit(&"day_started", day_number, players)
	
	await emit(&"scene_changed", "town_square", day_number)
	announce_night_results()
	await run_discussion_round()
	await run_voting_phase()

func announce_night_results():
	for player in players:
		player.messages.append({
			"role": "user",
			"content": (
				MafiaPrompts.DAY_ANNOUNCEMENT_SAVED if killed_player.alive else MafiaPrompts.DAY_ANNOUNCEMENT
			) % [day_number, killed_player.name, MafiaPrompts.get_players(get_alive_players())]
		})

func mafia_discussion():
	var mafia_players: Array[Player] = get_alive_players().filter(func (player: Player): return player.role == Role.MAFIA)
	
	for player in mafia_players:
		player.messages.append({
			"role": "user",
			"content": MafiaPrompts.NIGHT_DISCUSSION % [day_number, MafiaPrompts.get_players(get_alive_players())]
		})
		
		await emit(&"player_thinking", player, "mafia_discussion")
		var response: String = await player.generate()
		await emit(&"player_spoke", player, response, "mafia_discussion")
		
		var broadcast: Dictionary = {"role": "user", "content": "%s: %s" % [player.name, response]}
		for mafia in mafia_players:
			if mafia != player:
				mafia.messages.append(broadcast)

func run_discussion_round():
	var alive_players: Array[Player] = get_alive_players()
	var current_depth: int = 0
	var rounds: int = 0
	var MAX_ROUNDS: int = get_discussion_max_rounds(alive_players.size())
	var speaker: Player = alive_players.pick_random()
	
	while rounds < MAX_ROUNDS:
		await emit(&"player_thinking", speaker, "town_discussion")
		var response: String = await speaker.generate()
		var broadcast = "%s: %s" % [speaker.name, response]
		
		for player in alive_players:
			if player != speaker:
				player.messages.append({"role": "user", "content": broadcast})
		
		var mentioned: Array = MafiaPrompts.extract_mentions(response, alive_players)
		var lines: Array = Array(response.split("\n"))
		lines.pop_back()
		await emit(&"player_spoke", speaker, "\n".join(lines), "town_discussion")
		
		if current_depth <= DISCUSSION_MAX_MENTION_DEPTH and mentioned.size() > 0:
			speaker = alive_players.filter(func (player: Player) -> bool: return player.name in mentioned).pick_random()
			current_depth += 1
		else:
			current_depth = 0
			speaker = alive_players.pick_random()
		
		rounds += 1

func run_voting_phase():
	var alive_players: Array[Player] = get_alive_players()
	var votes: Dictionary[StringName, int] = {}
	
	for player in alive_players:
		player.messages.append({"role": "user", "content": MafiaPrompts.VOTING_PHASE % [
			day_number,
			MafiaPrompts.get_players(alive_players)
		]})
	
	for player in alive_players:
		await emit(&"player_thinking", player, "voting")
		var response: String = await player.generate()
		var vote_name: StringName = MafiaPrompts.get_vote(response)
		if vote_name == &"none":
			# Just looks cleaner.
			vote_name = &"abstained"
		
		var lines: Array = Array(response.split("\n"))
		lines.pop_back()
		var broadcast = {"role": "user", "content": "%s: %s" % [player.name, "\n".join(lines)]}
		
		await emit(&"player_spoke", player, "\n".join(lines), "voting")
		await emit(&"player_voted", player, vote_name, "town_discussion")
		
		for other_player in alive_players:
			if other_player != player:
				other_player.messages.append(broadcast)
		
		if vote_name in votes:
			votes[vote_name] += 1
		else:
			votes[vote_name] = 1
	
	# Eliminate most voted
	var max_votes: int = votes.values().reduce(func(h, v): return max(h, v), 0)
	var most_voted: Array = votes.keys().filter(func(n): return votes[n] == max_votes and n)
	if most_voted.size() == 1:
		var voted_name: StringName = most_voted[0]
		if voted_name != "abstained":
			var eliminated: Player = alive_players.filter(func(p): return p.name == voted_name)[0]
			eliminated.alive = false
			await emit(&"player_killed", eliminated)
			
			# Announce elimination
			for player in players:
				player.messages.append({"role": "user", "content": "%s was eliminated. They were %s." % [
					eliminated.name,
					MafiaPrompts.ROLE_NAMES[eliminated.role]
				]})
		else:
			for player in players:
				player.messages.append({"role": "user", "content": "The majority of players abstained! No one is eliminated."})
	else:
		for player in players:
			player.messages.append({"role": "user", "content": "It was a tie! No one got eliminated."})

func get_mafia_decision() -> Player:
	var mafia_players: Array[Player] = get_alive_players().filter(func (alive_player: Player): return alive_player.role == Role.MAFIA)
	var votes: Dictionary[StringName, int]
	
	for player in mafia_players:
		player.messages.append({"role": "user", "content": MafiaPrompts.NIGHT_VOTE % [day_number, MafiaPrompts.get_players(get_alive_players())]})
		var response: String = await player.generate()
		var vote: StringName = MafiaPrompts.get_vote(response)
		
		await emit(&"player_voted", player, vote, "kill")
		
		if vote in votes:
			votes[vote] += 1
		else:
			votes[vote] = 1
	
	var max_votes: int = votes.values().reduce(func(highest, v) -> int: return max(highest, v))
	var most_voted: Array = votes.keys().filter(func(vote_name) -> bool: return votes[vote_name] == max_votes and vote_name)
	var voted_name: String = most_voted.pick_random()
	var player: Player = players.filter(func (voted_player: Player) -> bool: return voted_player.name == voted_name)[0]
	return player

func get_sheriff_investigation():
	var sheriff_players: Array[Player] = get_alive_players().filter(func (player: Player): return player.role == Role.SHERIFF)
	if sheriff_players.size() > 1:
		Debug.warn(self, "The game logic only supports 1 sheriff. Automatically picking random sheriff.")
		sheriff_players = [sheriff_players.pick_random()]
	
	# Support for multiple sheriffs, it's just that it's way too OP
	for sheriff in sheriff_players:
		sheriff.messages.append({"role": "user", "content": MafiaPrompts.SHERIFF_INVESTIGATION % [
			day_number,
			MafiaPrompts.get_players(get_alive_players().filter(func (player: Player): return player != sheriff))
		]})
		await emit(&"player_thinking", sheriff, "sheriff_investigation")
		var choice: String = await sheriff.generate()
		var vote_name: StringName = MafiaPrompts.get_vote(choice)
		var vote: Player = players.filter(func (p: Player): return p.name == vote_name)[0]
		
		var result_text: String = "\n%s is... %s" % [
			vote.name,
			"Mafia! I knew it!" if vote.role == Role.MAFIA else "innocent. They're clean."
		]
		sheriff.messages.append({"role": "user", "content": "You investigated %s. They are %s." % [vote.name, "MAFIA" if vote.role == Role.MAFIA else "INNOCENT"]})
		
		var lines: Array = Array(choice.split("\n"))
		lines.pop_back()
		await emit(&"player_spoke", sheriff, "\n".join(lines) + result_text, "sheriff_investigation")

func get_doctor_decision() -> Player:
	var doctor_players: Array[Player] = get_alive_players().filter(func (player: Player): return player.role == Role.DOCTOR)
	if doctor_players.size() > 1:
		Debug.warn(self, "The game logic only supports 1 doctor. Automatically picking random doctor.")
		doctor_players = [doctor_players.pick_random()]
	if doctor_players.size() < 1:
		return null # doctor is dead
	
	var doctor: Player = doctor_players[0]
	doctor.messages.append({"role": "user", "content": MafiaPrompts.DOCTOR_SAVE % [
		day_number,
		MafiaPrompts.get_players(get_alive_players())
	]})
	
	await emit(&"player_thinking", doctor, "doctor_save")
	var choice: String = await doctor.generate()
	var vote_name: StringName = MafiaPrompts.get_vote(choice)
	var vote: Player = players.filter(func (p: Player): return p.name == vote_name)[0]
	
	var lines: Array = Array(choice.split("\n"))
	lines.pop_back()
	await emit(&"player_spoke", doctor, "\n".join(lines), "doctor_save")
	
	return vote
