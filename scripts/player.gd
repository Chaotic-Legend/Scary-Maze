extends CharacterBody2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var max_speed = 75
var last_direction := Vector2(0, 1)

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	reset_to_look_down()

func _physics_process(_delta):
	if get_tree().paused:
		velocity = Vector2.ZERO
		return
	var direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * max_speed
	move_and_slide()
	if direction.length() > 0:
		last_direction = direction
		play_walk_animation(direction)
	else:
		play_idle_animation(last_direction)

func reset_to_look_down():
	last_direction = Vector2(0, 1)
	velocity = Vector2.ZERO
	play_idle_animation(last_direction)

func play_walk_animation(direction):
	if direction.x > 0:
		animated_sprite.play("walk_right")
	elif direction.x < 0:
		animated_sprite.play("walk_left")
	elif direction.y > 0:
		animated_sprite.play("walk_down")
	elif direction.y < 0:
		animated_sprite.play("walk_up")

func play_idle_animation(direction):
	if direction.x > 0:
		animated_sprite.play("idle_right")
	elif direction.x < 0:
		animated_sprite.play("idle_left")
	elif direction.y > 0:
		animated_sprite.play("idle_down")
	elif direction.y < 0:
		animated_sprite.play("idle_up")
	else:
		animated_sprite.play("idle_down")
