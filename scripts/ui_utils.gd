class_name UIUtils
extends RefCounted
## set_anchors_preset(FULL_RECT) alone does not stretch a freshly-created
## Control to fill its parent (it preserves the control's current 0-size by
## adjusting offsets instead). Setting anchors and offsets explicitly does.

static func fill_parent(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
