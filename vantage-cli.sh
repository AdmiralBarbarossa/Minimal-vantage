#!/bin/bash
# vantage-cli.sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
trap "clear; echo 'exiting..'; exit 0" SIGINT SIGTERM

SUDOCMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDOCMD="sudo"
    elif command -v doas >/dev/null 2>&1; then SUDOCMD="doas"
    fi
fi

for tool in gum rfkill wpctl awk; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required dependency '$tool' is not installed."
        exit 1
    fi
done

CORE="/usr/local/bin/vantage-core"
if [ ! -x "$CORE" ]; then
    echo "Error: Backend not found or not executable at $CORE."
    echo "Please install the backend properly."
    exit 1
fi

RED="#E2231A"

short_label() {
    local name="$1" word
    [[ "$name" == Integrated\ * ]] && echo "Builtin" && return
    if [[ "$name" =~ [[:space:]]([^[:space:]]+)[[:space:]]Microphone$ ]]; then
        word="${BASH_REMATCH[1]}"
        [[ "$word" != "USB" ]] && echo "$word" && return
    fi
    echo "${name%% *}"
}
export GUM_CHOOSE_CURSOR_FOREGROUND="$RED"
export GUM_CHOOSE_SELECTED_FOREGROUND="$RED"
export GUM_INPUT_PROMPT_FOREGROUND="$RED"
export GUM_INPUT_CURSOR_FOREGROUND="$RED"

read -r -d '' LOGO << 'EOF'
██  ██ ▄████▄ ███  ██ ██████ ▄████▄  ▄████  ██████
██▄▄██ ██▄▄██ ██ ▀▄██   ██   ██▄▄██ ██  ▄▄▄ ██▄▄
 ▀██▀  ██  ██ ██   ██   ██   ██  ██  ▀███▀  ██▄▄▄▄
EOF

HASWLR=false
command -v wlr-randr &>/dev/null && HASWLR=true

