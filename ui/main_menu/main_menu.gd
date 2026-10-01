class_name MainMenu
extends Control

## The main menu. The "What is this game?" dialog greets a new player once: a flag
## in a user:// ConfigFile remembers it was shown, and the info button reopens it.

const SEEN_SECTION := "intro"
const SEEN_KEY := "seen"

## Where the flag lives; tests point it at a throwaway file.
static var flag_path := "user://intro_seen.cfg"

@onready var intro_dialog: AcceptDialog = $AcceptDialog
@onready var info_button: Button = $InfoButton

func _ready() -> void:
	info_button.pressed.connect(show_intro)
	if not intro_seen():
		show_intro()
		mark_intro_seen()

func show_intro() -> void:
	intro_dialog.popup_centered()

static func intro_seen() -> bool:
	var config := ConfigFile.new()
	if config.load(flag_path) != OK:
		return false
	return bool(config.get_value(SEEN_SECTION, SEEN_KEY, false))

## A failed write only means the dialog shows again next launch.
static func mark_intro_seen() -> void:
	var config := ConfigFile.new()
	config.set_value(SEEN_SECTION, SEEN_KEY, true)
	var err := config.save(flag_path)
	if err != OK:
		push_warning("Could not save the intro flag (%s)" % error_string(err))
