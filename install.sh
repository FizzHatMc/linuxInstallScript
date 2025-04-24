#!/bin/bash

# Sicherstellen, dass das Skript mit sudo-Rechten läuft
if [ "$EUID" -ne 0 ]; then
    echo "Bitte starte das Skript mit sudo: sudo $0"
    exit 1
fi

# Paketlisten aktualisieren
echo "Aktualisiere Paketlisten..."
pacman -Syu --noconfirm

# Yay installieren (falls nicht vorhanden)
echo "Installiere yay..."
pacman -S --needed --noconfirm git base-devel
if ! command -v yay &> /dev/null; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -
    rm -rf /tmp/yay
fi

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

# Pakete installieren

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




# Sicherstellen, dass Wayland genutzt wird
echo "Setze Wayland als Standard..."
if [[ ! -f /etc/environment ]]; then
    touch /etc/environment
fi
grep -qxF "XDG_SESSION_TYPE=wayland" /etc/environment || echo "XDG_SESSION_TYPE=wayland" >> /etc/environment

# OrcaSlicer neueste Version herunterladen
echo "Lade neueste OrcaSlicer-Version herunter..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/SoftFever/OrcaSlicer/releases/latest | grep "browser_download_url.*Linux_AppImage" | cut -d '"' -f 4)
wget "$LATEST_RELEASE" -O /usr/local/bin/OrcaSlicer.AppImage
chmod +x /usr/local/bin/OrcaSlicer.AppImage

# Erstelle Verzeichnis für Spiele
echo "Erstelle /mnt/games Verzeichnis..."
mkdir -p /mnt/games

#!/bin/bash

# Alle verfügbaren Partitionen anzeigen
echo "🔍 Erkenne angeschlossene Partitionen..."
mapfile -t DRIVES < <(blkid -o device)

if [ ${#DRIVES[@]} -eq 0 ]; then
    echo "❌ Keine Laufwerke erkannt."
    exit 1
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


echo "Installation abgeschlossen!"
