# ThinkPad Vantage (Terminal Edition)

A lightning-fast, Wayland-native, and minimal Terminal User Interface (TUI) to control hardware settings on modern Lenovo ThinkPads (e.g., X1 Carbon Gen 13). 

Built specifically for tiling window manager users (River, Sway, Hyprland) who want zero bloat, no GUI dependencies, and pure keyboard-driven efficiency.

## 🚀 Features
* **Battery Conservation:** Set exact start/stop charging thresholds to prolong battery life.
* **Thermal/Fan Modes:** Switch between `low-power`, `balanced`, and `performance` ACPI profiles.
* **Microphone Privacy:** Instantly mute the default audio source via PipeWire.
* **Radios:** Quick toggles for Wi-Fi and Bluetooth.
* **Camera Privacy Toggle:** Attempt to forcefully unload the webcam driver (See Known Issues).

## 📦 Requirements
This script uses standard Linux tools and Charmbracelet's `gum` for the beautiful terminal interface.
* `gum` (The terminal UI engine)
* `pipewire` / `wireplumber` (Provides `wpctl` for microphone toggling)
* `networkmanager` (Provides `nmcli` for Wi-Fi)
* `bluez` (Provides `bluetoothctl` for Bluetooth)

**Installation on Fedora:**
```bash
sudo dnf install gum pipewire NetworkManager bluez