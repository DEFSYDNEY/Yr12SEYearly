extends CharacterBody2D
# Archer Enemy - Ranged enemy that maintains distance and fires single, deliberate shots

@export var player: CharacterBody2D

@export_category("Stats")
@export var speed: int = 100
@export var chase_speed: int = 150  # Slower than melee enemies
@export var retreat_speed: int = 200  # Fast when retreating from danger
@export var accel: int = 2000
@export var health: int = 2
@export var max_posture: int = 100
@export var posture_reduction: float = 0.9

@export_category("Archer Combat")
@export var arrow_damage: int = 1
@export var arrow_speed: float = 500.0
@export var shot_cooldown: float = 2.0  # Time between shots
@export var arrow_scene_path: String

@export_category("Patrol Limits")
@export var left_bound_range = -150
@export var right_bound_range = 150
@export var stationary: bool = false

@export_category("Debug")
@export var show_debug_info: bool = true

@onready var sprite = $Sprite
@onready var ray_cast = $RayCast
@onready var player_loss_sight_timer = $PlayerLossSightTimer
@onready var engagement_area = $EngagementArea  # Area2D - when to start shooting (set size in editor!)
@onready var danger_zone = $DangerZone  # Area2D - when to retreat (set size in editor!)
@onready var blood_particles = $BloodParticles
@onready var attack_indication = $FlashIndication/AnimationPlayer
@onready var blood = preload("res://Scenes/World/blood.tscn")
@onready var posture_bar = $"Posture Bar"
@onready var arrow_spawn_point = $FirePoint  # Where arrows spawn from the bow

var arrow_scene = null
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var dir := Vector2.ZERO
var right_bounds: Vector2
var left_bounds: Vector2
var patrol_paused: bool = false
var current_posture = 0
var current_state = states.Patrol

# Archer-specific combat variables
var shot_cooldown_timer: float = 0.0
var can_shoot: bool = true
var player_in_engagement_zone: bool = false  # Set by Area2D signals
var player_in_danger_zone: bool = false  # Set by Area2D signals

# Debug
var debug_label: Label = null

enum states {
	Lookout,   # Standing guard
	Patrol,    # Walking patrol route
	Chase,     # Moving to get in range of player
	Attack,    # Aiming and shooting
	Retreat,   # Player too close, backing away!
	Stunned    # Posture broken
}

func _ready():
	left_bounds = self.position + Vector2(left_bound_range, 0)
	right_bounds = self.position + Vector2(right_bound_range, 0)
	
	if stationary:
		current_state = states.Lookout
	
	# Load arrow scene
	arrow_scene = load(arrow_scene_path)
	
	if show_debug_info:
		setup_debug_display()

func _process(delta):
	velocity.y += gravity * delta
	
	# Update debug display
	if show_debug_info:
		update_debug_display()
	
	# Posture bar visibility
	if current_posture > 0:
		posture_bar.visible = true
	else:
		posture_bar.visible = false

	# Handle shot cooldown
	if not can_shoot:
		shot_cooldown_timer -= delta
		if shot_cooldown_timer <= 0:
			can_shoot = true

func _physics_process(delta):
	movement(delta)
	update_facing_direction()
	look_for_player()

func movement(delta):
	match current_state:
		states.Patrol:
			velocity = velocity.move_toward(dir * speed, accel * delta)
			velocity.y += gravity * delta
			
		states.Chase:
			# Move toward player to get in range
			velocity = velocity.move_toward(dir * chase_speed, accel * delta)
			velocity.y += gravity * delta
			
		states.Attack:
			# Stand still while aiming and shooting
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta * 4)
			velocity.y += gravity * delta
			
		states.Retreat:
			# Move away from player quickly!
			velocity = velocity.move_toward(dir * retreat_speed, accel * delta * 1.5)
			velocity.y += gravity * delta
			
		states.Lookout:
			velocity = Vector2.ZERO
			velocity.y += gravity * delta
			
		states.Stunned:
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta * 0.5)
			velocity.y += gravity * delta

	move_and_slide()

