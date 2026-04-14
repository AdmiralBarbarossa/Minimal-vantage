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
    local KEY=$1 VAL=$2 TMPFILE
    TMPFILE=$(mktemp) || { echo "Error: Cannot create temp file"; return 1; }
    if awk -v k="$KEY" -v v="$VAL" -F= '
        $1 == k { print k "=" v; found=1; next }
        { print }
        END { if (!found) print k "=" v }
    ' < <(cat "$CONFIG" 2>/dev/null || true) > "$TMPFILE"; then
        chmod 600 "$TMPFILE"
        mv "$TMPFILE" "$CONFIG"
    else
        rm -f "$TMPFILE"
        return 1
    fi
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
        if [ -f "$BATDIR/power_now" ]; then
            POWERUW=$(cat "$BATDIR/power_now" 2>/dev/null || echo 0)
            if [ "$POWERUW" -eq 0 ]; then 
                BATPOWER="0.0W (Plugged in)"
            else 
                BATPOWER=$(awk -v p="$POWERUW" 'BEGIN {printf "%.1fW", p / 1000000}')
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
        PLATFORMPROFILE=$(cat "$PROFPAT" 2>/dev/null || echo "Unsupported")
        AVAILABLEPROFILES=$(cat "$PROFOPT" 2>/dev/null || echo "Unsupported")
    else 
        PLATFORMPROFILE="Unsupported"
        AVAILABLEPROFILES="Unsupported"
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
}

setlimits() {
    checkroot
    local START=$1
    local STOP=$2
    if [ -z "$BATDIR" ] || [ ! -d "$BATDIR" ]; then echo "Error: No battery found."; exit 1; fi
    if [[ "$START" =~ ^[0-9]+$ ]] && [ "$((10#$START))" -le 99 ] && \
       [[ "$STOP" =~ ^[0-9]+$ ]] && [ "$((10#$STOP))" -ge 1 ] && [ "$((10#$STOP))" -le 100 ]; then
        if [ "$((10#$START))" -ge "$((10#$STOP))" ]; then
            echo "Error: Start threshold ($START) must be less than stop threshold ($STOP)."
            exit 1
        fi

        local CURRENT_STOP
        CURRENT_STOP=$(cat "$BATDIR/charge_control_end_threshold" 2>/dev/null || echo 100)

        if [ "$((10#$START))" -ge "$((10#$CURRENT_STOP))" ]; then
            echo "$STOP" > "$BATDIR/charge_control_end_threshold" || \
                { echo "Error: Failed to write stop threshold."; exit 1; }
            saveconfig "STOPCHARGE" "$STOP"
            echo "$START" > "$BATDIR/charge_control_start_threshold" || \
                { echo "Error: Failed to write start threshold."; exit 1; }
            saveconfig "STARTCHARGE" "$START"
        else
            echo "$START" > "$BATDIR/charge_control_start_threshold" || \
                { echo "Error: Failed to write start threshold."; exit 1; }
            saveconfig "STARTCHARGE" "$START"
            echo "$STOP" > "$BATDIR/charge_control_end_threshold" || \
                { echo "Error: Failed to write stop threshold."; exit 1; }
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
        echo "$PROF" > "$PROFPAT" || { echo "Error: Failed to write profile."; exit 1; }
        saveconfig "PROFILE" "$PROF"
    else
        echo "Error: Invalid profile."
        exit 1
    fi
}

