extends CharacterBody2D

# ============================================
# EXPORT VARIABLES - Adjust these in Inspector
# ============================================

@export_category("Movement")
@export var speed = 300.0
@export var jump_speed = -400.0
@export var coyote_time = 0.15  # Grace period for jumping after leaving platform
@export var accel := 2000.0     # Acceleration to max speed
@export var decel := 3000.0     # Deceleration when stopping

@export_category("Camera")
@export var look_ahead_distance: float = 100.0
@export var look_ahead_speed: float = 5.0
@export var vertical_offset: float = -59.0

@export_category("Combat Stats")
@export var health = 4
@export var max_posture: int = 100
@export var damage: int = 1
@export var posture_damage_to_enemy: int = 100

@export_category("Parry System - Traditional Fighting Game Style")
@export var perfect_parry_frames := 1      # Perfect on first 1 frame (frame 0)
@export var good_parry_frames := 2         # Good on frames 1-2
# Late parry = frame 3 (chips health)
@export var health_ui:TextureProgressBar
@export var posture_ui:TextureProgressBar

# ============================================
# NODE REFERENCES
# ============================================

@onready var sprite = $Sprite
@onready var sword_hit_box = $SwordHitBox/CollisionShape2D
@onready var cam = $Camera
@onready var parry_box = $ParryHitBox
@onready var parry_shape = $ParryHitBox/CollisionShape2D
@onready var parry_particles = $ParryParticles
@onready var death_screen = $"../Death UI"
@onready var death_player = $"../CanvasModulate/AnimationPlayer"
@onready var ui = $CanvasLayer

# ============================================
# INTERNAL VARIABLES
# ============================================

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Movement state
var coyote_timer = 0.0
var camera_locked: bool = false
var look_ahead_offset: Vector2 = Vector2.ZERO

# Combat state
var can_attack: bool = true
var is_attacking: bool = false
var current_posture: int = 0

# Parry state
var parry_active: bool = false
var parry_current_frame: int = 0
var parry_blocked_this_attack: bool = false

# Parry quality enum
enum ParryResult {
	PERFECT,   # Early timing - frame 0 (best!)
	GOOD,      # Medium timing - frames 1-2
	LATE,      # Late timing - frame 3 (chips health)
}

# ============================================
# SIGNALS
# ============================================

signal attack_started
signal parry_executed(result: ParryResult)

# ============================================
# INITIALIZATION
# ============================================

func _ready():
	sprite.play("Idle")
	health_ui.value = health
	posture_ui.value = current_posture
	ui.visible = true

# ============================================
# PHYSICS PROCESS - Movement & Physics
# ============================================

func _physics_process(delta):
	handle_gravity(delta)
	handle_movement(delta)
	handle_posture_recovery(delta)
	move_and_slide()

func handle_gravity(delta):
	velocity.y += gravity * delta

func handle_movement(delta):
	# Coyote time - allows jumping shortly after walking off ledge
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta
	
	# Jump input
	if Input.is_action_just_pressed("jump") and coyote_timer > 0:
		velocity.y = jump_speed
		coyote_timer = 0

	# Horizontal movement with acceleration/deceleration
	var direction = Input.get_axis("left", "right")
	
	if direction != 0:
		velocity.x = move_toward(velocity.x, direction * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, decel * delta)
	
	# Flip sprite and hitboxes to match movement direction
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
	
	# Camera look-ahead based on movement
	look_ahead_offset.x = lerp(look_ahead_offset.x, direction * look_ahead_distance, delta * look_ahead_speed)
	look_ahead_offset.y = lerp(look_ahead_offset.y, velocity.y * 0.1, delta * look_ahead_speed)
	
	# Slow down during attack for weight
	if is_attacking:
		velocity.x *= 0.8

func handle_posture_recovery(delta):
	# Posture recovers slowly over time when not parrying
	if current_posture > 0 and not parry_active:
		current_posture = max(0, current_posture - int(15.0 * delta))

# ============================================
# PROCESS - Input & Animation Updates
# ============================================

func _process(delta):
	# Update camera position
	update_camera()
	
	# Handle combat inputs
	handle_combat_input()
	
	# Update hitboxes based on current animation
	update_combat_hitboxes()

func update_camera():
	if not camera_locked:
		var target_pos = global_position + look_ahead_offset + Vector2(0, vertical_offset)
		cam.global_position = cam.global_position.lerp(target_pos, 0.1)

func handle_combat_input():
	# Attack input
	if Input.is_action_just_pressed("attack") and can_attack and not parry_active:
		emit_signal("attack_started")
		perform_attack()
	
	# Parry input
	if Input.is_action_just_pressed("parry") and not is_attacking:
		initiate_parry()

func update_combat_hitboxes():
	# Enable sword hitbox only during attack frames
	if sprite.animation == "Attack":
		var frame = sprite.frame
		sword_hit_box.disabled = not (frame >= 2 and frame <= 4)
	else:
		sword_hit_box.disabled = true
	
	# Enable parry hitbox during parry frames and track current frame
	if sprite.animation == "Parry":
		parry_current_frame = sprite.frame
		var frame = sprite.frame
		parry_shape.disabled = not (frame >= 0 and frame <= 3)
	else:
		parry_shape.disabled = true
		parry_current_frame = 0

# ============================================
# ATTACK SYSTEM
# ============================================

func perform_attack():
	is_attacking = true
	sprite.play("Attack")
	await sprite.animation_finished
	sprite.play("Idle")
	is_attacking = false

func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Enemy"):
		apply_hitstop(0.05)  # 50ms hitstop for impact feel
		body.take_damage(damage)

