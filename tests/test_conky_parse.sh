#!/bin/bash
# Testa a funcao parse_json usada em core_conky.sh
CONKY_CONFIG='{"position":"bottom_left","transparent":false,"color_text":"#00FF00","font_size":12,"disk_partition":"/home","show_top_processes":false,"show_datetime":true}'

parse_json() {
    local key="$1"
    local default="$2"
    local val
    val=$(echo "$CONKY_CONFIG" | jq -r "if has(\"${key}\") then .${key} else \"__UNSET__\" end" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ] || [ "$val" = "__UNSET__" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

FAIL=0
[ "$(parse_json position top_right)" = "bottom_left" ] && echo "position OK" || { echo "position FAIL"; FAIL=1; }
[ "$(parse_json transparent true)" = "false" ] && echo "transparent=false OK" || { echo "transparent FAIL"; FAIL=1; }
[ "$(parse_json show_top_processes true)" = "false" ] && echo "show_top=false OK" || { echo "show_top FAIL"; FAIL=1; }
[ "$(parse_json show_datetime false)" = "true" ] && echo "show_datetime=true OK" || { echo "show_datetime FAIL"; FAIL=1; }
[ "$(parse_json missing_key defval)" = "defval" ] && echo "fallback OK" || { echo "fallback FAIL"; FAIL=1; }
exit $FAIL
