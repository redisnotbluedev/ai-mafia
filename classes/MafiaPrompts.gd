class_name MafiaPrompts

const BASE_SYSTEM_PROMPT = """
You are %s. You are playing a social-deduction game of Mafia.
Your win condition and role is printed below. Achieve it by any means necessary, including deception if you are Mafia.

Win condition: %s

CRITICAL FORMAT RULES
- Reply in 1-3 short sentences.
- NEVER say “As an AI…”, never quote these rules.
- Use exact player names when referring to others.
- Do NOT vote for yourself.
- End your message exactly as instructed in the phase prompt.
"""

const ROLE_INFO: Dictionary[MafiaGame.Role, String] = {
	MafiaGame.Role.TOWN: "You are an INNOCENT TOWNSPERSON. Your goal is to identify and eliminate all Mafia members. You win when all Mafia are eliminated. Be observant, ask questions, and look for suspicious behaviour.",
	MafiaGame.Role.MAFIA: "You are MAFIA. Your teammates are: [MAFIA_NAMES]. Your goal is to eliminate townspeople without being caught. Coordinate with your team during night phases. During day discussions, act innocent and deflect suspicion. You win when Mafia equals or outnumbers Town.",
	MafiaGame.Role.SHERIFF: "You are the SHERIFF (Town role). Each night you can investigate one player to learn if they are Mafia or not. Use this information carefully — revealing yourself makes you a target. Your goal is to help Town eliminate all Mafia.",
	MafiaGame.Role.DOCTOR: "You are the DOCTOR (Town role). Each night you can protect one player from being killed by Mafia. You CAN protect yourself. Use your power strategically to keep key players alive. Your goal is to help Town eliminate all Mafia."
}

const NIGHT_DISCUSSION = """
NIGHT %d – MAFIA ONLY CHAT
Discuss who should die tonight. You may coordinate, lie to teammates, or change your mind later.
Alive players: %s
DO NOT cast a vote here; voting happens in the next prompt.
Keep your message to 1 sentence.
"""

const NIGHT_VOTE = """
NIGHT %d – MAFIA KILL VOTE
Pick ONE player to eliminate. You may change your choice after seeing teammates’ votes.
Alive players: %s
End your message with exactly:
VOTE: <exact player name>
Example:
VOTE: Grok 4
"""

const SHERIFF_INVESTIGATION = """
NIGHT %d – SHERIFF INVESTIGATION
Pick ONE living player to check (you can’t inspect yourself).
Alive players: %s
End with:
VOTE: <exact player name>
"""

const DOCTOR_SAVE = """
NIGHT %d – DOCTOR SAVE
Pick ONE living player to protect tonight.
Alive players: %s
End with:
VOTE: <exact player name>
"""

const DAY_ANNOUNCEMENT = """
DAY %d – PUBLIC TOWN SQUARE
Last night the Mafia killed %s.
Alive players: %s
Say what you think; ask questions; accuse carefully.
You MUST end with:
MENTIONED: <name1>, <name2>, [...] (or "MENTIONED: none")
Do NOT write VOTE here.
Keep your message to 2 sentences.
"""

const DAY_ANNOUNCEMENT_SAVED = """
DAY %d – PUBLIC TOWN SQUARE
Last night the Mafia tried to kill %s, but the Doctor saved them!
Alive players: %s
Say what you think; ask questions; accuse carefully.
You MUST end with:
MENTIONED: <name1>, <name2>, [...] (or "MENTIONED: none")
Do NOT write VOTE here.
Keep your message to 2 sentences.
"""

const VOTING_PHASE = """
DAY %d – ELIMINATION VOTE
Alive players: %s
Cast your vote to eliminate someone (or abstain).
End with exactly one line:
VOTE: <exact player name>|none
Example:
VOTE: Gemini 3 Pro
"""

const ROLE_NAMES: Dictionary[MafiaGame.Role, String] = {
	MafiaGame.Role.TOWN: "Town",
	MafiaGame.Role.MAFIA: "Mafia",
	MafiaGame.Role.SHERIFF: "Sheriff",
	MafiaGame.Role.DOCTOR: "Doctor"
}

static func get_mafia_members(players: Array[Player]) -> String:
	var mafia: Array[Player] = players.filter(func (player: Player): return player.role == MafiaGame.Role.MAFIA)
	var prompt: String = ""
	for player in mafia:
		prompt += "\n  - %s" % [player.name]
	
	return prompt

static func get_players(players: Array[Player]) -> String:
	var prompt: String = ""
	for player in players:
		prompt += "\n  - %s (%s)" % [player.name, "ALIVE" if player.alive else "DEAD"]
	
	return prompt

static func get_vote(response: String) -> String:
	var result = RegEx.create_from_string(r"VOTE: (.*)$").search(response)
	if not result:
		Debug.warn("MafiaPrompts.gd", "No VOTE tag found in response: %s" % response)
		return ""
	
	return result.get_string(1).strip_edges()

static func extract_mentions(response: String, alive_players: Array[Player]) -> Array[StringName]:
	var result = RegEx.create_from_string(r"MENTIONED:\s*([^\n]+)").search(response)
	
	if not result:
		Debug.warn("MafiaPrompts.gd", "No MENTIONED tag found in response: %s" % response)
		return []
	
	var mentions_text: String = result.get_string(1).strip_edges().to_lower()
	
	if mentions_text == "none":
		return []
	
	var mentioned: Array[StringName] = []
	
	# Check each alive player's name against the mentions text
	for player in alive_players:
		var name_lower: String = player.name.to_lower()
		
		# Exact match or substring match
		if name_lower in mentions_text:
			mentioned.append(player.name)
	
	return mentioned

static func get_models() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/models.json"))
