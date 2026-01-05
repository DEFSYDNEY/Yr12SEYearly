extends RigidBody2D

@onready var sprite = $AnimatedSprite2D

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var explosivness: float = 0
var dir:int = 0

func _ready():
	sprite.frame = randi_range(0,14)
	
	var speed = explosivness * dir
	
	global_position.x = speed
	global_position.y = explosivness
	
func _physics_process(delta):
	
	global_position.y += gravity * delta