func update_facing_direction():
	"""Update which direction the archer is facing and their attack zones"""
	if current_state == states.Stunned:
		return
	
	# PATROL - face patrol direction
	if current_state == states.Patrol:
		if sprite.flip_h:
			if self.position.x <= right_bounds.x:
				dir = Vector2(1, 0)
			else:
				pause_and_flip(Vector2(-1, 0), false, 180)
		else:
			if self.position.x >= left_bounds.x:
				dir = Vector2(-1, 0)
			else:
				pause_and_flip(Vector2(1, 0), true, -180)
	
	# CHASE, ATTACK, or RETREAT - always face the player
	elif current_state == states.Chase or current_state == states.Attack or current_state == states.Retreat:
		if not player:
			return
		
		var to_player = player.position - self.position
		to_player.y = 0
		
		# For retreat, dir should point AWAY from player
		if current_state == states.Retreat:
			dir = -to_player.normalized()
		else:
			dir = to_player.normalized()
		
		# Face the player
		if to_player.x > 0:
			sprite.flip_h = true
			ray_cast.target_position = Vector2(-300, 0)  # Long range for archers
			engagement_area.scale.x = -1
			danger_zone.scale.x = -1
		else:
			sprite.flip_h = false
			ray_cast.target_position = Vector2(300, 0)
			engagement_area.scale.x = 1
			danger_zone.scale.x = 1

func pause_and_flip(new_dir: Vector2, flip_h: bool, raycast_pos: int):
	"""Pause at patrol endpoints and turn around"""
	if current_state != states.Patrol:
		return
	
	patrol_paused = true
	dir = Vector2.ZERO
	await get_tree().create_timer(1).timeout
	
	if current_state == states.Attack or current_state == states.Chase:
		return
	
	sprite.flip_h = flip_h
	ray_cast.target_position.x = raycast_pos
	dir = new_dir
	engagement_area.scale.x = 1 if not flip_h else -1
	danger_zone.scale.x = 1 if not flip_h else -1
	patrol_paused = false

func look_for_player():
	"""Check line of sight to player"""
	if not player or current_state == states.Stunned:
		return
	
	if ray_cast.is_colliding():
		var collider = ray_cast.get_collider()
		if collider.is_in_group("Player"):
			# Can see player!
			if current_state == states.Patrol or current_state == states.Lookout:
				enter_chase_state()
		else:
			# Lost sight
			if current_state == states.Chase or current_state == states.Attack:
				start_losing_sight()
	else:
		# Nothing blocking ray, but maybe player out of range
		if current_state == states.Chase or current_state == states.Attack:
			start_losing_sight()

func start_losing_sight():
	"""Start timer before giving up chase"""
	if player_loss_sight_timer.time_left <= 0:
		player_loss_sight_timer.start()

func _on_timer_timeout():
	"""Lost sight of player, return to patrol"""
	current_state = states.Patrol

func enter_chase_state():
	"""Start pursuing player to get in range"""
	player_loss_sight_timer.stop()
	current_state = states.Chase

func enter_attack_state():
	"""Enter attack state and start aiming"""
	current_state = states.Attack
	
	# Check if we can actually shoot
	start_attack()

func enter_retreat_state():
	"""Player too close! Back away!"""
	current_state = states.Retreat

# ============================================================
#                  AREA2D SIGNAL HANDLERS
# ============================================================

func _on_engagement_area_body_entered(body):
	"""Player entered shooting range (EngagementArea)"""
	if body.is_in_group("Player"):
		player_in_engagement_zone = true
		# If we're chasing and player enters range, start attacking
		enter_attack_state()

