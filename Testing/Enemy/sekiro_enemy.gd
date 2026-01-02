extends CharacterBody2D

@export var speed := 180.0
@export var max_posture := 100
@export var posture_recovery := 15.0
@export var aggression := 1.0

@export var weapon: WeaponStats
@export var attack: AttackData

@export var player: CharacterBody2D

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var posture_ui = $CanvasLayer

var posture := 0
var attacking := false
var stunned := false

func _physics_process(delta):
	if stunned:
		return

	posture = max(posture - posture_recovery * delta, 0)

	var dist := player.global_position.distance_to(global_position)

	if dist > 50:
		move_towards_player()
	else:
		try_attack()

func move_towards_player():
	var dir = sign(player.global_position.x - global_position.x)
	velocity.x = dir * speed
	sprite.flip_h = dir < 0
	sprite.play("run")
	move_and_slide()

func try_attack():
	if attacking:
		return

	attacking = true
	sprite.play("attack")
	await get_tree().create_timer(attack.windup_time).timeout

	if not attack.unblockable:
		player.receive_attack(attack.damage, attack.posture_damage, self)

	await get_tree().create_timer(attack.recovery_time).timeout
	attacking = false

func on_parried(posture_damage: int):
	posture += posture_damage
	stunned = true
	sprite.play("parried")
	await sprite.animation_finished
	stunned = false

	if posture >= max_posture:
		on_posture_broken()

func on_posture_broken():
	sprite.play("posture_break")
	await sprite.animation_finished
	queue_free()
