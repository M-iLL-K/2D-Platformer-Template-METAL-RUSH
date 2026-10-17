@tool
extends HBoxContainer

# 作弊：拖進關卡就能用，不用連任何線。勾選要開哪些功能，再選怎麼打開。
# 開關類的功能（無敵、飛行…）打開後一直有效，再觸發一次就關掉；拔掉這個組件時，它開的效果全部跟著關掉。
# 想用自己的按鈕、勾選框、零件來開：解鎖方式選「只當接口」，再把它們的訊號連到這裡的
# turn_on／turn_off／toggle（按鈕的 pressed、零件的訊號）或 set_on／set_off（勾選框的 toggled）。

## 打開作弊的時候發出（例如接音效、跳字）
signal turned_on
## 關掉作弊的時候發出
signal turned_off

@export_group("開關類")
## 無敵：碰到敵人、尖刺、按 H 這類受傷都不扣血、不被彈開（掉進岩漿、被秒殺還是會死）
@export var invincible: bool = false:
	set(value):
		invincible = value
		_refresh_editor()
## 不會死：連掉進岩漿、被秒殺都什麼事都沒發生（自動包含無敵）
@export var no_death: bool = false:
	set(value):
		no_death = value
		_refresh_editor()
## 飛行：不受重力，用上下左右鍵（WASD、方向鍵）自由飛
@export var fly: bool = false:
	set(value):
		fly = value
		_refresh_editor()
## 穿牆：飛的時候可以穿過牆壁、地板（勾這個會自動一起飛）
@export var pass_walls: bool = false:
	set(value):
		pass_walls = value
		_refresh_editor()
## 飛多快（每秒幾像素，一格是 16 像素）
@export_range(100.0, 600.0) var fly_speed: float = 250.0

@export_group("解鎖方式")
## 怎麼打開這個作弊：只當接口＝自己把按鈕、勾選框、零件的訊號連過來
@export_enum("只當接口:2") var unlock_by: int = UNLOCK_SIGNAL:
	set(value):
		unlock_by = value
		_refresh_editor()
## 打開的時候畫面上方顯示「作弊中」和開了哪些功能
@export var show_label: bool = true

const UNLOCK_SIGNAL := 2
const CheatLabel := preload("res://cheats/_scripts/CheatLabel.gd")

var _on: bool = false

# 遊戲中加入群組（連線驗證器檢查訊號連線、「作弊中」小字問要顯示什麼）
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("cheat")
	add_to_group("signal_source")
	add_to_group("cheat_label_source")
	for problem in _get_problems():
		push_warning("[作弊] %s：%s" % [name, problem])
		print("[作弊] %s：%s" % [name, problem])

# 拔掉這個組件（或換關）時，它開的效果全部關掉
func _exit_tree() -> void:
	if not Engine.is_editor_hint() and _on:
		_apply_toggles(false)
		_on = false

# 打開作弊：開關類的功能開始生效（已經開著就不重複）
func turn_on(..._args: Array) -> void:
	if _on:
		return
	if not _has_toggles():
		push_warning("[作弊] %s 沒有勾任何功能，打開了也沒有效果" % name)
		print("[作弊] %s 沒有勾任何功能：在 Inspector 的「開關類」勾選要開什麼" % name)
	_on = true
	_apply_toggles(true)
	print("[作弊] %s 打開了：%s" % [name, _feature_text()])
	CheatLabel.ensure(get_tree())
	turned_on.emit()

# 關掉作弊：開關類的功能全部恢復原狀
func turn_off(..._args: Array) -> void:
	if not _on:
		return
	_on = false
	_apply_toggles(false)
	print("[作弊] %s 關掉了" % name)
	turned_off.emit()

# 開著就關、關著就開，按鈕的 pressed 連過來用
func toggle(..._args: Array) -> void:
	if _on:
		turn_off()
	else:
		turn_on()

# 勾選框的 toggled 連過來：勾著就打開、取消勾就關掉
func set_on(on: bool, ..._args: Array) -> void:
	if on:
		turn_on()
	else:
		turn_off()

# 跟 set_on 相反：勾選框的字寫「關掉作弊」這類、勾了才關的時候連這個
func set_off(off: bool, ..._args: Array) -> void:
	set_on(not off)

# 回傳作弊現在是不是開著
func is_on() -> bool:
	return _on

# 「作弊中」小字要顯示的這一行：開著而且勾了 show_label 才顯示
func get_label_text() -> String:
	if not _on or not show_label:
		return ""
	return "作弊中：%s" % _feature_text()

# 把開關類的功能套到玩家身上（on＝打開、false＝恢復原狀）
func _apply_toggles(on: bool) -> void:
	var player := _find_player()
	if player == null:
		return
	if invincible or no_death:
		player.set_invincible(self, on, no_death)
	if fly or pass_walls:
		player.set_free_move(self, on, pass_walls, fly_speed)

# 找到場景裡的玩家，找不到就印中文警告
func _find_player() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if player == null and _on:
		push_warning("[作弊] %s 找不到玩家，作弊沒有效果" % name)
		print("[作弊] %s：場景裡沒有玩家（Player），作弊沒有效果" % name)
	return player

# 有沒有勾任何開關類的功能
func _has_toggles() -> bool:
	return invincible or no_death or fly or pass_walls

# 開了哪些功能，排成「無敵、飛行」
func _feature_text() -> String:
	var names := PackedStringArray()
	if no_death:
		names.append("不會死")
	elif invincible:
		names.append("無敵")
	if pass_walls:
		names.append("飛行穿牆")
	elif fly:
		names.append("飛行")
	return "、".join(names) if not names.is_empty() else "（沒有功能）"

# 設定有沒有問題，回傳中文說明（編輯器黃色驚嘆號跟執行時警告共用）
func _get_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	if not _has_toggles():
		problems.append("沒有勾任何功能，打開了也沒有效果：在 Inspector 勾選要開什麼")
	return problems

# 編輯器的黃色驚嘆號
func _get_configuration_warnings() -> PackedStringArray:
	return _get_problems()

# 沒有飛行時藏起飛行速度
func _validate_property(property: Dictionary) -> void:
	if property.name == "fly_speed" and not (fly or pass_walls):
		property.usage = PROPERTY_USAGE_NO_EDITOR

# 編輯器裡改了勾選：重新整理 Inspector 跟黃色驚嘆號
func _refresh_editor() -> void:
	if Engine.is_editor_hint():
		notify_property_list_changed()
		update_configuration_warnings()
