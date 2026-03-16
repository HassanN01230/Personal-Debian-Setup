#!/usr/bin/env bash
# Usage: chmod +x setup.sh && ./setup.sh   (or "bash setup.sh" if running from fish)
[ -z "$BASH_VERSION" ] && bash # trying to enforce bash if running from fish or another shell but this doesnt work i think
[[ -f "$0" && "$0" == *.sh ]] && chmod +x "$0" # doesnt really matter but just in case the script is run as a file, make it executable

REAL_USER="${SUDO_USER:-$USER}"  # get the real user name if running as sudo, otherwise use the current user
REAL_HOME=$(eval echo ~"$REAL_USER")  
LOG="$REAL_HOME/Desktop/setup-log-$(date '+%Y-%m-%d_%H-%M-%S').log"
mkdir -p "$(dirname "$LOG")"  # create the directory for the log file if it doesn't exist

FAILED=()  # array to store the names of the packages that failed to install
TMPDIR=$(mktemp -d)  # temporary directory to store the downloaded packages

say() { echo -e "\n$*" | tee -a "$LOG"; } # print to screen and log file
status() { echo "$*" | tee -a "$LOG"; } # same as above but no new line

# 0. Autologon and removing sudo password cuz im sick of typing it every 5 seconds (u will still have to type if resuming from sleep or somethin)
say "Configuring autologin and passwordless sudo"
sudo mkdir -p /etc/sddm.conf.d
echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma" | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null  # Auto-login
echo "$REAL_USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd >/dev/null  # Passwordless sudo

# 1. System Update
say "Updating system packages"
sudo apt update >> "$LOG" 2>&1
sudo apt install -y ntpsec-ntpdate >> "$LOG" 2>&1
sudo ntpdate pool.ntp.org >> "$LOG" 2>&1 || true
sudo apt update >> "$LOG" 2>&1
sudo apt upgrade -y >> "$LOG" 2>&1

# 2. Firmware & Essentials
say "Installing firmware and essentials"
sudo apt install -y firmware-linux firmware-amd-graphics >> "$LOG" 2>&1

# 3. Enable Non-Free Repositories, hardcoded so no issue even if script ran multiple times
say "Enabling non-free repositories"
DEBIAN_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
sudo tee /etc/apt/sources.list > /dev/null << EOF
deb http://deb.debian.org/debian/ $DEBIAN_CODENAME main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $DEBIAN_CODENAME main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security $DEBIAN_CODENAME-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security $DEBIAN_CODENAME-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ $DEBIAN_CODENAME-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $DEBIAN_CODENAME-updates main contrib non-free non-free-firmware
EOF
sudo apt update >> "$LOG" 2>&1

# 4. Fish Shell
say "Installing Fish shell"
sudo apt install -y fish >> "$LOG" 2>&1
sudo chsh -s /usr/bin/fish "$REAL_USER" >> "$LOG" 2>&1
status "Fish is now your default shell. It takes effect on next login/restart."

# 5. AMD GPU / Vulkan + 32-bit libraries
say "Installing AMD GPU / Vulkan drivers and 32-bit libraries"
sudo apt install -y mesa-vulkan-drivers libvulkan1 vulkan-tools mesa-utils >> "$LOG" 2>&1
sudo dpkg --add-architecture i386 >> "$LOG" 2>&1
sudo apt update >> "$LOG" 2>&1
sudo apt install -y mesa-vulkan-drivers:i386 libglx-mesa0:i386 mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 >> "$LOG" 2>&1 # 32-bit Vulkan libraries

# 6. Installing libraries and services
say "Installing libraries and services"
sudo apt install -y pipewire pipewire-audio pipewire-pulse wireplumber bluetooth bluez >> "$LOG" 2>&1
sudo systemctl enable --now bluetooth >> "$LOG" 2>&1
sudo apt install -y libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly ffmpeg >> "$LOG" 2>&1
sudo apt install -y mpv vlc obs-studio unrar curl wget firefox-esr cifs-utils lsb-release >> "$LOG" 2>&1

sudo apt install -y git python3-pip python3-venv pipx build-essential gdb cmake >> "$LOG" 2>&1
pipx ensurepath >> "$LOG" 2>&1

