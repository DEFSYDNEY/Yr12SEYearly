extends CharacterBody2D

@export var player: CharacterBody2D

@export_category("Stats")
@export var speed:int = 100
@export var chase_speed:int = 250
@export var accel:int = 2000
@export var health: int = 2
@export var damage: int = 1
@export var max_posture:int = 100
@export var posture_reduction: float = 0.9

@export_category("Combat Behavior")
# These new variables control the Sekiro-style combat flow
@export var combo_attack_count_min: int = 2  # Minimum attacks in a combo
@export var combo_attack_count_max: int = 3  # Maximum attacks in a combo
@export var recovery_time: float = 1.5  # How long enemy is vulnerable after attacking
@export var defensive_time: float = 1.0  # How long enemy stays defensive before attacking again
@export var attack_spacing_distance: float = 80.0  # Preferred distance to attack from

@export_category("Parrying")
@export var parry_chance := 0.25
@export var parry_window := 0.25
@export var parry_cooldown: float = 2.0  # Prevent parry spam

@export_category("Patrol Limits")
@export var left_bound_range = -150
@export var right_bound_range = 150
@export var stationary:bool = false

@export_category("Debug")
@export var show_debug_info: bool = true  # Toggle to show/hide debug display in-game

@onready var sprite = $Sprite
@onready var ray_cast = $Sprite/RayCast2D
@onready var player_loss_sight_timer = $PlayerLossSightTimer
@onready var attack_area = $"Attack area"
@onready var sword_hitbox_collision = $SwordHitBox/CollisionShape2D
@onready var defensive_area = $Defensive_Area
@onready var blood_particles = $BloodParticles
@onready var parry_particles = $ParryParticles
@onready var attack_timer = $Attack_timer
@onready var attack_indication = $FlashIndication/AnimationPlayer
@onready var blood = preload("res://Scenes/World/blood.tscn")
@onready var posture_bar = $"Posture Bar"
@onready var shield_icon = $Shield
#@onready var recover_icon = 

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var dir := Vector2.ZERO
var right_bounds: Vector2
var left_bounds: Vector2
var patrol_paused: bool = false
var attack_cooldown:bool = false
var is_stunned:bool = false
var aggro:bool = false
var current_posture = 0
var current_state = states.Patrol

# -------- PARRY SYSTEM --------
var parry_active: bool = false
var parry_consumed: bool = false
var can_parry: bool = true  # New: prevents parry spam
var parry_cooldown_timer: float = 0.0

# -------- SEKIRO-STYLE COMBAT FLOW --------
var current_combo_count: int = 0  # How many attacks we've done in current combo
var total_combo_attacks: int = 0  # Total attacks planned for this combo
var in_recovery: bool = false  # Enemy is recovering after combo, vulnerable window
var in_defensive_stance: bool = false  # Enemy is in defensive stance, waiting to attack
var recovery_timer: float = 0.0
var defensive_timer: float = 0.0

# -------- DEBUG DISPLAY --------
var debug_label: Label = null  # Dynamically created label to show state and velocity

enum states {
	Lookout, # Stands still 
	Patrol, # Wanders from two points set using code
	Chase, # Chases player even if cant see will chase for a little
	Attack, # Attacking the player
	Stunned, # From having posture broken unable to move or do any action
	Recovery,  #vulnerable after attacking
	Defensive  #observing player and parrying
}

func _ready():
	left_bounds = self.position + Vector2(left_bound_range, 0)
	right_bounds = self.position + Vector2(right_bound_range, 0)
	player.connect("attack_started", Callable(self, "on_player_attack_started"))
	if stationary == true:
		current_state = states.Lookout
	
	# Create debug display if enabled
	if show_debug_info:
		setup_debug_display()

func _process(delta):
	velocity.y += gravity * delta
	
	# Update debug display every frame if enabled
	if show_debug_info and debug_label != null:
		update_debug_display()
	
	if current_posture > 0:
		posture_bar.visible = true
	else:
		posture_bar.visible = false
	
	# Handle timers for combat flow
	if parry_cooldown_timer > 0:
		parry_cooldown_timer -= delta
		if parry_cooldown_timer <= 0:
			can_parry = true
	
	# Handle recovery state timer
	if recovery_timer > 0:
		recovery_timer -= delta
		if recovery_timer <= 0:
			end_recovery()
	
	# Handle defensive stance timer
	if defensive_timer > 0:
		defensive_timer -= delta
		if defensive_timer <= 0:
			end_defensive_stance()

