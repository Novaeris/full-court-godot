# Saves a picture of a screen (opens a window briefly).
# Usage:  ./tools/screenshot.ps1 screen=Roster out=C:/temp/roster.png [days=20] [offseason=draft|window]
$project = Split-Path -Parent $PSScriptRoot
godot_console --path $project --script res://tools/screenshot.gd -- @args
