#!/usr/bin/env bash
# Usage: chmod +x setup.sh && ./setup.sh   (or "bash setup.sh" if running from fish)

# All of the dialog helpers in this script use kdialog (GUI) on KDE since its preinstalled, and whiptail (TUI) everywhere else
# checklist: show_checklist "title" "text" "tag" "desc" "on/off" "tag2" "desc2" "on/off" ...
# menu:      show_menu "title" "text" "tag" "desc" "tag2" "desc2" ...
# msgbox:    show_msgbox "title" "text"

[ -z "$BASH_VERSION" ] && bash # trying to enforce bash if running from fish or another shell but this doesnt work i think
[[ -f "$0" && "$0" == *.sh ]] && chmod +x "$0" # doesnt really matter but just in case the script is run as a file, make it executable

REAL_USER="${SUDO_USER:-$USER}"  # get the real user name if running as sudo, otherwise use the current user
REAL_HOME=$(eval echo ~"$REAL_USER")
LOG="$REAL_HOME/Desktop/setup-log-$(date '+%Y-%m-%d_%H-%M-%S').log"
mkdir -p "$(dirname "$LOG")"  # create the directory for the log file if it doesn't exist

FAILED=()  # array to store the names of the packages that failed to install
POST_NOTES=()  # array to store post-install notes for the user
TMPDIR=$(mktemp -d)  # temporary directory to store the downloaded packages

say() { echo -e "\n$*" | tee -a "$LOG"; } # print to screen and log file
say_dont_skip_line() { echo "$*" | tee -a "$LOG"; } # same as above but no new line

# Get the user's desktop environment and set the appropriate value so that the correct type of dialog helper is used
if [[ -n "$DISPLAY" ]] && command -v kdialog &>/dev/null; then
    USE_KDIALOG=true
else
    USE_KDIALOG=false
fi