func _physics_process(delta):
	movement(delta)
	change_direction()
	look_for_player()

func movement(delta):
	match current_state:
		states.Patrol:
			velocity = velocity.move_toward(dir * speed, accel * delta)
			velocity.y += gravity * delta
			
		states.Chase:
			# Smarter chasing: slow down when close to player for better spacing
			var distance_to_player = global_position.distance_to(player.global_position)
			var effective_speed = chase_speed
			
			# Slow down when getting close to maintain spacing
			if distance_to_player < attack_spacing_distance * 1.5:
				effective_speed = chase_speed * 0.5
			
			velocity = velocity.move_toward(dir * effective_speed, accel * delta)
			velocity.y += gravity * delta
			
		states.Attack:
			# Very slight movement during attack for better feel
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta * 2)
			velocity.y += gravity * delta
			
		states.Lookout:
			velocity = Vector2.ZERO
			velocity.y += gravity * delta
			
		states.Stunned:
			# Stunned state keeps some momentum
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta * 0.5)
			velocity.y += gravity * delta
			
		states.Recovery:
			# Vulnerable, can't move much
			velocity = velocity.move_toward(Vector2.ZERO, accel * delta * 3)
			velocity.y += gravity * delta
			
		states.Defensive:
			# They're observing, ready to parry, creating tension slowly creeping forward if needed
			var distance_to_player = global_position.distance_to(player.global_position)
			var direction = (player.global_position - global_position).normalized()
			var effective_speed = 30
			
			if distance_to_player < 60:
				velocity = velocity.move_toward(-dir, accel * delta)
			else:
				velocity = velocity.move_toward(direction * effective_speed, accel * delta)
				velocity.y += gravity * delta


	move_and_slide()

func change_direction():
	if current_state == states.Stunned or current_state == states.Recovery:
		return
	
	# ------------------- PATROL -------------------
	if current_state == states.Patrol:
		aggro = false
		if sprite.flip_h:
			if self.position.x <= right_bounds.x:
				dir = Vector2(1,0)
			else:
				pause_and_flip(Vector2(-1,0), false, -125, -1, 1, 1)
		else:
			if self.position.x >= left_bounds.x:
				dir = Vector2(-1,0)
			else:
				pause_and_flip(Vector2(1,0), true, 125, 1, -1, -1)

	# -------------------- CHASE --------------------
	elif current_state == states.Chase:
		if !player: 
			return
		
		aggro = true
		
		var x_only = player.position - self.position
		x_only.y = 0
		dir = x_only.normalized()

		if dir.x > 0:
			sprite.flip_h = true
			ray_cast.target_position = Vector2(180,0)
			attack_area.scale.x = -1
			defensive_area.scale.x = -1
			sword_hitbox_collision.scale.x = 1
			parry_particles.position.x = 18
		else:
			sprite.flip_h = false
			ray_cast.target_position = Vector2(-180,0)
			attack_area.scale.x = 1
			defensive_area.scale.x = 1
			sword_hitbox_collision.scale.x = -1
			parry_particles.position.x = -18
	
	# -------------------- DEFENSIVE --------------------
	elif current_state == states.Defensive:
		if !player: 
			return
		
		aggro = true
		
		# Only update facing direction, not movement direction
		# Enemy holds ground but tracks player with their eyes/body
		var x_only = player.position - self.position
		x_only.y = 0
		var facing_dir = x_only.normalized()

		if facing_dir.x > 0:
			sprite.flip_h = true
			ray_cast.target_position = Vector2(180,0)
			attack_area.scale.x = -1
			defensive_area.scale.x = -1
			sword_hitbox_collision.scale.x = 1
			parry_particles.position.x = 18
		else:
			sprite.flip_h = false
			ray_cast.target_position = Vector2(-180,0)
			attack_area.scale.x = 1
			defensive_area.scale.x = 1
			sword_hitbox_collision.scale.x = -1
			parry_particles.position.x = -18
		
		# Keep dir at zero so enemy doesn't walk during defensive stance
		dir = Vector2.ZERO