# 7. Installing apps
CHOICES=$(whiptail --title "Choose Apps to Install" --checklist \
"Use SPACE to toggle, ENTER to confirm:" 20 50 10 \
"tailscale"   "Tailscale"              ON \
"discord"     "Discord"                ON \
"vscode"      "VS Code"                ON \
"cursor"      "Cursor"                 ON \
"jellyfin"    "Jellyfin Media Player"  ON \
"heroic"      "Heroic Games Launcher"  ON \
"localsend"   "LocalSend"              ON \
"steam"       "Steam"                  ON \
"lutris"      "Lutris"                 ON \
"lazygit"     "Lazygit"                ON \
3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then
    say "App selection cancelled, skipping app installs."
else
    say "Installing apps:"

    if [[ "$CHOICES" == *"tailscale"* ]]; then
        if curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG" 2>&1; then
            sudo systemctl enable tailscaled >> "$LOG" 2>&1
            status "Tailscale installed successfully"
        else
            status "Tailscale FAILED to install"
            FAILED+=("tailscale")
        fi
    fi

    if [[ "$CHOICES" == *"discord"* ]]; then
        if wget -qO "$TMPDIR/discord.deb" "https://discord.com/api/download?platform=linux&format=deb" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/discord.deb" >> "$LOG" 2>&1; then
            status "Discord installed successfully"
        else
            status "Discord FAILED to install"
            FAILED+=("discord")
        fi
    fi

    if [[ "$CHOICES" == *"vscode"* ]]; then
        if wget -qO "$TMPDIR/vscode.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/vscode.deb" >> "$LOG" 2>&1; then
            status "VS Code installed successfully"
        else
            status "VS Code FAILED to install"
            FAILED+=("vscode")
        fi
    fi

    if [[ "$CHOICES" == *"cursor"* ]]; then
        CURSOR_VER=$(curl -s "https://api2.cursor.sh/updates/latest?platform=linux-x64-deb" | grep -oP '"version":"\K[^"]+')
        if wget -O "$TMPDIR/cursor.deb" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/$CURSOR_VER" >> "$LOG" 2>&1 && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/cursor.deb" >> "$LOG" 2>&1; then
            status "Cursor installed successfully"
        else
            status "Cursor FAILED to install (download/install failed)"
            FAILED+=("cursor")
        fi
    fi

    if [[ "$CHOICES" == *"jellyfin"* ]]; then
        JELLYFIN_DEB_URL=$(curl -s "https://api.github.com/repos/jellyfin/jellyfin-desktop/releases/latest" | grep browser_download_url | grep "$DEBIAN_CODENAME" | grep -oP 'https://[^"]+')  # jellyfin url needs different grep for each debian release so getting codename dynamically to future proof it
        if [[ -n "$JELLYFIN_DEB_URL" ]] && wget -qO "$TMPDIR/jellyfin.deb" "$JELLYFIN_DEB_URL" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/jellyfin.deb" >> "$LOG" 2>&1; then
            status "Jellyfin Desktop installed successfully"
        else
            status "Jellyfin Desktop FAILED to install"
            FAILED+=("jellyfin-desktop")
        fi
    fi

    if [[ "$CHOICES" == *"heroic"* ]]; then
        HEROIC_DEB_URL=$(curl -s "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" | grep browser_download_url | grep linux-amd64.deb | grep -oP 'https://[^"]+')
        if [[ -n "$HEROIC_DEB_URL" ]] && wget -qO "$TMPDIR/heroic.deb" "$HEROIC_DEB_URL" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/heroic.deb" >> "$LOG" 2>&1; then
            status "Heroic installed successfully"
        else
            status "Heroic FAILED to install"
            FAILED+=("heroic")
        fi
    fi

    if [[ "$CHOICES" == *"localsend"* ]]; then
        LOCALSEND_DEB_URL=$(curl -s "https://api.github.com/repos/localsend/localsend/releases/latest" | grep browser_download_url | grep linux-x86-64.deb | grep -oP 'https://[^"]+')
        if [[ -n "$LOCALSEND_DEB_URL" ]] && wget -qO "$TMPDIR/localsend.deb" "$LOCALSEND_DEB_URL" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/localsend.deb" >> "$LOG" 2>&1; then
            status "LocalSend installed successfully"
        else
            status "LocalSend FAILED to install"
            FAILED+=("localsend")
        fi
    fi

    if [[ "$CHOICES" == *"steam"* ]]; then
        if wget -qO "$TMPDIR/steam.deb" "https://cdn.akamai.steamstatic.com/client/installer/steam.deb" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/steam.deb" >> "$LOG" 2>&1; then
            status "Steam installed successfully"
        else
            status "Steam FAILED to install"
            FAILED+=("steam")
        fi
    fi

    if [[ "$CHOICES" == *"lutris"* ]]; then
        LUTRIS_DEB_URL=$(curl -s "https://api.github.com/repos/lutris/lutris/releases/latest" | grep browser_download_url | grep '_all.deb' | grep -oP 'https://[^"]+')
        if [[ -n "$LUTRIS_DEB_URL" ]] && wget -qO "$TMPDIR/lutris.deb" "$LUTRIS_DEB_URL" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/lutris.deb" >> "$LOG" 2>&1; then
            status "Lutris installed successfully"
        else
            status "Lutris FAILED to install"
            FAILED+=("lutris")
        fi
    fi

    if [[ "$CHOICES" == *"lazygit"* ]]; then
        LAZYGIT_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+')
        if [[ -n "$LAZYGIT_VER" ]] \
        && curl -Lo "$TMPDIR/lazygit.tar.gz" "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VER}_Linux_x86_64.tar.gz" >> "$LOG" 2>&1 \
        && tar xf "$TMPDIR/lazygit.tar.gz" -C "$TMPDIR" lazygit && sudo install "$TMPDIR/lazygit" /usr/local/bin/lazygit; then
            status "Lazygit installed successfully"
        else
            status "Lazygit FAILED to install"
            FAILED+=("lazygit")
        fi
    fi
fi

# 8. Settings
say "Applying system settings"
kwriteconfig6 --file kwinrc --group NightColor --key Active true               
kwriteconfig6 --file kwinrc --group NightColor --key Mode Constant             # Nightlight configuration
kwriteconfig6 --file kwinrc --group NightColor --key NightTemperature 5300
qdbus6 org.kde.KWin /KWin reconfigure
kwriteconfig6 --file ksmserverrc --group General --key confirmLogout false

# 9. Cleanup
rm -rf "$TMPDIR" # remove the temporary directory
if [[ -f "$0" && "$0" == *.sh ]]; then
    rm -- "$0" && say "Script file deleted: $0" || say "Failed to delete script file: $0" # delete the script file if ran as a file, but not if pasted into terminal (where $0 is /bin/bash)
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    say "These failed to install: ${FAILED[*]}"
    status "NOT rebooting. Check log: $LOG"
else
    say "Everything installed successfully. Rebooting..."
    sudo reboot
fi