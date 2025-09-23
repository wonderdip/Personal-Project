extends CharacterBody3D

# --------- Constants ---------
const SENSITIVITY = 0.003
var GRAVITY = 9.8

# --------- Node References ---------
@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var current_gun_node: Node3D = $Head/Camera3D/CurrentGun

# --------- Gun Variables ---------
var gun_barrel : RayCast3D
var gun_anim : AnimationPlayer
var active_index := 0
var is_scoping = false
var gun : Node3D
var bullet = preload("res://Scenes/bullet.tscn")
var bullet_instance

# --------- Player Variables ---------
@export_range(1.0, 10, 0.5) var BASE_SPEED = 10.0
@export_range(1.0, 10, 0.5) var JUMP_VELOCITY = 6.0
@export_range(1.0, 3.0, 0.1) var sprint_multiplier = 1.5
@export_range(60, 120, 1) var Base_FOV = 75
@export var ACCELERATION = 45.0  # Constant acceleration
@export var DEACCELERATION = 50.0  # Instant deceleration
@export_range(0.1, 0.5, 0.02) var COYOTE_TIME = 0.2
@export_range(1.0, 3.0, 0.1) var FALL_MULTIPLIER = 1.5
@export_range(1.0, 3.0, 0.1) var LOW_JUMP_MULTIPLIER = 2.0
var base_speed : float
var base_gravity : float
var Jump_buffer = 0.2
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var FOV_multiplier = 30

# --------- Headbob Variables ---------
const BOB_FREQ = 1.4
const BOB_AMP = 0.08
var t_bob = 0.0
var camera_headbob_offset := Vector3.ZERO
var gun_headbob_offset := Vector3.ZERO
var shake_offset := Vector3.ZERO

# --------- Input / Camera Variables ---------
var pitch := 0.0
var mouse_unlocked := false
var target_velocity = Vector3.ZERO

# --------- Initialization ---------
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_gravity = GRAVITY
	base_speed = BASE_SPEED
	update_current_gun()

# --------- Input Handling ---------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and !mouse_unlocked:
		# Rotate head (yaw)
		head.rotate_y(-event.relative.x * SENSITIVITY)
		# Clamp camera rotation (pitch)
		pitch = clamp(pitch - event.relative.y * SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = pitch
		
	if event is InputEventKey and event.pressed:
		if event.keycode == Key.KEY_ESCAPE:
			if mouse_unlocked:
				mouse_unlocked = false
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				mouse_unlocked = true
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				switch_gun(-1)
				if gun_anim and gun_anim.has_animation("Swap"):
					gun_anim.play("Swap")
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				switch_gun(1)
				if gun_anim and gun_anim.has_animation("Swap"):
					gun_anim.play("Swap")

func _input(event: InputEvent) -> void:
	if mouse_unlocked and event is InputEventMouseButton and event.pressed:
		mouse_unlocked = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# --------- Physics Process ---------
func _physics_process(delta: float) -> void:
	if is_on_wall_only():
		camera.rotation = Vector3(0,0,0)
		
	# Apply gravity
	if not is_on_floor():
		if velocity.y < 0:
			velocity.y -= GRAVITY * FALL_MULTIPLIER * delta
		elif not Input.is_action_pressed("jump"):
			velocity.y -= GRAVITY * LOW_JUMP_MULTIPLIER * delta
		else:
			velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0  # Reset Y velocity on floor
	
	# Coyote time
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(coyote_timer - delta, 0)
	
	# Jump buffer for instant jumps
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = Jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)
		
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
	# Movement input
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Horizontal velocity only
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	
	if is_on_floor():
		if direction != Vector3.ZERO:
			# Get current speed
			var current_speed = horizontal_velocity.length()
			
			# Apply diminishing returns to acceleration based on current speed
			var speed_factor = 1.0 / (1.0 + current_speed * 0.2)  # Adjust 0.08 to control diminishing returns
			var effective_acceleration = ACCELERATION * speed_factor
			
			# Apply sprint multiplier to acceleration, not target speed
			if Input.is_action_pressed("sprint"):
				effective_acceleration *= sprint_multiplier
			
			# Accelerate in the desired direction
			var new_speed = current_speed + effective_acceleration * delta
			horizontal_velocity = direction * new_speed
			print(snapped(new_speed, 1))
		else:
			# Instant deceleration when no input
			horizontal_velocity = Vector3.ZERO
	else:
		# Air control
		if direction != Vector3.ZERO:
			var air_control_factor = 4.0
			var speed = horizontal_velocity.length()
			if speed < 0.1:
				speed = BASE_SPEED * 0.5
				
			var new_dir = horizontal_velocity.normalized().lerp(direction, air_control_factor * delta).normalized()
			horizontal_velocity = new_dir * speed
	
	# Apply back to velocity
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	# Move the character
	move_and_slide()
	
	# Apply headbob and gun positioning
	handle_headbob_and_gun(delta)
	
	# Handle shooting and scoping
	handle_shooting_and_scoping()
	
	# Handle FOV changes
	handle_fov(delta)

