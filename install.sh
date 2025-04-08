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
echo "Installiere gewünschte Programme..."
yay -S --noconfirm protonpass-bin prismlauncher prusa-slicer discord steam protonvpn-gui firefox intellij-idea-ultimate-edition solaar
pacman -S --noconfirm ntfs-3g

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

echo "Welche Java-Version(en) möchtest du installieren? (z.B. 8 11 17 21) Eingabe mit Leerzeichen getrennt:"
read -r JAVA_VERSIONS

for VERSION in $JAVA_VERSIONS; do
    echo "Installiere Java $VERSION..."
    yay -S --noconfirm "jdk${VERSION}-openjdk"
done

# Setze Standard-Java-Version (optional)
echo "Möchtest du eine dieser Versionen als Standard festlegen? (z.B. 17 / leer für keine)"
read -r DEFAULT_JAVA
if [[ -n "$DEFAULT_JAVA" ]]; then
    archlinux-java set "java-${DEFAULT_JAVA}-openjdk"
    echo "Standard-Java auf Version $DEFAULT_JAVA gesetzt."
fi

# Erstelle Verzeichnis für Spiele
echo "Erstelle /mnt/games Verzeichnis..."
mkdir -p /mnt/games

# Überprüfe auf eine Partition mit dem Label "GamesSSD"
echo "Suche nach Laufwerk mit dem Label 'GamesSSD'..."
GAMES_UUID=$(blkid | grep 'LABEL="GamesSSD"' | grep -oP 'UUID="\K[^"]+')

if [[ -n "$GAMES_UUID" ]]; then
    echo "Gefundene UUID: $GAMES_UUID"

    # Prüfe, ob Eintrag bereits in /etc/fstab vorhanden ist
    if ! grep -q "$GAMES_UUID" /etc/fstab; then
        echo "Füge Eintrag zu /etc/fstab hinzu..."
        echo "UUID=$GAMES_UUID /mnt/games ntfs-3g defaults,uid=1000,gid=1000 0 2" >> /etc/fstab
    else
        echo "Eintrag bereits in /etc/fstab vorhanden."
    fi
else
    echo "Kein Laufwerk mit dem Label 'GamesSSD' gefunden."
fi

echo "Installation abgeschlossen!"
