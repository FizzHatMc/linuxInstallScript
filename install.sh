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

# Function to setup GameSink virtual audio
setup_gamesink() {
    echo
    echo "🎧 Möchtest du eine virtuelle Audio-Ausgabe (GameSink) einrichten und automatisch verbinden? (y/n)"
    read -r GAMESINK_CHOICE

    if [[ "$GAMESINK_CHOICE" == "y" ]]; then
        echo "🔧 Richte GameSink ein..."

        # Verzeichnisse anlegen
        GAMESINK_SCRIPT_DIR="/home/$SUDO_USER/.config/pipewire/scripts"
        SYSTEMD_USER_DIR="/home/$SUDO_USER/.config/systemd/user"
        WIREPLUMBER_DIR="/home/$SUDO_USER/.config/wireplumber/main.lua.d"

        mkdir -p "$GAMESINK_SCRIPT_DIR" "$SYSTEMD_USER_DIR" "$WIREPLUMBER_DIR"

        # GameSink loopback-Skript
        cat > "$GAMESINK_SCRIPT_DIR/create-gamesink.sh" <<EOF
#!/bin/bash
pw-loopback --capture-props='node.name="GameSink"' --playback-props='media.class=Audio/Sink' --node-name=GameSink --target=auto_null.monitor &
EOF
        chmod +x "$GAMESINK_SCRIPT_DIR/create-gamesink.sh"

        # systemd-Dienst für GameSink
        cat > "$SYSTEMD_USER_DIR/game-sink.service" <<EOF
[Unit]
Description=Create GameSink virtual audio output
After=pipewire.service
Requires=pipewire.service

[Service]
ExecStart=$GAMESINK_SCRIPT_DIR/create-gamesink.sh
Restart=on-failure

[Install]
WantedBy=default.target
EOF

        # Liste aktueller Sinks für automatische Verbindung
        echo
        echo "🔊 Verfügbare Audio-Ausgaben:"
        AVAILABLE_OUTPUTS=$(runuser -u "$SUDO_USER" -- pw-cli ls Node | grep -E '^\s+name = "' | cut -d'"' -f2 | grep -v 'GameSink' | nl)
        if [ -z "$AVAILABLE_OUTPUTS" ]; then
            echo "⚠️  Keine verfügbaren Audio-Sinks gefunden!"
        else
            echo "$AVAILABLE_OUTPUTS"
            echo
            echo "👉 Gib die Nummer der Ausgabe ein, mit der GameSink automatisch verbunden werden soll:"
            read -r SINK_CHOICE_NUM
            SELECTED_SINK=$(echo "$AVAILABLE_OUTPUTS" | sed -n "${SINK_CHOICE_NUM}p" | cut -f2)

            if [ -n "$SELECTED_SINK" ]; then
                echo "🎯 Gewählter Sink: $SELECTED_SINK"

                # Auto-connect Skript
                cat > "$GAMESINK_SCRIPT_DIR/auto-connect-monitors.sh" <<EOF
#!/bin/bash
set -e

# Warten auf GameSink Monitor
for i in {1..20}; do
  MONITOR=\$(pw-cli ls Port | grep -B1 "node.name = \\"GameSink\\.*monitor.*" | grep "id =" | awk '{print \$3}')
  TARGETS=(\$(pw-cli ls Port | grep -B1 "node.name = \\"$SELECTED_SINK\\".*input.*" | grep "id =" | awk '{print \$3}'))

  if [ -n "\$MONITOR" ] && [ \${#TARGETS[@]} -gt 0 ]; then
    for TARGET in "\${TARGETS[@]}"; do
      pw-link "\$MONITOR" "\$TARGET" || echo "⚠️ Verbindung fehlgeschlagen"
    done
    exit 0
  fi
  sleep 0.5
done

echo "❌ Konnte Monitor nicht automatisch verbinden"
exit 255
EOF
                chmod +x "$GAMESINK_SCRIPT_DIR/auto-connect-monitors.sh"

                # systemd-Dienst zum Verbinden
                cat > "$SYSTEMD_USER_DIR/pw-monitor-links.service" <<EOF
[Unit]
Description=Auto-connect GameSink monitor ports to outputs
After=pipewire.service game-sink.service
Requires=pipewire.service game-sink.service

[Service]
ExecStart=$GAMESINK_SCRIPT_DIR/auto-connect-monitors.sh
Type=simple
Restart=on-failure

[Install]
WantedBy=default.target
EOF

                # WirePlumber: Standard-Sink setzen
                cat > "$WIREPLUMBER_DIR/99-default-sink.lua" <<EOF
default_nodes = {
  ["default.audio.sink"] = "GameSink",
}
for k, v in pairs(default_nodes) do
  node = Session:get_node_by_name(v)
  if node then
    Session:set_default_node(k, node)
  else
    print("Node not found:", v)
  end
end
EOF

                # Berechtigungen setzen
                chown -R "$SUDO_USER":"$SUDO_USER" "/home/$SUDO_USER/.config"

                # Dienste aktivieren
                runuser -u "$SUDO_USER" -- systemctl --user daemon-reexec
                runuser -u "$SUDO_USER" -- systemctl --user enable --now game-sink.service
                runuser -u "$SUDO_USER" -- systemctl --user enable --now pw-monitor-links.service

                echo "✅ GameSink wurde erstellt, verbunden und als Standard gesetzt."
            else
                echo "⚠️  Ungültige Auswahl, Verbindung wird übersprungen."
            fi
        fi
    else
        echo "⏭️  GameSink wird nicht eingerichtet."
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
if [ "$EUID" -ne 0 ]; then
    echo "Bitte starte das Skript mit sudo: sudo $0"
    exit 1
fi

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
        [xX]) echo "Beende Skript..."; exit 0 ;;
        *) echo "Ungültige Option. Bitte versuche es erneut." ;;
    esac

    read -p "Drücke Enter, um zum Menü zurückzukehren..."
done

cleanup() {
    rm -rf /tmp/yay* /tmp/makepkg*
}
trap cleanup EXIT
