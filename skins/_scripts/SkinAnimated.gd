@tool
extends AnimatedSprite2D

# 零件的皮（動畫）：在關卡裡選一個零件，把這個拖進去當子節點，在 Sprite Frames 裡做動畫。
# 動畫名稱照固定清單取：一般零件「平常」「啟動」（啟動＝狀態改變後）；敵人「走路」「受傷」「死亡」。
# 遊戲開始時零件會藏起原本的色塊、改播這裡的動畫。
# 編輯器裡的黃色虛線框是原本色塊的範圍：碰撞範圍不會跟著圖片變，圖要畫在框裡。
# fill_style 選「拉伸蓋滿」時，位置和大小自動對齊色塊（動畫沒辦法重複鋪滿，要鋪滿請用 Skin）。
# 訊號換動畫：別的零件的訊號可以連到 show_active／show_normal／next_look…，動畫照「平常」→「啟動」→ 其他動畫（照名稱排）的順序排。

## 要不要跟著零件左右翻（敵人轉向）
@export var follow_facing: bool = true
## 狀態改變後怎麼顯示：只換成「啟動」動畫、換動畫之外再加零件原本的效果（變色、變淡、藏起來、變暗），
## 或不換動畫只用原本的效果；沒有「啟動」動畫時一律用原本的效果
@export_enum("換圖就好", "換圖再加原本效果", "只用原本效果") var active_style: int = 0
## 動畫怎麼蓋住零件：只放一張（位置大小自己調）、拉伸蓋滿（自動對齊原本色塊的範圍，零件拉大拉小也跟著變）
@export_enum("只放一張", "拉伸蓋滿") var fill_style: int = 0:
	set(value):
		fill_style = value
		_fit()
## 要不要跟著零件的方向轉（風扇吹的方向）；動畫請畫成朝上吹
@export var follow_direction: bool = true
## 不檢查畫面風格（圖會不會糊、縮放是不是整數倍、像素大小跟其他皮差太多）：故意混用不同風格的素材時勾起來
@export var ignore_style_check: bool = false:
	set(value):
		ignore_style_check = value
		update_configuration_warnings()

@export_group("訊號換圖")
## 訊號換過動畫之後，零件自己的狀態又改變時（例如踩到終點、整關重來）聽誰的：
## 零件的狀態優先（換回零件該播的動畫）、訊號優先（維持訊號換的動畫，零件只加原本效果）
@export_enum("零件的狀態優先", "訊號優先") var signal_priority: int = 0
## next_look 換到最後一段之後回到第一段；不勾就停在最後一段（previous_look 也一樣停在第一段）
@export var loop_looks: bool = true

const NORMAL := "平常"
const ACTIVE := "啟動"
const WALK := "走路"
const HURT := "受傷"
const DIE := "死亡"
const FILL_STRETCH := 1
const PRIORITY_SIGNAL := 1
# 編輯器裡每隔幾秒重新檢查動畫名稱（學員一邊改 Sprite Frames，驚嘆號一邊更新）
const _CHECK_SECONDS := 1.0

var _base := NORMAL   # 沒有指定的動畫時播哪一段（一般零件「平常」、敵人「走路」）
var _check_timer := 0.0
var _base_flip := false  # 編輯器裡 Flip H 有沒有勾（當作「朝右」的樣子）
var _play_id := 0  # 每播一段加一，讓循環的「受傷」播一輪後回到平常（中間換播別段就不回）
var _state_anim := NORMAL  # 現在的狀態該播哪一段（平常或「啟動」），事件動畫播完回到這段
var _event_id := 0  # 每播一次事件動畫加一，讓舊的「播完回去」失效
var _in_event := false  # 正在播 SkinEvent 的動畫：這段時間狀態改變先記著，播完再換
var _look := -1  # 訊號換到第幾段（從 0 數）；-1 代表沒被訊號換過，照零件的狀態播
var _hidden_block: ColorRect = null  # 編輯器裡藏起來的零件色塊

# 編輯器裡持續重畫外框、檢查動畫名稱；換一格就重新對齊（每格大小可能不一樣）
func _ready() -> void:
	set_process(Engine.is_editor_hint())
	frame_changed.connect(_fit)
	animation_changed.connect(_fit)
	_fit()

# 編輯器裡每一幀重畫外框、動畫能用時藏起零件的色塊、跟著零件的大小方向重新對齊，每隔一段時間重新檢查動畫名稱
func _process(delta: float) -> void:
	queue_redraw()
	var host := get_parent()
	var usable := host != null and _anim_problem(SkinLink.is_enemy_host(host)) == ""
	_hidden_block = SkinLink.editor_hide_block(self, usable, _hidden_block)
	_fit()
	_check_timer += delta
	if _check_timer >= _CHECK_SECONDS:
		_check_timer = 0.0
		update_configuration_warnings()

