extends Area2D
# Arrow projectile - Simple Area2D based projectile for archer enemies

var direction: Vector2 = Vector2.RIGHT
var speed: float = 500.0
var damage: int = 1
var lifetime: float = 5.0

func _ready():
	# Connect area entered signal
	body_entered.connect(_on_body_entered)
	
	# Despawn after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func initialize(dir: Vector2, spd: float, dmg: int):
	"""Initialize the arrow with direction, speed, and damage"""
	direction = dir.normalized()
	speed = spd
	damage = dmg
	rotation = direction.angle()

func set_direction(dir: Vector2, spd: float):
	"""Alternative initialization method"""
	direction = dir.normalized()
	speed = spd
	rotation = direction.angle()

func _process(delta):
	# Move the arrow forward
	position += direction * speed * delta

func _on_body_entered(body):
	"""Handle collision with bodies"""
	# Hit the player
	if body.is_in_group("Player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
	
	# Arrow hit something, destroy it
	queue_free()
