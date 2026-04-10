#!/bin/bash
# ============================================================
#  BC250 Post-Install Setup Script
#  Para usar DESPUÉS del script de eabarriosTGC
#  https://github.com/eabarriosTGC/BC250--ARCH
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}\n"
}

print_ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
print_warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}  → $1${NC}"; }
print_err()  { echo -e "${RED}  ✗ $1${NC}"; }

check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_err "No ejecutes este script como root. Se pedirá sudo cuando sea necesario."
        exit 1
    fi
}

check_arch() {
    if ! command -v pacman &>/dev/null; then
        print_err "Este script es solo para Arch Linux."
        exit 1
    fi
}

check_yay() {
    if ! command -v yay &>/dev/null; then
        print_info "Instalando yay (AUR helper)..."
        sudo pacman -S --needed --noconfirm git base-devel
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay && makepkg -si --noconfirm
        cd - && rm -rf /tmp/yay
        print_ok "yay instalado"
    else
        print_ok "yay ya está instalado"
    fi
}

# ────────────────────────────────────────────────────────────
# 1. GOVERNOR SMU
# ────────────────────────────────────────────────────────────
install_governor() {
    print_header "1/3 — Cyan Skillfish Governor SMU"

    print_info "Instalando cyan-skillfish-governor-smu desde AUR..."
    yay -S --noconfirm cyan-skillfish-governor-smu

    CONFIG_DIR="/etc/cyan-skillfish-governor-smu"
    CONFIG_FILE="$CONFIG_DIR/config.toml"

    print_info "Escribiendo configuración optimizada..."
    sudo mkdir -p "$CONFIG_DIR"
    sudo tee "$CONFIG_FILE" > /dev/null << 'EOF'
# Cyan Skillfish Governor SMU
# Optimizado para AMD BC250

[timing.intervals]
sample = 500
adjust = 200_000

[gpu-usage]
fix-metrics = true
method = "busy-flag"
flush-every = 10

[gpu]
set-method = "smu"

[dbus]
enabled = true

[timing.ramp-rates]
normal = 1
burst = 50

[timing]
burst-samples = 60
down-events = 5

[frequency-thresholds]
adjust = 10

[load-target]
upper = 0.85
lower = 0.70

[temperature]
throttling = 83
throttling_recovery = 73

[[safe-points]]
frequency = 350
voltage = 700

[[safe-points]]
frequency = 1000
voltage = 800

[[safe-points]]
frequency = 1175
voltage = 850

[[safe-points]]
frequency = 1500
voltage = 900

[[safe-points]]
frequency = 1600
voltage = 910

[[safe-points]]
frequency = 1700
voltage = 920

[[safe-points]]
frequency = 1850
voltage = 930

[[safe-points]]
frequency = 2000
voltage = 960

[[safe-points]]
frequency = 2050
voltage = 980

[[safe-points]]
frequency = 2100
voltage = 1000

[[safe-points]]
frequency = 2125
voltage = 1020

[[safe-points]]
frequency = 2150
voltage = 1035

[[safe-points]]
frequency = 2200
voltage = 1050
EOF

    print_info "Habilitando e iniciando el servicio..."
    sudo systemctl enable --now cyan-skillfish-governor-smu

    if systemctl is-active --quiet cyan-skillfish-governor-smu; then
        print_ok "Governor SMU activo y corriendo"
    else
        print_warn "Governor instalado pero no está activo — revisa con: systemctl status cyan-skillfish-governor-smu"
    fi
}

# ────────────────────────────────────────────────────────────
# 2. NCT6687 PARA CONTROL DE VENTILADORES
# ────────────────────────────────────────────────────────────
install_nct6687() {
    print_header "2/3 — Driver nct6687 (Control de Ventiladores)"

    print_info "Instalando nct6687d desde AUR..."
    yay -S --noconfirm nct6687d-dkms-git 2>/dev/null || \
    yay -S --noconfirm nct6687d 2>/dev/null || \
    {
        print_info "Instalando desde fuente (Fred78290/nct6687d)..."
        git clone https://github.com/Fred78290/nct6687d.git /tmp/nct6687d
        cd /tmp/nct6687d && make && sudo make install
        cd - && rm -rf /tmp/nct6687d
    }

    print_info "Configurando módulos..."
    sudo tee /etc/modprobe.d/bc250-sensors.conf > /dev/null << 'EOF'
# BC250 - Deshabilitar nct6683 (solo lectura) y habilitar nct6687
blacklist nct6683
options nct6687 force=true
EOF

    print_info "Cargando módulo nct6687 en el arranque..."
    sudo tee /etc/modules-load.d/99-bc250-sensors.conf > /dev/null << 'EOF'
nct6687
EOF

    print_info "Reconstruyendo initramfs..."
    sudo mkinitcpio -P

    print_ok "nct6687 configurado — efectivo después del reboot"

    # Verificar si el módulo se puede cargar ahora
    if sudo modprobe nct6687 2>/dev/null; then
        print_ok "Módulo nct6687 cargado exitosamente"
    else
        print_warn "El módulo se cargará en el próximo reboot"
    fi
}

