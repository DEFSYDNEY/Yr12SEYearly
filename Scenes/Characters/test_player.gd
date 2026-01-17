extends CharacterBody2D

@export var speed = 300.0
@export var jump_speed = -400.0
@export var coyote_time = 0.15
@export var look_ahead_distance: float = 100.0
@export var look_ahead_speed: float = 5.0
@export var vertical_offset: float = -59.0 
@export var accel := 2000.0
@export var decel := 3000.0
@export var health: int = 1000
@export var max_posture: int = 100

# SEKIRO-STYLE PARRY SYSTEM
@export_category("Parry System")
@export var perfect_parry_window := 0.1      # Perfect deflect: 100ms before hit
@export var good_parry_window := 0.2         # Good deflect: 200ms before hit  
@export var poor_parry_window := 0.35        # Poor block: 350ms before hit
@export var parry_spam_decay := 0.5          # Window shrinks if spamming
@export var parry_recovery_time := 0.5       # Time to restore full window

@onready var sprite = $Sprite
@onready var sword_hit_box = $SwordHitBox/CollisionShape2D
@onready var cam = $Camera
@onready var parry_box = $ParryHitBox
@onready var parry_shape = $ParryHitBox/CollisionShape2D
@onready var parry_particles = $ParryParticles
@onready var death_screen = $"../CanvasLayer"
@onready var death_player = $"../CanvasModulate/AnimationPlayer"

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Combat variables
var damage = 1
var posture_damage = 100
var can_attack: bool = true
var is_attacking: bool = false
var coyote_timer = 0.0
var camera_locked: bool = false
var look_ahead_offset: Vector2 = Vector2.ZERO

# Parry state variables
var current_posture: int = 0
var parry_active: bool = false
var parry_start_time: float = 0.0
var last_parry_press_time: float = 0.0
var parry_spam_count: int = 0
var current_parry_window: float = 0.35  # Starts at poor window
var parry_successful: bool = false  # Flag to block damage when parry succeeds

# Parry result enum
enum ParryResult {
	NONE,
	PERFECT,    # Full deflect, no posture damage, high enemy posture damage
	GOOD,       # Deflect, minor posture damage, medium enemy posture damage
	POOR        # Block, chip damage to health and posture
}

signal attack_started
signal parry_executed(result: ParryResult)

func _ready():
	sprite.play("Idle")
	current_parry_window = poor_parry_window

func _physics_process(delta):
	handle_movement(delta)
	handle_posture_recovery(delta)
	update_parry_window_recovery(delta)
	move_and_slide()

func handle_movement(delta):
	# Gravity
	velocity.y += gravity * delta
	
	# Coyote time
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta
	
	# Jump
	if Input.is_action_just_pressed("jump") and coyote_timer > 0:
		velocity.y = jump_speed
		coyote_timer = 0

	# Horizontal movement
	var direction = Input.get_axis("left", "right")
	
	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, decel * delta)
	
	# Flip sprite and hitboxes
	if velocity.x < 0 and not is_attacking:
		sprite.flip_h = true
		sword_hit_box.scale.x = -1
		parry_box.scale.x = -1
		parry_particles.position.x = -27
	elif velocity.x > 0 and not is_attacking:
		sprite.flip_h = false
		sword_hit_box.scale.x = 1
		parry_box.scale.x = 1
		parry_particles.position.x = 27
	
	# Camera look-ahead
	look_ahead_offset.x = lerp(look_ahead_offset.x, direction * look_ahead_distance, delta * look_ahead_speed)
	look_ahead_offset.y = lerp(look_ahead_offset.y, velocity.y * 0.1, delta * look_ahead_speed)
	
	# Slow down during attack
	if is_attacking:
		velocity.x *= 0.8

func handle_posture_recovery(delta):
	# Posture recovers over time when not blocking/parrying
	if current_posture > 0 and not parry_active:
		current_posture = max(0, current_posture - int(20.0 * delta))

func update_parry_window_recovery(delta):
	# Restore parry window if player hasn't spammed recently
	var time_since_last_parry = Time.get_ticks_msec() / 1000.0 - last_parry_press_time
	
	if time_since_last_parry >= parry_recovery_time:
		parry_spam_count = max(0, parry_spam_count - 1)
		current_parry_window = poor_parry_window
	else:
		# Window shrinks with spam
		var shrink_factor = 1.0 - (parry_spam_count * 0.2)
		shrink_factor = max(0.3, shrink_factor)  # Minimum 30% of window
		current_parry_window = poor_parry_window * shrink_factor

func _process(delta):
	# Camera update
	if not camera_locked:
		var target_pos = global_position + look_ahead_offset + Vector2(0, vertical_offset)
		cam.global_position = cam.global_position.lerp(target_pos, 0.1)
	
	# Attack input
	if Input.is_action_just_pressed("attack") and can_attack and not parry_active:
		emit_signal("attack_started")
		attack()
		is_attacking = true
	
	# Parry input
	if Input.is_action_just_pressed("parry") and not is_attacking:
		initiate_parry()
	
	# Update hitboxes based on animation
	update_sword_hitbox()
	update_parry_hitbox()

func update_sword_hitbox():
	if sprite.animation == "Attack":
		var frame = sprite.frame
		sword_hit_box.disabled = not (frame >= 2 and frame <= 4)
	else:
		sword_hit_box.disabled = true

func update_parry_hitbox():
	if sprite.animation == "Parry":
		var frame = sprite.frame
		parry_shape.disabled = not (frame >= 0 and frame <= 3)
	else:
		parry_shape.disabled = true

