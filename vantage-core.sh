#!/bin/bash
# vantage-core.sh 

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -euo pipefail
umask 077
PROFPAT="/sys/firmware/acpi/platform_profile"
PROFOPT="/sys/firmware/acpi/platform_profile_choices"
CONFIG="/etc/vantage.conf"
shopt -s nullglob
BATS=(/sys/class/power_supply/BAT*)
shopt -u nullglob
BATDIR="${BATS[0]:-}"

checkroot() {
    if [ "$EUID" -ne 0 ]; then echo "Error: Requires root (sudo)."; exit 1; fi
}

saveconfig() {
    local KEY=$1; local VAL=$2
    [ ! -e "$CONFIG" ] && touch "$CONFIG"
    local TMPFILE
    TMPFILE=$(mktemp /tmp/vantage.XXXXXX)

    awk -v k="$KEY" -v v="$VAL" -F= '
        $1 == k { print k "=" v; found=1; next }
        { print }
        END { if (!found) print k "=" v }
    ' "$CONFIG" > "$TMPFILE"

    mv "$TMPFILE" "$CONFIG"
    chmod 600 "$CONFIG" 
}

getstatus() {
    if [ -n "$BATDIR" ] && [ -d "$BATDIR" ]; then
        STARTCHARGE=$(cat "$BATDIR/charge_control_start_threshold" 2>/dev/null || echo "Unsupported")
        STOPCHARGE=$(cat "$BATDIR/charge_control_end_threshold" 2>/dev/null || echo "Unsupported")
        CYCLECOUNT=$(cat "$BATDIR/cycle_count" 2>/dev/null || echo "N/A")
        BATCAPACITY=$(cat "$BATDIR/capacity" 2>/dev/null || echo "N/A")
        BATSTATUS=$(cat "$BATDIR/status" 2>/dev/null || echo "N/A")

        if [ -f "$BATDIR/energy_full_design" ] && [ -f "$BATDIR/energy_full" ]; then
            BATHEALTH=$(( $(cat "$BATDIR/energy_full" 2>/dev/null || echo 0) * 100 / $(cat "$BATDIR/energy_full_design" 2>/dev/null || echo 1) ))
        else 
            BATHEALTH="N/A"
        fi
        if [ -f "$BATDIR/power_now" ]; then
            POWERUW=$(cat "$BATDIR/power_now" 2>/dev/null || echo 0)
            if [ "$POWERUW" -eq 0 ]; then 
                BATPOWER="0.0W (Plugged in)"
            else 
                BATPOWER=$(awk "BEGIN {printf \"%.1fW\", $POWERUW / 1000000}")
            fi
        else 
            BATPOWER="N/A"
        fi
    else
        STARTCHARGE="Error"
        STOPCHARGE="Error"
        CYCLECOUNT="Error"
        BATCAPACITY="Error"
        BATSTATUS="Error"
        BATHEALTH="Error"
        BATPOWER="Error"
    fi
    if [ -f "$PROFPAT" ]; then
        PLATFORMPROFILE=$(cat "$PROFPAT" || echo "Unsupported")
        AVAILABLEPROFILES=$(cat "$PROFOPT" || echo "Unsupported")
    else 
        PLATFORMPROFILE="Unsupported"
        AVAILABLEPROFILES="Unsupported"
    fi
    if lsmod | grep -q "^uvcvideo" || true; then 
        CAMERA="on"
    else 
        CAMERA="off"
    fi

    echo "STARTCHARGE=$STARTCHARGE"
    echo "STOPCHARGE=$STOPCHARGE"
    echo "CYCLECOUNT=$CYCLECOUNT"
    echo "BATCAPACITY=$BATCAPACITY"
    echo "BATSTATUS=$BATSTATUS"
    echo "BATHEALTH=$BATHEALTH"
    echo "BATPOWER=$BATPOWER"
    echo "PLATFORMPROFILE=$PLATFORMPROFILE"
    echo "AVAILABLEPROFILES=$AVAILABLEPROFILES"
    echo "CAMERA=$CAMERA"
}

