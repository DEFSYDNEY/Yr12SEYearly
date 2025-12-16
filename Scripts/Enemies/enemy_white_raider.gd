extends CharacterBody2D

@export var player: CharacterBody2D
@export var speed:int = 100
@export var chase_speed:int = 250
@export var accel:int = 2000
@export var health: int = 2
@export var damage: int = 1
@export var stationary:bool = false

@export var parry_chance := 0.25
@export var parry_window := 0.25   # how long the parry can block hits makes it so every parry guarantees to register

@export var left_bound_range = -150 # So i can have multiple enemies with different patrol route distances
@export var right_bound_range = 150 # Remeber left must be negative, right positive 

@onready var sprite = $Sprite
@onready var ray_cast = $Sprite/RayCast2D
@onready var timer = $PlayerLossSightTimer
@onready var attack_area = $"Attack area"
@onready var sword_hitbox_collision = $SwordHitBox/CollisionShape2D
@onready var blood_particles = $BloodParticles
@onready var parry_particles = $ParryParticles
@onready var attack_timer = $Attack_timer
@onready var attack_indication = $FlashIndication/AnimationPlayer

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var dir := Vector2.ZERO
var right_bounds: Vector2
var left_bounds: Vector2
var patrol_paused: bool = false
var attack_cooldown:bool = false
var is_stunned:bool = false
var aggro:bool = false
# -------- PARRY SYSTEM --------
var parry_active: bool = false        # parry window currently open
var parry_consumed: bool = false      # player's current attack not blocked

#signal enemy_parry

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
	player.connect("attack_started", Callable(self, "on_player_attack_started"))
	sprite.connect("frame_changed", Callable(self, "_on_sprite_frame_changed"))
	sprite.connect("animation_finished", Callable(self, "_on_sprite_animation_finished"))
	if stationary == true:
		current_state = states.Lookout


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
			handle_gravity(delta)
		states.Chase:
			velocity = velocity.move_toward(dir * chase_speed, accel * delta)
			handle_gravity(delta)
		states.Attack:
			velocity = Vector2.ZERO
			handle_gravity(delta)
		states.Lookout:
			velocity = Vector2.ZERO
			handle_gravity(delta)
		states.Stunned:
			#velocity = Vector2.ZERO
			handle_gravity(delta)

	move_and_slide()


func change_direction():
	
	if current_state == states.Stunned:
		return
	
	# ------------------- PATROL -------------------
	if current_state == states.Patrol:
		aggro = false
		if sprite.flip_h:
			if self.position.x <= right_bounds.x:
				dir = Vector2(1,0)
			else:
				pause_and_flip(Vector2(-1,0), false, -125, -1, 1)
		else:
			if self.position.x >= left_bounds.x:
				dir = Vector2(-1,0)
			else:
				pause_and_flip(Vector2(1,0), true, 125, 1, -1)

	# -------------------- CHASE --------------------
	elif current_state == states.Chase:
		if !player: 
			return
		
		if current_state == states.Stunned:
			return
		
		aggro = true
		
		var x_only = player.position - self.position
		x_only.y = 0
		dir = x_only.normalized()

		if dir.x == 1:
			sprite.flip_h = true
			ray_cast.target_position = Vector2(125,0)
			attack_area.scale.x = -1
			sword_hitbox_collision.scale.x = 1
			parry_particles.position.x = 18
		else:
			sprite.flip_h = false
			ray_cast.target_position = Vector2(-125,0)
			attack_area.scale.x = 1
			sword_hitbox_collision.scale.x = -1
			parry_particles.position.x = -18

func pause_and_flip(new_dir: Vector2, flip_h: bool, raycast_new_pos: int, sword_hitbox_scale: int, attack_hitbox: int):
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
	patrol_paused = false

func look_for_player():
	if !player:
		return
		
	if current_state == states.Stunned:
		return
	
	if ray_cast.is_colliding():
		var collider = ray_cast.get_collider()
		if collider.is_in_group("Player") and current_state != states.Attack and current_state != states.Stunned:
			aggro = true
			chase_player()
		elif current_state == states.Chase and current_state != states.Stunned:
			stop_chase()

	elif current_state == states.Chase and current_state != states.Stunned:
		stop_chase()

func chase_player():
	if current_state == states.Stunned:
		return
	timer.stop()
	current_state = states.Chase

