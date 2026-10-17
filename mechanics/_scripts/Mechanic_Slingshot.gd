@tool
extends MechanicBase

# 只能用滑鼠控制：鍵盤移動完全鎖住，按住拖曳鍵（預設滑鼠左鍵）移動滑鼠瞄準，像彈弓一樣
# 放開往反方向射出去。拖進 Player → Mechanics 底下就能用，不用連任何線。

## 用哪一種按鍵拖曳；選鍵盤按鍵時，按住那顆鍵移動滑鼠瞄準，放開發射
@export_enum("鍵盤按鍵", "滑鼠左鍵", "滑鼠右鍵", "滑鼠中鍵", "Input Map 動作") var input_type: int = 1:
	set(value):
		input_type = value
		notify_property_list_changed()

## 拖曳鍵（「按鍵種類」選鍵盤按鍵時才會顯示這一欄）
@export var key: Key = KEY_E

## 「按鍵種類」選 Input Map 動作時，要聽哪一個動作（動作在「專案設定 → Input Map」裡加，可以綁手把等其他裝置）
@export_custom(PROPERTY_HINT_INPUT_NAME, "show_builtin") var action: StringName = &""

## 拖到最遠時發射的力道上限
@export_range(200.0, 1200.0) var max_launch_force: float = 700.0

## 拖曳超過這個距離，力道就不會再增加
@export_range(50.0, 300.0) var max_drag_distance: float = 150.0

## 開啟後只有站在地面上才能開始拖曳瞄準
@export var ground_only: bool = true

## 拖曳時要不要畫出瞄準線
@export var show_aim_line: bool = true

## 拖曳時要不要畫出拉的中心點（按下去的位置）、可拉範圍圈，和從中心點拉到滑鼠的線
@export var show_drag_center: bool = true:
	set(value):
		show_drag_center = value
		notify_property_list_changed()

@export_group("中心點外觀")
## 中心點、範圍圈要畫成什麼樣子
@export_enum("實線圈", "虛線圈", "沒有圈（只有中心點和拉線）", "只有中心點") var center_style: int = 0
## 開啟時範圍圈就是最遠能拉到的地方（跟著 max_drag_distance 變）；關掉就用下面的 range_size 自己決定圈多大
@export var range_follow_drag: bool = true:
	set(value):
		range_follow_drag = value
		notify_property_list_changed()
## 範圍圈的半徑（range_follow_drag 關掉才會顯示）；只是畫出來的大小，實際能拉多遠還是看 max_drag_distance
@export_range(20.0, 400.0) var range_size: float = 150.0
## 範圍圈、拉線的粗細
@export_range(1.0, 10.0) var line_width: float = 2.0
## 中心點的大小（有放圖片時就是圖片的大小）
@export_range(2.0, 40.0) var center_size: float = 5.0
## 中心點的顏色（點色塊選顏色，可以調透明度）
@export var center_color: Color = Color(1.0, 0.85, 0.3, 0.9)
## 範圍圈的顏色
@export var range_color: Color = Color(1.0, 1.0, 1.0, 0.35)
## 從中心點拉到滑鼠那條線的顏色
@export var band_color: Color = Color(1.0, 0.85, 0.3, 0.9)
## 中心點換成自己的圖：把圖片從檔案系統拖進來；空白就畫圓點
@export var center_texture: Texture2D
@export_group("")

## 開始拉的那一刻發出（例如連到 Player 的 stop_motion，拉的時候速度歸零）
signal drag_started
## 放開、要射出去的那一刻發出，在推力之前（連到 Player 的 stop_motion 就是先歸零再射）；拉的距離是 0 也會發出
signal launched

# 拖曳鍵用較高優先權向 InputRouter 註冊，跟其他綁同一顆鍵的組件同時存在時彈弓先收到
const _PRIORITY := 100

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _aim_line: Line2D
# 拉的中心點、可拉範圍圈、中心點拉到滑鼠的線；放在世界座標，角色移動時中心點不會跟著跑
var _center_mark: Node2D

