extends Node3D

func set_face(path: String):
	$Head/Sprite3D.texture = load(path)

func set_body(texture: StandardMaterial3D):
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = texture

func set_text(player: Player):
	$Name.text = player.name
	match player.role:
		MafiaGame.Role.TOWN:
			$Role.text = "Villager"
			$Role.modulate = Color("74b86cff")
		MafiaGame.Role.MAFIA:
			$Role.text = "Mafia"
			$Role.modulate = Color("eb7771ff")
		MafiaGame.Role.SHERIFF:
			$Role.text = "Sheriff"
			$Role.modulate = Color("c09938ff")
		MafiaGame.Role.DOCTOR:
			$Role.text = "Doctor"
			$Role.modulate = Color("59a7dfff")