func stop_chase():
	if timer.time_left <= 0:
		timer.start()

func _on_timer_timeout():
	current_state = states.Patrol
	aggro = false

func _on_attack_area_body_entered(body):
	if current_state == states.Stunned:
			return
	if body.is_in_group("Player"):
		current_state = states.Attack
		aggro = true
		if attack_cooldown == false:
			attack()

func _on_attack_area_body_exited(body):
	if current_state == states.Stunned:
			return
	if body.is_in_group("Player") and current_state == states.Attack:
		current_state = states.Chase

func attack():
	#play animation
	current_state = states.Attack
	sprite.play("Attack")
	# check if colliding with sword hit box somewhere

func _on_sprite_frame_changed():
	if sprite.animation == "Attack" and attack_cooldown == false:
		# Check if on the damage frames
		var frame = sprite.frame
		if frame == 1:
			attack_indication.play("attack")
		elif frame == 4 or frame == 5:
			sword_hitbox_collision.disabled = false
	else:
		sword_hitbox_collision.disabled = true # Fully works but gives an error


func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Player"):
		body.take_damage(damage)
		attack_cooldown = true
		attack_timer.start()

func _on_sprite_animation_finished():
	if current_state == states.Stunned:
		return
	
	if sprite.animation == "Attack":
		sword_hitbox_collision.disabled = true
		if current_state == states.Stunned:
			return
		if ray_cast.is_colliding() and current_state != states.Stunned:
			if ray_cast.get_collider().is_in_group("Player"):
				current_state = states.Chase
				aggro = true
			else:
				current_state = states.Patrol
				aggro = false

# ----------------------------------------------------
#                 PARRY SYSTEM
# ----------------------------------------------------
func on_player_attack_started():
	
	if not is_player_attack_dangerous():
		return
	
	if current_state == states.Stunned:
		return
	
	if randf() >= parry_chance:
		return  # didn't parry this attack
	# activate parry window
	#emit_signal("enemy_parry") # Not using yet might not need to could call a function in player to do the effects of knockback etc
	parry_active = true
	parry_consumed = false
	sprite.play("Parry")
	# schedule closing of parry window
	var t = get_tree().create_timer(parry_window)
	t.timeout.connect(Callable(self, "_on_parry_window_timeout"))

func _on_parry_window_timeout():
	parry_active = false

func is_player_attack_dangerous() -> bool:
	if not player:
		return false
	
	var sword_shape = player.sword_hit_box.shape
	var sword_transform = player.sword_hit_box.global_transform

	# Get enemy CollisionShape2D
	var enemy_shape = $CollisionShape2D.shape
	var enemy_transform = global_transform

	# Test collision
	return sword_shape.collide(sword_transform, enemy_shape, enemy_transform)

##### When Player parries #########

func stun_parried():
	#sword_hitbox_collision.disabled = true ## Works kinda but gives errors
	aggro = true
	current_state = states.Stunned
	dir = Vector2.ZERO
	velocity = Vector2.ZERO
	sprite.play("Stagger")
	await sprite.animation_finished
	#await get_tree().create_timer(1).timeout  ## Could use later
	restore_state_after_stun()

func restore_state_after_stun():
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("Player"):
			attack()
			return
	
	current_state = states.Chase
	
# ----------------------------------------------------
#                DAMAGE HANDLING
# ----------------------------------------------------
func take_damage(amount: int):
	# --- Blocked because enemy is currently parrying ---
	if parry_active and not parry_consumed:
		parry_consumed = true
		perform_parry_effects()
		return

	# If parry was active but already consumed, ignore extra hit
	if parry_active and parry_consumed:
		return
	
	# -------- Take Damage Normally ---------
	health -= amount
	blood_particles.emitting = true
	
	if aggro != true:
		if sprite.flip_h:
			ray_cast.target_position = Vector2(-125,0)
		else:
			ray_cast.target_position = Vector2(125,0)

	if health <= 0:
		queue_free()

func perform_parry_effects():
	# Small hitstop
	#Engine.time_scale = 0.01
	#await get_tree().create_timer(2).timeout
	#Engine.time_scale = 1.0
	parry_particles.emitting = true

	# Optional: push player back, play sound, particles, etc.

func on_attack_timer_timeout():
	attack_cooldown = false
	
	for body in attack_area.get_overlapping_bodies():
		if body.is_in_group("Player"):
			attack()
			return