func pause_and_flip(new_dir: Vector2, flip_h: bool, raycast_new_pos: int, sword_hitbox_scale: int, attack_hitbox: int, defensive_area_scale: int):
	if current_state != states.Patrol: 
		return

	patrol_paused = true
	dir = Vector2.ZERO
	await get_tree().create_timer(1).timeout

	if current_state == states.Attack or current_state == states.Chase:
		return

	sprite.flip_h = flip_h
	ray_cast.target_position.x = raycast_new_pos
	dir = new_dir
	sword_hitbox_collision.scale.x = sword_hitbox_scale
	attack_area.scale.x = attack_hitbox
	defensive_area.scale.x = defensive_area_scale
	patrol_paused = false

func look_for_player():
	if !player:
		return
	
	if current_state == states.Stunned:
		return
	
	if ray_cast.is_colliding():
		var collider = ray_cast.get_collider()
		if collider.is_in_group("Player") and current_state != states.Attack and current_state != states.Stunned and current_state != states.Recovery and current_state != states.Defensive:
			aggro = true
			chase_player()
		elif current_state == states.Chase:
			stop_chase()
	elif current_state == states.Chase:
		stop_chase()

func chase_player():
	if current_state == states.Stunned or current_state == states.Recovery:
		return
	player_loss_sight_timer.stop()
	current_state = states.Chase

func stop_chase():
	if player_loss_sight_timer.time_left <= 0:
		player_loss_sight_timer.start()

func _on_timer_timeout():
	current_state = states.Patrol
	aggro = false

func _on_attack_area_body_entered(body):
	if body.is_in_group("Player"):
		# Only attack if not in recovery or defensive stance
		if current_state != states.Recovery and current_state != states.Defensive and current_state != states.Stunned:
			initiate_attack_combo()

func _on_attack_area_body_exited(body):
	if body.is_in_group("Player"):
		# If we're not attacking, go back to chase
		if current_state == states.Attack:
			current_state = states.Chase
		elif current_state == states.Recovery:
			# Still in recovery, but player left - stay in recovery
			# Don't change state, let the recovery timer complete
			pass
		elif current_state == states.Defensive:
			# Player left defensive range
			# DON'T immediately chase - let the defensive stance complete
			# The defensive timer will handle the transition naturally
			# This prevents the flickering you're seeing
			pass

# ============================================================
#                      ATTACK SYSTEM
# ============================================================

func initiate_attack_combo():
	#Enemy commits to a sequence of attacks, creating pressure but also
	#leaving them vulnerable afterwards.
	if attack_cooldown:
		return
	
	if current_state == states.Recovery or current_state == states.Stunned:
		return
	
	current_state = states.Attack
	current_combo_count = 0
	
	# Randomly decide how many attacks in this combo from max and min combo
	total_combo_attacks = randi_range(combo_attack_count_min, combo_attack_count_max)
	
	# Start the first attack
	execute_attack()

func execute_attack():
	#Execute a single attack in the combo sequence
	sprite.play("Attack")
	current_combo_count += 1 # Track how many times attacked

func _on_sprite_frame_changed():
	if sprite.animation == "Attack":
		var frame = sprite.frame
		if frame == 1:
			attack_indication.play("attack")
			sword_hitbox_collision.disabled = true
		elif frame == 4:
			sword_hitbox_collision.disabled = false
		elif frame == 5:
			sword_hitbox_collision.disabled = true
	else:
		sword_hitbox_collision.disabled = true

func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Player"):
		body.take_damage(damage)

func _on_sprite_animation_finished():
	if sprite.animation == "Attack":
		sword_hitbox_collision.disabled = true
		
		# Check if it should continue the combo or enter recovery
		if current_combo_count < total_combo_attacks and current_state != states.Stunned:
			# Continue combo with a small delay for rhythm
			await get_tree().create_timer(0.3).timeout
			if current_state == states.Attack:  # Make sure its still in attack state
				execute_attack()
		else:
			# Combo finished - enter recovery state (THIS IS THE PLAYER OPENING)
			enter_recovery()

