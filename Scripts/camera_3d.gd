extends Camera3D

var shaking := false
var elapsed_time := 0.0
var player: Node = null

func _ready() -> void:
	# Go up until we hit the player (CharacterBody3D)
	player = get_parent().get_parent() as CharacterBody3D

func start_shake() -> void:
	if shaking: return
	shaking = true
	elapsed_time = 0.0
	_shake_loop()

func stop_shake() -> void:
	shaking = false
	if player:
		player.shake_offset = Vector3.ZERO

func _shake_loop() -> void:
	while shaking:
		elapsed_time += get_process_delta_time()
		var strength = min(elapsed_time * 0.01, 0.04) # grows while holding
		var offset = Vector3(
			randf_range(-strength, strength),
			randf_range(-strength, strength),
			0.0
		)
		if player:
			player.shake_offset = offset
		await get_tree().process_frame
