#!/usr/bin/env bash
# Presentation helpers only; optional Python provides Unicode display widths.
ui_init() {
    C_RESET= C_BOLD= C_RED= C_GREEN= C_YELLOW= C_BLUE= C_CYAN= C_WHITE= C_DIM=
    if [[ -t 1 && ! ${NO_COLOR+x} ]]; then
        C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[1;31m'
        C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'
        C_CYAN=$'\033[1;36m'; C_WHITE=$'\033[1;37m'; C_DIM=$'\033[2;36m'
    fi
    C_TITLE=$C_CYAN C_SECTION=$C_BLUE C_OK=$C_GREEN C_WARN=$C_YELLOW C_ERR=$C_RED
}
ui_width() {
    python3 - "$1" <<'PY'
import re, sys, unicodedata
text = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', sys.argv[1])
print(sum(0 if unicodedata.combining(c) or unicodedata.category(c).startswith('C')
          else 2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text))
PY
}
ui_layout() {
    TERM_COLS=$(tput cols 2>/dev/null || printf 80)
    [[ $TERM_COLS =~ ^[0-9]+$ ]] || TERM_COLS=80
    MENU_MAX_WIDTH=100
    MENU_WIDTH=$TERM_COLS
    (( MENU_WIDTH > MENU_MAX_WIDTH )) && MENU_WIDTH=$MENU_MAX_WIDTH
    (( MENU_WIDTH < 20 )) && MENU_WIDTH=20
    UI_TWO_COLUMNS=NO
    if [[ -t 1 && $TERM_COLS -ge 96 ]] && command -v python3 >/dev/null &&
        [[ $(locale charmap 2>/dev/null || true) == UTF-8 ]]; then
        UI_TWO_COLUMNS=YES
    fi
}
ui_separator() { printf '%s' "$C_DIM"; printf '%*s' "$MENU_WIDTH" '' | tr ' ' '-'; printf '%s\n' "$C_RESET"; }
ui_section() {
    local title=$1 width left right
    width=${#title}
    command -v python3 >/dev/null && width=$(ui_width "$title")
    left=$(( (MENU_WIDTH-width-2)/2 )); (( left < 1 )) && left=1
    right=$(( MENU_WIDTH-width-2-left )); (( right < 1 )) && right=1
    printf '%s' "$C_BLUE"; printf '%*s' "$left" '' | tr ' ' '-'
    printf ' %s ' "$title"; printf '%*s' "$right" '' | tr ' ' '-'; printf '%s\n' "$C_RESET"
}
ui_item() { printf '%s%2s.%s %s%s%s' "$C_GREEN" "$1" "$C_RESET" "${3:-$C_WHITE}" "$2" "$C_RESET"; }
ui_pair() {
    ui_item "$1" "$2"
    if [[ -n ${3:-} ]]; then
        if [[ $UI_TWO_COLUMNS == YES ]]; then
            local used padding
            used=$(ui_width "$(printf '%2s. %s' "$1" "$2")")
            padding=$((MENU_WIDTH/2-used)); (( padding < 2 )) && padding=2
            printf '%*s' "$padding" ''
        else printf '\n'; fi
        ui_item "$3" "$4"
    fi
    printf '\n'
}
