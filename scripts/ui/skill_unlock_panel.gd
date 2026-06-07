extends Control

signal skill_chosen(index: int)

var _buttons: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center_wrap)

	var panel := PanelContainer.new()
	center_wrap.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = "Choose a Skill to Unlock"
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	for i in 3:
		var idx := i
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(260, 48)
		btn.pressed.connect(func(): _on_skill_pressed(idx))
		vbox.add_child(btn)
		_buttons.append(btn)

	visible = false

func show_for_archetype(arch: ArchetypeBase, unlocked: Array) -> void:
	_buttons[0].text = arch.get_skill1_name()
	_buttons[1].text = arch.get_skill2_name()
	_buttons[2].text = arch.get_skill3_name()
	for i in 3:
		_buttons[i].disabled = unlocked[i]
	move_to_front()
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event is InputEventKey or not event.pressed or not event.ctrl_pressed:
		return
	var idx := -1
	match event.physical_keycode:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
	if idx >= 0 and not _buttons[idx].disabled:
		get_viewport().set_input_as_handled()
		_on_skill_pressed(idx)

func _on_skill_pressed(index: int) -> void:
	visible = false
	skill_chosen.emit(index)