while true; do
    CORE_OUT=$($CORE --status 2>/dev/null)
    if [ -z "$CORE_OUT" ]; then
        clear
        echo "error: Backend returned no data; check vantage-core is installed and working."
        exit 1
    fi

    unset SYS_STATUS
    declare -A SYS_STATUS
    while IFS='=' read -r KEY VAL; do
        if [[ "$KEY" =~ ^[A-Z]+$ ]]; then
            SYS_STATUS["$KEY"]="$VAL"
        fi
    done <<< "$CORE_OUT"

    MICSTATUS=""
    unset MICMAP MICLIST
    declare -A MICMAP
    declare -a MICLIST
    while IFS=$'\t' read -r _srcid _srcname _srcstate; do
        [ -n "$_srcid" ] || continue
        MICMAP["$_srcname"]="$_srcid"
        MICLIST+=("$_srcname")
        MICSTATUS="${MICSTATUS:+$MICSTATUS | }$(short_label "$_srcname"): ${_srcstate}"
    done < <(wpctl status | awk '
        /Sources:/ { in_src=1; next }
        in_src && /(Sinks|Filters|Streams|Devices|Video):/ { in_src=0 }
        in_src && /[0-9]+\./ && !/Monitor of/ && !/V4L2/ {
            state = /MUTED/ ? "off" : "on"
            match($0, /[0-9]+\./)
            id = substr($0, RSTART, RLENGTH-1)
            rest = substr($0, RSTART+RLENGTH)
            sub(/ \[.*/, "", rest)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
            if (rest != "") print id "\t" rest "\t" state
        }
    ')
    [ -z "$MICSTATUS" ] && MICSTATUS="Unknown"

    CAMSTATUS=""
    unset CAMMAP CAMLIST _CAMSEEN
    declare -A CAMMAP _CAMSEEN
    declare -a CAMLIST
    for _iface in /sys/bus/usb/devices/*:*/; do
        [ "$(cat "${_iface}bInterfaceClass" 2>/dev/null)" = "0e" ] || continue
        [ "$(cat "${_iface}bInterfaceSubClass" 2>/dev/null)" = "01" ] || continue
        _tmp="${_iface%:*}"; _pid="${_tmp##*/}"
        [[ -n "${_CAMSEEN[$_pid]:-}" ]] && continue
        _CAMSEEN[$_pid]=1
        _prod=$(cat "/sys/bus/usb/devices/${_pid}/product" 2>/dev/null || echo "Unknown")
        _label="$_prod ($_pid)"
        CAMMAP["$_label"]="$_pid"
        CAMLIST+=("$_label")
        shopt -s nullglob
        _uvbound=(/sys/bus/usb/drivers/uvcvideo/"${_pid}":*)
        shopt -u nullglob
        if [ "${#_uvbound[@]}" -gt 0 ]; then
            _cstate="on"
        else
            _cstate="off"
        fi
        CAMSTATUS="${CAMSTATUS:+$CAMSTATUS | }$(short_label "$_prod"): ${_cstate}"
    done
    [ -z "$CAMSTATUS" ] && CAMSTATUS="Unknown"

    if rfkill list wlan | grep -q "Soft blocked: yes"; then WIFISTATUS="off"
    else WIFISTATUS="on"; fi

    if rfkill list bluetooth | grep -q "Soft blocked: yes"; then BTSTATUS="off"
    else BTSTATUS="on"; fi

    _wlr_ok=false
    if [ "$HASWLR" = true ] && WLROUT=$(wlr-randr 2>/dev/null); then
        _wlr_ok=true
        mapfile -t MONITORS < <(awk '/^[^[:space:]]/{cur=$1} /Enabled: yes/{print cur}' <<< "$WLROUT")
        DISPMODE=""
        for mon in "${MONITORS[@]}"; do
            mode=$(awk -v m="$mon" '
                /^[^[:space:]]/ { in_mon = ($1 == m) }
                in_mon && /current/ { printf "%s @ %.0f Hz", $1, $3; exit }
            ' <<< "$WLROUT")
            [ -z "$mode" ] && mode="Unknown"
            DISPMODE="${DISPMODE:+$DISPMODE | }${mon}: ${mode}"
        done
        [ -z "$DISPMODE" ] && DISPMODE="Unknown"
    fi

    clear
    gum style --foreground "$RED" --margin "1 2" "$LOGO"

    STARTCHARGE=${SYS_STATUS["STARTCHARGE"]:-"Unknown"}
    STOPCHARGE=${SYS_STATUS["STOPCHARGE"]:-"Unknown"}
    BATCAPACITY=${SYS_STATUS["BATCAPACITY"]:-"Unknown"}
    BATSTATUS=${SYS_STATUS["BATSTATUS"]:-"Unknown"}
    BATHEALTH=${SYS_STATUS["BATHEALTH"]:-"Unknown"}
    CYCLECOUNT=${SYS_STATUS["CYCLECOUNT"]:-"Unknown"}
    BATPOWER=${SYS_STATUS["BATPOWER"]:-"Unknown"}
    PLATFORMPROFILE=${SYS_STATUS["PLATFORMPROFILE"]:-"Unknown"}
    AVAILABLEPROFILES=${SYS_STATUS["AVAILABLEPROFILES"]:-""}

    STATUSTEXT="  Battery Limits : Start: ${STARTCHARGE}% | Stop: ${STOPCHARGE}%
  Battery Stats  : ${BATCAPACITY}% (${BATSTATUS}) | Health: ${BATHEALTH}% | Cycles: ${CYCLECOUNT}
  Power Draw     : $BATPOWER
  Thermal Mode   : $PLATFORMPROFILE"
    
    if [ "$_wlr_ok" = true ]; then
        STATUSTEXT="$STATUSTEXT
󰍹  Display Mode   : $DISPMODE"
    fi

    STATUSTEXT="$STATUSTEXT
  Camera         : $CAMSTATUS
  Microphone     : $MICSTATUS
  Wi-Fi          : $WIFISTATUS
  Bluetooth      : $BTSTATUS"

    echo " System Status:"
    gum style --border rounded --border-foreground "$RED" --padding "1 3" --margin "0 1" "$STATUSTEXT"
    echo ""

    MENUOPTS=("  Set Battery Limits")

    if [[ "$AVAILABLEPROFILES" != "Unsupported" && -n "$AVAILABLEPROFILES" ]]; then
        MENUOPTS+=("  Set Thermal Profile")
    fi

    if [ "$_wlr_ok" = true ]; then
        MENUOPTS+=("󰍹  Set Display Mode")
    fi

    MENUOPTS+=(
        "  Toggle Camera"
        "  Toggle Microphone"
        "  Toggle Wi-Fi"
        "  Toggle Bluetooth"
        "  Exit"
    )

    CHOICE=$(gum choose --cursor " █ " "${MENUOPTS[@]}")

    if [ -z "$CHOICE" ]; then clear; exit 0; fi

    case "$CHOICE" in
        "  Set Battery Limits")
            START=$(gum input --header "Start Threshold (0-99) | Press Esc to go back" --placeholder "Currently ${STARTCHARGE}%")
            if [ -z "$START" ]; then continue; fi
            STOP=$(gum input --header "Stop Threshold (1-100) | Press Esc to go back" --placeholder "Currently ${STOPCHARGE}%")
            if [ -z "$STOP" ]; then continue; fi

            ERR=$( ${SUDOCMD:+"$SUDOCMD"} "$CORE" --set-limits "$START" "$STOP" 2>&1 )
            if [ -n "$ERR" ]; then
                gum style --foreground "$RED" --margin "0 2" "$ERR"
                sleep 3
            fi
            ;;
        "  Set Thermal Profile")
            PROF=$(echo "$AVAILABLEPROFILES" | tr ' ' '\n' | gum choose --header "Select Thermal Profile (Esc to go back):")
            if [ -n "$PROF" ]; then
                ERR=$( ${SUDOCMD:+"$SUDOCMD"} "$CORE" --set-profile "$PROF" 2>&1 )
                if [ -n "$ERR" ]; then
                    gum style --foreground "$RED" --margin "0 2" "$ERR"
                    sleep 3
                fi
            fi
            ;;
        "󰍹  Set Display Mode")
            if [ "${#MONITORS[@]}" -gt 1 ]; then
                SELMON=$(printf "%s\n" "${MONITORS[@]}" | gum choose --header "Select Monitor (Esc to go back):")
                [ -z "$SELMON" ] && continue
            else
                SELMON="${MONITORS[0]}"
            fi
            unset MODEMAP MENULIST _rawmodes _roundcount
            declare -A MODEMAP _roundcount
            declare -a MENULIST _rawmodes
            while read -r RES HZEXACT; do
                _rawmodes+=("$RES $HZEXACT")
                HZROUND=$(printf "%.0f" "$HZEXACT")
                UILABEL="${RES} @ ${HZROUND} Hz"
                _roundcount["$UILABEL"]=$(( ${_roundcount["$UILABEL"]:-0} + 1 ))
            done < <(awk -v m="$SELMON" '
                /^[^[:space:]]/ { in_mon = ($1 == m) }
                in_mon && /px,/ { print $1, $3 }
            ' <<< "$WLROUT")
            for _entry in "${_rawmodes[@]}"; do
                RES="${_entry% *}"; HZEXACT="${_entry##* }"
                HZROUND=$(printf "%.0f" "$HZEXACT")
                UILABEL="${RES} @ ${HZROUND} Hz"
                if [[ "${_roundcount[$UILABEL]:-0}" -gt 1 ]]; then
                    UILABEL="${RES} @ $(printf "%.2f" "$HZEXACT") Hz"
                fi
                MODEMAP["$UILABEL"]="${RES}@${HZEXACT}"
                MENULIST+=("$UILABEL")
            done
            CHOSENMODE=$(printf "%s\n" "${MENULIST[@]}" | sort -Vru | gum choose --header "Select Display Mode (Esc to go back):")
            if [ -n "$CHOSENMODE" ]; then
                EXACTCMD="${MODEMAP[$CHOSENMODE]}"
                if [ -n "$EXACTCMD" ]; then
                    wlr-randr --output "$SELMON" --mode "$EXACTCMD"
                fi
            fi
        ;;
        "  Toggle Camera")
            if [ "${#CAMLIST[@]}" -gt 1 ]; then
                SELCAM_LABEL=$(printf "%s\n" "${CAMLIST[@]}" | gum choose --header "Select Camera (Esc to go back):")
                [ -z "$SELCAM_LABEL" ] && continue
                SELCAM_ID="${CAMMAP[$SELCAM_LABEL]}"
            elif [ "${#CAMLIST[@]}" -eq 1 ]; then
                SELCAM_ID="${CAMMAP[${CAMLIST[0]}]}"
            else
                SELCAM_ID=""
            fi
            CAMSTATE=$(gum choose --header "Camera Driver (Esc to go back):" "on" "off")
            if [ -n "$CAMSTATE" ]; then
                ERR=$( ${SUDOCMD:+"$SUDOCMD"} "$CORE" --set-camera "$CAMSTATE" ${SELCAM_ID:+"$SELCAM_ID"} 2>&1 )
                if [ -n "$ERR" ]; then
                    gum style --foreground "$RED" --margin "0 2" "$ERR"
                    sleep 3
                fi
            fi
            ;;
        "  Toggle Microphone")
            if [ "${#MICLIST[@]}" -gt 1 ]; then
                SELMIC_LABEL=$(printf "%s\n" "${MICLIST[@]}" | gum choose --header "Select Microphone (Esc to go back):")
                [ -z "$SELMIC_LABEL" ] && continue
                SELMIC_ID="${MICMAP[$SELMIC_LABEL]}"
            elif [ "${#MICLIST[@]}" -eq 1 ]; then
                SELMIC_ID="${MICMAP[${MICLIST[0]}]}"
            else
                SELMIC_ID="@DEFAULT_AUDIO_SOURCE@"
            fi
            ERR=""
            MICSTATE=$(gum choose --header "Microphone State (Esc to go back):" "unmute (on)" "mute (off)")
            if [ "$MICSTATE" == "mute (off)" ]; then
                ERR=$(wpctl set-mute "$SELMIC_ID" 1 2>&1)
            elif [ "$MICSTATE" == "unmute (on)" ]; then
                ERR=$(wpctl set-mute "$SELMIC_ID" 0 2>&1)
            fi
            if [ -n "$ERR" ]; then
                gum style --foreground "$RED" --margin "0 2" "$ERR"
                sleep 3
            fi
            ;;
        "  Toggle Wi-Fi")
            WIFISTATE=$(gum choose --header "Wi-Fi State (Esc to go back):" "on" "off")
            if [ -n "$WIFISTATE" ]; then
                ERR=$( ${SUDOCMD:+"$SUDOCMD"} "$CORE" --set-wifi "$WIFISTATE" 2>&1 )
                if [ -n "$ERR" ]; then
                    gum style --foreground "$RED" --margin "0 2" "$ERR"
                    sleep 3
                fi
            fi
            ;;
        "  Toggle Bluetooth")
            BTSTATE=$(gum choose --header "Bluetooth State (Esc to go back):" "on" "off")
            if [ -n "$BTSTATE" ]; then
                ERR=$( ${SUDOCMD:+"$SUDOCMD"} "$CORE" --set-bluetooth "$BTSTATE" 2>&1 )
                if [ -n "$ERR" ]; then
                    gum style --foreground "$RED" --margin "0 2" "$ERR"
                    sleep 3
                fi
            fi
            ;;
        "  Exit") clear; exit 0 ;;
    esac
done