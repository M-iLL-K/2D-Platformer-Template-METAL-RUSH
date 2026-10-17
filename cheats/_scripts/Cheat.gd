@tool
extends HBoxContainer

# 作弊：拖進關卡就能用，不用連任何線。勾選要開哪些功能，再選怎麼打開。
# 預設是「按鍵指令」：在遊戲裡依序按下 code 打的那幾個鍵（預設 wwssadad，也就是上上下下左右左右）就會打開，再按一次關掉。
# 「選單勾選框」：拖進暫停選單（或標題畫面）裡，選單上就多一個勾選框讓玩家開關；換關、重開遊戲都從關著開始。
# 開關類的功能（無敵、飛行…）打開後一直有效，再觸發一次就關掉；拔掉這個組件時，它開的效果全部跟著關掉。
# 想用自己的按鈕、勾選框、零件來開：解鎖方式選「只當接口」，再把它們的訊號連到這裡的
# turn_on／turn_off／toggle（按鈕的 pressed、零件的訊號）或 set_on／set_off（勾選框的 toggled）。

## 打開作弊的時候發出（例如接音效、跳字）
signal turned_on
## 關掉作弊的時候發出
signal turned_off
## 按鍵指令輸入完成的那一刻發出，在打開或關掉之前（例如接「叮」的音效）
signal code_entered

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
## 怎麼打開這個作弊：按鍵指令＝依序按下 code 的那幾個鍵；選單勾選框＝拖進暫停選單裡變成一個勾選框；
## 只當接口＝自己把按鈕、勾選框、零件的訊號連過來
@export_enum("按鍵指令:0", "選單勾選框:1", "只當接口:2") var unlock_by: int = UNLOCK_CODE:
	set(value):
		unlock_by = value
		_refresh_editor()
## 按鍵指令：打英文字母或數字，就是依序按鍵盤上的這幾個鍵（大小寫都可以），例如 wwssadad＝上上下下左右左右
@export var code: String = DEFAULT_CODE:
	set(value):
		code = value
		_refresh_editor()
## 兩個鍵之間最多可以隔幾秒，隔太久就要從頭按
@export_range(0.3, 3.0) var delay: float = 1.0
## 選單上勾選框的字，空白就用「作弊：」加上開了哪些功能
@export var label: String = "":
	set(value):
		label = value
		_build()
## 打開的時候畫面上方顯示「作弊中」和開了哪些功能
@export var show_label: bool = true

const UNLOCK_CODE := 0
const UNLOCK_MENU := 1
const UNLOCK_SIGNAL := 2
const DEFAULT_CODE := "wwssadad"
# 指令短於這個長度很容易亂按就觸發，編輯器會提醒
const _MIN_CODE_LENGTH := 4
const CheatLabel := preload("res://cheats/_scripts/CheatLabel.gd")

var _on: bool = false
var _typed: String = ""        # 最近按下的幾個字母、數字
var _last_key_ms: int = 0      # 上一次按下字母、數字的時間（毫秒）
var _check: CheckButton = null # 選單勾選框（開場建的，不存進場景）
var _syncing: bool = false

# 選單勾選框的話建出勾選框；遊戲中加入群組（連線驗證器檢查訊號連線、「作弊中」小字問要顯示什麼）
func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_build()
	if Engine.is_editor_hint():
		return
	if unlock_by == UNLOCK_MENU:
		process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("cheat")
	add_to_group("signal_source")
	add_to_group("cheat_label_source")
	for problem in _get_problems():
		push_warning("[作弊] %s：%s" % [name, problem])
		print("[作弊] %s：%s" % [name, problem])

# 按鍵指令：記下按了哪些字母、數字，最後幾個鍵跟指令一樣就觸發；隔太久沒按就從頭算
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or unlock_by != UNLOCK_CODE:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var typed := _key_to_char((event as InputEventKey).physical_keycode)
	if typed == "":
		return
	var now := Time.get_ticks_msec()
	if now - _last_key_ms > int(delay * 1000.0):
		_typed = ""
	_last_key_ms = now
	var wanted := get_code()
	_typed = (_typed + typed).right(wanted.length())
	if wanted != "" and _typed == wanted:
		_typed = ""
		print("[作弊] %s 輸入了指令 %s" % [name, wanted])
		code_entered.emit()
		toggle()

# 把按鍵換成指令用的字：英文字母（小寫）、數字（含右邊數字鍵盤），其他鍵回傳空字串
func _key_to_char(key: Key) -> String:
	if key >= KEY_A and key <= KEY_Z:
		return char(key).to_lower()
	if key >= KEY_0 and key <= KEY_9:
		return char(key)
	if key >= KEY_KP_0 and key <= KEY_KP_9:
		return str(key - KEY_KP_0)
	return ""

# 回傳整理過、真正要按的指令：全形轉半形、去掉空白、轉小寫、只留英文字母和數字；空白就用預設指令
func get_code() -> String:
	var cleaned := _clean_code(code)
	return cleaned if cleaned != "" else DEFAULT_CODE

