#!/bin/bash

# Function to display the main menu
show_menu() {
    clear
    echo "======================================"
    echo "         Arch Linux Setup Menu        "
    echo "======================================"
    echo "[1] Install GPU Drivers"
    echo "[2] Install Software (through yay)"
    echo "[3] Set Wayland as Default"
    echo "[4] Install OrcaSlicer"
    echo "[5] Create Games Directory"
    echo "[6] Configure Automatic Mounts"
    echo "[7] Setup GameSink Virtual Audio"
    echo "[8] Run Full Setup (All Options)"
    echo "[9] Create GameSink standalone"
    echo "[a] Create auto connection for Audio Game Sink"
    echo "[X] Exit"
    echo
    echo -n "Please select an option (1-8 or X): "
}

# Function to install GPU drivers
install_gpu_drivers() {
    # Automatische Erkennung der Hardware
    echo "Erkenne Hardware..."
    GPU_VENDOR=$(lspci | grep -E "VGA|3D" | grep -oE "NVIDIA|AMD|Intel")

    # Nutzer nach spezifischen Treibern fragen
    if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
        echo "NVIDIA-Grafikkarte erkannt. Möchtest du den offiziellen Treiber oder den Open-Source Nouveau-Treiber installieren? (offiziell/open/nicht)"
        read -r NVIDIA_CHOICE
        if [[ "$NVIDIA_CHOICE" == "offiziell" ]]; then
            pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
        elif [[ "$NVIDIA_CHOICE" == "open" ]]; then
            pacman -S --noconfirm mesa lib32-mesa xf86-video-nouveau
        fi
    elif [[ "$GPU_VENDOR" == "AMD" ]]; then
        echo "AMD-Grafikkarte erkannt. Möchtest du die AMD-Treiber installieren? (y/n)"
        read -r AMD_CHOICE
        if [[ "$AMD_CHOICE" == "y" ]]; then
            pacman -S --noconfirm mesa lib32-mesa xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon
        fi
    elif [[ "$GPU_VENDOR" == "Intel" ]]; then
        echo "Intel-Grafik erkannt. Möchtest du die Intel-Treiber installieren? (y/n)"
        read -r INTEL_CHOICE
        if [[ "$INTEL_CHOICE" == "y" ]]; then
            pacman -S --noconfirm mesa lib32-mesa xf86-video-intel vulkan-intel lib32-vulkan-intel
        fi
    else
        echo "Keine unterstützte GPU erkannt oder unbekannter Hersteller."
    fi
}

