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
VPCS=(/sys/bus/platform/devices/VPC2004:*/)
shopt -u nullglob
BATDIR="${BATS[0]:-}"
VPCDIR="${VPCS[0]:-}"

checkroot() {
    if [ "$EUID" -ne 0 ]; then echo "Error: Requires root (sudo)."; exit 1; fi
}

saveconfig() {
    local KEY=$1; local VAL=$2
    local TMPFILE
    TMPFILE=$(mktemp) || { echo "Error: Cannot create temp file"; return 1; }
    awk -v k="$KEY" -v v="$VAL" -F= '
        $1 == k { print k "=" v; found=1; next }
        { print }
        END { if (!found) print k "=" v }
    ' < <(cat "$CONFIG" 2>/dev/null || true) > "$TMPFILE"
    mv "$TMPFILE" "$CONFIG"
    chmod 600 "$CONFIG"    
    rm -f "$TMPFILE"
}

getstatus() {
    if [ -n "$BATDIR" ] && [ -d "$BATDIR" ]; then
        STARTCHARGE=$(cat "$BATDIR/charge_control_start_threshold" 2>/dev/null || echo "Unsupported")
        STOPCHARGE=$(cat "$BATDIR/charge_control_end_threshold" 2>/dev/null || echo "Unsupported")
        CYCLECOUNT=$(cat "$BATDIR/cycle_count" 2>/dev/null || echo "N/A")
        BATCAPACITY=$(cat "$BATDIR/capacity" 2>/dev/null || echo "N/A")
        BATSTATUS=$(cat "$BATDIR/status" 2>/dev/null || echo "N/A")

        if [ -f "$BATDIR/energy_full_design" ] && [ -f "$BATDIR/energy_full" ]; then
            _EF=$(cat "$BATDIR/energy_full" 2>/dev/null || echo 0)
            _EFD=$(cat "$BATDIR/energy_full_design" 2>/dev/null || echo 0)
            if [ "$_EFD" -gt 0 ]; then
                BATHEALTH=$(( _EF * 100 / _EFD ))
            else
                BATHEALTH="N/A"
            fi
        else
            BATHEALTH="N/A"
        fi
        POWERUW=$(cat "$BATDIR/power_now" 2>/dev/null || echo 0)
        if [ "$POWERUW" -gt 0 ]; then
            BATPOWER=$(awk -v p="$POWERUW" 'BEGIN {printf "%.1fW", p / 1000000}')
        else
            local CURUA VOLTUV
            CURUA=$(cat "$BATDIR/current_now" 2>/dev/null || echo 0)
            VOLTUV=$(cat "$BATDIR/voltage_now" 2>/dev/null || echo 0)
            if [ "$CURUA" -gt 0 ] && [ "$VOLTUV" -gt 0 ]; then
                BATPOWER=$(awk -v c="$CURUA" -v v="$VOLTUV" 'BEGIN {printf "%.1fW", (c * v) / 1000000000000}')
            else
                BATPOWER="0.0W (Plugged in)"
            fi
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
    if lsmod | grep -q "^uvcvideo"; then
        CAMERA="on"
    else
        CAMERA="off"
    fi

    if [ -n "$VPCDIR" ] && [ -f "${VPCDIR}conservation_mode" ]; then
        local CVAL
        CVAL=$(cat "${VPCDIR}conservation_mode" 2>/dev/null || echo "")
        if [ "$CVAL" = "1" ]; then CONSERVMODE="on"
        elif [ "$CVAL" = "0" ]; then CONSERVMODE="off"
        else CONSERVMODE="unknown"; fi
    else
        CONSERVMODE="Unsupported"
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
    echo "CONSERVMODE=$CONSERVMODE"
}