# center_style 的選項
const _STYLE_DASHED := 1
const _STYLE_NO_RING := 2
const _STYLE_DOT_ONLY := 3
# 範圍圈切成幾段（虛線圈就是隔一段畫一段）
const _RANGE_POINTS := 48
# 「中心點外觀」群組裡的欄位，show_drag_center 關掉時一起藏起來
const _LOOK_FIELDS := ["center_style", "range_follow_drag", "range_size", "line_width", "center_size",
		"center_color", "range_color", "band_color", "center_texture"]

# input_type 的「Input Map 動作」選項
const _INPUT_MAP_ACTION := 4

# 編輯器裡不跑卡片的檢查（@tool 只是為了讓欄位能跟著下拉選項藏起來）
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	super._ready()

# 選滑鼠按鍵時隱藏 key 欄位；沒開中心點時藏起外觀欄位；範圍圈跟著拉的距離時藏起 range_size
func _validate_property(property: Dictionary) -> void:
	if property.name == "key" and input_type != 0:
		property.usage = PROPERTY_USAGE_NONE
	elif property.name == "action" and input_type != _INPUT_MAP_ACTION:
		property.usage = PROPERTY_USAGE_NONE
	elif property.name in _LOOK_FIELDS and not show_drag_center:
		property.usage = PROPERTY_USAGE_NONE
	elif property.name == "range_size" and range_follow_drag:
		property.usage = PROPERTY_USAGE_NONE

# 向 InputRouter 註冊拖曳鍵的按下／放開；show_aim_line 開啟時自己生成一條瞄準線，學員不用擺
func _on_setup() -> void:
	if input_type == 0:
		InputRouter.warn_if_dangerous_key(key, "[彈弓]")
	InputRouter.bind_input(self, input_type, key, InputRouter.PRESSED, _on_drag_pressed, _PRIORITY, action)
	InputRouter.bind_input(self, input_type, key, InputRouter.RELEASED, _on_drag_released, _PRIORITY, action)
	if show_drag_center:
		_make_center_mark()
		_warn_invisible_colors()
	if not show_aim_line:
		return
	_aim_line = Line2D.new()
	_aim_line.width = 2.0
	_aim_line.default_color = Color(1.0, 1.0, 1.0, 0.8)
	_aim_line.visible = false
	add_child(_aim_line)

# 按下拖曳鍵：開始拖曳（ground_only 開啟時要先站在地面上）；沒開始拖曳就不攔截，讓其他組件收到
func _on_drag_pressed() -> bool:
	if ground_only and not player.is_on_ground():
		return false
	_dragging = true
	_drag_start = player.get_global_mouse_position()
	if _center_mark:
		_center_mark.global_position = _drag_start
		_refresh_center_mark()
	drag_started.emit()
	return true

# 放開拖曳鍵：正在拖曳才發射並攔截，否則讓其他組件收到
func _on_drag_released(_seconds: float) -> bool:
	if not _dragging:
		return false
	_release()
	return true

# 鍵盤全鎖住；拖曳中同步更新瞄準線
func apply(ctx: MoveContext) -> void:
	ctx.input_locked = true

	if _dragging and _aim_line:
		var drag: Vector2 = player.get_global_mouse_position() - _drag_start
		drag = drag.limit_length(max_drag_distance)
		_aim_line.visible = true
		_aim_line.points = PackedVector2Array([Vector2.ZERO, -drag])
	if _dragging and _center_mark:
		var pull: Vector2 = (player.get_global_mouse_position() - _drag_start).limit_length(max_drag_distance)
		(_center_mark.get_node("Band") as Line2D).points = PackedVector2Array([Vector2.ZERO, pull])
		_center_mark.visible = true

# 重生時取消拖曳中的狀態、藏起瞄準線
func on_respawn() -> void:
	_dragging = false
	if _aim_line:
		_aim_line.visible = false
	if _center_mark:
		_center_mark.visible = false