# Function to install software through yay
install_software() {
    # Check if yay is installed
    if ! command -v yay &> /dev/null; then
        echo "yay ist nicht installiert. Installiere yay zuerst..."
        pacman -S --needed --noconfirm git base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay
        makepkg -si --noconfirm
        cd -
        rm -rf /tmp/yay
    fi

    echo "Welche Programme möchtest du installieren (durch Leerzeichen getrennt)?"
    read -r USER_PROGRAMS

    declare -a FINAL_SELECTIONS

    for prog in $USER_PROGRAMS; do
        echo
        echo "🔍 Suche nach '$prog' mit yay..."

        # Ganze Ausgabe in Array, Zeile für Zeile
        mapfile -t SEARCH_OUTPUT < <(yay -Ss "$prog")

        # Ergebnisse sammeln
        RESULTS=()
        for ((i=0; i<${#SEARCH_OUTPUT[@]}-1; i++)); do
            LINE="${SEARCH_OUTPUT[i]}"
            NEXT_LINE="${SEARCH_OUTPUT[i+1]}"
            if [[ "$LINE" == aur/* ]] && [[ "$NEXT_LINE" =~ ^\ + ]]; then
                RESULTS+=("$LINE" "$NEXT_LINE")
            fi
        done

        if [ ${#RESULTS[@]} -eq 0 ]; then
            echo "❌ Keine Pakete für '$prog' gefunden."
            continue
        fi

        echo "Ergebnisse für '$prog':"
        COUNT=0
        for ((i=0; i<${#RESULTS[@]}; i+=2)); do
            PACKAGE_LINE="${RESULTS[i]}"
            DESCRIPTION_LINE="${RESULTS[i+1]}"
            echo "[$COUNT] $PACKAGE_LINE"
            echo "     -> $DESCRIPTION_LINE"
            ((COUNT++))
        done

        echo
        echo "👉 Gib die Nummer des gewünschten Pakets ein (oder leer lassen zum Überspringen):"
        read -r CHOICE

        if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
            INDEX=$((CHOICE * 2))
            SELECTED_LINE="${RESULTS[INDEX]}"
            SELECTED_PKG=$(echo "$SELECTED_LINE" | awk '{print $1}')
            FINAL_SELECTIONS+=("$SELECTED_PKG")
            echo "✅ Hinzugefügt: $SELECTED_PKG"
        else
            echo "⏭️  '$prog' übersprungen."
        fi
    done

    if [ ${#FINAL_SELECTIONS[@]} -gt 0 ]; then
        echo
        echo "📦 Installiere ausgewählte Pakete:"
        for pkg in "${FINAL_SELECTIONS[@]}"; do
            echo " - $pkg"
        done
        yay -S --noconfirm "${FINAL_SELECTIONS[@]}"
    else
        echo "🚫 Keine Pakete zur Installation ausgewählt."
    fi
}

# Function to set Wayland as default
set_wayland() {
    echo "Setze Wayland als Standard..."
    if [[ ! -f /etc/environment ]]; then
        touch /etc/environment
    fi
    grep -qxF "XDG_SESSION_TYPE=wayland" /etc/environment || echo "XDG_SESSION_TYPE=wayland" >> /etc/environment
    echo "Wayland wurde als Standard gesetzt."
}

# Function to install OrcaSlicer
install_orcaslicer() {
    echo "Lade neueste OrcaSlicer-Version herunter..."
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/SoftFever/OrcaSlicer/releases/latest | grep "browser_download_url.*Linux_AppImage" | cut -d '"' -f 4)
    install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    wget "$LATEST_RELEASE" -O "$install_dir/OrcaSlicer.AppImage"
    chmod +x "$install_dir/OrcaSlicer.AppImage"
    echo "OrcaSlicer wurde installiert in $install_dir"
}

# Function to create games directory
create_games_dir() {
    echo "Erstelle /mnt/games Verzeichnis..."
    mkdir -p /mnt/games
    echo "/mnt/games Verzeichnis wurde erstellt."
}

# Function to configure automatic mounts
configure_mounts() {
    # Alle verfügbaren Partitionen anzeigen
    echo "🔍 Erkenne angeschlossene Partitionen..."
    mapfile -t DRIVES < <(blkid -o device)

    if [ ${#DRIVES[@]} -eq 0 ]; then
        echo "❌ Keine Laufwerke erkannt."
        return 1
    fi

    echo "Gefundene Partitionen:"
    for i in "${!DRIVES[@]}"; do
        DEVICE="${DRIVES[$i]}"
        INFO=$(blkid -o export "$DEVICE")
        echo "[$i] $DEVICE"
        echo "$INFO" | sed 's/^/    /'
        echo
    done

    # Auswahl durch den Nutzer
    echo
    echo "Welche Partitionen sollen automatisch gemountet werden? (Mehrfachauswahl z. B. '0 2 3')"
    read -r DRIVE_SELECTION

    for index in $DRIVE_SELECTION; do
        DEVICE="${DRIVES[$index]}"
        INFO=$(blkid -o export "$DEVICE")

        # Extrahieren der Informationen
        UUID=$(echo "$INFO" | grep -oP '^UUID=\K.*')
        FS_TYPE=$(echo "$INFO" | grep -oP '^TYPE=\K.*')
        LABEL=$(echo "$INFO" | grep -oP '^LABEL=\K.*')

        # Sicherstellen, dass UUID und Dateisystemtyp vorhanden sind
        if [ -z "$UUID" ] || [ -z "$FS_TYPE" ]; then
            echo "❌ Fehler: UUID oder Dateisystemtyp konnte nicht extrahiert werden. Überspringe Partition $DEVICE."
            continue
        fi

        # Wenn kein Label vorhanden, benutzerdefinierten Namen vergeben
        if [ -z "$LABEL" ]; then
            echo "Kein Label gefunden für UUID=$UUID."
            echo "Gib einen Namen für das Mount-Verzeichnis ein (z. B. 'Datenplatte'):"
            read -r LABEL
        fi

        # Pfadwahl
        echo "Möchtest du ein benutzerdefiniertes Verzeichnis zum Mounten angeben für '$LABEL'? (j/n)"
        read -r CUSTOM_PATH_CHOICE

        if [[ "$CUSTOM_PATH_CHOICE" == "j" ]]; then
            echo "Gib den vollständigen Mount-Pfad an (z. B. '/media/games'):"
            read -r MOUNT_POINT
        else
            MOUNT_POINT="/mnt/$LABEL"
        fi

        mkdir -p "$MOUNT_POINT"

        # Standardmäßige Optionen annehmen
        if [[ "$FS_TYPE" == "ntfs" || "$FS_TYPE" == "ntfs-3g" ]]; then
            OPTIONS="defaults,uid=1000,gid=1000 0 2"
        elif [[ "$FS_TYPE" == "ext4" ]]; then
            OPTIONS="defaults 0 2"
        elif [[ "$FS_TYPE" == "vfat" ]]; then
            OPTIONS="defaults,umask=0002,utf8=true 0 0"
        else
            OPTIONS="defaults 0 2"
        fi

        # Prüfen, ob bereits vorhanden
        if grep -q "$UUID" /etc/fstab; then
            echo "⚠️  Eintrag für UUID=$UUID ist bereits in /etc/fstab vorhanden - überspringe."
        else
            echo "🔧 Füge Mountpoint hinzu: UUID=$UUID -> $MOUNT_POINT"
            # Füge den Eintrag in /etc/fstab hinzu (korrekt formatiert in einer Zeile)
            echo "UUID=$UUID $MOUNT_POINT $FS_TYPE $OPTIONS" | tee -a /etc/fstab > /dev/null
        fi
    done

    # Mount alle fstab-Einträge
    echo
    echo "🔄 Aktualisiere Mounts gemäß /etc/fstab..."
    mount -a && echo "✅ Alle ausgewählten Laufwerke wurden gemountet." || echo "⚠️  Fehler beim Mounten. Bitte /etc/fstab prüfen."
}

# Function to create virtual GameSink
create_gamesink() {
    echo "🎧 Creating virtual audio sink..."
    SINK_NAME="GameSink"
    SINK_DESCRIPTION="GameAudio"

    # Create the null sink
    pactl load-module module-null-sink sink_name="$SINK_NAME" sink_properties=device.description="$SINK_DESCRIPTION"
    pactl set-default-sink "$SINK_NAME"

    echo "✅ Virtual sink '$SINK_NAME' created and set as default"
}

# Function to auto-connect audio devices to GameSink
# Function to auto-connect audio devices to GameSink
connect_to_gamesink() {
    SINK_NAME="GameSink"

    echo "🔍 Checking audio service status..."

    # First ensure pipewire/pulseaudio is running
    if ! pactl info &>/dev/null; then
        echo "⚠️ Audio service not running - attempting to start..."
        systemctl --user start pipewire pipewire-pulse
        sleep 2  # Give it time to start

        if ! pactl info &>/dev/null; then
            echo "❌ Failed to start audio service - cannot connect devices"
            return 1
        fi
    fi

    echo "✅ Audio service is running"
    echo ""
    echo "Available audio output sinks:"

    mapfile -t sinks < <(pactl list short sinks | grep -v "$SINK_NAME" | awk '{print $2}')

    if [ ${#sinks[@]} -eq 0 ]; then
        echo "❌ No available audio sinks found (except GameSink)"
        return 1
    fi

    # Display available sinks with numbers
    for i in "${!sinks[@]}"; do
        echo "[$((i+1))] ${sinks[$i]}"
    done

    echo ""
    while true; do
        read -p "👉 Enter the numbers of sinks to connect (e.g. '1 3') or 'q' to quit: " -a selected_indices

        if [[ "${selected_indices[0]}" == "q" ]]; then
            echo "⏭️ Skipping connection"
            return 0
        fi

        # Validate input
        valid=true
        for i in "${selected_indices[@]}"; do
            if ! [[ "$i" =~ ^[0-9]+$ ]] || [ "$i" -lt 1 ] || [ "$i" -gt "${#sinks[@]}" ]; then
                echo "❌ Invalid selection: $i"
                valid=false
                break
            fi
        done

        if $valid; then
            break
        fi
    done

    # Map selected numbers back to sink names
    selected_sinks=()
    for i in "${selected_indices[@]}"; do
        idx=$((i-1))
        selected_sinks+=("${sinks[$idx]}")
    done

    # Connect each selected sink
    echo ""
    echo "🔗 Connecting to: ${selected_sinks[*]}"
    for sink in "${selected_sinks[@]}"; do
        echo " - Connecting $SINK_NAME to $sink"
        pw-link "${SINK_NAME}:monitor_FL" "${sink}:playback_FL"
        pw-link "${SINK_NAME}:monitor_FR" "${sink}:playback_FR"
    done

    echo "✅ Successfully connected GameSink to selected devices"
}

# Function to setup GameSink with systemd service
setup_gamesink() {
    echo
    echo "🎧 Would you like to set up GameSink virtual audio? (y/n)"
    read -r GAMESINK_CHOICE

    if [[ "$GAMESINK_CHOICE" == "y" ]]; then
        SERVICE_NAME="virtual-sink"
        SINK_NAME="GameSink"
        SERVICE_FILE="$HOME/.config/systemd/user/$SERVICE_NAME.service"

        # Create the GameSink first
        create_gamesink

        # Then connect selected devices
        connect_to_gamesink

        # Create systemd service to persist these settings
        mkdir -p "$HOME/.config/systemd/user"

        # Get the current connections to persist them
        current_connections=$(pactl list short sinks | grep "$SINK_NAME")
        link_commands=""
        while read -r line; do
            sink_id=$(echo "$line" | awk '{print $1}')
            sink_name=$(echo "$line" | awk '{print $2}')
            if [[ "$sink_name" != "$SINK_NAME" ]]; then
                link_commands+="pw-link ${SINK_NAME}:monitor_FL ${sink_name}:playback_FL\n"
                link_commands+="pw-link ${SINK_NAME}:monitor_FR ${sink_name}:playback_FR\n"
            fi
        done <<< "$current_connections"

        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Create virtual audio sink and set as default

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/bin/pactl load-module module-null-sink sink_name=$SINK_NAME sink_properties=device.description=GameAudio; sleep 1; /usr/bin/pactl set-default-sink $SINK_NAME; sleep 1; ${link_commands//\\n/;}'
RemainAfterExit=true

[Install]
WantedBy=default.target
EOF

        echo "🔄 Reloading systemd user daemon..."
        systemctl --user daemon-reexec
        systemctl --user daemon-reload

        echo "📌 Enabling and starting the service..."
        systemctl --user enable --now "$SERVICE_NAME.service"

        echo "✅ GameSink setup complete with persistent connections"
    else
        echo "⏭️ Skipping GameSink setup"
    fi
}

# Function to run full setup
run_full_setup() {
    echo "=== Führe vollständige Installation aus ==="
    install_gpu_drivers
    install_software
    set_wayland
    install_orcaslicer
    create_games_dir
    configure_mounts
    setup_gamesink
    echo "=== Vollständige Installation abgeschlossen ==="
}

# Main script execution
#if [ "$EUID" -ne 0 ]; then
#    echo "Bitte starte das Skript mit sudo: sudo $0"
#    exit 1
#fi

# Initialize logging
log_file="/var/log/system_setup.log"
exec > >(tee -a "$log_file") 2>&1
echo "=== $(date) ==="

# Update package lists
echo "Aktualisiere Paketlisten..."
pacman -Syu --noconfirm

# Install base dependencies
echo "Installiere grundlegende Abhängigkeiten..."
pacman -S --needed base-devel git --noconfirm

# Main menu loop
while true; do
    show_menu
    read -r OPTION

    case $OPTION in
        1) install_gpu_drivers ;;
        2) install_software ;;
        3) set_wayland ;;
        4) install_orcaslicer ;;
        5) create_games_dir ;;
        6) configure_mounts ;;
        7) setup_gamesink ;;
        8) run_full_setup ;;
        9) create_gamesink ;;
        a) connect_to_gamesink ;;
        [xX]) echo "Beende Skript..."; exit 0 ;;
        *) echo "Ungültige Option. Bitte versuche es erneut." ;;
    esac

    read -p "Drücke Enter, um zum Menü zurückzukehren..."
done

cleanup() {
    rm -rf /tmp/yay* /tmp/makepkg*
}
trap cleanup EXIT