# --------- Headbob and Gun Positioning ---------
func handle_headbob_and_gun(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Only update headbob time when moving and on floor
	if horizontal_speed > 0.1 and is_on_floor():
		# Normalize the speed for headbob calculation - this prevents crazy fast bobbing
		var normalized_speed = sqrt(horizontal_speed) * 2.0  # Square root dampening + scaling
		t_bob += delta * normalized_speed * float(is_on_floor())
	else:
		# Gradually reduce headbob when stopping
		t_bob = lerp(t_bob, 0.0, delta * 3.0)
	
	# Calculate separate headbob offsets
	camera_headbob_offset = camera_headbob(t_bob, horizontal_speed)
	gun_headbob_offset = gun_headbob(t_bob, horizontal_speed)
	
	# Apply to camera and gun
	camera.transform.origin = camera_headbob_offset + shake_offset
	if gun:
		gun.transform.origin = gun_headbob_offset + shake_offset - Vector3(-0.24, 0.05, 0.2)

# --------- Camera Headbob Function ---------
func camera_headbob(time: float, speed: float) -> Vector3:
	var pos = Vector3.ZERO
	
	if speed > 0.1:
		# Normalize speed for amplitude calculation to prevent extreme bobbing
		var speed_factor = sqrt(speed) / sqrt(BASE_SPEED)  # Square root normalization
		speed_factor = clamp(speed_factor, 0.3, 1.5)  # Keep reasonable range
		
		pos.y = sin(time * BOB_FREQ) * BOB_AMP * speed_factor
		pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP * speed_factor
	
	return pos

# --------- Gun Headbob Function ---------
func gun_headbob(time: float, speed: float) -> Vector3:
	var pos = Vector3.ZERO
	
	if speed > 0.1:
		# Normalize speed for amplitude, gun bobs slightly less than camera
		var speed_factor = sqrt(speed) / sqrt(BASE_SPEED)  # Square root normalization
		speed_factor = clamp(speed_factor, 0.3, 1.3)  # Slightly more conservative than camera
		
		pos.y = sin(time * BOB_FREQ) * BOB_AMP * 0.8 * speed_factor  # 80% of camera bob
		pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP * 0.8 * speed_factor
	
	return pos

# --------- Shooting and Scoping ---------
func handle_shooting_and_scoping() -> void:
	if Input.is_action_pressed("shoot") and gun_barrel:
		shoot()
		camera.start_shake()
	else:
		camera.stop_shake()
	
	if Input.is_action_pressed("right_click") and gun_anim and gun_anim.has_animation("Scope"):
		if !is_scoping:
			gun_anim.play("Scope")
			is_scoping = true
	else:
		if is_scoping and gun_anim and gun_anim.has_animation("Unscope"):
			gun_anim.play("Unscope")
		is_scoping = false

func shoot():
	# No gun equipped
	if gun_anim == null or gun_barrel == null:
		return  
		
	if !gun_anim.is_playing():
		if is_scoping and gun_anim.has_animation("Scope_Shot"):
			gun_anim.play("Scope_Shot")
		elif gun_anim.has_animation("Shoot"):
			gun_anim.play("Shoot")
		
		# Only spawn bullets if we have a barrel
		if gun_barrel:
			bullet_instance = bullet.instantiate()
			bullet_instance.position = gun_barrel.global_position
			bullet_instance.transform.basis = gun_barrel.global_transform.basis
			get_parent().add_child(bullet_instance)

# --------- FOV Handling ---------
func handle_fov(delta: float) -> void:
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	# Use logarithmic scaling for FOV as well to prevent extreme FOV changes
	var speed_factor = log(horizontal_speed + 1) / log(BASE_SPEED + 1)
	speed_factor = clamp(speed_factor, 0.0, 2.0)  # Cap the FOV multiplier
	
	# Increase FOV for sprinting
	var sprint_factor = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var target_fov = Base_FOV + FOV_multiplier * speed_factor * sprint_factor
	
	camera.fov = lerp(camera.fov, target_fov, delta * 12.0)

# --------- Gun Management ---------
func update_current_gun():
	GRAVITY = base_gravity
	
	# Clear references
	gun_anim = null
	gun_barrel = null
	
	if current_gun_node.get_child_count() == 0:
		return
		
	gun = current_gun_node.get_child(active_index)
	
	# Only treat this as a weapon if it's in the Weapons group
	if gun.is_in_group("Weapons"):
		if gun.has_node("AnimationPlayer"):
			gun_anim = gun.get_node("AnimationPlayer")
		if gun.has_node("RayCast3D"):
			gun_barrel = gun.get_node("RayCast3D")
			
		# Handle weight if exported - use proper calculations
		if "Weight" in gun:
			var weight = gun.Weight
			# Clamp weight to reasonable values to prevent issues
			weight = clamp(weight, 0, 50)  # Adjust max as needed
			
			# Apply weight effects (modify from base values)
			# Weight affects acceleration rather than top speed
			ACCELERATION = max(25.0 - (weight * 0.8), 5.0)  # Heavier guns accelerate slower
			GRAVITY = max(base_gravity + (weight * 0.08), base_gravity * 0.1)  # Min 10% of base gravity
func switch_gun(order: int):
	var count = current_gun_node.get_child_count()
	if count == 0:
		return
	
	# Proper wrapping for both directions
	active_index = (active_index + order + count) % count
	
	for i in range(count):
		current_gun_node.get_child(i).visible = (i == active_index)
	
	update_current_gun()
