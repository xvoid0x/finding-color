extends Node

const SCREENSHOT_DIR := "user://screenshots/"
const SCREENSHOT_KEY := KEY_F12

func _ready() -> void:
	# Ensure screenshot directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCREENSHOT_DIR))
	print("[ScreenshotManager] Ready — press F12 to capture screenshot")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == SCREENSHOT_KEY:
			_take_screenshot()

func _take_screenshot() -> void:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename := "screenshot_%s.png" % timestamp
	var full_path := ProjectSettings.globalize_path(SCREENSHOT_DIR + filename)

	# Capture the viewport
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(full_path)

	if err == OK:
		print("[ScreenshotManager] Saved: %s" % full_path)
		# Also copy to a fixed 'latest.png' so tooling can always find the most recent one
		var latest_path := ProjectSettings.globalize_path(SCREENSHOT_DIR + "latest.png")
		image.save_png(latest_path)
	else:
		push_error("[ScreenshotManager] Failed to save screenshot: %s" % full_path)

func take_screenshot_now() -> String:
	## Call this from code to trigger a screenshot and return the file path
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename := "screenshot_%s.png" % timestamp
	var full_path := ProjectSettings.globalize_path(SCREENSHOT_DIR + filename)

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(full_path)

	if err == OK:
		var latest_path := ProjectSettings.globalize_path(SCREENSHOT_DIR + "latest.png")
		image.save_png(latest_path)
		print("[ScreenshotManager] Saved: %s" % full_path)
		return full_path
	else:
		push_error("[ScreenshotManager] Failed to save screenshot")
		return ""