setcamera() {
    checkroot
    local STATE=$1
    local TARGET="${2:-}"
    if [ -n "$TARGET" ] && ! [[ "$TARGET" =~ ^[0-9][0-9.\-]*$ ]]; then
        echo "Error: Invalid camera device ID."; exit 1
    fi
    shopt -s nullglob
    if [ "$STATE" == "off" ]; then
        local found=0
        if [ -n "$TARGET" ]; then
            for dev in /sys/bus/usb/drivers/uvcvideo/"${TARGET}":*; do
                found=1
                echo "${dev##*/}" > /sys/bus/usb/drivers/uvcvideo/unbind 2>/dev/null || true
            done
        else
            for dev in /sys/bus/usb/drivers/uvcvideo/[0-9]*; do
                found=1
                echo "${dev##*/}" > /sys/bus/usb/drivers/uvcvideo/unbind 2>/dev/null || true
            done
        fi
        if [ "$found" -eq 0 ]; then
            exit 0
        fi
        local _still_bound
        if [ -n "$TARGET" ]; then
            _still_bound=(/sys/bus/usb/drivers/uvcvideo/"${TARGET}":*)
        else
            _still_bound=(/sys/bus/usb/drivers/uvcvideo/[0-9]*)
        fi
        if [ "${#_still_bound[@]}" -gt 0 ]; then
            echo "Error: Could not unbind camera device."
            exit 1
        fi
    elif [ "$STATE" == "on" ]; then
        modprobe uvcvideo 2>/dev/null || true
        if [ -n "$TARGET" ]; then
            for iface in /sys/bus/usb/devices/"${TARGET}":*/; do
                [ "$(cat "${iface}bInterfaceClass" 2>/dev/null)" = "0e" ] || continue
                [ "$(cat "${iface}bInterfaceSubClass" 2>/dev/null)" = "01" ] || continue
                _n="${iface%/}"; echo "${_n##*/}" > /sys/bus/usb/drivers/uvcvideo/bind 2>/dev/null || true
            done
            _bound=(/sys/bus/usb/drivers/uvcvideo/"${TARGET}":*)
            if [ "${#_bound[@]}" -eq 0 ]; then
                echo "Error: No camera device found."
                exit 1
            fi
        else
            for iface in /sys/bus/usb/devices/*:*/; do
                [ "$(cat "${iface}bInterfaceClass" 2>/dev/null)" = "0e" ] || continue
                [ "$(cat "${iface}bInterfaceSubClass" 2>/dev/null)" = "01" ] || continue
                _n="${iface%/}"; echo "${_n##*/}" > /sys/bus/usb/drivers/uvcvideo/bind 2>/dev/null || true
            done
            _bound=(/sys/bus/usb/drivers/uvcvideo/[0-9]*)
            if [ "${#_bound[@]}" -eq 0 ]; then
                echo "Error: No camera device found."
                exit 1
            fi
        fi
    fi
    shopt -u nullglob
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
        STARTCHARGE=""; STOPCHARGE=""; PROFILE=""
        while IFS='=' read -r _k _v; do
            case "$_k" in
                STARTCHARGE) STARTCHARGE="$_v" ;;
                STOPCHARGE)  STOPCHARGE="$_v"  ;;
                PROFILE)     PROFILE="$_v"     ;;
            esac
        done < "$CONFIG"

        if [ -n "$BATDIR" ] && [ -d "$BATDIR" ]; then
            [[ "$STOPCHARGE" =~ ^[0-9]+$ ]] && echo "$STOPCHARGE" > "$BATDIR/charge_control_end_threshold" 2>/dev/null || true
            [[ "$STARTCHARGE" =~ ^[0-9]+$ ]] && echo "$STARTCHARGE" > "$BATDIR/charge_control_start_threshold" 2>/dev/null || true
        fi
        if [ -n "$PROFILE" ] && [ -f "$PROFOPT" ]; then
            local rmatch=0
            local rallowed
            rallowed=$(cat "$PROFOPT")
            for p in $rallowed; do [ "$p" = "$PROFILE" ] && rmatch=1 && break; done
            [ "$rmatch" -eq 1 ] && echo "$PROFILE" > "$PROFPAT" 2>/dev/null || true
        fi
    fi
}

case "${1:-}" in
    --status) getstatus ;;
    --set-limits) setlimits "${2:-}" "${3:-}" ;;
    --set-profile) setprofile "${2:-}" ;;
    --set-camera) setcamera "${2:-}" "${3:-}" ;;
    --set-wifi) setwifi "${2:-}" ;;
    --set-bluetooth) setbluetooth "${2:-}" ;;
    --restore) restoresettings ;;
    *) exit 1 ;;
esac