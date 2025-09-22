extends CharacterBody3D


const SENSITIVITY = 0.003
var GRAVITY = 9.8

@onready var head = $Head
@onready var camera = $Head/Camera3D

@onready var current_gun_node: Node3D = $Head/Camera3D/CurrentGun
var gun_barrel : RayCast3D
var gun_anim : AnimationPlayer
var active_index := 0
var is_scoping = false
var gun : Node3D
var bullet = preload("res://Scenes/bullet.tscn")
var bullet_instance


#Player vars
@export_range(1.0, 10, 0.5) var SPEED = 10.0
@export_range(1.0, 10, 0.5) var JUMP_VELOCITY = 6.0
@export_range(1.0, 3.0, 0.1) var sprint_multiplier = 1.5
@export_range(60, 120, 1) var Base_FOV = 75
@export var ACCELERATION = SPEED * 3.0
@export var DEACCELERATION = SPEED * 2.5
@export_range(0.1, 0.5, 0.02) var COYOTE_TIME = 0.2
@export_range(1.0, 3.0, 0.1) var FALL_MULTIPLIER = 1.5
@export_range(1.0, 3.0, 0.1) var LOW_JUMP_MULTIPLIER = 2.0
var base_speed : float
var base_gravity : float

var Jump_buffer = 0.2
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var FOV_multiplier = 30

#headbob vars
const BOB_FREQ = 1.4
const BOB_AMP = 0.08
var t_bob = 0.0
var headbob_offset := Vector3.ZERO
var shake_offset := Vector3.ZERO

var pitch := 0.0

var mouse_unlocked := false
var target_velocity = Vector3.ZERO

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	base_gravity = GRAVITY
	base_speed = SPEED
	update_current_gun()
	
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
	
	#Checking Coyote Time
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(coyote_timer - delta, 0)
	
	#Jump Buffer For instant jumps
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = Jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)
		
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
	# Movement
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Horizontal velocity only
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	
	if is_on_floor():
		if direction != Vector3.ZERO:
			# Pick target speed (sprint or normal)
			var target_speed = SPEED
			
			if Input.is_action_pressed("sprint"):
				target_speed *= sprint_multiplier
			
			# Current horizontal speed
			var speed = horizontal_velocity.length()
			
			# Accelerate toward target speed
			speed = move_toward(speed, target_speed, ACCELERATION * delta)
			
			# Snap instantly to new direction
			horizontal_velocity = direction * speed
		else:
			# No input → decelerate to zero
			var speed = horizontal_velocity.length()
			speed = move_toward(speed, 0, DEACCELERATION * delta)
			
			if speed > 0.01:
				horizontal_velocity = horizontal_velocity.normalized() * speed
			else:
				horizontal_velocity = Vector3.ZERO
	else:
		# --- AIR CONTROL ---
		
		if direction != Vector3.ZERO:
			var air_control_factor = 4.0  # tweak for stronger/weaker steering
			# Preserve speed magnitude
			var speed = horizontal_velocity.length()
			#If input is after jump give a lil speed
			if speed < 0.1:
				speed = SPEED * 0.5
				
			# Blend current direction toward input direction
			var new_dir = horizontal_velocity.normalized().lerp(direction, air_control_factor * delta).normalized()
			horizontal_velocity = new_dir * speed
		
		
	# Apply back to velocity
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	
	#headbob
	t_bob += delta * velocity.length() * float(is_on_floor())
	headbob_offset = headbob(t_bob)

	# Final camera position = headbob + shake
	camera.transform.origin = headbob_offset + shake_offset
	gun.transform.origin = headbob_offset + shake_offset - Vector3(-0.24,0.05,0.2)
	
	if Input.is_action_pressed("shoot") and gun_barrel:
		shoot()
		camera.start_shake()
	else:
		camera.stop_shake()
	
	if Input.is_action_pressed("right_click") and gun_anim.has_animation("Scope"):
		if !is_scoping:
			gun_anim.play("Scope")
			is_scoping = true
	else:
		if is_scoping and gun_anim.has_animation("Unscope"):
			gun_anim.play("Unscope")
		is_scoping = false
	
	# Move the character
	move_and_slide()
	
	#FOV
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var speed_fraction = clamp(horizontal_speed / SPEED, 0.0, 1.0)
	
	# Increase FOV for sprinting
	var sprint_factor = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var target_fov = Base_FOV + FOV_multiplier * speed_fraction * sprint_factor
	
	camera.fov = lerp(camera.fov, target_fov, delta * 12.0)
	
func headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos
	
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
		
func update_current_gun():
	# Always reset to base values first
	SPEED = base_speed
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
			SPEED = max(base_speed - (weight * 0.1), base_speed * 0.2)  # Min 20% of base speed
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
