extends CharacterBody2D

@export var speed = 300.0
@export var jump_speed = -400.0
@export var coyote_time = 0.15  # seconds allowed after walking off a ledge
@export var look_ahead_distance: float = 100.0  # how far ahead to shift
@export var look_ahead_speed: float = 5.0       # how fast the camera catches up
@export var vertical_offset: float = -59.0 
@export var accel := 2000.0       # how fast you reach max speed
@export var decel := 3000.0       # how fast you stop when letting go
@export var health:int = 1000

@export var parry_window := 0.25   # how long the parry can block hits makes it so every parry guarantees to register
var parry_active: bool = false        # parry window currently open
var parry_consumed: bool = false      # player's current attack not blocked


@onready var sprite = $Sprite
@onready var sword_hit_box = $SwordHitBox/CollisionShape2D
@onready var cam = $Camera
@onready var parry_box = $ParryHitBox
@onready var parry_shape = $ParryHitBox/CollisionShape2D
@onready var parry_particles = $ParryParticles

## Will change but for now ##
@onready var death_screen = $"../CanvasLayer"
@onready var death_player = $"../CanvasModulate/AnimationPlayer"
#############################
# Get the gravity from the project settings so you can sync with rigid body nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

var damage = 1 # Can change when blacksmith upgrades sword or if adding multiple swords
var can_attack:bool = true
var is_attacking:bool = false
var coyote_timer = 0.0
var camera_locked:bool = false
var look_ahead_offset: Vector2 = Vector2.ZERO
var parry_block = false

signal attack_started # So the ai can parry on time looking cooler

func _ready():
	sprite.play("Idle")

func _physics_process(delta):
	############ Movement ####################
	# Add the gravity.
	velocity.y += gravity * delta
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta
	# Handle Jump.
	if Input.is_action_just_pressed("jump") and coyote_timer > 0:
		velocity.y = jump_speed
		coyote_timer = 0

	# Get the input direction.
	var direction = Input.get_axis("left", "right")
	# Horizontal movement with acceleration/deceleration

	if direction != 0:
	# Accelerate quickly toward the target speed
		velocity.x = move_toward(velocity.x, direction * speed, accel * delta)
	else:
	# Decelerate quickly when no input
		velocity.x = move_toward(velocity.x, 0, decel * delta)
	
	if velocity.x < 0:
		if is_attacking == false:
			sprite.flip_h = true
			sword_hit_box.scale.x = -1
			sword_hit_box.scale.y = 1
			parry_box.scale.x = -1
			parry_particles.position.x = -27
	elif velocity.x > 0:
		if is_attacking == false:
			sprite.flip_h = false
			sword_hit_box.scale.x = 1
			sword_hit_box.scale.y = 1
			parry_box.scale.x = 1
			parry_particles.position.x = 27
	
		# Look-ahead based on horizontal movement
	look_ahead_offset.x = lerp(look_ahead_offset.x, direction * look_ahead_distance, delta * look_ahead_speed)

	# small vertical look-ahead for jumping/falling
	look_ahead_offset.y = lerp(look_ahead_offset.y, velocity.y * 0.1, delta * look_ahead_speed)
	
	if is_attacking == true:
		velocity.x *= 0.8

	move_and_slide()
	############################################
func _process(delta):
	if not camera_locked:
		var target_pos = global_position + look_ahead_offset + Vector2(0, vertical_offset)
		cam.global_position = cam.global_position.lerp(target_pos, 0.1)
		
		
	if Input.is_action_just_pressed("attack") and can_attack == true and !parry_active:
		emit_signal("attack_started")
		attack()
		is_attacking = true
	
	if Input.is_action_just_pressed("parry") and !is_attacking:
		parry()
		parry_active = true
	
	####### Handles the sword collisions #######   Use this to disable collision when rolling or copy for parrying
	if sprite.animation == "Attack":
		var frame = sprite.frame
		# Enable hitbox on specific frames
		if frame == 2 or frame == 3 or frame == 4:
			sword_hit_box.disabled = false
		else:
			sword_hit_box.disabled = true
	else:
		# Not attacking, always disable hitbox
		sword_hit_box.disabled = true
	
	#############################################

		###### Parry collisions#########
	
	if sprite.animation == "Parry":
		var frame = sprite.frame
		# Enable hitbox on specific frames
		if frame == 0 or frame == 1 or frame == 2 or frame == 3:
			parry_shape.disabled = false
		else:
			parry_shape.disabled = true
	else:
		# Not attacking, always disable hitbox
		parry_shape.disabled = true

####### Attacking Code ############

func attack():
	sprite.play("Attack")
	await sprite.animation_finished
	sprite.play("Idle")
	is_attacking = false

func hitstop(duration: float):
	Engine.time_scale = 0.01   # “fake freeze” but timers still work
	await get_tree().create_timer(duration).timeout
	Engine.time_scale = 1.0
	pass
	
func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Enemy"):
		hitstop(0.018)  # 18ms hitstop this is perfect for soft hits but still shows impact, 0.01 = 10ms,
		body.take_damage(damage)

###################################

######## Parry ####################

func parry():
	sprite.play("Parry")
	parry_active = true
	await sprite.animation_finished
	sprite.play("Idle")
	parry_active = false
	parry_block = false   # Reset after parry window ends

func _on_parry_hit_box_area_entered(area):
	if area.is_in_group("Enemy") and parry_active and not parry_block:

		parry_block = true     # Block further damage for this attack
		parry_particles.emitting = true
		var enemy = area.get_parent()
		enemy.stun_parried()
		hitstop(0.019)
		
		#print("Parry!")
###################################

################## DAMAGE ####################

func take_damage(amount: int):
	print("before attack: ", + health)
	if parry_block:
		return
	
	health -= amount
	print("after attack: ", + health)
	if health <= 0:
		die()

func die():
	death_screen.visible = true
	hide()
	set_physics_process(false)
	set_process(false)
	set_collision_layer_value(2, false)
	death_player.play("Death")
	#queue_free()
	
############################################

######### Camera Locking and movement ##########
func lock_camera_to_room(pos: Vector2, size: Vector2):
	camera_locked = true

	# Set camera limits
	cam.limit_left = global_position.x
	cam.limit_right = global_position.x + size.x
	cam.limit_top = global_position.y + 59 * 2
	cam.limit_bottom = global_position.y - size.y

	# Move to room center
	var room_center = global_position + size / 2
	cam.global_position = room_center
	
func unlock_camera():
	camera_locked = false
	cam.position.y = -0
	# Remove limits so camera follows freely
	cam.limit_left = -99999
	cam.limit_right = 99999
	cam.limit_top = -99999
	cam.limit_bottom = 99999
	
##################################################