# ────────────────────────────────────────────────────────────
# 3. VARIABLES DE ENTORNO PARA GAMING
# ────────────────────────────────────────────────────────────
install_env_vars() {
    print_header "3/3 — Variables de Entorno para Gaming"

    ENV_FILE="/etc/environment"

    print_info "Aplicando variables de entorno en $ENV_FILE..."

    # Respaldar archivo original
    sudo cp "$ENV_FILE" "${ENV_FILE}.bc250.bak" 2>/dev/null || true

    # Remover entradas previas del BC250 si existen
    sudo sed -i '/# BC250 Gaming/,/# END BC250/d' "$ENV_FILE" 2>/dev/null || true

    sudo tee -a "$ENV_FILE" > /dev/null << 'EOF'

# BC250 Gaming — Variables de rendimiento
ENABLE_VK_NULLVRS_1=1
RADV_DEBUG=nohiz
RADV_PERFTEST=nggc
radv_enable_unified_heap_on_apu=1
# END BC250
EOF

    print_ok "Variables de entorno configuradas"
    print_info "Estas variables aplican a todos los juegos del sistema"
    print_warn "Para Steam, también puedes añadir por juego: ENABLE_VK_NULLVRS_1=1 RADV_DEBUG=nohiz %command%"
}

# ────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ────────────────────────────────────────────────────────────
show_summary() {
    print_header "Instalación Completa"

    echo -e "${GREEN}  Lo que se instaló:${NC}"
    echo -e "  ✓ Cyan Skillfish Governor SMU (con config optimizada)"
    echo -e "  ✓ Driver nct6687 para sensores y control de ventiladores"
    echo -e "  ✓ Variables de entorno para gaming"
    echo ""
    echo -e "${YELLOW}  Próximos pasos:${NC}"
    echo -e "  1. Reinicia el sistema: ${CYAN}sudo reboot${NC}"
    echo -e "  2. Verifica el governor: ${CYAN}systemctl status cyan-skillfish-governor-smu${NC}"
    echo -e "  3. Verifica sensores: ${CYAN}sensors${NC}"
    echo -e "  4. En idle deberías ver la GPU en 350 MHz y ~43°C"
    echo ""
    echo -e "${BLUE}  Comandos útiles:${NC}"
    echo -e "  Monitoreo en tiempo real: ${CYAN}watch -n 1 sensors${NC}"
    echo -e "  Ver frecuencia GPU:       ${CYAN}watch -n 1 cat /sys/class/drm/card1/device/pp_dpm_sclk${NC}"
    echo -e "  Logs del governor:        ${CYAN}journalctl -u cyan-skillfish-governor-smu -f${NC}"
    echo ""
}

# ────────────────────────────────────────────────────────────
# MAIN
# ────────────────────────────────────────────────────────────
main() {
    clear
    echo -e "${CYAN}"
    echo "  ██████╗  ██████╗    ██████╗ ███████╗ ██████╗"
    echo "  ██╔══██╗██╔════╝   ╚════██╗██╔════╝██╔═████╗"
    echo "  ██████╔╝██║         █████╔╝███████╗██║██╔██║"
    echo "  ██╔══██╗██║        ██╔═══╝ ╚════██║████╔╝██║"
    echo "  ██████╔╝╚██████╗   ███████╗███████║╚██████╔╝"
    echo "  ╚═════╝  ╚═════╝   ╚══════╝╚══════╝ ╚═════╝"
    echo -e "${NC}"
    echo -e "  ${BLUE}Post-Install Setup Script para Arch Linux${NC}"
    echo -e "  ${BLUE}Usar después del script de eabarriosTGC${NC}"
    echo ""

    check_root
    check_arch
    check_yay

    install_governor
    install_nct6687
    install_env_vars
    show_summary
}

main "$@"
