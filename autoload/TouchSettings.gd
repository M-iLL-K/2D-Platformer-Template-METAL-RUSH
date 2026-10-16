extends Node

# 手機按鈕的共用狀態：記住玩家現在是不是在用觸控（手指碰螢幕就算，改按鍵盤、手把就不算），換關也記得。
# 手機按鈕、套件、搖桿的 show_on 選「摸到螢幕才出現」時看這裡決定要不要顯示，狀態變了會發 changed。

signal changed

const SHOW_TOUCH_DEVICE := 0
const SHOW_ALWAYS := 1
const SHOW_AUTO := 2
# 手把搖桿推超過這個程度才算改用手把
const _STICK_PUSH := 0.5

var touch_used: bool = false   # 玩家最後用的是不是觸控

var _fake_keys: Dictionary = {}   # 手機按鈕送出、還沒處理到的假按鍵（按鍵 -> 幾個），收到時不算按鍵盤

# 暫停時也要收得到輸入
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# 依零件的 show_on 決定現在要不要顯示，手機按鈕、套件、搖桿用這個
func should_show(show_on: int) -> bool:
	match show_on:
		SHOW_ALWAYS:
			return true
		SHOW_AUTO:
			return touch_used
	return DisplayServer.is_touchscreen_available()

# 手機按鈕送出假按鍵前先說一聲，收到這個按鍵事件時不會當成玩家改按鍵盤
func expect_fake_key(key: Key) -> void:
	_fake_keys[key] = _fake_keys.get(key, 0) + 1

# 手指碰螢幕就算在用觸控；按鍵盤（手機按鈕送的假按鍵不算）、手把就不算
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_touch_used(true)
	elif event is InputEventKey:
		var key: Key = (event as InputEventKey).physical_keycode
		if _fake_keys.has(key):
			_fake_keys[key] -= 1
			if _fake_keys[key] <= 0:
				_fake_keys.erase(key)
		elif event.pressed:
			_set_touch_used(false)
	elif event is InputEventJoypadButton and event.pressed:
		_set_touch_used(false)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > _STICK_PUSH:
		_set_touch_used(false)

# 改「是不是在用觸控」，有變才發 changed
func _set_touch_used(value: bool) -> void:
	if touch_used == value:
		return
	touch_used = value
	changed.emit()