# ============================================
# PARRY SYSTEM - Ghost of Tsushima Style
# ============================================

func initiate_parry():
	# Start parry window
	parry_active = true
	parry_current_frame = 0
	parry_blocked_this_attack = false
	
	# Play parry animation
	sprite.play("Parry")
	await sprite.animation_finished
	sprite.play("Idle")
	
	# End parry window
	parry_active = false
	parry_blocked_this_attack = false
	parry_current_frame = 0

func _on_parry_hit_box_area_entered(area):
	# Only process if actively parrying and haven't blocked an attack yet
	if not area.is_in_group("Enemy") or not parry_active or parry_blocked_this_attack:
		return
	
	var enemy = area.get_parent()
	if not enemy:
		return
	
	# Determine parry quality based on CURRENT FRAME (Traditional fighting game style)
	var result = calculate_parry_quality_by_frame(parry_current_frame)
	
	# Mark that we blocked an attack
	parry_blocked_this_attack = true
	
	# Execute parry based on quality
	match result:
		ParryResult.PERFECT:
			execute_perfect_parry(enemy)
		ParryResult.GOOD:
			execute_good_parry(enemy)
		ParryResult.LATE:
			# Parried too late - chips health
			execute_late_parry(enemy)

func calculate_parry_quality_by_frame(current_frame: int) -> ParryResult:
	# Traditional fighting game style: EARLIER frames = BETTER parry
	# For 4-frame animation (frames 0, 1, 2, 3):
	# Frame 0 = Perfect (first frame - instant reaction!)
	# Frames 1-2 = Good 
	# Frame 3 = Late (chips health)
	
	# Perfect parry: First frame(s)
	if current_frame < perfect_parry_frames:
		return ParryResult.PERFECT
	
	# Good parry: Next few frames
	elif current_frame < perfect_parry_frames + good_parry_frames:
		return ParryResult.GOOD
	
	# Too late: Last frame - chips health
	else:
		return ParryResult.LATE

func execute_perfect_parry(enemy):
	# Perfect parry - Gold sparks, no posture damage, massive enemy posture damage
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 0.85, 0.0)  # Gold
	
	# No posture damage to player
	enemy.posture_damage(posture_damage_to_enemy * 1.3)  # 130% posture damage
	
	apply_hitstop(0.08)  # Longer hitstop for satisfaction
	
	emit_signal("parry_executed", ParryResult.PERFECT)
	print("⚔️ PERFECT PARRY!")

func execute_good_parry(enemy):
	# Good parry - White sparks, minor posture damage, good enemy posture damage
	parry_particles.emitting = true
	parry_particles.modulate = Color(0.298, 0.596, 1.0, 1.0)  # White
	
	current_posture += 9  # Very small posture damage
	posture_ui.value = current_posture
	enemy.posture_damage(posture_damage_to_enemy * 0.9)  # 90% posture damage
	
	apply_hitstop(0.05)
	
	emit_signal("parry_executed", ParryResult.GOOD)
	print("✓ Good Parry")

func execute_late_parry(enemy):
	# Late parry - Red sparks, chip damage to health, some posture cost
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 0.3, 0.3)  # Red
	
	health -= 0.5
	health_ui.value = health
	current_posture += 20
	posture_ui.value = current_posture
	
	enemy.posture_damage(posture_damage_to_enemy * 0.7)  # 70% posture damage
	
	apply_hitstop(0.03)
	
	emit_signal("parry_executed", ParryResult.LATE)
	print("⚠️ Late Parry - took chip damage")
	
	if health <= 0:
		die()

# ============================================
# DAMAGE SYSTEM
# ============================================

func take_damage(amount: int):
	# If actively parrying and blocked an attack, ignore all damage
	if parry_active and parry_blocked_this_attack:
		return
	
	
	# Take full damage
	health -= amount
	current_posture += 15  # Taking damage increases posture
	health_ui.value = health
	posture_ui.value = current_posture
	
	print("💔 Took damage: ", amount, " | Health: ", health)
	
	# Check for death
	if health <= 0:
		die()
	
	# Check for posture break
	if current_posture >= max_posture:
		posture_break()

func posture_break():
	print("⚠️ POSTURE BROKEN!")
	current_posture = 0
	# TODO: Add stagger animation and temporary vulnerability

func die():
	death_screen.visible = true
	hide()
	set_physics_process(false)
	set_process(false)
	set_collision_layer_value(2, false)
	death_player.play("Death")
	ui.visible = false

# ============================================
# HITSTOP / FREEZE FRAMES
# ============================================

func apply_hitstop(duration: float):
	"""Freezes the game briefly for impact feel"""
	# Slow time to near-zero
	Engine.time_scale = 0.05
	
	# Wait for duration (in real time, not slowed time)
	await get_tree().create_timer(duration, true, false, true).timeout
	
	# Restore normal time
	Engine.time_scale = 1.0

# ============================================
# CAMERA CONTROL
# ============================================

func lock_camera_to_room(pos: Vector2, size: Vector2):
	"""Lock camera within room bounds"""
	camera_locked = true
	
	cam.limit_left = int(global_position.x)
	cam.limit_right = int(global_position.x + size.x)
	cam.limit_top = int(global_position.y + 59 * 2)
	cam.limit_bottom = int(global_position.y - size.y)
	
	var room_center = global_position + size / 2
	cam.global_position = room_center

func unlock_camera():
	"""Unlock camera to follow player freely"""
	camera_locked = false
	cam.position.y = 0
	
	cam.limit_left = -99999
	cam.limit_right = 99999
	cam.limit_top = -99999
	cam.limit_bottom = 99999