# 放開拖曳鍵：往拖曳的反方向發射，力道依拖曳距離比例縮放。launched 一定在推力之前發出，
# 拉的距離是 0 也發，學員用 drag_started 凍住、launched 解凍時才不會卡在空中
func _release() -> void:
	_dragging = false
	if _aim_line:
		_aim_line.visible = false
	if _center_mark:
		_center_mark.visible = false
	var drag: Vector2 = player.get_global_mouse_position() - _drag_start
	drag = drag.limit_length(max_drag_distance)
	var ratio := drag.length() / max_drag_distance
	launched.emit()
	if ratio <= 0.0:
		return
	var direction := -drag.normalized()
	player.add_impulse(direction * max_launch_force * ratio)
	Events.mechanic_event.emit("Mechanic_Slingshot", "launched")

# 生成中心點、範圍圈、拉線的節點，平常藏著；樣子在每次開始拉時由 _refresh_center_mark 照欄位畫
func _make_center_mark() -> void:
	_center_mark = Node2D.new()
	_center_mark.name = "DragCenter"
	_center_mark.top_level = true
	_center_mark.visible = false
	add_child(_center_mark)
	var ring := Node2D.new()
	ring.name = "Ring"
	_center_mark.add_child(ring)
	var band := Line2D.new()
	band.name = "Band"
	_center_mark.add_child(band)
	var dot := Polygon2D.new()
	dot.name = "Dot"
	_center_mark.add_child(dot)
	var picture := Sprite2D.new()
	picture.name = "Picture"
	_center_mark.add_child(picture)

# 照外觀欄位重畫中心點、範圍圈、拉線（遊戲中改了欄位，下次開始拉就會套用）
func _refresh_center_mark() -> void:
	var ring: Node2D = _center_mark.get_node("Ring")
	for child in ring.get_children():
		child.free()
	if center_style != _STYLE_NO_RING and center_style != _STYLE_DOT_ONLY:
		var radius := max_drag_distance if range_follow_drag else range_size
		var points := _circle_points(radius, _RANGE_POINTS)
		if center_style == _STYLE_DASHED:
			for i in range(0, _RANGE_POINTS, 2):
				_add_ring_line(ring, PackedVector2Array([points[i], points[i + 1]]), false)
		else:
			_add_ring_line(ring, points, true)
	var band: Line2D = _center_mark.get_node("Band")
	band.width = line_width
	band.default_color = band_color
	band.visible = center_style != _STYLE_DOT_ONLY
	var dot: Polygon2D = _center_mark.get_node("Dot")
	var picture: Sprite2D = _center_mark.get_node("Picture")
	dot.visible = center_texture == null
	picture.visible = center_texture != null
	if center_texture == null:
		dot.color = center_color
		dot.polygon = _circle_points(center_size, 16)
	else:
		picture.texture = center_texture
		var longest := maxf(center_texture.get_width(), center_texture.get_height())
		picture.scale = Vector2.ONE * (center_size * 2.0 / maxf(longest, 1.0))
		picture.modulate = Color.WHITE

# 在範圍圈底下加一段線
func _add_ring_line(ring: Node2D, points: PackedVector2Array, closed: bool) -> void:
	var line := Line2D.new()
	line.width = line_width
	line.default_color = range_color
	line.closed = closed
	line.points = points
	ring.add_child(line)

# 顏色的透明度拉到 0 會完全看不到，提醒學員（不然會以為壞掉）
func _warn_invisible_colors() -> void:
	var names := {"center_color": "中心點", "range_color": "範圍圈", "band_color": "拉線"}
	for field in names:
		if (get(field) as Color).a <= 0.01:
			var message: String = "[彈弓] %s 的顏色（%s）透明度是 0，畫出來會完全看不到；點色塊把透明度（A）拉高" % [names[field], field]
			push_warning(message)
			print(message)

# 算出一圈圓周上的點
func _circle_points(radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		points.append(Vector2.RIGHT.rotated(TAU * i / count) * radius)
	return points