func enter_recovery():
	#Enter recovery state after finishing attack combo.
	
	current_state = states.Recovery
	in_recovery = true
	recovery_timer = recovery_time
	attack_cooldown = true
	
	# During recovery, enemy cannot parry
	can_parry = false
	sprite.play("Test")
	# Play recovery animation if you have one
	dir = Vector2.ZERO
	velocity = Vector2.ZERO

func end_recovery():
	#Exit recovery state and enter defensive stance.
	#Enemy becomes cautious, waiting and ready to parry.
	in_recovery = false
	attack_cooldown = false
	
	# Check if player is still in range
	var bodies_in_range = defensive_area.get_overlapping_bodies()
	var player_in_range = false
	
	for body in bodies_in_range:
		if body.is_in_group("Player"):
			player_in_range = true
			break
	
	if player_in_range:
		# Enter defensive stance - this creates the back-and-forth rhythm
		enter_defensive_stance()
	else:
		# Player left, go back to chasing
		current_state = states.Chase

func enter_defensive_stance():
	#Enemy enters a defensive/observant state.
	#They're ready to parry and waiting for the right moment to attack again.
	
	current_state = states.Defensive
	in_defensive_stance = true
	defensive_timer = defensive_time
	can_parry = true  # Ready to parry during defensive stance
	shield_icon.visible = true
	
	# Stop movement when entering defensive stance - enemy holds their ground
	#dir = Vector2.ZERO
	#velocity = Vector2.ZERO

func end_defensive_stance():
	#Exit defensive stance and potentially attack again.
	
	in_defensive_stance = false
	# Check if player is still in range
	var bodies_in_range = attack_area.get_overlapping_bodies()
	var player_in_range = false
	
	for body in bodies_in_range:
		if body.is_in_group("Player"):
			player_in_range = true
			break
	
	if player_in_range:
		# 70% chance to attack again, 30% chance to stay defensive longer
		if randf() < 0.7:
			initiate_attack_combo()
			shield_icon.visible = false
		else:
			# Stay defensive a bit longer
			print("Continue defense")
			defensive_timer = defensive_time * 0.5
	else:
		current_state = states.Chase
		shield_icon.visible = false

# ============================================================
#                    PARRY SYSTEM
# ============================================================

func on_player_attack_started():
	#Called when player starts an attack.
	#Enemy may attempt to parry if conditions are right.
	
	# Cannot parry during recovery
	if current_state == states.Recovery:
		return
	
	# Cannot parry when stunned
	if current_state == states.Stunned:
		return
	
	# Cannot parry if on cooldown
	if not can_parry:
		return
	
	if not aggro:
		return
	
	# Check if attack is dangerous
	if not is_player_attack_dangerous():
		return
	
	# Activate parry window
	parry_active = true
	parry_consumed = false
	sprite.play("Parry")
	
	# Put parry on cooldown
	can_parry = false
	parry_cooldown_timer = parry_cooldown
	
	# Schedule closing of parry window
	var t = get_tree().create_timer(parry_window)
	t.timeout.connect(Callable(self, "_on_parry_window_timeout"))

func _on_parry_window_timeout():
	parry_active = false

func is_player_attack_dangerous() -> bool:
	if not player:
		return false
	
	var sword_shape = player.sword_hit_box.shape
	var sword_transform = player.sword_hit_box.global_transform
	var enemy_shape = $CollisionShape2D.shape
	var enemy_transform = global_transform
	
	return sword_shape.collide(sword_transform, enemy_shape, enemy_transform)

# ============================================================
#                    STAGGER/POSTURE SYSTEM
# ============================================================

func staggered():
	#Enemy is staggered when posture breaks.
	#This is a punish opportunity for the player.
	
	aggro = true
	current_state = states.Stunned
	dir = Vector2.ZERO
	velocity = Vector2.ZERO
	in_recovery = false  # Clear recovery state
	in_defensive_stance = false  # Clear defensive state
	sprite.play("Stagger")
	await sprite.animation_finished
	restore_state_after_stun()