# 被拖到別的地方時重新檢查黃色驚嘆號、Inspector 要顯示哪些欄位；被刪掉、拖走時把藏起來的色塊顯示回來
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_UNPARENTED:
		SkinLink.editor_show_block(_hidden_block)
		_hidden_block = null
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()
		notify_property_list_changed()

# 用不到的欄位不顯示：不在零件底下時的 fill_style、零件沒有方向時的 follow_direction
func _validate_property(property: Dictionary) -> void:
	if property.name == "fill_style" and SkinLink.block_visual(get_parent()) == null:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "follow_direction" and not SkinLink.is_directional_host(get_parent()):
		property.usage = PROPERTY_USAGE_NO_EDITOR

# 跟著零件的方向轉；拉伸蓋滿時把位置和大小對齊原本色塊的範圍（依現在這一格的大小）
func _fit() -> void:
	var host := get_parent()
	if host == null:
		return
	if follow_direction and SkinLink.is_directional_host(host):
		var angle := SkinLink.host_angle(host)
		if not is_equal_approx(rotation, angle):
			rotation = angle
	var visual := SkinLink.block_visual(host)
	if fill_style != FILL_STRETCH or visual == null or sprite_frames == null:
		return
	if not sprite_frames.has_animation(animation) or sprite_frames.get_frame_count(animation) == 0:
		return
	var frame_texture := sprite_frames.get_frame_texture(animation, frame)
	if frame_texture == null or frame_texture.get_width() == 0 or frame_texture.get_height() == 0:
		return
	var rect := Rect2(visual.position, visual.size)
	centered = true
	offset = Vector2.ZERO
	if position != rect.get_center():
		position = rect.get_center()
	var target_scale := rect.size / frame_texture.get_size()
	if scale != target_scale:
		scale = target_scale

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
	warnings.append_array(StyleCheck.problems(self, true))
	return warnings

# 風格檢查用：拉伸蓋滿會自己縮放，不檢查縮放與像素大小
func style_scale_free() -> bool:
	return fill_style == FILL_STRETCH and SkinLink.block_visual(get_parent()) != null

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
	_look = -1
	_state_anim = _base
	_base_flip = flip_h
	animation_finished.connect(_on_animation_finished)
	play(_base)
	return ""

# 零件呼叫：狀態改變後要怎麼顯示（SkinLink.LOOK_…）；沒有「啟動」動畫時只能用原本的效果
func skin_active_look() -> int:
	return active_style if sprite_frames.has_animation(ACTIVE) else SkinLink.LOOK_EFFECT_ONLY

# 零件呼叫：播「啟動」（use_active）或平常的動畫，再用 tint 染色／變淡（不加效果時是白色）；已經在播同一段就不重播。
# 正在播事件動畫時先記著，播完再換
func skin_set_state(use_active: bool, tint: Color) -> void:
	self_modulate = tint
	if _look >= 0 and signal_priority == PRIORITY_SIGNAL:
		return
	_look = -1
	_state_anim = ACTIVE if use_active and sprite_frames.has_animation(ACTIVE) else _base
	if not _in_event and animation != _state_anim:
		play(_state_anim)

# SkinLink 開場時呼叫：把零件交給底下的 SkinEvent，讓它們去聽零件的事件
func skin_bind(host: Node) -> void:
	for child in get_children():
		if child.has_method("skin_event_setup"):
			child.skin_event_setup(host, self)

# SkinEvent 在編輯器裡用：這個皮套在哪個零件上（列出零件有哪些事件）
func skin_host() -> Node:
	return get_parent()

# SkinEvent 呼叫：從頭播一次這段動畫（勾了循環也只播一輪），播完回到現在狀態該播的那段
func play_event(anim_name: String) -> void:
	if not sprite_frames.has_animation(anim_name):
		return
	_event_id += 1
	_play_id += 1
	_in_event = true
	stop()
	play(anim_name)
	var id := _event_id
	get_tree().create_timer(skin_anim_length(anim_name)).timeout.connect(func():
		if id == _event_id:
			_in_event = false
			play(_state_anim)
	)

# 零件呼叫：面向左邊時翻過來（follow_facing 有勾才翻），以編輯器裡的 Flip H 當朝右的樣子
func skin_set_facing(facing_left: bool) -> void:
	if follow_facing:
		flip_h = _base_flip != facing_left