func _on_engagement_area_body_exited(body):
	"""Player left shooting range (EngagementArea)"""
	if body.is_in_group("Player"):
		player_in_engagement_zone = false
		# If we're attacking and player leaves range, chase them
		if current_state == states.Attack:
			current_state = states.Chase

func _on_danger_zone_body_entered(body):
	"""Player got too close! (DangerZone)"""
	if body.is_in_group("Player"):
		player_in_danger_zone = true
		# Player is dangerously close, retreat!
		if current_state != states.Stunned:
			enter_retreat_state()

func _on_danger_zone_body_exited(body):
	"""Player backed off (DangerZone)"""
	if body.is_in_group("Player"):
		player_in_danger_zone = false
		# Player is no longer a threat, return to chase
		if current_state == states.Retreat:
			enter_chase_state()

# ============================================================
#                  ARCHER SHOOTING SYSTEM
# ============================================================

func start_attack():
	sprite.play("Shoot")  # Your bow draw animation
	
	# Show attack indication
	attack_indication.play("attack")

func _on_sprite_frame_changed():
	if sprite.animation == "Shoot":
		var frame = sprite.frame
		
		if frame == 14:
			fire_arrow()

func fire_arrow():
	# Create arrow
	var arrow = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = arrow_spawn_point.global_position
	
	# Aim at where player currently is
	var target_pos = player.global_position
	var direction = (target_pos - arrow_spawn_point.global_position).normalized()
	
	# Initialize arrow
	if arrow.has_method("initialize"):
		arrow.initialize(direction, arrow_speed, arrow_damage)
	elif arrow.has_method("set_direction"):
		arrow.set_direction(direction, arrow_speed)
	
	# After shooting, decide next action based on player position
	await get_tree().create_timer(0.2).timeout
	
	# Check if player is still in engagement zone
	if current_state == states.Attack:
		if not player_in_engagement_zone:
			# Player left range while we were shooting, chase them
			current_state = states.Chase
		elif not can_shoot:
			# On cooldown, might want to reposition slightly
			# Stay in attack state and will shoot again when cooldown ends
			pass

# ============================================================
#                    DAMAGE HANDLING
# ============================================================

func take_damage(amount: int):
	"""Handle taking damage from player attacks"""
	health -= amount
	blood_particles.emitting = true
	
	# Spawn blood effect
	var bloods = blood.instantiate()
	get_tree().current_scene.call_deferred("add_child", bloods)
	bloods.call_deferred("set_global_position", global_position)
	
	# If hit while not in combat, become alert and retreat
	if current_state == states.Patrol or current_state == states.Lookout:
		enter_retreat_state()
	
	if health <= 0:
		queue_free()

# ============================================================
#                    DEBUG DISPLAY
# ============================================================

func setup_debug_display():
	"""Create debug label"""
	debug_label = Label.new()
	debug_label.position = Vector2(-60, -100)
	debug_label.add_theme_font_size_override("font_size", 12)
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.7)
	style_box.set_corner_radius_all(4)
	style_box.set_content_margin_all(4)
	debug_label.add_theme_stylebox_override("normal", style_box)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	add_child(debug_label)

func update_debug_display():
	"""Update debug info"""
	if debug_label == null:
		return
	
	var state_name = states.keys()[current_state]
	var vel_x = snappedf(velocity.x, 0.1)
	var vel_y = snappedf(velocity.y, 0.1)
	
	var debug_text = "State: %s\n" % state_name
	debug_text += "Vel: (%.1f, %.1f)\n" % [vel_x, vel_y]
	
	if player:
		var dist = global_position.distance_to(player.global_position)
		debug_text += "Dist: %.0f\n" % dist
	
	# Show zone status
	if player_in_engagement_zone:
		debug_text += "[IN RANGE] "
	if player_in_danger_zone:
		debug_text += "[DANGER!]"
	if not can_shoot:
		debug_text += "\n[COOLDOWN %.1fs]" % shot_cooldown_timer
	
	debug_label.text = debug_text
