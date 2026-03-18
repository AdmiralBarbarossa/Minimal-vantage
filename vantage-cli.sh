#!/bin/bash
# vantage-cli.sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
trap "clear; echo 'exiting..'; exit" SIGINT SIGTERM

SUDOCMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDOCMD="sudo"
    elif command -v doas >/dev/null 2>&1; then SUDOCMD="doas"
    fi
fi

for tool in gum rfkill wpctl; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required dependency '$tool' is not installed."
        exit 1
    fi
done

#CORE="./vantage-core.sh"

CORE="/usr/local/bin/vantage-core"
if [ ! -x "$CORE" ]; then
    echo "Error: Backend not found or not executable at $CORE."
    echo "Please install the backend properly before running the CLI."
    exit 1
fi

export RED="#E2231A"
export GUM_CHOOSE_CURSOR_FOREGROUND="$RED"
export GUM_CHOOSE_SELECTED_FOREGROUND="$RED"
export GUM_INPUT_PROMPT_FOREGROUND="$RED"
export GUM_INPUT_CURSOR_FOREGROUND="$RED"

read -r -d '' LOGO << 'EOF'
██  ██ ▄████▄ ███  ██ ██████ ▄████▄  ▄████  ██████ 
██▄▄██ ██▄▄██ ██ ▀▄██   ██   ██▄▄██ ██  ▄▄▄ ██▄▄   
 ▀██▀  ██  ██ ██   ██   ██   ██  ██  ▀███▀  ██▄▄▄▄ 
EOF

while true; do
    CORE_OUT=$($CORE --status 2>/dev/null)
    if [ -z "$CORE_OUT" ]; then
        clear
        echo "error: Backend returned no data; check vantage-core is installed and working."
        exit 1
    fi

    declare -A SYS_STATUS
    while IFS='=' read -r KEY VAL; do
        if [[ "$KEY" =~ ^[A-Z]+$ ]]; then
            SYS_STATUS["$KEY"]="$VAL"
        fi
    done <<< "$CORE_OUT"

    if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q "\[MUTED\]"; then MICSTATUS="off"
    else MICSTATUS="on"; fi

    if rfkill list wlan | grep -q "Soft blocked: yes"; then WIFISTATUS="off"
    else WIFISTATUS="on"; fi

    if rfkill list bluetooth | grep -q "Soft blocked: yes"; then BTSTATUS="off"
    else BTSTATUS="on"; fi

    HASWLR=false
    if command -v wlr-randr &> /dev/null && wlr-randr &> /dev/null; then
        HASWLR=true
        DISPOUT=$(wlr-randr | head -n 1 | awk '{print $1}')
        DISPMODE=$(wlr-randr | grep current | awk '{printf "%s @ %.0f Hz", $1, $3}')
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
    CAMERA=${SYS_STATUS["CAMERA"]:-"Unknown"}

    STATUSTEXT="  Battery Limits : Start: ${STARTCHARGE}% | Stop: ${STOPCHARGE}%
  Battery Stats  : ${BATCAPACITY}% (${BATSTATUS}) | Health: ${BATHEALTH}% | Cycles: ${CYCLECOUNT}
  Power Draw     : $BATPOWER
  Thermal Mode   : $PLATFORMPROFILE"
    
    if [ "$HASWLR" = true ]; then
        STATUSTEXT="$STATUSTEXT
󰍹  Display Mode   : $DISPMODE"
    fi

    STATUSTEXT="$STATUSTEXT
  Camera         : $CAMERA
  Microphone     : $MICSTATUS
  Wi-Fi          : $WIFISTATUS
  Bluetooth      : $BTSTATUS"

    echo " System Status:"
    gum style --border rounded --border-foreground "$RED" --padding "1 3" --margin "0 1" "$STATUSTEXT"
    echo ""

    MENUOPTS=(
        "  Set Battery Limits"
        "  Set Thermal Profile"
    )
    
    if [ "$HASWLR" = true ]; then
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
            $SUDOCMD $CORE --set-start "$START"
            
            STOP=$(gum input --header "Stop Threshold (1-100) | Press Esc to go back" --placeholder "Currently ${STOPCHARGE}%")
            if [ -z "$STOP" ]; then continue; fi
            $SUDOCMD $CORE --set-stop "$STOP"
            ;;
        "  Set Thermal Profile")
            PROF=$(echo "$AVAILABLEPROFILES" | tr ' ' '\n' | gum choose --header "Select Thermal Profile (Esc to go back):")
            if [ -n "$PROF" ]; then $SUDOCMD $CORE --set-profile "$PROF"; fi
            ;;
        "󰍹  Set Display Mode")
            if [ "$HASWLR" = true ]; then
                AVAILMODES=$(wlr-randr | grep 'px,' | awk '{printf "%s @ %.0f Hz\n", $1, $3}' | sort -ur)
                CHOSENMODE=$(echo "$AVAILMODES" | gum choose --header "Select Display Mode (Esc to go back):")
                
                if [ -n "$CHOSENMODE" ]; then
                    RES=$(echo "$CHOSENMODE" | awk '{print $1}')
                    HZ=$(echo "$CHOSENMODE" | awk '{print $3}')
                    wlr-randr --output "$DISPOUT" --mode "${RES}@${HZ}"
                fi
            fi
            ;;
        "  Toggle Camera")
            CAMSTATE=$(gum choose --header "Camera Driver (Esc to go back):" "on" "off")
            if [ -n "$CAMSTATE" ]; then $SUDOCMD $CORE --set-camera "$CAMSTATE"; fi
            ;;
        "  Toggle Microphone")
            MICSTATE=$(gum choose --header "Microphone State (Esc to go back):" "unmute (on)" "mute (off)")
            if [ "$MICSTATE" == "mute (off)" ]; then wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1
            elif [ "$MICSTATE" == "unmute (on)" ]; then wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0; fi
            ;;
        "  Toggle Wi-Fi")
            WIFISTATE=$(gum choose --header "Wi-Fi State (Esc to go back):" "on" "off")
            if [ -n "$WIFISTATE" ]; then $SUDOCMD $CORE --set-wifi "$WIFISTATE"; fi 
            ;;
        "  Toggle Bluetooth")
            BTSTATE=$(gum choose --header "Bluetooth State (Esc to go back):" "on" "off")
            if [ -n "$BTSTATE" ]; then $SUDOCMD $CORE --set-bluetooth "$BTSTATE"; fi 
            ;;
        "  Exit") clear; exit 0 ;;
    esac
done