@tool
extends AnimatedSprite2D

# 零件的皮（動畫）：在關卡裡選一個零件，把這個拖進去當子節點，在 Sprite Frames 裡做動畫。
# 動畫名稱照固定清單取：一般零件「平常」「啟動」（啟動＝狀態改變後）；敵人「走路」「受傷」「死亡」。
# 遊戲開始時零件會藏起原本的色塊、改播這裡的動畫。
# 編輯器裡的黃色虛線框是原本色塊的範圍：碰撞範圍不會跟著圖片變，圖要畫在框裡。

## 要不要跟著零件左右翻（敵人轉向）
@export var follow_facing: bool = true
## 狀態改變後怎麼顯示：只換成「啟動」動畫、換動畫之外再加零件原本的效果（變色、變淡、藏起來、變暗），
## 或不換動畫只用原本的效果；沒有「啟動」動畫時一律用原本的效果
@export_enum("換圖就好", "換圖再加原本效果", "只用原本效果") var active_style: int = 0

const NORMAL := "平常"
const ACTIVE := "啟動"
const WALK := "走路"
const HURT := "受傷"
const DIE := "死亡"
# 編輯器裡每隔幾秒重新檢查動畫名稱（學員一邊改 Sprite Frames，驚嘆號一邊更新）
const _CHECK_SECONDS := 1.0

var _base := NORMAL   # 沒有指定的動畫時播哪一段（一般零件「平常」、敵人「走路」）
var _check_timer := 0.0

# 編輯器裡持續重畫外框、檢查動畫名稱
func _ready() -> void:
	set_process(Engine.is_editor_hint())

# 編輯器裡每一幀重畫外框，每隔一段時間重新檢查動畫名稱
func _process(delta: float) -> void:
	queue_redraw()
	_check_timer += delta
	if _check_timer >= _CHECK_SECONDS:
		_check_timer = 0.0
		update_configuration_warnings()

# 被拖到別的地方時重新檢查黃色驚嘆號
func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()

# 編輯器裡畫原本色塊的虛線外框
func _draw() -> void:
	if Engine.is_editor_hint():
		SkinLink.draw_outline(self)

# 黃色驚嘆號：放錯地方、沒有 Sprite Frames、缺必要的動畫
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var problem := SkinLink.placement_problem(self)
	if problem != "":
		warnings.append(problem)
	var host := get_parent()
	if host != null and not SkinLink.is_player_visual(host):
		var anim_problem := _anim_problem(SkinLink.is_enemy_host(host))
		if anim_problem != "":
			warnings.append(anim_problem)
	return warnings

# 必要的動畫在不在：一般零件要有「平常」，敵人要有「走路」；能用回傳空字串
func _anim_problem(is_enemy: bool) -> String:
	if sprite_frames == null:
		return "Sprite Frames 是空的：在 Inspector 的 Sprite Frames 選「新增 SpriteFrames」再做動畫"
	var required := WALK if is_enemy else NORMAL
	if sprite_frames.has_animation(required):
		return ""
	var names: Array = Array(sprite_frames.get_animation_names())
	var message := "缺少「%s」動畫（名稱要一字不差），現在有的：%s" % [required, NameCheck.list_text(names)]
	var similar := _similar_name(required, names)
	if similar != "":
		message += "。「%s」是不是要改名成「%s」？" % [similar, required]
	return message

# 找跟必要名稱很像的動畫名稱：差一個字，或是互相包含（「跑」→「跑步」）
func _similar_name(required: String, names: Array) -> String:
	var similar := NameCheck.find_similar(required, names)
	if similar != "":
		return similar
	for n in names:
		var clean := NameCheck.clean(str(n))
		if clean != "" and (required.contains(clean) or clean.contains(required)):
			return str(n)
	return ""

# 零件開場時呼叫：檢查動畫、開始播平常的那一段；能用回傳空字串，不能用回傳原因
func skin_setup(is_enemy: bool) -> String:
	var problem := _anim_problem(is_enemy)
	if problem != "":
		return problem
	_base = WALK if is_enemy else NORMAL
	animation_finished.connect(_on_animation_finished)
	play(_base)
	return ""

# 零件呼叫：狀態改變後要怎麼顯示（SkinLink.LOOK_…）；沒有「啟動」動畫時只能用原本的效果
func skin_active_look() -> int:
	return active_style if sprite_frames.has_animation(ACTIVE) else SkinLink.LOOK_EFFECT_ONLY

# 零件呼叫：播「啟動」（use_active）或平常的動畫，再用 tint 染色／變淡（不加效果時是白色）；已經在播同一段就不重播
func skin_set_state(use_active: bool, tint: Color) -> void:
	self_modulate = tint
	var anim := ACTIVE if use_active and sprite_frames.has_animation(ACTIVE) else _base
	if animation != anim:
		play(anim)

# 零件呼叫：面向左邊時翻過來（follow_facing 有勾才翻）
func skin_set_facing(facing_left: bool) -> void:
	if follow_facing:
		flip_h = facing_left

# 零件呼叫：播指定的動畫（敵人的「受傷」「死亡」）；沒有這段就繼續播平常的
func skin_play(anim_name: String) -> void:
	if sprite_frames.has_animation(anim_name):
		play(anim_name)
	elif animation != _base:
		play(_base)

# 「受傷」播完回到平常的那一段（「死亡」停在最後一格）
func _on_animation_finished() -> void:
	if animation == HURT:
		play(_base)
