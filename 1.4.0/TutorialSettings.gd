# TutorialSettings.gd (autoload / singleton is easiest)
extends Node

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "tutorial"
const KEY := "seen"

var tutorial_seen: bool = false

func _ready():
	_load()

func _load():
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err == OK:
		tutorial_seen = cfg.get_value(SECTION, KEY, false)
	else:
		tutorial_seen = false

func mark_tutorial_seen():
	tutorial_seen = true
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY, tutorial_seen)
	cfg.save(CONFIG_PATH)