setlimits() {
    checkroot
    local START=$1
    local STOP=$2
    if [ -z "$BATDIR" ] || [ ! -d "$BATDIR" ]; then exit 1; fi
    if [[ "$START" =~ ^[0-9]+$ ]] && [ "$((10#$START))" -ge 0 ] && [ "$((10#$START))" -le 99 ] && \
       [[ "$STOP" =~ ^[0-9]+$ ]] && [ "$((10#$STOP))" -ge 1 ] && [ "$((10#$STOP))" -le 100 ]; then
        if [ "$((10#$START))" -ge "$((10#$STOP))" ]; then
            echo "Error: Start threshold ($START) must be less than stop threshold ($STOP)."
            exit 1
        fi

        if echo "$START" > "$BATDIR/charge_control_start_threshold" 2>/dev/null; then
            saveconfig "STARTCHARGE" "$START"
        fi
        
        if echo "$STOP" > "$BATDIR/charge_control_end_threshold" 2>/dev/null; then
            saveconfig "STOPCHARGE" "$STOP"
        fi
    else
        echo "Error: Start must be 0-99 and Stop must be 1-100."
        exit 1
    fi
}

setprofile() {
    checkroot; local PROF=$1
    local ALLOWED
    ALLOWED=$(cat "$PROFOPT" 2>/dev/null || echo "")
    local match=0
    for p in $ALLOWED; do [ "$p" = "$PROF" ] && match=1 && break; done
    if [ "$match" -eq 1 ]; then
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

setconservation() {
    checkroot
    local STATE=$1
    if [ -z "$VPCDIR" ] || [ ! -f "${VPCDIR}conservation_mode" ]; then
        echo "Error: Conservation mode not supported on this hardware."
        exit 1
    fi
    if [ "$STATE" == "on" ]; then
        echo "1" > "${VPCDIR}conservation_mode" || { echo "Error: Failed to enable conservation mode."; exit 1; }
        saveconfig "CONSERVMODE" "on"
    elif [ "$STATE" == "off" ]; then
        echo "0" > "${VPCDIR}conservation_mode" || { echo "Error: Failed to disable conservation mode."; exit 1; }
        saveconfig "CONSERVMODE" "off"
    else
        echo "Error: Invalid state. Use 'on' or 'off'."
        exit 1
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
            [[ "$STARTCHARGE" =~ ^[0-9]+$ ]] && echo "$STARTCHARGE" > "$BATDIR/charge_control_start_threshold" 2>/dev/null || true
            [[ "$STOPCHARGE" =~ ^[0-9]+$ ]] && echo "$STOPCHARGE" > "$BATDIR/charge_control_end_threshold" 2>/dev/null || true
        fi
        if [ -n "$PROFILE" ] && [ -f "$PROFOPT" ]; then
            local rmatch=0
            local rallowed
            rallowed=$(cat "$PROFOPT")
            for p in $rallowed; do [ "$p" = "$PROFILE" ] && rmatch=1 && break; done
            [ "$rmatch" -eq 1 ] && echo "$PROFILE" > "$PROFPAT" 2>/dev/null || true
        fi

        local CONSERVMODESAVED
        CONSERVMODESAVED=$(grep -E "^CONSERVMODE=" "$CONFIG" | cut -d'=' -f2 || echo "")
        if [ -n "$CONSERVMODESAVED" ] && [ -n "$VPCDIR" ] && [ -f "${VPCDIR}conservation_mode" ]; then
            if [ "$CONSERVMODESAVED" = "on" ]; then echo "1" > "${VPCDIR}conservation_mode" 2>/dev/null || true
            elif [ "$CONSERVMODESAVED" = "off" ]; then echo "0" > "${VPCDIR}conservation_mode" 2>/dev/null || true
            fi
        fi
    fi
}

case "${1:-}" in
    --status) getstatus ;;
    --set-limits) setlimits "${2:-}" "${3:-}" ;;
    --set-profile) setprofile "${2:-}" ;;
    --set-camera) setcamera "${2:-}" ;;
    --set-conservation) setconservation "${2:-}" ;;
    --set-wifi) setwifi "${2:-}" ;;
    --set-bluetooth) setbluetooth "${2:-}" ;;
    --restore) restoresettings ;;
    *) exit 1 ;;
esac