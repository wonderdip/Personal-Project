extends CharacterBody3D


const SENSITIVITY = 0.003
const GRAVITY = 9.8

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var gun_anim = $Head/Camera3D/Rifle/AnimationPlayer
@onready var gun_barrel = $Head/Camera3D/Rifle/RayCast3D

var bullet = preload("res://Scenes/bullet.tscn")
var bullet_instance


#Player vars
@export_range(1.0, 10, 0.5) var SPEED = 5.0
@export_range(1.0, 10, 0.5) var JUMP_VELOCITY = 6.0
@export_range(1.0, 3.0, 0.1) var sprint_multiplier = 1.5
@export_range(60, 120, 1) var Base_FOV = 75
@export var ACCELERATION = 15.0
@export var DEACCELERATION = 13.0
@export_range(0.1, 0.5, 0.02) var COYOTE_TIME = 0.2
@export_range(1.0, 3.0, 0.1) var FALL_MULTIPLIER = 1.5
@export_range(1.0, 3.0, 0.1) var LOW_JUMP_MULTIPLIER = 2.0

var Jump_buffer = 0.2
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var FOV_multiplier = 12

#headbob vars
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

var pitch := 0.0

var mouse_unlocked := false
var target_velocity = Vector3.ZERO

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
			
func _input(event: InputEvent) -> void:
	if mouse_unlocked and event is InputEventMouseButton and event.pressed:
		mouse_unlocked = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
func _physics_process(delta: float) -> void:
	
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
	camera.transform.origin = headbob(t_bob)
	
	if Input.is_action_pressed("shoot"):
		if !gun_anim.is_playing():
			gun_anim.play("Shoot")
			bullet_instance = bullet.instantiate()
			bullet_instance.position = gun_barrel.global_position
			bullet_instance.transform.basis = gun_barrel.global_transform.basis
			get_parent().add_child(bullet_instance)
	
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
