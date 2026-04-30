extends Node
##
## Theme tokens for the War Council UI direction.
##
## Spec: docs/specs/2026-04-29-ui-rebuild-phase1-primitives.md
##
## All visual primitives read colors, fonts, and grid math from this
## autoload. There should be exactly one source of truth for the palette
## and font stack — if you find yourself hard-coding a hex value or a
## font path in a .gd or .tscn, it likely belongs here instead.
##

# --- Color palette (War Council direction) -------------------------------

const FELT       := Color("#1a2024")  # main table felt
const FELT_LIGHT := Color("#26303a")  # panel hover, throne highlight
const FELT_DARK  := Color("#0e1418")  # vignette, shadow gradients
const BRASS      := Color("#c9a064")  # gilded frame, primary chrome
const BRASS_DIM  := Color("#8a6f3e")  # borders, disabled brass
const BONE       := Color("#e8dcc4")  # parchment, primary text
const BONE_DIM   := Color("#b9a98a")  # secondary text
const INK        := Color("#0a0e12")  # darkest, text on brass
const CANDLE     := Color("#f4d27a")  # highlights, victory glow
const BLOOD      := Color("#a8323a")  # player Aelia, hostile, danger
const EMBER      := Color("#e07a3c")  # tension, warning
const AZURE      := Color("#2f5d7c")  # player Borovic
const OCHRE      := Color("#9c7a1f")  # player Cyrene
const SABLE      := Color("#3d6b3a")  # player Drevan

# --- Player palette (player_id 0..3 → main + dim color pair) -------------
#
# Each player gets a paired darker shade so sculpted shapes can shade
# without computing a darken() at draw time.

const PLAYER_COLORS := {
	0: { "main": BLOOD, "dim": Color("#6e1f25") },  # Aelia
	1: { "main": AZURE, "dim": Color("#1e3e54") },  # Borovic
	2: { "main": OCHRE, "dim": Color("#5e4912") },  # Cyrene
	3: { "main": SABLE, "dim": Color("#234221") },  # Drevan
}

const FACTION_NAMES := {
	0: "Aelia", 1: "Borovic", 2: "Cyrene", 3: "Drevan"
}

const FACTION_TAGS := {
	0: "AEL", 1: "BOR", 2: "CYR", 3: "DRE"
}

# --- Font paths ----------------------------------------------------------
#
# Variable fonts: weight is selected at use-site via the "wght" axis
# (Godot's FontFile or Theme variations). Italic is a separate file
# where the family ships a discrete italic master.
#
# The theme (themes/war_council_theme.tres) loads these and exposes them
# as Theme default fonts.

const FONT_DISPLAY        := "res://fonts/PlayfairDisplay.ttf"      # 400-900
const FONT_SERIF          := "res://fonts/CormorantGaramond.ttf"     # 300-700
const FONT_SERIF_ITALIC   := "res://fonts/CormorantGaramond-Italic.ttf"
const FONT_SANS           := "res://fonts/IBMPlexSans.ttf"           # 100-700, wdth axis too
const FONT_MONO           := "res://fonts/JetBrainsMono.ttf"         # 100-800

# Suggested weight constants for direct font use (the theme presets these
# for chrome controls; only override for one-off text)
const WEIGHT_DISPLAY_BOLD  := 700
const WEIGHT_DISPLAY_BLACK := 900
const WEIGHT_SERIF_BODY    := 400
const WEIGHT_SERIF_BOLD    := 700
const WEIGHT_SANS_BOLD     := 700
const WEIGHT_MONO          := 400
const WEIGHT_MONO_MEDIUM   := 500

# --- Hex grid math -------------------------------------------------------
#
# Pointy-top axial coordinates → pixel offset. Mirrors the math in the
# design's d3-godot-spec.jsx so the visual primitives match Claude
# Design's intended scale.

const HEX_R := 32

static func hex_to_px(q: int, r: int) -> Vector2:
	return Vector2(
		HEX_R * sqrt(3.0) * (q + r / 2.0),
		HEX_R * 1.5 * r
	)


# --- Helpers -------------------------------------------------------------

static func player_main(pid: int) -> Color:
	return PLAYER_COLORS.get(pid, {"main": BONE_DIM}).main

static func player_dim(pid: int) -> Color:
	return PLAYER_COLORS.get(pid, {"dim": BONE_DIM}).dim

static func faction_name(pid: int) -> String:
	return FACTION_NAMES.get(pid, "—")

static func faction_tag(pid: int) -> String:
	return FACTION_TAGS.get(pid, "???")
