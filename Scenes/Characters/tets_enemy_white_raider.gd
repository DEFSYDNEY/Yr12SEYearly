extends CharacterBody2D

@export var player: CharacterBody2D

@export_category("Stats")
@export var speed: int = 100
@export var chase_speed: int = 250
@export var accel: int = 2000
@export var health: int = 2
@export var damage: int = 1
@export var max_posture: int = 100
@export var posture_reduction: float = 0.9

@export_category("AI Parrying")
@export var parry_chance := 0.25
@export var perfect_parry_chance := 0.15  # Chance to do perfect parry
@export var parry_window := 0.25
@export var parry_prediction_time := 0.3  # How early AI starts parry

@export_category("Patrol Limits")
@export var left_bound_range = -150
@export var right_bound_range = 150
@export var stationary: bool = false

@onready var sprite = $Sprite
@onready var ray_cast = $Sprite/RayCast2D
@onready var player_loss_sight_timer = $PlayerLossSightTimer
@onready var attack_area = $"Attack area"
@onready var sword_hitbox_collision = $SwordHitBox/CollisionShape2D
@onready var blood_particles = $BloodParticles
@onready var parry_particles = $ParryParticles
@onready var attack_timer = $Attack_timer
@onready var attack_indication = $FlashIndication/AnimationPlayer
@onready var blood = preload("res://Scenes/World/blood.tscn")
@onready var posture_bar = $"Posture Bar"

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var dir := Vector2.ZERO
var right_bounds: Vector2
var left_bounds: Vector2
var patrol_paused: bool = false
var attack_cooldown: bool = false
var is_stunned: bool = false
var aggro: bool = false
var current_posture = 0

# Parry system
var parry_active: bool = false
var parry_type: int = 0  # 0=none, 1=perfect, 2=good, 3=poor
var parry_start_time: float = 0.0
var last_parry_attempt: float = 0.0

enum states {
	Lookout,
	Patrol,
	Chase,
	Attack,
	Stunned,
}

var current_state = states.Patrol

func _ready():
	left_bounds = self.position + Vector2(left_bound_range, 0)
	right_bounds = self.position + Vector2(right_bound_range, 0)
	
	if player:
		player.connect("attack_started", Callable(self, "on_player_attack_started"))
	
	if stationary:
		current_state = states.Lookout

func _process(delta):
	posture_bar.visible = current_posture > 0
	
	# Posture recovery
	if current_posture > 0 and not parry_active:
		current_posture = max(0, current_posture - int(10.0 * delta))

func _physics_process(delta):
	handle_gravity(delta)
	movement(delta)
	change_direction()
	look_for_player()

func handle_gravity(delta):
	velocity.y += gravity * delta

func movement(delta):
	match current_state:
		states.Patrol:
			velocity = velocity.move_toward(dir * speed, accel * delta)
		states.Chase:
			velocity = velocity.move_toward(dir * chase_speed, accel * delta)
		states.Attack, states.Lookout:
			velocity = Vector2.ZERO
		states.Stunned:
			velocity.x = move_toward(velocity.x, 0, accel * delta)
	
	move_and_slide()

func change_direction():
	if current_state == states.Stunned:
		return
	
	# PATROL
	if current_state == states.Patrol:
		aggro = false
		if sprite.flip_h:
			if self.position.x <= right_bounds.x:
				dir = Vector2(1, 0)
			else:
				pause_and_flip(Vector2(-1, 0), false, -125, -1, 1)
		else:
			if self.position.x >= left_bounds.x:
				dir = Vector2(-1, 0)
			else:
				pause_and_flip(Vector2(1, 0), true, 125, 1, -1)
	
	# CHASE
	elif current_state == states.Chase:
		if not player:
			return
		
		aggro = true
		var x_only = player.position - self.position
		x_only.y = 0
		dir = x_only.normalized()
		
		if dir.x > 0:
			sprite.flip_h = true
			ray_cast.target_position = Vector2(125, 0)
			attack_area.scale.x = -1
			sword_hitbox_collision.scale.x = 1
			parry_particles.position.x = 18
		else:
			sprite.flip_h = false
			ray_cast.target_position = Vector2(-125, 0)
			attack_area.scale.x = 1
			sword_hitbox_collision.scale.x = -1
			parry_particles.position.x = -18

func pause_and_flip(new_dir: Vector2, flip_h: bool, raycast_new_pos: int, sword_scale: int, attack_scale: int):
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
	sword_hitbox_collision.scale.x = sword_scale
	attack_area.scale.x = attack_scale
	patrol_paused = false

func look_for_player():
	if not player or current_state == states.Stunned:
		return
	
	if ray_cast.is_colliding():
		var collider = ray_cast.get_collider()
		if collider and collider.is_in_group("Player") and current_state != states.Attack:
			chase_player()
		elif current_state == states.Chase:
			stop_chase()
	elif current_state == states.Chase:
		stop_chase()

func chase_player():
	if current_state == states.Stunned:
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
	if current_state == states.Stunned:
		return
	if body.is_in_group("Player"):
		current_state = states.Attack
		aggro = true
		if not attack_cooldown:
			attack()

func _on_attack_area_body_exited(body):
	if current_state == states.Stunned:
		return
	if body.is_in_group("Player") and current_state == states.Attack:
		current_state = states.Chase

func attack():
	current_state = states.Attack
	sprite.play("Attack")

