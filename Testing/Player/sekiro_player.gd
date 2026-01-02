extends CharacterBody2D

@export var speed := 260.0
@export var max_posture := 100
@export var posture_recovery := 20.0

@export var weapon: WeaponStats

@onready var sprite: AnimatedSprite2D = $Sprite

var posture := 0
var parrying := false
var parry_window := 0.18
var parry_timer := 0.0
var attacking := false

func _physics_process(delta):
	handle_movement()
	handle_parry(delta)
	posture = max(posture - posture_recovery * delta, 0)

func handle_movement():
	if attacking:
		velocity.x = 0
		return

	var dir := Input.get_action_strength("right") - Input.get_action_strength("left")
	velocity.x = dir * speed
	move_and_slide()

	if dir != 0:
		sprite.flip_h = dir < 0

func handle_parry(delta):
	if parrying:
		parry_timer -= delta
		if parry_timer <= 0:
			parrying = false

	if Input.is_action_just_pressed("parry") and not attacking:
		parrying = true
		parry_timer = parry_window
		sprite.play("Parry")

	if Input.is_action_just_pressed("attack") and not attacking:
		start_attack()

func start_attack():
	attacking = true
	sprite.play("Attack")
	await sprite.animation_finished
	attacking = false

func receive_attack(damage: int, posture_damage: int, attacker):
	if parrying:
		attacker.on_parried(posture_damage * 2)
	else:
		posture += posture_damage
		sprite.play("Parry")
		if posture >= max_posture:
			on_posture_broken()

func on_posture_broken():
	sprite.play("stagger")
	await sprite.animation_finished
	posture = 0