# 整理學員打的指令：全形轉半形、去掉所有空白、轉小寫、拿掉英文字母和數字以外的字
static func _clean_code(text: String) -> String:
	var result := ""
	for c in NameCheck.clean(text).to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
	return result

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
	_sync()
	turned_on.emit()

# 關掉作弊：開關類的功能全部恢復原狀
func turn_off(..._args: Array) -> void:
	if not _on:
		return
	_on = false
	_apply_toggles(false)
	print("[作弊] %s 關掉了" % name)
	_sync()
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

# 選單勾選框：拿掉舊的，重建一個勾選框（不存進場景）；其他解鎖方式什麼都不顯示
func _build() -> void:
	if not is_inside_tree():
		return
	if _check != null:
		_check.queue_free()
		_check = null
	if unlock_by != UNLOCK_MENU:
		return
	_check = CheckButton.new()
	_check.text = get_menu_text()
	add_child(_check)
	_check.toggled.connect(_on_check_toggled)
	_sync()

# 回傳選單勾選框上的字：有打 label 就用它，空白就用「作弊：」加上開了哪些功能
func get_menu_text() -> String:
	var text := label.strip_edges()
	return text if text != "" else "作弊：%s" % _feature_text()

# 讓勾選框顯示現在開著還是關著
func _sync() -> void:
	if _check == null:
		return
	_syncing = true
	_check.button_pressed = _on
	_syncing = false

# 玩家點了選單上的勾選框
func _on_check_toggled(on: bool) -> void:
	if not _syncing and not Engine.is_editor_hint():
		set_on(on)

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
	if unlock_by == UNLOCK_CODE:
		problems.append_array(_code_problems())
	if unlock_by == UNLOCK_MENU and not (get_parent() is Container):
		problems.append("解鎖方式是「選單勾選框」，但沒有放在選單裡：拖進暫停選單的按鈕清單（例如 PauseMenuTemplate 的 List）底下，勾選框才會排好")
	return problems

# 按鍵指令有沒有問題：空白、有不能按的字、太短、跟別的作弊的指令重複或包含在裡面
func _code_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var cleaned := _clean_code(code)
	if cleaned == "":
		problems.append("code 是空白的（或只有英文字母和數字以外的字），先用預設指令 %s" % DEFAULT_CODE)
		return problems
	var plain := NameCheck.clean(code).to_lower().replace(" ", "")
	if plain != cleaned:
		problems.append("code「%s」裡有英文字母和數字以外的字，按不出來，會當成「%s」" % [code.strip_edges(), cleaned])
	if cleaned.length() < _MIN_CODE_LENGTH:
		problems.append("code「%s」只有 %d 個鍵，玩的時候很容易不小心按到；建議至少 %d 個" % [cleaned, cleaned.length(), _MIN_CODE_LENGTH])
	for other in _other_code_cheats():
		var other_code: String = other.get_code()
		if other_code == cleaned:
			problems.append("跟 %s 的指令一樣（%s），按一次兩個會一起開關；想一次開好幾個功能，在同一個 Cheat 多勾幾個就好" % [other.name, cleaned])
		elif other_code.contains(cleaned):
			problems.append("指令 %s 包含在 %s 的指令 %s 裡面，按 %s 的時候這個會先被打開" % [cleaned, other.name, other_code, other.name])
	return problems

# 場景裡其他用按鍵指令打開的作弊（編輯器裡掃正在編輯的場景，遊戲中用群組）
func _other_code_cheats() -> Array[Node]:
	var out: Array[Node] = []
	if not is_inside_tree():
		return out
	var nodes: Array[Node] = []
	if Engine.is_editor_hint():
		var root := get_tree().edited_scene_root
		if root == null:
			return out
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			nodes.append(node)
			stack.append_array(node.get_children())
	else:
		nodes = get_tree().get_nodes_in_group("cheat")
	for node in nodes:
		if node != self and node.get_script() == get_script() and node.unlock_by == UNLOCK_CODE:
			out.append(node)
	return out

# 編輯器的黃色驚嘆號
func _get_configuration_warnings() -> PackedStringArray:
	return _get_problems()

# 沒有飛行時藏起飛行速度；解鎖方式不是按鍵指令時藏起指令與間隔
func _validate_property(property: Dictionary) -> void:
	if property.name == "fly_speed" and not (fly or pass_walls):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name in ["code", "delay"] and unlock_by != UNLOCK_CODE:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "label" and unlock_by != UNLOCK_MENU:
		property.usage = PROPERTY_USAGE_NO_EDITOR

# 編輯器裡改了勾選：重建選單勾選框（字會跟著功能變），重新整理 Inspector 跟黃色驚嘆號
func _refresh_editor() -> void:
	_build()
	if Engine.is_editor_hint():
		notify_property_list_changed()
		update_configuration_warnings()