func _on_sprite_frame_changed():
	if sprite.animation == "Attack" and not attack_cooldown:
		var frame = sprite.frame
		if frame == 1:
			attack_indication.play("attack")
		elif frame == 4 or frame == 5:
			sword_hitbox_collision.disabled = false
	else:
		sword_hitbox_collision.disabled = true

func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Player"):
		body.take_damage(damage)
		attack_cooldown = true
		attack_timer.start()

func _on_sprite_animation_finished():
	if sprite.animation == "Attack":
		sword_hitbox_collision.disabled = true
		
		if current_state == states.Stunned:
			return
		
		if ray_cast.is_colliding():
			var collider = ray_cast.get_collider()
			if collider and collider.is_in_group("Player"):
				current_state = states.Chase
				aggro = true
			else:
				current_state = states.Patrol
				aggro = false
		else:
			current_state = states.Patrol
			aggro = false
	
	elif sprite.animation == "Parry":
		parry_active = false

# SEKIRO-STYLE PARRY SYSTEM
func on_player_attack_started():
	if not is_player_attack_dangerous():
		return
	
	if current_state == states.Stunned:
		return
	
	# Roll for parry attempt
	if randf() >= parry_chance:
		return
	
	# Determine parry quality
	var perfect_roll = randf() < perfect_parry_chance
	
	if perfect_roll:
		# Perfect parry - react at optimal time
		parry_type = 1
		await get_tree().create_timer(parry_prediction_time * 0.8).timeout
	else:
		# Normal parry - slight variation in timing
		parry_type = 2
		var timing_variation = randf_range(0.9, 1.1)
		await get_tree().create_timer(parry_prediction_time * timing_variation).timeout
	
	if current_state == states.Stunned:
		return
	
	initiate_parry()

func initiate_parry():
	parry_active = true
	parry_start_time = Time.get_ticks_msec() / 1000.0
	last_parry_attempt = parry_start_time
	
	sprite.play("Parry")
	
	# Set timeout for parry window
	var timer = get_tree().create_timer(parry_window)
	timer.timeout.connect(Callable(self, "_on_parry_window_timeout"))

func _on_parry_window_timeout():
	parry_active = false
	parry_type = 0

func is_player_attack_dangerous() -> bool:
	if not player:
		return false
	
	var player_sword = player.get_node_or_null("SwordHitBox/CollisionShape2D")
	if not player_sword:
		return false
	
	var sword_shape = player_sword.shape
	if not sword_shape:
		return false
	
	var sword_transform = player_sword.global_transform
	var enemy_shape = $CollisionShape2D.shape
	var enemy_transform = global_transform
	
	return sword_shape.collide(sword_transform, enemy_shape, enemy_transform)

# POSTURE SYSTEM
func posture_damage(player_damage: int):
	var adjusted_damage = player_damage * posture_reduction
	current_posture += int(adjusted_damage)
	
	print("Enemy posture: ", current_posture, "/", max_posture)
	posture_bar.value = current_posture
	
	if current_posture >= max_posture:
		staggered()
		current_posture = 0

func staggered():
	print("Enemy STAGGERED!")
	aggro = true
	current_state = states.Stunned
	dir = Vector2.ZERO
	velocity = Vector2.ZERO
	
	sprite.play("Stagger")
	await sprite.animation_finished
	restore_state_after_stun()

func restore_state_after_stun():
	# Check if player is still in attack range
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("Player"):
			attack()
			return
	
	current_state = states.Chase

# DAMAGE HANDLING WITH PARRY
func take_damage(amount: int):
	# Perfect parry - no damage, enemy gets staggered
	if parry_active and parry_type == 1:
		perform_perfect_enemy_parry()
		return
	
	# Good parry - partial posture damage, no health damage
	if parry_active and parry_type == 2:
		perform_good_enemy_parry()
		return
	
	# No parry or poor timing - take damage
	health -= amount
	blood_particles.emitting = true
	
	var bloods = blood.instantiate()
	get_tree().current_scene.call_deferred("add_child", bloods)
	bloods.call_deferred("set_global_position", global_position)
	
	if not aggro:
		ray_cast.target_position.x = -ray_cast.target_position.x
	
	if health <= 0:
		queue_free()

func perform_perfect_enemy_parry():
	print("Enemy PERFECT PARRY!")
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 0.85, 0.0)  # Gold
	
	# No health damage
	# Enemy counters - player takes posture damage
	if player and player.has_method("take_posture_damage"):
		player.current_posture += 30
	
	# Small hitstop for impact
	Engine.time_scale = 0.01
	await get_tree().create_timer(0.025 * 0.01).timeout
	Engine.time_scale = 1.0
	
	parry_active = false
	parry_type = 0

func perform_good_enemy_parry():
	print("Enemy Good Parry")
	parry_particles.emitting = true
	parry_particles.modulate = Color(1.0, 1.0, 1.0)  # White
	
	# Takes minor posture damage but no health damage
	current_posture += 10
	
	if player and player.has_method("take_posture_damage"):
		player.current_posture += 10
	
	Engine.time_scale = 0.01
	await get_tree().create_timer(0.019 * 0.01).timeout
	Engine.time_scale = 1.0
	
	parry_active = false
	parry_type = 0

func on_attack_timer_timeout():
	attack_cooldown = false
	
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("Player"):
			attack()
			return