setstart() {
    checkroot
    local LIMIT=$1
    if [ -z "$BATDIR" ] || [ ! -d "$BATDIR" ]; then exit 1; fi
    if [[ "$LIMIT" =~ ^[0-9]+$ ]] && [ "$((10#$LIMIT))" -ge 0 ] && [ "$((10#$LIMIT))" -le 99 ]; then
        if echo "$LIMIT" > "$BATDIR/charge_control_start_threshold" 2>/dev/null; then
            saveconfig "STARTCHARGE" "$LIMIT"
        fi
    fi
    }

setstop() {
    checkroot
    local LIMIT=$1
    if [ -z "$BATDIR" ] || [ ! -d "$BATDIR" ]; then exit 1; fi
    if [[ "$LIMIT" =~ ^[0-9]+$ ]] && [ "$((10#$LIMIT))" -ge 1 ] && [ "$((10#$LIMIT))" -le 100 ]; then
        if echo "$LIMIT" > "$BATDIR/charge_control_end_threshold" 2>/dev/null; then
            saveconfig "STOPCHARGE" "$LIMIT"
        fi
    fi
    }

setprofile() {
    checkroot; local PROF=$1
    local ALLOWED
    ALLOWED=$(cat "$PROFOPT" 2>/dev/null || echo "")
    if [[ " $ALLOWED " =~ " $PROF " ]]; then
        if echo "$PROF" > "$PROFPAT" 2>/dev/null; then
            saveconfig "PROFILE" "$PROF"
        fi
    else
        echo "Error: Invalid profile."
        exit 1
    fi
    }

setcamera() {
    checkroot
    local STATE=$1
    if [ "$STATE" == "off" ]; then 
        modprobe -r uvcvideo 2>/dev/null || true
    elif [ "$STATE" == "on" ]; then 
        modprobe uvcvideo 2>/dev/null || true
    fi
    }

setwifi() {
    checkroot; local STATE=$1
    if [ "$STATE" == "on" ]; then rfkill unblock wlan 2>/dev/null || true
    elif [ "$STATE" == "off" ]; then rfkill block wlan 2>/dev/null || true; fi
    }

setbluetooth() {
    checkroot; local STATE=$1
    if [ "$STATE" == "on" ]; then rfkill unblock bluetooth 2>/dev/null || true
    elif [ "$STATE" == "off" ]; then rfkill block bluetooth 2>/dev/null || true; fi
    }

restoresettings() {
    checkroot
    if [ -f "$CONFIG" ]; then
        STARTCHARGE=$(grep -E "^STARTCHARGE=" "$CONFIG" | cut -d'=' -f2 || echo "")
        STOPCHARGE=$(grep -E "^STOPCHARGE=" "$CONFIG" | cut -d'=' -f2 || echo "")
        PROFILE=$(grep -E "^PROFILE=" "$CONFIG" | cut -d'=' -f2 || echo "")

        if [ -n "$BATDIR" ] && [ -d "$BATDIR" ]; then
            [ -n "$STARTCHARGE" ] && echo "$STARTCHARGE" > "$BATDIR/charge_control_start_threshold" 2>/dev/null || true
            [ -n "$STOPCHARGE" ] && echo "$STOPCHARGE" > "$BATDIR/charge_control_end_threshold" 2>/dev/null || true
        fi
        [ -n "$PROFILE" ] && echo "$PROFILE" > "$PROFPAT" 2>/dev/null || true
    fi
    }

case "${1:-}" in
    --status) getstatus ;;
    --set-start) setstart "${2:-}" ;;
    --set-stop) setstop "${2:-}" ;;
    --set-profile) setprofile "${2:-}" ;;
    --set-camera) setcamera "${2:-}" ;;
    --set-wifi) setwifi "${2:-}" ;;
    --set-bluetooth) setbluetooth "${2:-}" ;;
    --restore) restoresettings ;;
    *) exit 1 ;;
esac