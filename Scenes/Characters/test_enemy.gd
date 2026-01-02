extends CharacterBody2D

@export var player: CharacterBody2D

# ---------- Movement ----------
@export var speed := 140
@export var chase_speed := 260
@export var accel := 2400

# ---------- Combat ----------
@export var damage := 1
@export var attack_range := 60.0
@export var attack_delay := 0.2

# ---------- Posture System ----------
@export var posture_max := 100.0
@export var posture_recovery := 18.0
@export var posture_damage_on_block := 30.0
@export var posture_damage_on_parry := 45.0

# ---------- Behaviour ----------
@export var aggression := 0.6   # 0–1 (higher = attacks more)

@onready var sprite = $Sprite
@onready var ray_cast = $Sprite/RayCast2D
@onready var sword_hitbox = $SwordHitBox/CollisionShape2D
@onready var attack_indicator = $FlashIndication/AnimationPlayer
@onready var parry_particles = $ParryParticles

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

enum State { IDLE, CHASE, ATTACK, RECOVER, STAGGERED, DEATHBLOW }
var state := State.IDLE

var dir := Vector2.ZERO
var posture := 0.0
var can_attack := true
var parry_active := false
var parry_consumed := false

# -------------------------------------------------

func _physics_process(delta):
	velocity.y += gravity * delta

	match state:
		State.IDLE:
			look_for_player()
		State.CHASE:
			chase_player(delta)
		State.ATTACK:
			velocity.x = 0
		State.RECOVER:
			recover_posture(delta)
		State.STAGGERED:
			velocity = Vector2.ZERO
		State.DEATHBLOW:
			velocity = Vector2.ZERO

	move_and_slide()

# -------------------------------------------------
#                  AWARENESS
# -------------------------------------------------

func look_for_player():
	if ray_cast.is_colliding():
		var c = ray_cast.get_collider()
		if c.is_in_group("Player"):
			state = State.CHASE

# -------------------------------------------------
#                  CHASE
# -------------------------------------------------

func chase_player(delta):
	if not player:
		return

	var to_player = player.global_position - global_position
	to_player.y = 0
	dir = to_player.normalized()

	velocity.x = move_toward(velocity.x, dir.x * chase_speed, accel * delta)
	face_player()

	if to_player.length() <= attack_range and can_attack:
		if randf() <= aggression:
			start_attack()

# -------------------------------------------------
#                  ATTACK
# -------------------------------------------------

func start_attack():
	can_attack = false
	state = State.ATTACK
	sprite.play("Attack")

func _on_sprite_frame_changed():
	if sprite.animation == "Attack":
		if sprite.frame == 1:
			attack_indicator.play("attack")
		elif sprite.frame == 4:
			sword_hitbox.disabled = false
	else:
		sword_hitbox.disabled = true

func _on_sprite_animation_finished():
	if sprite.animation == "Attack":
		sword_hitbox.disabled = true
		state = State.CHASE
		await get_tree().create_timer(attack_delay).timeout
		can_attack = true

# -------------------------------------------------
#                  DAMAGE
# -------------------------------------------------

func _on_sword_hit_box_body_entered(body):
	if body.is_in_group("Player"):
		body.take_damage(damage)

# -------------------------------------------------
#                  POSTURE SYSTEM
# -------------------------------------------------

func add_posture(amount: float):
	posture += amount
	if posture >= posture_max:
		enter_stagger()

func recover_posture(delta):
	posture = max(posture - posture_recovery * delta, 0)
	if posture <= posture_max * 0.3:
		state = State.CHASE

func enter_stagger():
	state = State.STAGGERED
	sprite.play("Stagger")
	await sprite.animation_finished
	enter_deathblow()

func enter_deathblow():
	state = State.DEATHBLOW
	sprite.play("Deathblow")
	await sprite.animation_finished
	queue_free()

# -------------------------------------------------
#                  PLAYER PARRY
# -------------------------------------------------

func on_player_attack_started():
	if state == State.STAGGERED:
		return

	if randf() > 0.4:
		return

	parry_active = true
	parry_consumed = false
	sprite.play("Parry")

	await get_tree().create_timer(0.25).timeout
	parry_active = false

func take_damage(amount: int):
	if parry_active and not parry_consumed:
		parry_consumed = true
		parry_particles.emitting = true
		add_posture(posture_damage_on_parry)
		return

	add_posture(posture_damage_on_block)

# -------------------------------------------------
#                  UTILS
# -------------------------------------------------

func face_player():
	if dir.x > 0:
		sprite.flip_h = false
		ray_cast.target_position.x = 120
	else:
		sprite.flip_h = true
		ray_cast.target_position.x = -120