# ATTACK SYSTEM
func attack():
	sprite.play("Attack")
	await sprite.animation_finished
	sprite.play("Idle")
	is_attacking = false

func hitstop(duration: float):
	Engine.time_scale = 0.01
	await get_tree().create_timer(duration * 0.1).timeout
	Engine.time_scale = 1.0

func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Enemy"):
		hitstop(0.018)
		body.take_damage(damage)

# SEKIRO-STYLE PARRY SYSTEM
func initiate_parry():
	last_parry_press_time = Time.get_ticks_msec() / 1000.0
	parry_start_time = last_parry_press_time
	parry_active = true
	parry_successful = false  # Reset flag
	parry_spam_count += 1
	
	sprite.play("Parry")
	await sprite.animation_finished
	sprite.play("Idle")
	parry_active = false
	parry_successful = false  # Clear flag after parry window ends

func calculate_parry_result(time_before_hit: float) -> ParryResult:
	# Perfect parry: within perfect window
	if time_before_hit <= perfect_parry_window:
		return ParryResult.PERFECT
	# Good parry: within good window
	elif time_before_hit <= good_parry_window:
		return ParryResult.GOOD
	# Poor parry: within poor window (adjusted for spam)
	elif time_before_hit <= current_parry_window:
		return ParryResult.POOR
	else:
		return ParryResult.NONE

func _on_parry_hit_box_area_entered(area):
	if not area.is_in_group("Enemy") or not parry_active:
		return
	
	# Calculate timing - how long before the attack would have hit
	var current_time = Time.get_ticks_msec() / 1000.0
	var parry_reaction_time = current_time - parry_start_time
	
	var enemy = area.get_parent()
	if not enemy:
		return
	
	# Determine parry quality based on timing
	var result = calculate_parry_result(parry_reaction_time)
	
	match result:
		ParryResult.PERFECT:
			perform_perfect_parry(enemy)
		ParryResult.GOOD:
			perform_good_parry(enemy)
		ParryResult.POOR:
			perform_poor_parry(enemy)
		_:
			# Missed parry window - take damage
			pass

func perform_perfect_parry(enemy):
	# Perfect deflect - golden sparks, no posture damage, maximum enemy posture damage
	parry_successful = true  # Set flag to block incoming damage
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 0.85, 0.0)  # Gold color
	
	enemy.posture_damage(posture_damage * 1.5)  # 150% posture damage
	hitstop(0.025)  # Longer hitstop for satisfaction
	
	# Reset spam counter as reward
	parry_spam_count = max(0, parry_spam_count - 2)
	
	emit_signal("parry_executed", ParryResult.PERFECT)
	print("PERFECT DEFLECT!")

func perform_good_parry(enemy):
	# Good deflect - white sparks, minor posture damage, normal enemy posture damage
	parry_successful = true  # Set flag to block incoming damage
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 1.0, 1.0)  # White color
	
	current_posture += 5  # Small posture damage
	enemy.posture_damage(posture_damage)  # Normal posture damage
	hitstop(0.019)
	
	emit_signal("parry_executed", ParryResult.GOOD)
	print("Good Deflect")

func perform_poor_parry(enemy):
	# Poor block - red sparks, chip damage, low enemy posture damage
	parry_successful = true  # Set flag to modify damage (not block completely)
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 0.3, 0.3)  # Red color
	
	var chip_damage = enemy.damage / 4  # 25% damage gets through
	health -= chip_damage
	current_posture += 15  # Significant posture damage
	
	enemy.posture_damage(posture_damage * 0.5)  # 50% posture damage
	hitstop(0.015)
	
	emit_signal("parry_executed", ParryResult.POOR)
	print("Poor Block - took chip damage")
	
	if health <= 0:
		die()

# DAMAGE HANDLING
func take_damage(amount: int):
	# If parry successfully blocked/deflected, ignore damage
	if parry_successful:
		return
	
	# If parry is active but hasn't been triggered yet, wait a frame
	# This prevents race conditions where damage arrives before parry detection
	if parry_active:
		return
	
	health -= amount
	current_posture += 20  # Taking damage increases posture
	modulate = Color(1.0, 0.3, 0.3)
	await get_tree().create_timer(0.3).timeout
	modulate = Color(1.0, 1.0, 1.0)
	
	print("Took damage: ", amount, " | Health: ", health)
	
	if health <= 0:
		die()
	
	# Posture break if full
	if current_posture >= max_posture:
		posture_break()

func posture_break():
	print("POSTURE BROKEN!")
	current_posture = 0
	# Could add stagger animation here
	# Temporary invulnerability or knockback

func die():
	death_screen.visible = true
	hide()
	set_physics_process(false)
	set_process(false)
	set_collision_layer_value(2, false)
	death_player.play("Death")

# CAMERA SYSTEM
func lock_camera_to_room(pos: Vector2, size: Vector2):
	camera_locked = true
	cam.limit_left = int(global_position.x)
	cam.limit_right = int(global_position.x + size.x)
	cam.limit_top = int(global_position.y + 59 * 2)
	cam.limit_bottom = int(global_position.y - size.y)
	
	var room_center = global_position + size / 2
	cam.global_position = room_center

func unlock_camera():
	camera_locked = false
	cam.position.y = 0
	cam.limit_left = -99999
	cam.limit_right = 99999
	cam.limit_top = -99999
	cam.limit_bottom = 99999