func restore_state_after_stun():
	#After being staggered, enemy returns to combat but in defensive stance.
	#They're more cautious after being broken.
	
	var bodies = attack_area.get_overlapping_bodies()
	for body in bodies:
		if body.is_in_group("Player"):
			# Player is close, enter defensive stance rather than attacking immediately
			enter_defensive_stance()
			return
	
	# No player nearby, return to chase
	current_state = states.Chase

func posture_damage(player_posture_damage: int):
	#Handle posture damage. When posture breaks, enemy is staggered.
	
	current_posture += player_posture_damage * posture_reduction
	posture_bar.value = current_posture
	
	# Brief hitstop for feedback
	#Engine.time_scale = 0.01
	#await get_tree().create_timer(0.01).timeout
	#Engine.time_scale = 1.0
	
	if current_posture >= max_posture:
		staggered()
		current_posture = 0

# ============================================================
#                    DAMAGE HANDLING
# ============================================================

func take_damage(amount: int):
	#Handle taking damage from player attacks.
	#Parry system is integrated here.
	
	# Blocked because enemy is currently parrying
	if parry_active and not parry_consumed:
		parry_consumed = true
		perform_parry_effects()
		return

	# If parry was active but already consumed, ignore extra hit
	if parry_active and parry_consumed:
		return
	
	# Take Damage Normally
	health -= amount
	blood_particles.emitting = true
	
	# Spawn blood effect
	var bloods = blood.instantiate()
	get_tree().current_scene.call_deferred("add_child", bloods)
	bloods.call_deferred("set_global_position", global_position)
	
	# If hit while not aggressive, turn around to face attacker
	if aggro != true:
		enter_defensive_stance()
		if sprite.flip_h:
			ray_cast.target_position = Vector2(-180,0)
		else:
			ray_cast.target_position = Vector2(180,0)

	if health <= 0:
		queue_free()

func perform_parry_effects():
	#Visual and mechanical effects when enemy successfully parries.
	parry_particles.emitting = true
	
	# Could add knockback to player here if you want
	# player.apply_knockback(...)

func on_attack_timer_timeout():
	attack_cooldown = false

# ============================================================
#                    DEBUG DISPLAY SYSTEM
# ============================================================

func setup_debug_display():
	#Creates a Label node that floats above the enemy showing real-time debug info.
	# helps with bug fixes
	# Create a new Label node
	debug_label = Label.new()
	
	# Position it above the enemy's head (adjust Y value based on your sprite size)
	debug_label.position = Vector2(-50, -100)  # X offset for centering, Y offset above head
	
	# Make the text more readable
	debug_label.add_theme_font_size_override("font_size", 12)
	
	# Add a semi-transparent background so text is always readable
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.7)  # Black with 70% opacity
	style_box.set_corner_radius_all(4)
	style_box.set_content_margin_all(4)
	debug_label.add_theme_stylebox_override("normal", style_box)
	
	# Make sure the label doesn't affect physics or mouse input
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Add the label as a child of this enemy
	add_child(debug_label)

func update_debug_display():
	#Updates the debug label every frame with current state and velocity info.
	
	if debug_label == null:
		return
	
	# Get the state name as a string for display
	var state_name = states.keys()[current_state]
	
	# Format velocity values to 1 decimal place for readability
	var vel_x = snappedf(velocity.x, 0.1)
	var vel_y = snappedf(velocity.y, 0.1)
	
	# Build the debug text with all relevant info
	var debug_text = "State: %s\n" % state_name
	debug_text += "Vel: (%.1f, %.1f)\n" % [vel_x, vel_y]
	debug_text += "Dir: (%.1f, %.1f)" % [dir.x, dir.y]
	
	# Optional: Add more debug info as needed
	if in_recovery:
		debug_text += "\n[VULNERABLE]"
	if can_parry and current_state == states.Defensive:
		debug_text += "\n[CAN PARRY]"
	if attack_cooldown:
		debug_text += "\n[COOLDOWN]"
	
	# Update the label text
	debug_label.text = debug_text
