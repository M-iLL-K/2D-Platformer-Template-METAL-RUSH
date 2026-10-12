@tool
extends Area2D
class_name Portal

# 傳送門：感應，站進去會被傳到配對的另一座。pair 是設定用的節點欄位，不是訊號連接，
# 只要在其中一座指定另一座，另一座會自動連回來，學員只需要接一邊。
# pair 也可以指定傳送門以外的東西（例如一個平台、Marker2D），一樣傳得過去，但只能單向、不會傳回來，
# 編輯器會出現黃色驚嘆號、執行時印中文警告提醒。
# 也可以用 activate/deactivate/toggle 開關（例如踩按鈕才打開傳送門）；關掉時站進來不會傳送、外觀變暗，
# 但從另一座傳過來還是會出現在這裡。開關狀態重生時不重置。
# 見 documents/01c_blocks_and_abilities.md §1、§2.1。

## 目的地：另一座傳送門（只要指定其中一座，另一座會自動連回來）。
## 也可以指定其他東西，會傳到它的位置，但只能單向、不會傳回來
@export var pair: NodePath = ^""

## 傳送時要不要保留原本的速度方向與大小；關掉的話落地時速度會歸零
@export var keep_velocity: bool = true

## 箱子要不要也能被這座傳送門傳送
@export var allow_boxes: bool = false

## 一開始就是開著的（關著的話要靠別的零件的訊號 activate 才會傳送）
@export var start_on: bool = true

## 傳送時發出，帶被傳送的物件，給學員自己接特效／音效用
signal teleported(body: Node)

const _COOLDOWN := 0.3
const _LINE_COLOR := Color(0.75, 0.45, 1.0, 0.8)
# 編輯器裡每隔幾秒重新檢查一次目的地，學員改了 pair 或別座傳送門之後黃色警告會跟著更新
const _WARNING_REFRESH_SECONDS := 1.0

var _pair_portal: Portal = null
var _destination: Node2D = null  # 實際傳過去的位置：配對的傳送門，或 pair 指定的其他東西
var _warning_timer: float = 0.0
var _cooldown_until: Dictionary = {}  # body(Node) -> 時間戳，避免傳送過去立刻被傳回來
var _active: bool = true
var _skin: SkinLink = null

## 開啟：開始傳送；開啟當下已經站在裡面的也會被傳走
func activate() -> void:
	if _active:
		return
	_set_active(true)
	for body in get_overlapping_bodies():
		_on_body_entered(body)

## 關閉：站進來不會傳送
func deactivate() -> void:
	_set_active(false)

## 切換
func toggle() -> void:
	if _active:
		deactivate()
	else:
		activate()

# 場景一進樹就解析 pair 節點路徑：是傳送門就互相補上配對，是其他 2D 節點就當單向目的地；
# 搶在雙方的 _ready() 檢查之前完成
func _enter_tree() -> void:
	if Engine.is_editor_hint() or pair.is_empty():
		return
	var target := get_node_or_null(pair)
	if target is Portal:
		_pair_portal = target
		_destination = target
		if target._pair_portal == null:
			target._pair_portal = self
			target._destination = self
	elif target is Node2D:
		_destination = target

# 設定碰撞層／遮罩，箱子要不要能傳依 allow_boxes 決定；底下有皮就換上皮
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("signal_source")
	_skin = SkinLink.new(self, $Visual)
	collision_layer = Layers.SENSOR
	collision_mask = Layers.PLAYER | (Layers.BOX if allow_boxes else 0)
	body_entered.connect(_on_body_entered)
	_set_active(start_on)
	var message := _pair_problem(get_tree().current_scene)
	if message != "":
		push_warning("[傳送門] %s" % message)
		printerr("⚠ [傳送門] %s" % message)

# 判斷這個 body 算不算「傳得動」：玩家一定行，箱子看 allow_boxes
func _is_valid(body: Node) -> bool:
	if body.is_in_group("player"):
		return true
	return allow_boxes and body.is_in_group("box")

# 切換開關狀態，關掉時變暗（有皮就換皮的樣子）讓學員看得出它沒在運作
func _set_active(is_active: bool) -> void:
	_active = is_active
	_skin.show_dark(not _active)

# 有東西站進來：傳到配對的另一座，0.3 秒內不會再次觸發（不管是這座還是另一座）；關著時不傳
func _on_body_entered(body: Node) -> void:
	if not _active or not is_instance_valid(_destination) or not _is_valid(body):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _cooldown_until.get(body, 0.0) > now:
		return
	body.global_position = _destination.global_position
	if body is CharacterBody2D and not keep_velocity:
		body.velocity = Vector2.ZERO
	var until := now + _COOLDOWN
	_cooldown_until[body] = until
	if _pair_portal != null:
		_pair_portal._cooldown_until[body] = until
	teleported.emit(body)

# 檢查目的地有沒有問題，回傳中文說明（沒問題回傳空字串）；編輯器黃色警告跟執行時警告共用
func _pair_problem(root: Node) -> String:
	if pair.is_empty():
		if root != null and _is_paired_by_other(root):
			return ""
		return "「%s」還沒有設定目的地，不會傳送任何東西：在 Inspector 的 pair 指定另一座傳送門" % name
	var target := get_node_or_null(pair)
	if target == null:
		return "「%s」的目的地找不到了（可能被刪掉或改名），請在 Inspector 重新指定 pair" % name
	if target is Portal:
		return ""
	if not (target is Node2D):
		return "「%s」的目的地「%s」沒有位置（不是 2D 的東西），不會傳送：請改指定傳送門或場景裡看得到的東西" % [name, target.name]
	return "「%s」的目的地「%s」不是傳送門：還是會傳過去，但只能單向、不會傳回來；也注意目的地不要在牆壁裡面" % [name, target.name]

# 場景裡有沒有別座傳送門把 pair 指到這一座（被指到的這座不用自己設 pair）
func _is_paired_by_other(root: Node) -> bool:
	for node in root.find_children("*", "Area2D", true, false):
		if node != self and node is Portal and not (node as Portal).pair.is_empty():
			if node.get_node_or_null((node as Portal).pair) == self:
				return true
	return false

# 編輯器裡的黃色驚嘆號：沒有目的地、目的地找不到、或目的地不是傳送門
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_inside_tree():
		return warnings
	var message := _pair_problem(get_tree().edited_scene_root)
	if message != "":
		warnings.append(message)
	return warnings

# 編輯畫面持續請求重畫，讓虛線跟著變化即時更新；每隔一段時間重新檢查目的地
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	queue_redraw()
	_warning_timer += delta
	if _warning_timer >= _WARNING_REFRESH_SECONDS:
		_warning_timer = 0.0
		update_configuration_warnings()

# 編輯畫面用：畫訊號連接的黃色虛線，再畫一條紫色細虛線到 pair 指定的目的地
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	SignalLines.draw(self, teleported)
	var target := get_node_or_null(pair) if not pair.is_empty() else null
	if target is Node2D:
		draw_dashed_line(Vector2.ZERO, to_local((target as Node2D).global_position), _LINE_COLOR, 1.0, 4.0)
