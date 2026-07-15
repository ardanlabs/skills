#!/bin/bash
# Claude Code statusline. Renders two lines:
#   1) Powerline segments: model [+style]  ·  dir  ·  git branch/track/dirty
#   2) context-remaining bar  ·  cost  ·  edits  ·  200K warn  ·  time
#
# Portability:
#   - Truecolor (24-bit) is used when $COLORTERM advertises it; otherwise colors
#     degrade to the 256-color cube. Set STATUSLINE_TRUECOLOR=1/0 to force.
#   - Powerline/Nerd-Font glyphs are used by default. Set STATUSLINE_ASCII=1 (or
#     run in a non-UTF-8 locale) to fall back to plain ASCII separators/marks.
#   - Runs on bash 3.2+ (the macOS system bash).

input=$(cat)

# ── Single jq pass: tab-separated fields ──
IFS=$'\t' read -r MODEL DIR COST PCT DURATION_MS ADDED REMOVED OVER STYLE < <(
  jq -r '[
    .model.display_name,
    .workspace.current_dir,
    (.cost.total_cost_usd // 0),
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_duration_ms // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.exceeds_200k_tokens // false),
    (.output_style.name // "")
  ] | @tsv' <<<"$input"
)

# ── Capability detection ──
# Truecolor: honor explicit override, else sniff $COLORTERM.
if [ -n "$STATUSLINE_TRUECOLOR" ]; then
  [ "$STATUSLINE_TRUECOLOR" = "1" ] && TRUECOLOR=1 || TRUECOLOR=0
elif [[ "$COLORTERM" == *truecolor* || "$COLORTERM" == *24bit* ]]; then
  TRUECOLOR=1
else
  TRUECOLOR=0
fi

# Fancy glyphs: on unless ASCII forced or the locale isn't UTF-8.
if [ "$STATUSLINE_ASCII" = "1" ]; then
  FANCY=0
elif [[ "${LC_ALL}${LC_CTYPE}${LANG}" == *[Uu][Tt][Ff]* ]]; then
  FANCY=1
else
  FANCY=0
fi

if [ "$FANCY" -eq 1 ]; then
  # Powerline/Nerd-Font glyphs via UTF-8 byte escapes so they survive editing
  # (private-use-area chars get stripped by some editors) and work on bash 3.2.
  SEP=$'\xee\x82\xb0'          # U+E0B0 powerline right-pointing separator
  MARK_DIRTY=" ✗"; ARR_UP="↑"; ARR_DN="↓"
  BLK_FULL="█"; BLK_EMPTY="░"
  GIT_ICON=$'\xee\x82\xa0 '    # U+E0A0 branch glyph + space
  STYLE_ICON="  "
else
  SEP=""; MARK_DIRTY=" *"; ARR_UP="+"; ARR_DN="-"
  BLK_FULL="#"; BLK_EMPTY="-"; GIT_ICON=""; STYLE_ICON=" @"
fi

RESET=$'\033[0m'; BOLD=$'\033[1m'

# ── Color builders (fork-free: printf -v assigns directly, no subshells) ──
# setcol VARNAME LAYER R G B   (LAYER: 38=fg, 48=bg). No forks in truecolor;
# the 256 path does arithmetic inline via $(( )) — still fork-free.
setcol() {
  local v=$1 layer=$2 r=$3 g=$4 b=$5
  if [ "$TRUECOLOR" -eq 1 ]; then
    printf -v "$v" '\033[%d;2;%d;%d;%dm' "$layer" "$r" "$g" "$b"
  else
    local ri gi bi
    if   [ "$r" -lt 48 ];  then ri=0; elif [ "$r" -lt 114 ]; then ri=1; else ri=$(( (r-35)/40 )); fi
    if   [ "$g" -lt 48 ];  then gi=0; elif [ "$g" -lt 114 ]; then gi=1; else gi=$(( (g-35)/40 )); fi
    if   [ "$b" -lt 48 ];  then bi=0; elif [ "$b" -lt 114 ]; then bi=1; else bi=$(( (b-35)/40 )); fi
    printf -v "$v" '\033[%d;5;%dm' "$layer" "$(( 16 + 36*ri + 6*gi + bi ))"
  fi
}

# Palette → precomputed escapes (built once, reused free at render).
setcol FG_MODEL 38 220 224 240; setcol BG_MODEL 48 86 95 137; setcol FGON_MODEL 38 86 95 137
setcol FG_DIR   38 198 208 245; setcol BG_DIR   48 48 52 70;  setcol FGON_DIR   38 48 52 70
setcol FG_GIT   38 203 166 247; setcol BG_GIT   48 64 60 82;  setcol FGON_GIT   38 64 60 82
setcol FG_GIT_DIRTY 38 243 139 168
setcol FG_DIM   38 120 128 160
setcol FG_GREEN 38 166 227 161; setcol FG_YELLOW 38 249 226 175; setcol FG_RED 38 243 139 168
setcol FG_PEACH 38 250 179 135

# ── Git: single git call → one awk pass (branch, ahead, behind, dirty) ──
GIT_TEXT=""; GIT_DIRTY=0
if STATUS=$(git status --porcelain=v2 --branch 2>/dev/null); then
  IFS=$'\t' read -r BRANCH AHEAD BEHIND GIT_DIRTY < <(awk '
    /^# branch.head/ { b = $3 }
    /^# branch.ab/   { a = $3; be = $4 }
    !/^#/            { d = 1 }
    END { printf "%s\t%s\t%s\t%d", b, a, be, d }
  ' <<<"$STATUS")
  TRACK=""
  [ "${AHEAD#+}" -gt 0 ]  2>/dev/null && TRACK+=" ${ARR_UP}${AHEAD#+}"
  [ "${BEHIND#-}" -gt 0 ] 2>/dev/null && TRACK+=" ${ARR_DN}${BEHIND#-}"
  DIRTY=""; [ "$GIT_DIRTY" -eq 1 ] && DIRTY="$MARK_DIRTY"
  GIT_TEXT="${GIT_ICON}${BRANCH}${TRACK}${DIRTY}"
fi

# ── Powerline segment assembly (colors are precomputed escape strings) ──
# The separator glyph is drawn in the current segment's bg-as-foreground over
# the next segment's background, giving the seamless powerline arrow.
OUT=""
add_seg() { # add_seg <bg-esc> <fg-esc> "<text>" <this-bg-as-fg-esc> <next-bg-esc-or-empty>
  local bg=$1 fg=$2 text=$3 curfg=$4 nextbg=$5
  OUT+="${bg}${fg}${BOLD} ${text} ${RESET}"
  OUT+="${curfg}${nextbg}${SEP}${RESET}"
}

STYLE_TAG=""; [ -n "$STYLE" ] && [ "$STYLE" != "null" ] && STYLE_TAG="${STYLE_ICON}${STYLE}"
if [ -n "$GIT_TEXT" ]; then
  add_seg "$BG_MODEL" "$FG_MODEL" "$MODEL$STYLE_TAG" "$FGON_MODEL" "$BG_DIR"
  add_seg "$BG_DIR"   "$FG_DIR"   " ${DIR##*/}"      "$FGON_DIR"   "$BG_GIT"
  gfg=$FG_GIT; [ "$GIT_DIRTY" -eq 1 ] && gfg=$FG_GIT_DIRTY
  add_seg "$BG_GIT"   "$gfg"      "$GIT_TEXT"        "$FGON_GIT"   ""
else
  add_seg "$BG_MODEL" "$FG_MODEL" "$MODEL$STYLE_TAG" "$FGON_MODEL" "$BG_DIR"
  add_seg "$BG_DIR"   "$FG_DIR"   " ${DIR##*/}"      "$FGON_DIR"   ""
fi
printf '%s\n' "$OUT"

# ── Line 2: context bar + cost + edits + time ──
REMAIN=$((100 - PCT))
if   [ "$REMAIN" -le 10 ]; then BAR_FG="$FG_RED"
elif [ "$REMAIN" -le 30 ]; then BAR_FG="$FG_YELLOW"
else BAR_FG="$FG_GREEN"; fi
FILLED=$((REMAIN / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /$BLK_FULL}${PAD// /$BLK_EMPTY}"

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
printf -v COST_FMT '$%.2f' "$COST"

SEP2="${FG_DIM} │ ${RESET}"
LINE2="${BAR_FG}${BAR}${RESET} ${REMAIN}% left"
LINE2+="${SEP2}${FG_YELLOW}${COST_FMT}${RESET}"
{ [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; } 2>/dev/null && \
  LINE2+=" ${FG_GREEN}+${ADDED}${RESET}/${FG_RED}-${REMOVED}${RESET}"
[ "$OVER" = "true" ] && LINE2+=" ${FG_RED}${BOLD}200K+${RESET}"
LINE2+="${SEP2}${FG_PEACH}${MINS}m ${SECS}s${RESET}"

printf '%b\n' "$LINE2"
