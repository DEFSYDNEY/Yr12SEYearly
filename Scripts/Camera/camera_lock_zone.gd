@tool   # IMPORTANT: allows drawing in editor
extends Area2D

@export var lock_camera: bool = false
@export var room_position := Vector2.ZERO:
	set(value):
		room_position = value
		queue_redraw()

@export var room_size := Vector2(300, 200):
	set(value):
		room_size = value
		queue_redraw()

func _draw():
	# Draw rectangle outline
	draw_rect(Rect2(room_position, room_size), Color(0, 0.6, 1, 1), false)

func _on_body_entered(body):
	if body.is_in_group("Player"):
		if lock_camera:
			body.lock_camera_to_room(room_position, room_size)
		else:
			body.unlock_camera()
