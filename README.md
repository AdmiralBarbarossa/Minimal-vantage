<div align="center">

# Minimal-Vantage

**A minimal Terminal User Interface (TUI) to control hardware settings on Lenovo ThinkPads**
<br>

[![Linux Supported](https://img.shields.io/badge/Linux-Supported-success?style=flat-square&logo=linux&logoColor=white)](https://kernel.org)
[![Wayland Native](https://img.shields.io/badge/Wayland-Native-blue?style=flat-square&logo=linux&logoColor=white)](https://wayland.freedesktop.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](https://opensource.org/licenses/MIT)
<br><br>

<img src="screenshots/interface.png" alt="ThinkPad Vantage TUI Interface" width="700">

</div>

## Compatibility

Based on Linux kernel ACPI drivers (Kernel 5.12+) and expected to work on modern Lenovo hardware from **2021 onwards**, including:
* **ThinkPad X1 Carbon** (Gen 9 through Gen 13+)
* **ThinkPad T-Series** (T14/T14s Gen 2+)
* **ThinkPad P-Series** (P14s, P1, etc.)
* **ThinkPad X1 Yoga** (Gen 6+)
* *Other modern Lenovo models utilizing the `thinkpad_acpi` driver.*

Optimized for **`wlroots`** users (River, Sway, Hyprland) seeking a simple, keyboard-driven tool; however, the kernel features remain compatible with **GNOME** and **KDE Plasma** without enforcing `wlr-randr` in `DE` setups.

Certain features require root access; **in-menu root authentication** —including fingerprints if pre-configured (e.g., PAM/`fprintd` on Fedora)— **is** supported; thereby, visual flow stays consistent.

## Features

* **Battery Conservation:** Set start/stop charging thresholds to prolong battery life with path detection (`BAT0`, `BAT1`, `BATT`).
* **Hardware Telemetry:** Readouts of Battery Health %, Cycle Counts, and Power Draw (Watts) snapshot.
* **Thermal/Fan Modes:** Switch between `low-power`, `balanced`, and `performance` ACPI profiles.
* **Display Control (`wlroots` only):** Adjust resolution and refresh rate via `wlr-randr`. Detects Wayland compositors and hides the option on GNOME/KDE to prevent clutter.
* **Microphone Privacy:** Instant audio muting via PipeWire.
* **Radios:** Quick toggles for Wi-Fi and Bluetooth using native kernel `rfkill` without reliance on NetworkManager or BlueZ.
* **Camera Privacy:** Attempts to load/unload the standard webcam kernel module.
* **Persistence:** Save settings across reboots, with an installer that supports both `systemd` and non-systemd environments.

> [!NOTE]
> Newer ThinkPad models (e.g., Intel Core Ultra) utilize Intel IPU6 (MIPI) architecture, and bypasses the internal USB hub; therefore, the `uvcvideo` driver may be absent, causing software toggles in this TUI to appear unresponsive. The actual switch (ThinkShutter) remains functional at the hardware level.

## Requirements
Standard Linux tools are prioritized; the only required external packages are Charmbracelet's `gum` for the UI, and Nerd Fonts for iconography.

* **OS:** Ubuntu 22.04+, Fedora 34+, Arch Linux, or any modern distro already using Wayland.
* `gum` (The terminal UI engine)
* A Nerd Font (e.g., `jetbrains-mono-nerd-fonts`)
* `pipewire` / `wireplumber` (Provides `wpctl` for microphone toggling)
* **[Optional]** `wlr-randr` (Only required if display control on `wlroots` compositors is desired, must be ignored for GNOME/KDE).

### Fedora
```bash
# 1. base dependencies
sudo dnf install gum pipewire jetbrains-mono-nerd-fonts

# 2. check wlr-randr ONLY if the wayland compositor is in use  
sudo dnf install wlr-randr
```

### Arch

```bash
# 1. base dependencies
sudo pacman -S gum pipewire wireplumber ttf-jetbrains-mono-nerd

# 2. check wlr-randr ONLY if the wayland compositor is in use
sudo pacman -S wlr-randr
```

### Debian/Ubuntu

*Note: `gum` requires adding the Charmbracelet repository on Debian/Ubuntu.*

```bash
# 1. base dependencies
sudo apt update
sudo apt install pipewire wireplumber fonts-jetbrains-mono

# 2. gum installation
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install gum

# 3. check wlr-randr ONLY if the wayland compositor is in use
sudo apt install wlr-randr
```

## Installation

Clone the repository and install it globally via `make`:

```bash
git clone https://github.com/AdmiralBarbarossa/Minimal-vantage.git
cd Minimal-vantage
sudo make install
```

Upon installation, run `vantage` in terminal. Native `sudo` authentication (including fingerprint) is supported inline.

> [!TIP]
> **Non-Systemd Environments (Void, Artix, Alpine):** The `Makefile` automatically detects the init system and bypass `systemd` service installation. To maintain hardware settings across reboots, choose from the following native persistence methods:
> **System Init (Recommended):** Append `/usr/local/bin/vantage-core --restore` to `/etc/rc.local` (Void/runit), an `/etc/local.d/*.start` script (OpenRC), or a root crontab (`@reboot`). This ensures settings are applied during the early boot sequence.
> **Wayland Autostart (Fallback):** By configuring `/etc/sudoers` for `NOPASSWD` execution of the core binary, the command `exec sudo /usr/local/bin/vantage-core --restore` (or `exec-once` for Hyprland) can be invoked directly from the compositor configuration. *Note: This method ties hardware state to the graphical session rather than the system boot sequence.*

## Uninstallation

```bash
sudo make uninstall
```

## Usage & Navigation

The pre-compiled nature of the Charmbracelet’s `gum` prevents custom remapping of keys; the default engine supports Vim-style vertical movement.

* **`j` / `k` (or Arrows):** Navigate up and down.
* **`Enter`:** Confirm selection or enter a submenu.
* **`Esc`:** Cancel the current prompt, return to the main menu, or quit the application.

## Inspiration & Alternatives

Inspired by the [niizam/vantage](https://github.com/niizam/vantage) repository, **Minimal-Vantage** adapts the concept for **ThinkPads** and modern workflows. While the original project targets Lenovo IdeaPads/Legions on legacy X11, this alternative swaps GTK popups (`zenity`) and X11 protocols for terminal-native styling (`gum`) and Wayland support (`wlr-randr`).

Power management suites like **TLP** or **auto-cpufreq** are great, but not my cup of tea for basic tasks like setting charge thresholds. Since I already run a minimal Fedora Basic + River setup with `tuned` with `thermald` (averaging a 4W draw on a 268VPro processor), I wanted something that just works and gets out of the way. This tool applies settings directly to the kernel via a `one-shot` boot service or on-demand execution without persistent background processes.

## Contributing & Feedback

Lenovo's hardware architecture and ACPI implementation can vary between generations and specific models. In the event of errors, bugs, or suggestions to make the script faster or more robust, as well as hardware compatibility confirmations, **Issues** or **Pull Requests** are much appreciated.