show_checklist() { 
    local title="$1" text="$2"
    shift 2
    if [[ "$USE_KDIALOG" == true ]]; then
        # kdialog only shows the label, not the tag — combine them so the app name is visible
        local args=()
        while [[ $# -ge 3 ]]; do
            args+=("$1" "$1 — $2" "$3")  # tag, "tag — description", state
            shift 3
        done
        QT_FONT_DPI=120 kdialog --title "$title" --geometry 700x600 --checklist "$text" "${args[@]}" 2>/dev/null
    else
        local count=$(( $# / 3 ))
        local height=$((count + 8))
        whiptail --title "$title" --checklist "$text" "$height" 60 "$count" "$@" 3>&1 1>&2 2>&3
    fi
}

show_menu() {
    local title="$1" text="$2"
    shift 2
    if [[ "$USE_KDIALOG" == true ]]; then
        # kdialog only shows the label, not the tag — combine them so the app name is visible
        local args=()
        while [[ $# -ge 2 ]]; do
            args+=("$1" "$1 — $2")
            shift 2
        done
        QT_FONT_DPI=120 kdialog --title "$title" --geometry 600x400 --menu "$text" "${args[@]}" 2>/dev/null
    else
        local count=$(( $# / 2 ))
        local height=$((count + 8))
        whiptail --title "$title" --menu "$text" "$height" 60 "$count" "$@" 3>&1 1>&2 2>&3
    fi
}

show_msgbox() { 
    local title="$1" text="$2"
    if [[ "$USE_KDIALOG" == true ]]; then
        # write to temp file and use --textbox for better text rendering and sizing
        local tmpfile=$(mktemp)
        echo -e "$text" > "$tmpfile"
        QT_FONT_DPI=120 kdialog --title "$title" --geometry 700x500 --textbox "$tmpfile" 2>/dev/null
        rm -f "$tmpfile"
    else
        whiptail --title "$title" --scrolltext --msgbox "$text" 24 78
    fi
}

show_yesno() {
    local title="$1" text="$2"
    if [[ "$USE_KDIALOG" == true ]]; then
        QT_FONT_DPI=120 kdialog --title "$title" --yesno "$text" 2>/dev/null
    else
        whiptail --title "$title" --yesno "$text" 12 60
    fi
}

show_input() {
    local title="$1" text="$2"
    if [[ "$USE_KDIALOG" == true ]]; then
        QT_FONT_DPI=120 kdialog --title "$title" --inputbox "$text" 2>/dev/null
    else
        whiptail --title "$title" --inputbox "$text" 10 60 3>&1 1>&2 2>&3
    fi
}

show_password() {
    local title="$1" text="$2"
    if [[ "$USE_KDIALOG" == true ]]; then
        QT_FONT_DPI=120 kdialog --title "$title" --password "$text" 2>/dev/null
    else
        whiptail --title "$title" --passwordbox "$text" 10 60 3>&1 1>&2 2>&3
    fi
}

# helper to install a .deb from a URL, keeps the same pattern as the rest of the script
install_deb() {
    local name="$1" url="$2" filename="$3"
    if wget -qO "$TMPDIR/$filename" "$url" && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/$filename" >> "$LOG" 2>&1; then
        say_dont_skip_line "$name installed successfully"
        return 0
    else
        say_dont_skip_line "$name FAILED to install"
        FAILED+=("$name")
        return 1
    fi
}

# 0. Detect which DE is installed so we can configure the right display manager and settings
if command -v plasmashell &>/dev/null; then
    DE="kde"
elif command -v gnome-shell &>/dev/null; then
    DE="gnome"
elif command -v xfce4-session &>/dev/null; then
    DE="xfce"
elif command -v cinnamon &>/dev/null; then
    DE="cinnamon"
elif command -v mate-session &>/dev/null; then
    DE="mate"
elif command -v lxqt-session &>/dev/null; then
    DE="lxqt"
elif command -v lxsession &>/dev/null; then
    DE="lxde"
else
    DE="unknown"
fi
say "Detected desktop environment: $DE"

# 1. Detect GPU
if lspci | grep -qiE "VGA.*NVIDIA|3D.*NVIDIA"; then
    GPU="nvidia"
elif lspci | grep -qiE "VGA.*AMD|VGA.*\bATI\b|3D.*AMD"; then  # for ATI, use \b to match the word "ATI" specifically since "ati" is a common substring
    GPU="amd"
elif lspci | grep -qiE "VGA.*Intel|3D.*Intel"; then
    GPU="intel"
else
    GPU="unknown"
fi
say "Detected GPU: $GPU"

# 2. Detect device type (laptop vs desktop) for power/input settings
if [[ -e /sys/class/power_supply/BAT0 ]] || [[ -e /sys/class/power_supply/BAT1 ]]; then # checks if a battery is present
    DEVICE_TYPE="laptop"
else
    DEVICE_TYPE="desktop"
fi
say "Detected device type: $DEVICE_TYPE"

# Ask display scaling early so all subsequent dialogs render at the right size
SCALE_CHOICE="1"
if [[ "$DE" == "kde" ]]; then
    SCALE_CHOICE=$(show_menu "Display Scaling" "Select display scaling (or ESC to keep current):" \
    "1"      "100%" \
    "1.25"   "125%" \
    "1.5"    "150%" \
    "1.75"   "175%" \
    "2"      "200%" \
    ) || SCALE_CHOICE=""
fi

# 3. Autologon and removing sudo password cuz im sick of typing it every 5 seconds (u will still have to type if resuming from sleep or somethin)
say "[1/16] Configuring autologin and passwordless sudo"

if [[ "$DE" == "kde" ]]; then
    sudo mkdir -p /etc/sddm.conf.d
    echo -e "[Autologin]\nUser=$REAL_USER\nSession=plasma" | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null  # SDDM auto-login for KDE
elif [[ "$DE" == "gnome" ]]; then
    # GDM auto-login
    sudo mkdir -p /etc/gdm3
    if [[ -f /etc/gdm3/daemon.conf ]]; then
        sudo sed -i "s/^\[daemon\]/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$REAL_USER/" /etc/gdm3/daemon.conf
    else
        echo -e "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$REAL_USER" | sudo tee /etc/gdm3/daemon.conf >/dev/null
    fi
elif [[ "$DE" == "lxqt" ]]; then
    sudo mkdir -p /etc/sddm.conf.d
    echo -e "[Autologin]\nUser=$REAL_USER\nSession=lxqt" | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null  # SDDM auto-login for LXQt
else
    # Xfce, Cinnamon, MATE, LXDE all use LightDM
    if [[ -f /etc/lightdm/lightdm.conf ]]; then
        sudo sed -i "s/^#\?autologin-user=.*/autologin-user=$REAL_USER/" /etc/lightdm/lightdm.conf
    else
        sudo mkdir -p /etc/lightdm
        echo -e "[Seat:*]\nautologin-user=$REAL_USER" | sudo tee /etc/lightdm/lightdm.conf >/dev/null
    fi
fi

echo "$REAL_USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/nopasswd >/dev/null  # Passwordless sudo
say_dont_skip_line "done."

# 4. System Update
say "[2/16] Updating system packages"
say_dont_skip_line "Syncing package lists..."
sudo apt update >> "$LOG" 2>&1
say_dont_skip_line "Installing NTP time sync..."
sudo apt install -y ntpsec-ntpdate >> "$LOG" 2>&1
sudo ntpdate pool.ntp.org >> "$LOG" 2>&1 || true
say_dont_skip_line "Upgrading packages..."
sudo apt update >> "$LOG" 2>&1
sudo apt upgrade -y >> "$LOG" 2>&1
say_dont_skip_line "done."

# 5. Firmware & Essentials (GPU-aware)
say "[3/16] Installing firmware and essentials"
say_dont_skip_line "Installing firmware-linux..."
sudo apt install -y firmware-linux >> "$LOG" 2>&1 || true
if [[ "$GPU" == "nvidia" ]]; then
    say_dont_skip_line "Installing firmware-misc-nonfree (NVIDIA)..."
    sudo apt install -y firmware-misc-nonfree >> "$LOG" 2>&1 || true
elif [[ "$GPU" == "amd" ]]; then
    say_dont_skip_line "Installing firmware-amd-graphics..."
    sudo apt install -y firmware-amd-graphics >> "$LOG" 2>&1 || true
fi
say_dont_skip_line "done."

# 6. Enable Non-Free Repositories, hardcoded so no issue even if script ran multiple times
say "[4/16] Enabling non-free repositories"
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
say_dont_skip_line "done."

# 7. KDE bloatware removal — apps nobody asked for
if [[ "$DE" == "kde" ]]; then
    say "[5/16] Removing KDE bloatware"
    # mark ALL currently installed packages as manually installed so autoremove can never cascade
    # and accidentally remove critical KDE packages like SDDM
    say_dont_skip_line "Protecting installed packages..."
    sudo apt-mark manual $(apt-mark showauto) >> "$LOG" 2>&1 || true

    BLOAT_PACKAGES="akregator dragonplayer imagemagick imagemagick-6-common imagemagick-7-common imagemagick-7.q16 juk kaddressbook kaddressbook-data kmail kdepim-themeeditors kmousetool kmouth konqueror konqueror-data konq-plugins korganizer ktnef pim-data-exporter pim-sieve-editor qsynth sweeper xterm libreoffice-core libreoffice-common libreoffice-calc libreoffice-draw libreoffice-impress libreoffice-math libreoffice-writer libreoffice-base-core libreoffice-help-common libreoffice-help-en-us libreoffice-kf6 libreoffice-plasma libreoffice-qt6 libreoffice-style-breeze libreoffice-style-colibre"
    say_dont_skip_line "Purging bloatware..."
    for pkg in $BLOAT_PACKAGES; do
        sudo apt purge -y "$pkg" >> "$LOG" 2>&1 || true
    done
    say_dont_skip_line "done."
fi

# 8. Fish Shell
say "[6/16] Installing Fish shell"
sudo apt install -y fish >> "$LOG" 2>&1
sudo chsh -s /usr/bin/fish "$REAL_USER" >> "$LOG" 2>&1
say_dont_skip_line "Fish is now your default shell. It takes effect on next login/restart."

# 9. GPU Drivers
say "[7/16] Installing GPU drivers"
say_dont_skip_line "Enabling 32-bit architecture..."
sudo dpkg --add-architecture i386 >> "$LOG" 2>&1  # needed for Steam and 32-bit game libs regardless of GPU
sudo apt update >> "$LOG" 2>&1

if [[ "$GPU" == "amd" ]]; then
    say_dont_skip_line "Installing AMD GPU/Vulkan drivers + 32-bit libraries..."
    sudo apt install -y mesa-vulkan-drivers libvulkan1 vulkan-tools mesa-utils >> "$LOG" 2>&1
    sudo apt install -y mesa-vulkan-drivers:i386 libglx-mesa0:i386 mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 >> "$LOG" 2>&1  # 32-bit Vulkan libraries

elif [[ "$GPU" == "nvidia" ]]; then
    say_dont_skip_line "Installing NVIDIA drivers + kernel headers..."
    sudo apt install -y linux-headers-$(uname -r) >> "$LOG" 2>&1  # kernel headers needed for dkms
    sudo apt install -y nvidia-driver firmware-misc-nonfree nvidia-kernel-dkms >> "$LOG" 2>&1

    # GRUB config for NVIDIA — fixes black screen issues and enables DRM modesetting
    say_dont_skip_line "Configuring GRUB for NVIDIA"
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet nvidia-drm.modeset=1 nvidia-drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"/' /etc/default/grub
    sudo update-grub >> "$LOG" 2>&1

    # Modprobe config — blacklist nouveau + NVIDIA module loading chain
    say_dont_skip_line "Configuring modprobe for NVIDIA"
    sudo tee /etc/modprobe.d/nvidia.conf > /dev/null << 'MODPROBE_EOF'
# Blacklist nouveau to prevent conflicts with nvidia driver
blacklist nouveau

# Preserve video memory allocations across suspend/resume
options nvidia-current NVreg_PreserveVideoMemoryAllocations=1

# NVIDIA module loading chain — ensures correct load order
install nvidia modprobe -i nvidia-current $CMDLINE_OPTS
install nvidia-modeset modprobe nvidia ; modprobe -i nvidia-current-modeset $CMDLINE_OPTS
install nvidia-drm modprobe nvidia-modeset ; modprobe -i nvidia-current-drm $CMDLINE_OPTS
install nvidia-uvm modprobe nvidia ; modprobe -i nvidia-current-uvm $CMDLINE_OPTS
install nvidia-peermem modprobe nvidia ; modprobe -i nvidia-current-peermem $CMDLINE_OPTS

# Unloading uses internal names
remove nvidia modprobe -r -i nvidia-drm nvidia-modeset nvidia-peermem nvidia-uvm nvidia
remove nvidia-modeset modprobe -r -i nvidia-drm nvidia-modeset

alias char-major-195* nvidia
alias   pci:v000010DEd00000E00sv*sd*bc04sc80i00*        nvidia
alias   pci:v000010DEd00000AA3sv*sd*bc0Bsc40i00*        nvidia
alias   pci:v000010DEd*sv*sd*bc03sc02i00*               nvidia
alias   pci:v000010DEd*sv*sd*bc03sc00i00*               nvidia
MODPROBE_EOF
    sudo update-initramfs -u >> "$LOG" 2>&1

    # Enable NVIDIA suspend/hibernate/resume services
    sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service >> "$LOG" 2>&1
    say_dont_skip_line "NVIDIA drivers and configuration done."

else
    say_dont_skip_line "Unknown GPU, skipping GPU-specific drivers"
fi

# 10. Installing utilities + services (base packages always installed)
say "[8/16] Installing utilities + services"
say_dont_skip_line "Installing audio (pipewire, wireplumber)..."
sudo apt install -y pipewire pipewire-audio pipewire-pulse wireplumber >> "$LOG" 2>&1
say_dont_skip_line "Installing bluetooth..."
sudo apt install -y bluetooth bluez >> "$LOG" 2>&1
sudo systemctl enable --now bluetooth >> "$LOG" 2>&1
say_dont_skip_line "Installing media codecs (ffmpeg, gstreamer)..."
sudo apt install -y libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly ffmpeg >> "$LOG" 2>&1
say_dont_skip_line "Installing media players, tools, browser..."
sudo apt install -y mpv vlc unrar curl wget firefox-esr cifs-utils lsb-release >> "$LOG" 2>&1
# auto-install uBlock Origin for Firefox via enterprise policy
say_dont_skip_line "Configuring uBlock Origin for Firefox..."
sudo mkdir -p /usr/lib/firefox-esr/distribution
sudo tee /usr/lib/firefox-esr/distribution/policies.json > /dev/null << 'FIREFOX_POLICY'
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi",
        "installation_mode": "normal_installed"
      }
    }
  }
}
FIREFOX_POLICY
say_dont_skip_line "Installing dev tools (git, python, pipx, cmake)..."
sudo apt install -y git python3-pip python3-venv pipx build-essential gdb cmake >> "$LOG" 2>&1
pipx ensurepath >> "$LOG" 2>&1
say_dont_skip_line "Installing coding fonts (JetBrains Mono, Nerd Fonts)..."
sudo apt install -y fonts-jetbrains-mono >> "$LOG" 2>&1 || true
# Nerd Fonts (JetBrainsMono patched) — not in apt, download from GitHub
NERDFONT_URL=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | grep browser_download_url | grep 'JetBrainsMono.tar.xz' | grep -oP 'https://[^"]+')
if [[ -n "$NERDFONT_URL" ]]; then
    mkdir -p "$REAL_HOME/.local/share/fonts"
    wget -qO "$TMPDIR/nerdfonts.tar.xz" "$NERDFONT_URL" >> "$LOG" 2>&1 \
    && tar xf "$TMPDIR/nerdfonts.tar.xz" -C "$REAL_HOME/.local/share/fonts/" >> "$LOG" 2>&1 \
    && chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/fonts" \
    && sudo -u "$REAL_USER" fc-cache -f >> "$LOG" 2>&1
fi
say_dont_skip_line "done."

# ==================================================================================
# 11. Installing apps — single checklist with category headers
# ==================================================================================
say "[9/16] Select apps to install"

# --- Screen 1: Apps (Dev + Media + Browsers + Office) ---
APP_CHOICES=$(show_checklist "Apps" "Select apps to install:" \
"VSCode"            "Visual Studio Code" on \
"VS Codium"         "FOSS VS Code fork" off \
"Cursor"            "AI code editor" off \
"Claude Code"       "Anthropic CLI (needs Node)" off \
"Node.js"           "via nvm" off \
"Java JDK"          "OpenJDK" off \
"Flutter"           "Flutter SDK" off \
"Android Studio"    "Android IDE" off \
"Docker"            "Container engine" off \
"Git"               "Version control" on \
"Lazygit"           "Terminal git UI" off \
"Qt Dev"            "Qt6 headers + tools" off \
"DBeaver"           "Database manager (needs Java)" off \
"FileZilla"         "FTP client" off \
"Steam"             "Steam client" off \
"Lutris"            "Game manager" on \
"Heroic"            "Epic/GOG launcher" on \
"Jellyfin Client"   "Media player" on \
"Sunshine"          "Game stream host" off \
"Moonlight"         "Game stream client" off \
"OBS Studio"        "Screen recording" off \
"Discord"           "Chat client" on \
"Audacity"          "Audio editor" off \
"Kdenlive"          "Video editor" off \
"HandBrake"         "Video transcoder" off \
"qBittorrent"       "Torrent client" off \
"Zen Browser"       "Privacy browser" off \
"Brave"             "Brave browser" off \
"Google Chrome"     "Chrome browser" off \
"Obsidian"          "Note-taking app" off \
"LibreOffice Writer" "Word processor" off \
"LibreOffice Calc"  "Spreadsheets" off \
"LibreOffice Impress" "Presentations" off \
"LibreOffice Draw"  "Diagrams/drawings" off \
"LibreOffice Math"  "Math formulas" off \
"LibreOffice Base"  "Database" off \
"OnlyOffice"        "Office suite" off \
"Vicinae"           "Local AI assistant" off \
"NoMachine"         "Remote desktop" off \
"LocalSend"         "Local file sharing" on \
"Tailscale"         "Mesh VPN" on \
"ProtonVPN"         "Privacy VPN" off \
"Windscribe"        "Windscribe VPN" off \
"Mullvad"           "Mullvad VPN" off \
"Virt-manager"      "VM manager + QEMU" off \
"htop"              "Process viewer" off \
"btop"              "Resource monitor" off \
"s3fs-fuse"         "Mount S3 buckets" off \
"lm-sensors"        "CPU/GPU temps + fans" off \
"psensor"           "HW monitor GUI" off \
"smartmontools"     "Disk health monitoring" off \
"Whisper"           "faster-whisper + model" off \
) || true

# Auto-resolve dependencies
if [[ "$APP_CHOICES" == *"Claude Code"* ]] && [[ "$APP_CHOICES" != *"Node.js"* ]]; then
    say_dont_skip_line "Claude Code requires Node.js — adding it automatically"
    APP_CHOICES="$APP_CHOICES Node.js"
fi
if [[ "$APP_CHOICES" == *"DBeaver"* ]] && [[ "$APP_CHOICES" != *"Java JDK"* ]]; then
    say_dont_skip_line "DBeaver requires Java JDK — adding it automatically"
    APP_CHOICES="$APP_CHOICES Java JDK"
fi
if [[ "$APP_CHOICES" == *"Flutter"* ]] && [[ "$APP_CHOICES" != *"Google Chrome"* ]]; then
    say_dont_skip_line "Flutter needs Chrome for web development — adding it automatically"
    APP_CHOICES="$APP_CHOICES Google Chrome"
fi

if [[ -n "$APP_CHOICES" ]]; then
    say "[10/16] Installing selected apps..."
fi

# ---- Dev Tools installs ----

if [[ "$APP_CHOICES" == *"Git"* ]]; then
    # git is already installed in base utilities but making sure
    sudo apt install -y git >> "$LOG" 2>&1 && say_dont_skip_line "Git installed successfully"
fi

if [[ "$APP_CHOICES" == *"Node.js"* ]]; then
    say_dont_skip_line "Installing Node.js via nvm"
    # install nvm as the real user, not root
    sudo -u "$REAL_USER" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash' >> "$LOG" 2>&1
    # source nvm and install latest LTS
    sudo -u "$REAL_USER" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm install --lts' >> "$LOG" 2>&1
    if [[ -d "$REAL_HOME/.nvm" ]]; then
        say_dont_skip_line "Node.js installed successfully via nvm"
    else
        say_dont_skip_line "Node.js FAILED to install"
        FAILED+=("node.js")
    fi
fi

if [[ "$APP_CHOICES" == *"Java JDK"* ]]; then
    if sudo apt install -y default-jdk >> "$LOG" 2>&1; then
        say_dont_skip_line "Java JDK installed successfully"
    else
        say_dont_skip_line "Java JDK FAILED to install"
        FAILED+=("java-jdk")
    fi
fi

if [[ "$APP_CHOICES" == *"VSCode"* ]]; then
    install_deb "VSCode" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" "vscode.deb"
fi

if [[ "$APP_CHOICES" == *"VS Codium"* ]]; then
    say_dont_skip_line "Installing VS Codium"
    wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/vscodium-archive-keyring.gpg > /dev/null 2>&1
    echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" | sudo tee /etc/apt/sources.list.d/vscodium.list > /dev/null
    if sudo apt update >> "$LOG" 2>&1 && sudo apt install -y codium >> "$LOG" 2>&1; then
        say_dont_skip_line "VS Codium installed successfully"
    else
        say_dont_skip_line "VS Codium FAILED to install"
        FAILED+=("vscodium")
    fi
fi

if [[ "$APP_CHOICES" == *"Cursor"* ]]; then
    CURSOR_VER=$(curl -s "https://api2.cursor.sh/updates/latest?platform=linux-x64-deb" | grep -oP '"version":"\K[^"]+')
    if wget -O "$TMPDIR/cursor.deb" "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/$CURSOR_VER" >> "$LOG" 2>&1 && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/cursor.deb" >> "$LOG" 2>&1; then
        say_dont_skip_line "Cursor installed successfully"
    else
        say_dont_skip_line "Cursor FAILED to install (download/install failed)"
        FAILED+=("cursor")
    fi
fi

if [[ "$APP_CHOICES" == *"Claude Code"* ]]; then
    say_dont_skip_line "Installing Claude Code"
    # needs node/npm from nvm
    if sudo -u "$REAL_USER" bash -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && npm install -g @anthropic-ai/claude-code' >> "$LOG" 2>&1; then
        say_dont_skip_line "Claude Code installed successfully"
        POST_NOTES+=("Claude Code: Run 'claude' in terminal and enter your API key to get started")
    else
        say_dont_skip_line "Claude Code FAILED to install"
        FAILED+=("claude-code")
    fi
fi

if [[ "$APP_CHOICES" == *"Flutter"* ]]; then
    say_dont_skip_line "Installing Flutter SDK"
    # install Linux toolchain deps needed for flutter desktop development
    say_dont_skip_line "Installing Flutter Linux toolchain dependencies..."
    sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev >> "$LOG" 2>&1 || true
    mkdir -p "$REAL_HOME/.local/share"
    if sudo -u "$REAL_USER" git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$REAL_HOME/.local/share/flutter" >> "$LOG" 2>&1; then
        say_dont_skip_line "Flutter SDK installed successfully"
        POST_NOTES+=("Flutter: Run 'flutter doctor' to verify your setup. Android SDK requires launching Android Studio first.")
    else
        say_dont_skip_line "Flutter SDK FAILED to install"
        FAILED+=("flutter")
    fi
fi

if [[ "$APP_CHOICES" == *"Android Studio"* ]]; then
    say_dont_skip_line "Installing Android Studio"
    # install 32-bit libs needed by Android SDK tools
    sudo apt install -y libc6:i386 libncurses6:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386 >> "$LOG" 2>&1
    # download Android Studio — URL may need updating if this version goes stale
    # check https://developer.android.com/studio#downloads for the latest linux tar.gz link
    AS_URL="https://edgedl.me.gvt1.com/android/studio/ide-zips/2025.3.2.6/android-studio-panda2-linux.tar.gz"
    say_dont_skip_line "Downloading Android Studio (~1GB, this may take a while)..."
    if wget --progress=dot:mega -O "$TMPDIR/android-studio.tar.gz" "$AS_URL" 2>&1 | tail -1 | tee -a "$LOG" \
    && file "$TMPDIR/android-studio.tar.gz" | grep -q "gzip"; then
        mkdir -p "$REAL_HOME/.local/share"
        say_dont_skip_line "Extracting Android Studio..."
        tar xzf "$TMPDIR/android-studio.tar.gz" -C "$REAL_HOME/.local/share/" >> "$LOG" 2>&1
        # find the actual extracted directory name (could be android-studio or android-studio-*)
        AS_DIR=$(find "$REAL_HOME/.local/share/" -maxdepth 1 -type d -name "android-studio*" | head -1)
        if [[ -z "$AS_DIR" ]]; then
            say_dont_skip_line "Android Studio FAILED — extraction produced no directory"
            FAILED+=("android-studio")
        fi
        if [[ -n "$AS_DIR" && "$AS_DIR" != "$REAL_HOME/.local/share/android-studio" ]]; then
            mv "$AS_DIR" "$REAL_HOME/.local/share/android-studio"
        fi
        if [[ -d "$REAL_HOME/.local/share/android-studio" ]]; then
            chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/android-studio"
        # create desktop entry so it shows up in the app launcher
        mkdir -p "$REAL_HOME/.local/share/applications"
        cat > "$REAL_HOME/.local/share/applications/android-studio.desktop" << DESKTOP_EOF
[Desktop Entry]
Name=Android Studio
Exec=$REAL_HOME/.local/share/android-studio/bin/studio.sh
Icon=$REAL_HOME/.local/share/android-studio/bin/studio.svg
Type=Application
Categories=Development;IDE;
DESKTOP_EOF
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/android-studio.desktop"
            say_dont_skip_line "Android Studio installed successfully"
            POST_NOTES+=("Android Studio: Launch it to complete the first-time setup wizard")
        fi
    else
        say_dont_skip_line "Android Studio FAILED to download (invalid file)"
        FAILED+=("android-studio")
    fi
fi

if [[ "$APP_CHOICES" == *"Docker"* ]]; then
    say_dont_skip_line "Installing Docker"
    sudo install -m 0755 -d /etc/apt/keyrings >> "$LOG" 2>&1
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc >> "$LOG" 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $DEBIAN_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    if sudo apt update >> "$LOG" 2>&1 && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >> "$LOG" 2>&1; then
        sudo adduser "$REAL_USER" docker >> "$LOG" 2>&1
        say_dont_skip_line "Docker installed successfully"
        POST_NOTES+=("Docker: Log out and back in for docker group permissions to take effect")
    else
        say_dont_skip_line "Docker FAILED to install"
        FAILED+=("docker")
    fi
fi

if [[ "$APP_CHOICES" == *"Lazygit"* ]]; then
    LAZYGIT_VER=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -oP '"tag_name":\s*"v\K[^"]+')
    if [[ -n "$LAZYGIT_VER" ]] \
    && curl -Lo "$TMPDIR/lazygit.tar.gz" "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VER}_Linux_x86_64.tar.gz" >> "$LOG" 2>&1 \
    && tar xf "$TMPDIR/lazygit.tar.gz" -C "$TMPDIR" lazygit && sudo install "$TMPDIR/lazygit" /usr/local/bin/lazygit; then
        say_dont_skip_line "Lazygit installed successfully"
    else
        say_dont_skip_line "Lazygit FAILED to install"
        FAILED+=("lazygit")
    fi
fi

if [[ "$APP_CHOICES" == *"DBeaver"* ]]; then
    install_deb "DBeaver" "https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb" "dbeaver.deb"
fi

if [[ "$APP_CHOICES" == *"FileZilla"* ]]; then
    if sudo apt install -y filezilla >> "$LOG" 2>&1; then
        say_dont_skip_line "FileZilla installed successfully"
    else
        say_dont_skip_line "FileZilla FAILED to install"
        FAILED+=("filezilla")
    fi
fi

if [[ "$APP_CHOICES" == *"Qt Dev"* ]]; then
    say_dont_skip_line "Installing Qt6 development packages..."
    if sudo apt install -y qt6-base-dev qt6-declarative-dev qt6-tools-dev qtcreator >> "$LOG" 2>&1; then
        say_dont_skip_line "Qt Dev installed successfully"
    else
        say_dont_skip_line "Qt Dev FAILED to install"
        FAILED+=("qt-dev")
    fi
fi

# ---- Media & Gaming installs ----

if [[ "$APP_CHOICES" == *"Steam"* ]]; then
    install_deb "Steam" "https://cdn.akamai.steamstatic.com/client/installer/steam.deb" "steam.deb"
fi

if [[ "$APP_CHOICES" == *"Lutris"* ]]; then
    LUTRIS_DEB_URL=$(curl -s "https://api.github.com/repos/lutris/lutris/releases/latest" | grep browser_download_url | grep '_all.deb' | grep -oP 'https://[^"]+')
    if [[ -n "$LUTRIS_DEB_URL" ]]; then
        install_deb "Lutris" "$LUTRIS_DEB_URL" "lutris.deb"
    else
        say_dont_skip_line "Lutris FAILED to install (could not find download URL)"
        FAILED+=("lutris")
    fi
fi

if [[ "$APP_CHOICES" == *"Heroic"* ]]; then
    HEROIC_DEB_URL=$(curl -s "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" | grep browser_download_url | grep linux-amd64.deb | grep -oP 'https://[^"]+')
    if [[ -n "$HEROIC_DEB_URL" ]]; then
        install_deb "Heroic" "$HEROIC_DEB_URL" "heroic.deb"
    else
        say_dont_skip_line "Heroic FAILED to install (could not find download URL)"
        FAILED+=("heroic")
    fi
fi

if [[ "$APP_CHOICES" == *"Jellyfin Client"* ]]; then
    JELLYFIN_DEB_URL=$(curl -s "https://api.github.com/repos/jellyfin/jellyfin-desktop/releases/latest" | grep browser_download_url | grep "$DEBIAN_CODENAME" | grep -oP 'https://[^"]+')  # jellyfin url needs different grep for each debian release so getting codename dynamically to future proof it
    if [[ -n "$JELLYFIN_DEB_URL" ]]; then
        install_deb "Jellyfin Client" "$JELLYFIN_DEB_URL" "jellyfin.deb"
    else
        say_dont_skip_line "Jellyfin Client FAILED to install (could not find download URL for $DEBIAN_CODENAME)"
        FAILED+=("jellyfin-desktop")
    fi
fi

if [[ "$APP_CHOICES" == *"Sunshine"* ]]; then
    say_dont_skip_line "Installing Sunshine"
    SUNSHINE_DEB_URL=$(curl -s "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" | grep browser_download_url | grep -iE "debian.*amd64\.deb" | grep -oP 'https://[^"]+' | head -1)
    if [[ -n "$SUNSHINE_DEB_URL" ]]; then
        if install_deb "Sunshine" "$SUNSHINE_DEB_URL" "sunshine.deb"; then
            sudo setcap cap_sys_admin+p $(which sunshine 2>/dev/null || echo "/usr/bin/sunshine") >> "$LOG" 2>&1 || true  # capture permissions
            # create user-level systemd service for auto-start (not system-level)
            mkdir -p "$REAL_HOME/.config/systemd/user"
            cat > "$REAL_HOME/.config/systemd/user/sunshine.service" << 'SUNSHINE_SVC'
[Unit]
Description=Sunshine self-hosted game stream host for Moonlight
After=network.target

[Service]
ExecStart=/usr/bin/sunshine
Restart=on-failure

[Install]
WantedBy=default.target
SUNSHINE_SVC
            chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/systemd/user"
            sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$(id -u $REAL_USER)" systemctl --user enable sunshine >> "$LOG" 2>&1 || true
            POST_NOTES+=("Sunshine: Open https://localhost:47990 in your browser to set up pairing")
        fi
    else
        say_dont_skip_line "Sunshine FAILED to install (could not find download URL)"
        FAILED+=("sunshine")
    fi
fi

if [[ "$APP_CHOICES" == *"Moonlight"* ]]; then
    say_dont_skip_line "Installing Moonlight..."
    mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications"
    MOONLIGHT_URL=$(curl -s "https://api.github.com/repos/moonlight-stream/moonlight-qt/releases/latest" | grep browser_download_url | grep 'x86_64.AppImage' | grep -oP 'https://[^"]+')
    if [[ -n "$MOONLIGHT_URL" ]] && wget -qO "$REAL_HOME/.local/bin/moonlight" "$MOONLIGHT_URL" >> "$LOG" 2>&1; then
        chmod +x "$REAL_HOME/.local/bin/moonlight"
        cat > "$REAL_HOME/.local/share/applications/moonlight.desktop" << MOON_EOF
[Desktop Entry]
Name=Moonlight
Exec=$REAL_HOME/.local/bin/moonlight
Type=Application
Categories=Game;
MOON_EOF
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/moonlight" "$REAL_HOME/.local/share/applications/moonlight.desktop"
        say_dont_skip_line "Moonlight installed successfully"
    else
        say_dont_skip_line "Moonlight FAILED to install"
        FAILED+=("moonlight")
    fi
fi

if [[ "$APP_CHOICES" == *"OBS Studio"* ]]; then
    if sudo apt install -y obs-studio >> "$LOG" 2>&1; then
        say_dont_skip_line "OBS Studio installed successfully"
    else
        say_dont_skip_line "OBS Studio FAILED to install"
        FAILED+=("obs-studio")
    fi
fi

if [[ "$APP_CHOICES" == *"Discord"* ]]; then
    install_deb "Discord" "https://discord.com/api/download?platform=linux&format=deb" "discord.deb"
fi

if [[ "$APP_CHOICES" == *"qBittorrent"* ]]; then
    if sudo apt install -y qbittorrent >> "$LOG" 2>&1; then
        say_dont_skip_line "qBittorrent installed successfully"
    else
        say_dont_skip_line "qBittorrent FAILED to install"
        FAILED+=("qbittorrent")
    fi
fi

if [[ "$APP_CHOICES" == *"Audacity"* ]]; then
    if sudo apt install -y audacity >> "$LOG" 2>&1; then
        say_dont_skip_line "Audacity installed successfully"
    else
        say_dont_skip_line "Audacity FAILED to install"
        FAILED+=("audacity")
    fi
fi

if [[ "$APP_CHOICES" == *"Kdenlive"* ]]; then
    if sudo apt install -y kdenlive >> "$LOG" 2>&1; then
        say_dont_skip_line "Kdenlive installed successfully"
    else
        say_dont_skip_line "Kdenlive FAILED to install"
        FAILED+=("kdenlive")
    fi
fi

if [[ "$APP_CHOICES" == *"HandBrake"* ]]; then
    if sudo apt install -y handbrake >> "$LOG" 2>&1; then
        say_dont_skip_line "HandBrake installed successfully"
    else
        say_dont_skip_line "HandBrake FAILED to install"
        FAILED+=("handbrake")
    fi
fi

# ---- Browsers & Productivity installs ----

if [[ "$APP_CHOICES" == *"Zen Browser"* ]]; then
    say_dont_skip_line "Installing Zen Browser..."
    mkdir -p "$REAL_HOME/.local/share/zen" "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications"
    if wget --progress=dot:mega -O "$TMPDIR/zen.tar.xz" "https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz" 2>&1 | tail -1 | tee -a "$LOG" \
    && tar xf "$TMPDIR/zen.tar.xz" -C "$REAL_HOME/.local/share/zen" --strip-components=1 >> "$LOG" 2>&1; then
        # create symlink and desktop entry
        ln -sf "$REAL_HOME/.local/share/zen/zen" "$REAL_HOME/.local/bin/zen-browser"
        cat > "$REAL_HOME/.local/share/applications/zen-browser.desktop" << ZEN_EOF
[Desktop Entry]
Name=Zen Browser
Exec=$REAL_HOME/.local/share/zen/zen %u
Icon=$REAL_HOME/.local/share/zen/browser/chrome/icons/default/default128.png
Type=Application
Categories=Network;WebBrowser;
ZEN_EOF
        chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/zen" "$REAL_HOME/.local/share/applications/zen-browser.desktop"
        say_dont_skip_line "Zen Browser installed successfully"
    else
        say_dont_skip_line "Zen Browser FAILED to install"
        FAILED+=("zen-browser")
    fi
fi

if [[ "$APP_CHOICES" == *"Brave"* ]]; then
    say_dont_skip_line "Installing Brave Browser"
    sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg >> "$LOG" 2>&1
    echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
    if sudo apt update >> "$LOG" 2>&1 && sudo apt install -y brave-browser >> "$LOG" 2>&1; then
        say_dont_skip_line "Brave Browser installed successfully"
    else
        say_dont_skip_line "Brave Browser FAILED to install"
        FAILED+=("brave")
    fi
fi

if [[ "$APP_CHOICES" == *"Google Chrome"* ]]; then
    install_deb "Google Chrome" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" "chrome.deb"
fi

if [[ "$APP_CHOICES" == *"Obsidian"* ]]; then
    OBSIDIAN_DEB_URL=$(curl -s "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" | grep browser_download_url | grep 'amd64.deb' | grep -oP 'https://[^"]+')
    if [[ -n "$OBSIDIAN_DEB_URL" ]]; then
        install_deb "Obsidian" "$OBSIDIAN_DEB_URL" "obsidian.deb"
    else
        say_dont_skip_line "Obsidian FAILED to install (could not find download URL)"
        FAILED+=("obsidian")
    fi
fi

if [[ "$APP_CHOICES" == *"LibreOffice Writer"* ]]; then
    sudo apt install -y libreoffice-writer >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Writer installed" || FAILED+=("libreoffice-writer")
fi
if [[ "$APP_CHOICES" == *"LibreOffice Calc"* ]]; then
    sudo apt install -y libreoffice-calc >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Calc installed" || FAILED+=("libreoffice-calc")
fi
if [[ "$APP_CHOICES" == *"LibreOffice Impress"* ]]; then
    sudo apt install -y libreoffice-impress >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Impress installed" || FAILED+=("libreoffice-impress")
fi
if [[ "$APP_CHOICES" == *"LibreOffice Draw"* ]]; then
    sudo apt install -y libreoffice-draw >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Draw installed" || FAILED+=("libreoffice-draw")
fi
if [[ "$APP_CHOICES" == *"LibreOffice Math"* ]]; then
    sudo apt install -y libreoffice-math >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Math installed" || FAILED+=("libreoffice-math")
fi
if [[ "$APP_CHOICES" == *"LibreOffice Base"* ]]; then
    sudo apt install -y libreoffice-base >> "$LOG" 2>&1 && say_dont_skip_line "LibreOffice Base installed" || FAILED+=("libreoffice-base")
fi

if [[ "$APP_CHOICES" == *"Vicinae"* ]]; then
    say_dont_skip_line "Installing Vicinae..."
    mkdir -p "$REAL_HOME/.local/bin" "$REAL_HOME/.local/share/applications"
    VICINAE_URL=$(curl -s "https://api.github.com/repos/vicinaehq/vicinae/releases/latest" | grep browser_download_url | grep 'x86_64.AppImage' | grep -oP 'https://[^"]+')
    if [[ -n "$VICINAE_URL" ]] && wget -qO "$REAL_HOME/.local/bin/vicinae" "$VICINAE_URL" >> "$LOG" 2>&1; then
        chmod +x "$REAL_HOME/.local/bin/vicinae"
        cat > "$REAL_HOME/.local/share/applications/vicinae.desktop" << VICINAE_EOF
[Desktop Entry]
Name=Vicinae
Exec=$REAL_HOME/.local/bin/vicinae
Type=Application
Categories=Utility;
VICINAE_EOF
        chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/bin/vicinae" "$REAL_HOME/.local/share/applications/vicinae.desktop"
        say_dont_skip_line "Vicinae installed successfully"
    else
        say_dont_skip_line "Vicinae FAILED to install"
        FAILED+=("vicinae")
    fi
fi

if [[ "$APP_CHOICES" == *"OnlyOffice"* ]]; then
    install_deb "OnlyOffice" "https://github.com/ONLYOFFICE/DesktopEditors/releases/latest/download/onlyoffice-desktopeditors_amd64.deb" "onlyoffice.deb"
fi

if [[ "$APP_CHOICES" == *"NoMachine"* ]]; then
    # URL has version number but NoMachine has a built-in updater
    install_deb "NoMachine" "https://web9001.nomachine.com/download/9.3/Linux/nomachine_9.3.7_1_amd64.deb" "nomachine.deb"
fi

if [[ "$APP_CHOICES" == *"LocalSend"* ]]; then
    LOCALSEND_DEB_URL=$(curl -s "https://api.github.com/repos/localsend/localsend/releases/latest" | grep browser_download_url | grep linux-x86-64.deb | grep -oP 'https://[^"]+')
    if [[ -n "$LOCALSEND_DEB_URL" ]]; then
        install_deb "LocalSend" "$LOCALSEND_DEB_URL" "localsend.deb"
    else
        say_dont_skip_line "LocalSend FAILED to install (could not find download URL)"
        FAILED+=("localsend")
    fi
fi

# ---- System & Utilities installs ----

if [[ "$APP_CHOICES" == *"Tailscale"* ]]; then
    if curl -fsSL https://tailscale.com/install.sh | sh >> "$LOG" 2>&1; then
        sudo systemctl enable tailscaled >> "$LOG" 2>&1
        say_dont_skip_line "Tailscale installed successfully"
        POST_NOTES+=("Tailscale: Run 'tailscale up' to authenticate and connect to your network")
    else
        say_dont_skip_line "Tailscale FAILED to install"
        FAILED+=("tailscale")
    fi
fi

if [[ "$APP_CHOICES" == *"ProtonVPN"* ]]; then
    say_dont_skip_line "Installing ProtonVPN..."
    if wget -qO "$TMPDIR/protonvpn-release.deb" "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb" \
    && sudo dpkg -i "$TMPDIR/protonvpn-release.deb" >> "$LOG" 2>&1 \
    && sudo apt update >> "$LOG" 2>&1 \
    && sudo apt install -y proton-vpn-gnome-desktop >> "$LOG" 2>&1; then
        say_dont_skip_line "ProtonVPN installed successfully"
        POST_NOTES+=("ProtonVPN: Launch and sign in to your Proton account")
    else
        say_dont_skip_line "ProtonVPN FAILED to install"
        FAILED+=("protonvpn")
    fi
fi


if [[ "$APP_CHOICES" == *"Windscribe"* ]]; then
    say_dont_skip_line "Installing Windscribe..."
    if wget -qO "$TMPDIR/windscribe.deb" "https://windscribe.com/install/desktop/linux_deb_x64" \
    && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$TMPDIR/windscribe.deb" >> "$LOG" 2>&1; then
        say_dont_skip_line "Windscribe installed successfully"
        POST_NOTES+=("Windscribe: Launch and sign in to your account")
    else
        say_dont_skip_line "Windscribe FAILED to install"
        FAILED+=("windscribe")
    fi
fi

if [[ "$APP_CHOICES" == *"Mullvad"* ]]; then
    say_dont_skip_line "Installing Mullvad VPN..."
    sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc >> "$LOG" 2>&1
    echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" | sudo tee /etc/apt/sources.list.d/mullvad.list > /dev/null
    if sudo apt update >> "$LOG" 2>&1 && sudo apt install -y mullvad-vpn >> "$LOG" 2>&1; then
        say_dont_skip_line "Mullvad VPN installed successfully"
        POST_NOTES+=("Mullvad: Launch and enter your account number")
    else
        say_dont_skip_line "Mullvad VPN FAILED to install"
        FAILED+=("mullvad")
    fi
fi

if [[ "$APP_CHOICES" == *"Virt-manager"* ]]; then
    say_dont_skip_line "Installing Virt-manager + QEMU/KVM"
    if sudo apt install -y virt-manager qemu-system libvirt-daemon-system >> "$LOG" 2>&1; then
        sudo adduser "$REAL_USER" libvirt >> "$LOG" 2>&1
        sudo adduser "$REAL_USER" kvm >> "$LOG" 2>&1
        say_dont_skip_line "Virt-manager installed successfully"
        POST_NOTES+=("Virt-manager: Log out and back in for libvirt/kvm group permissions to take effect")
    else
        say_dont_skip_line "Virt-manager FAILED to install"
        FAILED+=("virt-manager")
    fi
fi

if [[ "$APP_CHOICES" == *"htop"* ]]; then
    sudo apt install -y htop >> "$LOG" 2>&1 && say_dont_skip_line "htop installed successfully"
fi

if [[ "$APP_CHOICES" == *"btop"* ]]; then
    sudo apt install -y btop >> "$LOG" 2>&1 && say_dont_skip_line "btop installed successfully"
fi

if [[ "$APP_CHOICES" == *"s3fs-fuse"* ]]; then
    if sudo apt install -y s3fs >> "$LOG" 2>&1; then
        say_dont_skip_line "s3fs-fuse installed successfully"
        # offer to set up S3 bucket mounts
        while show_yesno "S3 Bucket" "Do you want to mount an S3 bucket?"; do
            S3_BUCKET=$(show_input "S3 Bucket" "Enter bucket name:")
            if [[ -z "$S3_BUCKET" ]]; then break; fi

            S3_ACCESS_KEY=$(show_input "S3 Bucket" "Enter Access Key ID for $S3_BUCKET:")
            S3_SECRET_KEY=$(show_password "S3 Bucket" "Enter Secret Access Key for $S3_BUCKET:")
            S3_ENDPOINT=$(show_input "S3 Bucket" "Enter endpoint URL (REQUIRED for Backblaze/MinIO/etc, e.g., https://s3.us-west-004.backblazeb2.com). Leave empty ONLY for AWS us-east-1:")

            MOUNT_POINT="$REAL_HOME/S3/$S3_BUCKET"
            mkdir -p "$MOUNT_POINT"
            chown "$REAL_USER:$REAL_USER" "$MOUNT_POINT"

            # store credentials
            S3_CRED_FILE="$REAL_HOME/.passwd-s3fs-$S3_BUCKET"
            echo "$S3_ACCESS_KEY:$S3_SECRET_KEY" > "$S3_CRED_FILE"
            chown "$REAL_USER:$REAL_USER" "$S3_CRED_FILE"
            chmod 600 "$S3_CRED_FILE"

            # build fstab entry
            S3_OPTS="passwd_file=$S3_CRED_FILE,allow_other,use_path_request_style,uid=$(id -u $REAL_USER),gid=$(id -g $REAL_USER),_netdev,nofail"
            if [[ -n "$S3_ENDPOINT" ]]; then
                S3_OPTS="$S3_OPTS,url=$S3_ENDPOINT"
            fi
            echo "s3fs#$S3_BUCKET $MOUNT_POINT fuse $S3_OPTS 0 0" | sudo tee -a /etc/fstab > /dev/null

            # enable allow_other in fuse config
            sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null || true

            # mount it now
            sudo mount "$MOUNT_POINT" >> "$LOG" 2>&1 || true
            say_dont_skip_line "S3 bucket $S3_BUCKET mounted at $MOUNT_POINT"
            POST_NOTES+=("S3 bucket: $S3_BUCKET mounted at ~/S3/$S3_BUCKET")
        done
    else
        say_dont_skip_line "s3fs-fuse FAILED to install"
        FAILED+=("s3fs-fuse")
    fi
fi

if [[ "$APP_CHOICES" == *"lm-sensors"* ]]; then
    if sudo apt install -y lm-sensors >> "$LOG" 2>&1; then
        sudo sensors-detect --auto >> "$LOG" 2>&1 || true  # auto-detect sensor modules
        say_dont_skip_line "lm-sensors installed successfully"
    else
        say_dont_skip_line "lm-sensors FAILED to install"
        FAILED+=("lm-sensors")
    fi
fi

if [[ "$APP_CHOICES" == *"psensor"* ]]; then
    if sudo apt install -y psensor >> "$LOG" 2>&1; then
        say_dont_skip_line "psensor installed successfully"
    else
        say_dont_skip_line "psensor FAILED to install"
        FAILED+=("psensor")
    fi
fi

if [[ "$APP_CHOICES" == *"smartmontools"* ]]; then
    if sudo apt install -y smartmontools >> "$LOG" 2>&1; then
        say_dont_skip_line "smartmontools installed successfully"
    else
        say_dont_skip_line "smartmontools FAILED to install"
        FAILED+=("smartmontools")
    fi
fi

if [[ "$APP_CHOICES" == *"Whisper"* ]]; then
    say_dont_skip_line "Installing faster-whisper in a virtual environment..."
    WHISPER_VENV="$REAL_HOME/.local/share/faster-whisper-venv"
    if sudo -u "$REAL_USER" python3 -m venv "$WHISPER_VENV" >> "$LOG" 2>&1 \
    && sudo -u "$REAL_USER" "$WHISPER_VENV/bin/pip" install faster-whisper >> "$LOG" 2>&1; then
        say_dont_skip_line "Pre-caching large-v3-turbo model (~1.5GB, this may take a while)..."
        sudo -u "$REAL_USER" "$WHISPER_VENV/bin/python" -c "from faster_whisper import WhisperModel; WhisperModel('large-v3-turbo', device='cpu')" >> "$LOG" 2>&1
        say_dont_skip_line "faster-whisper + large-v3-turbo model installed successfully"
    else
        say_dont_skip_line "faster-whisper FAILED to install"
        FAILED+=("faster-whisper")
    fi
fi

# ==================================================================================
# Network share mount setup (optional)
# ==================================================================================
while show_yesno "Network Share" "Do you want to mount a network share (SMB/CIFS)?"; do
    SHARE_PATH=$(show_input "Network Share" "Enter share path (e.g., //192.168.1.100/MyShare):")
    if [[ -z "$SHARE_PATH" ]]; then break; fi

    SHARE_USER=$(show_input "Network Share" "Enter username for $SHARE_PATH:")
    SHARE_PASS=$(show_password "Network Share" "Enter password for $SHARE_PATH:")
    SHARE_NAME=$(echo "$SHARE_PATH" | sed 's|^//||;s|/|-|g')
    MOUNT_POINT="$REAL_HOME/Network/$SHARE_NAME"
    mkdir -p "$MOUNT_POINT"
    chown "$REAL_USER:$REAL_USER" "$MOUNT_POINT"

    CRED_FILE="$REAL_HOME/.smbcredentials-$SHARE_NAME"
    cat > "$CRED_FILE" << CRED_EOF
username=$SHARE_USER
password=$SHARE_PASS
CRED_EOF
    chown "$REAL_USER:$REAL_USER" "$CRED_FILE"
    chmod 600 "$CRED_FILE"

    REAL_UID=$(id -u "$REAL_USER")
    REAL_GID=$(id -g "$REAL_USER")
    echo "$SHARE_PATH $MOUNT_POINT cifs credentials=$CRED_FILE,uid=$REAL_UID,gid=$REAL_GID,iocharset=utf8,nofail,_netdev 0 0" | sudo tee -a /etc/fstab > /dev/null

    sudo mount "$MOUNT_POINT" >> "$LOG" 2>&1 || true
    say_dont_skip_line "Network share $SHARE_PATH mounted at $MOUNT_POINT"
    POST_NOTES+=("Network share: $SHARE_PATH mounted at ~/Network/$SHARE_NAME")
done

# ==================================================================================
# 12. Settings (DE-specific)
# ==================================================================================
say "[11/16] Applying system settings"

if [[ "$DE" == "kde" ]]; then
    # all KDE settings must be written to the real user's config, not root's
    # we write directly to the config files using full paths instead of relying on kwriteconfig6's HOME detection
    KDE_CFG="$REAL_HOME/.config"

    say_dont_skip_line "Setting Breeze Dark theme..."
    sudo -u "$REAL_USER" plasma-apply-lookandfeel -a org.kde.breezedark.desktop >> "$LOG" 2>&1 || \
        sudo -u "$REAL_USER" lookandfeeltool -a org.kde.breezedark.desktop >> "$LOG" 2>&1 || true

    # write KDE settings directly to config files to avoid kwriteconfig6 hanging issues
    say_dont_skip_line "Enabling night light (5300K)..."
    sudo -u "$REAL_USER" bash -c "cat >> '$KDE_CFG/kwinrc'" << 'KWIN_NIGHT'

[NightColor]
Active=true
Mode=Constant
NightTemperature=5300
KWIN_NIGHT

    say_dont_skip_line "Adding Always-on-Top button to title bar..."
    # F = Keep Above (always on top), M = Menu, S = On All Desktops
    sed -i '/^\[org\.kde\.kdecoration2\]/,/^$/d' "$KDE_CFG/kwinrc" 2>/dev/null || true
    sudo -u "$REAL_USER" bash -c "cat >> '$KDE_CFG/kwinrc'" << 'KWIN_BUTTONS'

[org.kde.kdecoration2]
ButtonsOnLeft=MFS
ButtonsOnRight=IAX
KWIN_BUTTONS

    say_dont_skip_line "Disabling logout confirmation..."
    sudo -u "$REAL_USER" bash -c "cat >> '$KDE_CFG/ksmserverrc'" << 'KSMSRV'

[General]
confirmLogout=false
KSMSRV

    if [[ "$DEVICE_TYPE" == "laptop" ]]; then
        say_dont_skip_line "Enabling natural scrolling (laptop)..."
        # KDE Wayland stores touchpad settings per-device using vendor/product IDs
        # auto-detect the touchpad and set natural scroll for it
        sudo apt install -y libinput-tools >> "$LOG" 2>&1 || true
        TOUCHPAD_INFO=$(sudo libinput list-devices 2>/dev/null | grep -A5 -i touchpad | grep "Kernel:" | head -1 | awk '{print $2}')
        if [[ -n "$TOUCHPAD_INFO" ]]; then
            # get vendor and product IDs from the device
            TOUCHPAD_VENDOR=$(cat "$(dirname $(realpath /sys/class/input/$(basename $TOUCHPAD_INFO)/device))/id/vendor" 2>/dev/null)
            TOUCHPAD_PRODUCT=$(cat "$(dirname $(realpath /sys/class/input/$(basename $TOUCHPAD_INFO)/device))/id/product" 2>/dev/null)
            TOUCHPAD_NAME=$(sudo libinput list-devices 2>/dev/null | grep -B1 "$TOUCHPAD_INFO" | head -1 | sed 's/.*Device: *//')
            if [[ -n "$TOUCHPAD_VENDOR" && -n "$TOUCHPAD_PRODUCT" && -n "$TOUCHPAD_NAME" ]]; then
                # convert hex to decimal for KDE config
                VENDOR_DEC=$((16#$TOUCHPAD_VENDOR))
                PRODUCT_DEC=$((16#$TOUCHPAD_PRODUCT))
                sudo -u "$REAL_USER" kwriteconfig6 --file kcminputrc \
                    --group "Libinput" --group "$VENDOR_DEC" --group "$PRODUCT_DEC" --group "$TOUCHPAD_NAME" \
                    --key NaturalScroll true
                say_dont_skip_line "Natural scrolling enabled for $TOUCHPAD_NAME (takes effect after reboot)"
            fi
        fi
        # also set the generic Touchpad group as fallback
        sudo -u "$REAL_USER" kwriteconfig6 --file kcminputrc --group Touchpad --key NaturalScroll true 2>/dev/null || true
    fi

    # Display scaling — apply the choice made at the start of the script
    if [[ -n "$SCALE_CHOICE" ]]; then
        say_dont_skip_line "Setting display scaling to ${SCALE_CHOICE}x..."
        # use kscreen-doctor to set per-output scaling (works on Wayland + persists via kscreen)
        # strip ANSI color codes from kscreen-doctor output before parsing
        for output_id in $(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep "Output:" | awk '{print $2}'); do
            kscreen-doctor "output.$output_id.scale.$SCALE_CHOICE" >> "$LOG" 2>&1 || true
        done
        say_dont_skip_line "Display scaling set to ${SCALE_CHOICE}x"
    fi

    # Taskbar on all monitors — uses plasmashell JS evaluation
    # This adds a default panel to any monitor that doesnt already have one
    REAL_UID=$(id -u "$REAL_USER")
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
        var allScreens = desktops();
        for (var i = 0; i < allScreens.length; i++) {
            var screen = allScreens[i].screen;
            var found = false;
            var panels = panelIds;
            for (var j = 0; j < panels.length; j++) {
                var p = panelById(panels[j]);
                if (p.screen === screen) { found = true; break; }
            }
            if (!found) {
                var newPanel = new Panel("org.kde.panel");
                newPanel.screen = screen;
                newPanel.location = "bottom";
                newPanel.height = gridUnit * 2;
                newPanel.addWidget("org.kde.plasma.kickoff");
                newPanel.addWidget("org.kde.plasma.icontasks");
                newPanel.addWidget("org.kde.plasma.systemtray");
                newPanel.addWidget("org.kde.plasma.digitalclock");
            }
        }
    ' >> "$LOG" 2>&1 || say_dont_skip_line "Note: panel-on-all-monitors may need a logout to take effect"

    # Add Meta+Shift+P shortcut to restart plasmashell
    say_dont_skip_line "Adding restart plasmashell shortcut (Meta+Shift+P)..."
    # create desktop file with the command shortcut flag KDE needs
    mkdir -p "$REAL_HOME/.local/share/applications" "$REAL_HOME/.local/bin"
    cat > "$REAL_HOME/.local/share/applications/restart-plasmashell.desktop" << 'DESKTOP_EOF'
[Desktop Entry]
Exec=killall plasmashell && kstart plasmashell
Name=Restart Plasmashell
NoDisplay=true
StartupNotify=false
Type=Application
X-KDE-GlobalAccel-CommandShortcut=true
DESKTOP_EOF
    chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.local/share/applications/restart-plasmashell.desktop"

    # register the shortcut in kglobalshortcutsrc
    sudo -u "$REAL_USER" kwriteconfig6 --file kglobalshortcutsrc \
        --group "services" --group "restart-plasmashell.desktop" \
        --key "_launch" "Meta+Shift+P"
    POST_NOTES+=("Shortcut: Meta+Shift+P restarts plasmashell (useful if desktop glitches)")

    # Populate taskbar — defaults + user picks from installed apps
    say_dont_skip_line "Configuring taskbar apps..."
    TASKBAR_LAUNCHERS="applications:systemsettings.desktop,preferred://filemanager,applications:firefox-esr.desktop,applications:org.kde.konsole.desktop"

    # use .desktop filenames as tags so we get them back directly from the checklist
    PIN_ARGS=()
    [[ "$APP_CHOICES" == *"VSCode"* ]]        && PIN_ARGS+=("code.desktop" "VSCode" off)
    [[ "$APP_CHOICES" == *"VS Codium"* ]]     && PIN_ARGS+=("codium.desktop" "VS Codium" off)
    [[ "$APP_CHOICES" == *"Cursor"* ]]        && PIN_ARGS+=("cursor.desktop" "Cursor" off)
    [[ "$APP_CHOICES" == *"Discord"* ]]       && PIN_ARGS+=("discord.desktop" "Discord" off)
    [[ "$APP_CHOICES" == *"Steam"* ]]         && PIN_ARGS+=("steam.desktop" "Steam" off)
    [[ "$APP_CHOICES" == *"Lutris"* ]]        && PIN_ARGS+=("net.lutris.Lutris.desktop" "Lutris" off)
    [[ "$APP_CHOICES" == *"Heroic"* ]]        && PIN_ARGS+=("com.heroicgameslauncher.hgl.desktop" "Heroic" off)
    [[ "$APP_CHOICES" == *"Jellyfin"* ]]      && PIN_ARGS+=("com.github.iwalton3.jellyfin-media-player.desktop" "Jellyfin" off)
    [[ "$APP_CHOICES" == *"OBS Studio"* ]]    && PIN_ARGS+=("com.obsproject.Studio.desktop" "OBS Studio" off)
    [[ "$APP_CHOICES" == *"Brave"* ]]         && PIN_ARGS+=("brave-browser.desktop" "Brave" off)
    [[ "$APP_CHOICES" == *"Google Chrome"* ]] && PIN_ARGS+=("google-chrome.desktop" "Chrome" off)
    [[ "$APP_CHOICES" == *"Zen Browser"* ]]   && PIN_ARGS+=("zen-browser.desktop" "Zen Browser" off)
    [[ "$APP_CHOICES" == *"Obsidian"* ]]      && PIN_ARGS+=("obsidian.desktop" "Obsidian" off)
    [[ "$APP_CHOICES" == *"LocalSend"* ]]     && PIN_ARGS+=("localsend_app.desktop" "LocalSend" off)
    [[ "$APP_CHOICES" == *"FileZilla"* ]]     && PIN_ARGS+=("filezilla.desktop" "FileZilla" off)
    [[ "$APP_CHOICES" == *"Kdenlive"* ]]      && PIN_ARGS+=("org.kde.kdenlive.desktop" "Kdenlive" off)
    [[ "$APP_CHOICES" == *"qBittorrent"* ]]   && PIN_ARGS+=("org.qbittorrent.qBittorrent.desktop" "qBittorrent" off)
    [[ "$APP_CHOICES" == *"NoMachine"* ]]     && PIN_ARGS+=("nomachine.desktop" "NoMachine" off)

    if [[ ${#PIN_ARGS[@]} -gt 0 ]]; then
        PIN_CHOICES=$(show_checklist "Taskbar Apps" "Settings, Files, Firefox, Konsole are always pinned. Select additional apps:" "${PIN_ARGS[@]}") || true
        if [[ -n "$PIN_CHOICES" ]]; then
            # PIN_CHOICES contains .desktop filenames since we used them as tags
            for desktop_file in $(echo "$PIN_CHOICES" | tr -d '"'); do
                TASKBAR_LAUNCHERS="$TASKBAR_LAUNCHERS,applications:$desktop_file"
            done
        fi
    fi

    PANEL_CFG="$KDE_CFG/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "$PANEL_CFG" ]]; then
        sed -i "s|^launchers=.*|launchers=$TASKBAR_LAUNCHERS|g" "$PANEL_CFG"
        chown "$REAL_USER:$REAL_USER" "$PANEL_CFG"
    fi

    # Power/sleep timers — write directly to config files since kwriteconfig6 nested groups are unreliable
    say_dont_skip_line "Setting power/sleep timers ($DEVICE_TYPE profile)..."
    if [[ "$DEVICE_TYPE" == "desktop" ]]; then
        sudo -u "$REAL_USER" tee "$KDE_CFG/powerdevilrc" > /dev/null << 'POWER_EOF'
[AC][Display]
DimDisplayIdleTimeoutSec=1800
TurnOffDisplayIdleTimeoutSec=3600

[AC][SuspendAndShutdown]
AutoSuspendIdleTimeoutSec=7200
PowerButtonAction=1
POWER_EOF
        sudo -u "$REAL_USER" kwriteconfig6 --file "$KDE_CFG/kscreenlockerrc" --group Daemon --key Timeout 30
    else
        sudo -u "$REAL_USER" tee "$KDE_CFG/powerdevilrc" > /dev/null << 'POWER_EOF'
[AC][Display]
DimDisplayIdleTimeoutSec=600
TurnOffDisplayIdleTimeoutSec=900

[AC][SuspendAndShutdown]
AutoSuspendIdleTimeoutSec=3600
PowerButtonAction=1

[Battery][Display]
DimDisplayIdleTimeoutSec=300
TurnOffDisplayIdleTimeoutSec=600

[Battery][SuspendAndShutdown]
AutoSuspendIdleTimeoutSec=1800
POWER_EOF
        sudo -u "$REAL_USER" kwriteconfig6 --file "$KDE_CFG/kscreenlockerrc" --group Daemon --key Timeout 10
    fi

    say_dont_skip_line "Applying KDE config changes..."
    REAL_UID=$(id -u "$REAL_USER")
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
        qdbus6 org.kde.KWin /KWin reconfigure >> "$LOG" 2>&1 || true
    say_dont_skip_line "done."

elif [[ "$DE" == "gnome" || "$DE" == "cinnamon" ]]; then
    # GNOME and Cinnamon both use gsettings for night light
    sudo -u "$REAL_USER" gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
    sudo -u "$REAL_USER" gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 5300  # Nightlight configuration
    if [[ "$DE" == "gnome" ]]; then
        sudo -u "$REAL_USER" gsettings set org.gnome.SessionManager logout-prompt false  # disable confirmation for logout
    fi

elif [[ "$DE" == "xfce" ]]; then
    say_dont_skip_line "Xfce doesnt have a built-in night light, install redshift if you want one"

elif [[ "$DE" == "mate" ]]; then
    say_dont_skip_line "MATE doesnt have a built-in night light, install redshift if you want one"

elif [[ "$DE" == "lxqt" || "$DE" == "lxde" ]]; then
    say_dont_skip_line "LXQt/LXDE doesnt have a built-in night light, install redshift if you want one"
fi



# ==================================================================================
# 13. Shell PATH configuration — only adds entries for tools that were actually installed
# ==================================================================================
say "[12/16] Configuring shell PATH entries"
mkdir -p "$REAL_HOME/.config/fish"
touch "$REAL_HOME/.config/fish/config.fish"

# ~/.local/bin is always useful (pipx, user scripts, etc)
if ! grep -q 'fish_add_path.*\.local/bin' "$REAL_HOME/.config/fish/config.fish" 2>/dev/null; then
    echo 'fish_add_path ~/.local/bin' >> "$REAL_HOME/.config/fish/config.fish"
fi
if ! grep -q '\.local/bin' "$REAL_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$REAL_HOME/.bashrc"
fi

# Node.js / nvm — nvm auto-configures .bashrc, but fish needs manual PATH for the node binary
if [[ "$APP_CHOICES" == *"Node.js"* ]] && [[ -d "$REAL_HOME/.nvm/versions/node" ]]; then
    NODE_VER=$(ls "$REAL_HOME/.nvm/versions/node/" 2>/dev/null | sort -V | tail -1)
    if [[ -n "$NODE_VER" ]]; then
        echo "fish_add_path $REAL_HOME/.nvm/versions/node/$NODE_VER/bin" >> "$REAL_HOME/.config/fish/config.fish"
    fi
fi

# Flutter SDK
if [[ "$APP_CHOICES" == *"Flutter"* ]] && [[ -d "$REAL_HOME/.local/share/flutter" ]]; then
    echo 'fish_add_path ~/.local/share/flutter/bin' >> "$REAL_HOME/.config/fish/config.fish"
    echo 'export PATH="$HOME/.local/share/flutter/bin:$PATH"' >> "$REAL_HOME/.bashrc"
fi

# Android Studio / Android SDK
if [[ "$APP_CHOICES" == *"Android Studio"* ]] && [[ -d "$REAL_HOME/.local/share/android-studio" ]]; then
    echo 'fish_add_path ~/.local/share/android-studio/bin' >> "$REAL_HOME/.config/fish/config.fish"
    echo 'set -gx ANDROID_HOME ~/Android/Sdk' >> "$REAL_HOME/.config/fish/config.fish"
    echo 'export PATH="$HOME/.local/share/android-studio/bin:$PATH"' >> "$REAL_HOME/.bashrc"
    echo 'export ANDROID_HOME="$HOME/Android/Sdk"' >> "$REAL_HOME/.bashrc"
fi

chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/fish"

# ==================================================================================
# 14. Default media player — MPV takes priority since its always installed
# ==================================================================================
say "[13/16] Setting default media player to mpv"
MEDIA_TYPES="video/mp4 video/x-matroska video/webm video/mpeg video/x-msvideo video/quicktime audio/mpeg audio/flac audio/ogg audio/x-wav audio/mp4"
for mime in $MEDIA_TYPES; do
    sudo -u "$REAL_USER" xdg-mime default mpv.desktop "$mime" >> "$LOG" 2>&1
done

# ==================================================================================
# 15. Post-install notes — show the user what they need to do after reboot
# ==================================================================================
say "[14/16] Post-install notes"
NOTES_TEXT="Post-Install Notes\n==================\n"
if [[ ${#POST_NOTES[@]} -gt 0 ]]; then
    NOTES_TEXT="${NOTES_TEXT}\nThese apps need a manual step after reboot:\n"
    for note in "${POST_NOTES[@]}"; do
        say_dont_skip_line "  - $note"
        NOTES_TEXT="$NOTES_TEXT\n- $note"
    done
fi
NOTES_TEXT="$NOTES_TEXT\n\nThe system will restart to apply all changes (dark theme, scaling, etc)."

# save to desktop so the user can reference later
echo -e "$NOTES_TEXT" > "$REAL_HOME/Desktop/post-install-notes.txt"
chown "$REAL_USER:$REAL_USER" "$REAL_HOME/Desktop/post-install-notes.txt"
say_dont_skip_line "Notes saved to ~/Desktop/post-install-notes.txt"

show_msgbox "Post-Install Notes" "$(echo -e "$NOTES_TEXT")" || true

# ==================================================================================
# 16. Cleanup
# ==================================================================================
say "[15/16] Cleaning up"
rm -rf "$TMPDIR" # remove the temporary directory

# remove the autostart entry so this script doesnt run again on next login
say_dont_skip_line "Removing autostart entry..."
sudo rm -f /etc/xdg/autostart/debian-setup.desktop 2>/dev/null

if [[ -f "$0" && "$0" == *.sh ]]; then
    rm -- "$0" && say "Script file deleted: $0" || say "Failed to delete script file: $0" # delete the script file if ran as a file, but not if pasted into terminal (where $0 is /bin/bash)
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    say "[16/16] These failed to install: ${FAILED[*]}"
    say_dont_skip_line "NOT rebooting. Check log: $LOG"
else
    say "[16/16] Everything installed successfully. Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
fi