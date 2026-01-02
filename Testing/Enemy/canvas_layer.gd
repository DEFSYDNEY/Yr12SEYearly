extends CanvasLayer

@export var enemy: CharacterBody2D
@export var y_offset := -40

@onready var bar: ProgressBar = $ProgressBar

func _ready():
	bar.visible = false
	bar.value = 0

func _process(_delta):
	if enemy == null:
		queue_free()
		return

	# Follow enemy
	#global_position = enemy.global_position + Vector2(0, y_offset)

	# Update posture
	bar.max_value = enemy.max_posture
	bar.value = enemy.posture

	# Show only when engaged
	bar.visible = enemy.posture > 0