# 零件呼叫：播指定的動畫（敵人的「受傷」「死亡」）；沒有這段就繼續播平常的。
# 「受傷」就算勾了循環，播一輪也會回到平常
func skin_play(anim_name: String) -> void:
	_play_id += 1
	_event_id += 1
	_in_event = false
	if not sprite_frames.has_animation(anim_name):
		if animation != _base:
			play(_base)
		return
	play(anim_name)
	if anim_name == HURT and sprite_frames.get_animation_loop(HURT):
		var id := _play_id
		get_tree().create_timer(skin_anim_length(HURT)).timeout.connect(func():
			if id == _play_id and animation == HURT:
				play(_state_anim)
		)

# 零件呼叫：這段動畫播一次要幾秒（沒有這段回傳 0）
func skin_anim_length(anim_name: String) -> float:
	if sprite_frames == null or not sprite_frames.has_animation(anim_name):
		return 0.0
	var fps := sprite_frames.get_animation_speed(anim_name) * absf(speed_scale)
	if fps <= 0.0:
		return 0.0
	var total := 0.0
	for i in sprite_frames.get_frame_count(anim_name):
		total += sprite_frames.get_frame_duration(anim_name, i)
	return total / fps

# 零件呼叫：回到平常的動畫（敵人復活時從「死亡」回到「走路」）
func skin_reset() -> void:
	_play_id += 1
	_event_id += 1
	_in_event = false
	if _look < 0 or signal_priority != PRIORITY_SIGNAL:
		_look = -1
		_state_anim = _base
	play(_state_anim)

# 「受傷」播完回到平常的那一段（「死亡」停在最後一格）
func _on_animation_finished() -> void:
	if animation == HURT:
		play(_state_anim)

# ---- 訊號換圖（別的零件的訊號連過來，或自己寫程式呼叫）

# 換回平常的動畫（一般零件「平常」、敵人「走路」）
func show_normal() -> void:
	_go_to_look(0)

# 換成「啟動」動畫；沒有「啟動」時印警告、不換
func show_active() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(ACTIVE):
		SkinLink.warn("「%s」的 show_active 被呼叫了，但沒有「啟動」動畫，動畫沒有換" % _host_name())
		return
	_go_to_look(1)

# 換下一段；最後一段之後回到第一段（loop_looks 沒勾就停在最後一段）
func next_look() -> void:
	var count := _looks().size()
	var next := _current_look() + 1
	if next >= count:
		next = 0 if loop_looks else count - 1
	_go_to_look(next)

# 換上一段；第一段之前回到最後一段（loop_looks 沒勾就停在第一段）
func previous_look() -> void:
	var count := _looks().size()
	var previous := _current_look() - 1
	if previous < 0:
		previous = count - 1 if loop_looks else 0
	_go_to_look(previous)

# 換成第一段（平常）
func show_first() -> void:
	_go_to_look(0)

# 換成最後一段
func show_last() -> void:
	_go_to_look(_looks().size() - 1)

# 換成第幾段（從 1 開始數：1 是平常、2 是「啟動」、3 以後是其他動畫照名稱排），會寫程式的人用
func show_look(number: int) -> void:
	var count := _looks().size()
	if number < 1 or number > count:
		SkinLink.warn("「%s」的 show_look(%d)：只有 %d 段動畫（1～%d），動畫沒有換" % [_host_name(), number, count, count])
		return
	_go_to_look(number - 1)

# 全部的動畫照順序排：平常、「啟動」、其他動畫照名稱排（「受傷」「死亡」是敵人自己用的，不排進來）
func _looks() -> Array[String]:
	var list: Array[String] = []
	if sprite_frames == null:
		return list
	for n in [_base, ACTIVE]:
		if sprite_frames.has_animation(n) and not list.has(n):
			list.append(n)
	var names: Array = Array(sprite_frames.get_animation_names())
	names.sort()
	for n in names:
		var anim := String(n)
		if not list.has(anim) and anim not in [NORMAL, WALK, HURT, DIE]:
			list.append(anim)
	return list

# 現在播的是第幾段（從 0 數）；被訊號換過就用記下來的，不然看現在狀態該播的那段
func _current_look() -> int:
	if _look >= 0:
		return _look
	return maxi(_looks().find(_state_anim), 0)

# 換到第幾段（從 0 數）並記下來；正在播事件動畫時等播完再換
func _go_to_look(index: int) -> void:
	var list := _looks()
	if list.is_empty():
		return
	_look = clampi(index, 0, list.size() - 1)
	_state_anim = list[_look]
	if not _in_event and animation != _state_anim:
		play(_state_anim)

# 警告訊息裡用的名字：零件名稱／皮的名稱
func _host_name() -> String:
	var host := get_parent()
	return "%s/%s" % [host.name, name] if host != null else str(name)
