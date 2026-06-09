extends Camera2D

const CAM_SPEED := 700.0

var _arena1: Node2D = null
var _arena2: Node2D = null
var _current_arena_idx: int = 0

func init(arena1: Node2D, arena2: Node2D) -> void:
	_arena1 = arena1
	_arena2 = arena2
	_snap_to_arena(0)

func _ready() -> void:
	make_current()

func _snap_to_arena(idx: int) -> void:
	_current_arena_idx = idx
	var arena: Node2D = _arena1 if idx == 0 else _arena2
	var arena_x: float = arena.position.x
	limit_left = int(arena_x)
	limit_right = int(arena_x + Constants.WORLD_SIZE_X)
	limit_top = 0
	limit_bottom = int(Constants.WORLD_SIZE_Y)
	position = arena.position + Vector2(Constants.WORLD_SIZE_X * 0.5, Constants.WORLD_SIZE_Y * 0.5)
	zoom = Vector2(0.4, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.physical_keycode == KEY_TAB:
			_snap_to_arena(1 - _current_arena_idx)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * CAM_SPEED * delta
