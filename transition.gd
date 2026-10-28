extends CanvasLayer

# 场景间淡入淡出转场。作为 Autoload 常驻，layer 最高，覆盖所有场景之上。
# 用法：Transition.change_scene("res://game.tscn")

const FADE_OUT_TIME: float = 0.3
const FADE_IN_TIME: float = 0.4

var _panel: ColorRect
var _tween: Tween
var _transitioning := false

func _ready() -> void:
	layer = 128
	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 1.0)   # 起始全黑，开场淡入
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	# 开场：黑 → 透明
	_fade(0.0, 0.5)
	await _tween.finished
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _fade(to_alpha: float, dur: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "color:a", to_alpha, dur)

## 探针：转场遮罩当前的不透明度（0 = 全透明，画面没被压暗）。
## ★ 截图/量色前必须等它归零：开场淡入是 0.5s，而截图流程只等 0.15s → 截到**半途**，
##   整张图被均匀压暗（2026-09-22 实测菜单截图被压暗 8%：面板底色 23,26,33 而非 25,28,36，
##   标题对比度从 4.56 掉到 4.45）。审外观会把"配色偏暗"的责任算到面板头上，量对比度也会失真。
func cover_alpha() -> float:
	return _panel.color.a if _panel != null else 0.0

## 探针：转场**进行中**。★ `change_scene()` 期间重复调用会被**直接丢弃**（`if _transitioning: return`），
##   而新场景的 `_ready()` 正好落在上一次转场的「等两帧」里 —— 那里再调一次等于没调
##   （实测 `--apprt`：游戏侧立刻请求回菜单，被静默吞掉 → 进程空跑到超时）。
##   调用方要么先等这一条归假，要么延迟到下一帧之后。
func is_busy() -> bool:
	return _transitioning

## 淡出 → 切换场景 → 淡入。切换期间屏蔽点击，避免重复触发
func change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade(1.0, FADE_OUT_TIME)
	await _tween.finished
	get_tree().change_scene_to_file(path)
	# 等两帧，确保新场景已就位并跑完 _ready
	await get_tree().process_frame
	await get_tree().process_frame
	_fade(0.0, FADE_IN_TIME)
	await _tween.finished
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
