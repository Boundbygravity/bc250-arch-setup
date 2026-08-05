#!/bin/bash
# ============================================================
#  BC250 Post-Install Setup Script (versión robustecida)
#  Para usar DESPUÉS del script de eabarriosTGC
#  https://github.com/eabarriosTGC/BC250--ARCH
#  Basado en: https://github.com/Boundbygravity/bc250-arch-setup
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directorios temporales — declarados arriba para que el trap los vea
YAY_TMP="/tmp/yay-bc250-setup"
NCT_TMP="/tmp/nct6687d-bc250-setup"

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════${NC}\n"
}

print_ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
print_warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}  → $1${NC}"; }
print_err()  { echo -e "${RED}  ✗ $1${NC}"; }

# ────────────────────────────────────────────────────────────
# FIX: limpieza garantizada de directorios temporales, incluso
# si el script se interrumpe o falla a mitad de camino.
# ────────────────────────────────────────────────────────────
cleanup() {
    rm -rf "$YAY_TMP" "$NCT_TMP"
}
trap cleanup EXIT INT TERM

check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_err "No ejecutes este script como root. Se pedirá sudo cuando sea necesario."
        exit 1
    fi
}

check_arch() {
    if ! command -v pacman &>/dev/null; then
        print_err "Este script es solo para Arch Linux / derivados (CachyOS, etc.)."
        exit 1
    fi
}

# ────────────────────────────────────────────────────────────
# FIX: verificar que realmente estamos en una BC-250 antes de
# tocar nada. Antes el script corría "a ciegas" en cualquier
# máquina Arch.
# ────────────────────────────────────────────────────────────
check_hardware() {
    print_info "Verificando hardware BC-250..."
    if ! lspci -d 1002:13fe &>/dev/null; then
        print_err "No se detectó una GPU AMD BC-250 (Cyan Skillfish, ID 1002:13fe) en este sistema."
        print_err "Este script no debería correr en otro hardware — abortando."
        exit 1
    fi
    print_ok "BC-250 detectada"
}

# ────────────────────────────────────────────────────────────
# FIX: pedir sudo una sola vez al inicio, y mantenerlo vivo con
# un keep-alive en background, en vez de pedirlo a mitad de una
# instalación larga (donde un timeout de sudo puede matar el
# script a la mitad de una operación no idempotente).
# ────────────────────────────────────────────────────────────
prime_sudo() {
    print_info "Este script necesita sudo — puede pedir tu contraseña una vez."
    sudo -v
    ( while true; do sudo -v; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; cleanup' EXIT INT TERM
}

check_yay() {
    if command -v yay &>/dev/null; then
        print_ok "yay ya está instalado"
        return
    fi

    print_info "Instalando yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel

    # FIX: limpiar restos de una corrida anterior fallida antes
    # de clonar — si el directorio ya existe, `git clone` falla.
    rm -rf "$YAY_TMP"
    git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    (cd "$YAY_TMP" && makepkg -si --noconfirm)
    rm -rf "$YAY_TMP"
    print_ok "yay instalado"
}

# ────────────────────────────────────────────────────────────
# 1. GOVERNOR SMU
# ────────────────────────────────────────────────────────────
install_governor() {
    print_header "1/4 — Cyan Skillfish Governor SMU"

    # FIX: detectar si ya hay otro gestor de frecuencia/CU corriendo
    # (ej. bc250-cu-live-manager) que podría chocar con este governor
    # controlando el mismo hardware SMU.
    if systemctl is-active --quiet bc250-cu-live-manager 2>/dev/null; then
        print_warn "Detecté bc250-cu-live-manager activo — este governor también controla"
        print_warn "el SMU y podría chocar con él. Verifica que no se pisen entre sí."
    fi

    if systemctl is-active --quiet cyan-skillfish-governor-smu 2>/dev/null; then
        print_warn "cyan-skillfish-governor-smu ya está instalado y corriendo."
        read -rp "  ¿Sobreescribir su configuración? [y/N] " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            print_info "Omitiendo reconfiguración del governor."
            return
        fi
    fi

    print_info "Instalando cyan-skillfish-governor-smu desde AUR..."
    yay -S --noconfirm cyan-skillfish-governor-smu

    CONFIG_DIR="/etc/cyan-skillfish-governor-smu"
    CONFIG_FILE="$CONFIG_DIR/config.toml"

    # FIX: respaldar la config existente solo si aún no hay backup —
    # antes se sobreescribía el backup en cada corrida, perdiendo el
    # original real.
    if [ -f "$CONFIG_FILE" ] && [ ! -f "${CONFIG_FILE}.orig.bak" ]; then
        sudo cp "$CONFIG_FILE" "${CONFIG_FILE}.orig.bak"
        print_info "Config previa respaldada en ${CONFIG_FILE}.orig.bak"
    fi

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

    # FIX: dar un margen antes de chequear el estado — systemctl
    # puede reportar "activating" en vez de "active" justo al inicio.
    sleep 2
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
    print_header "2/4 — Driver nct6687 (Control de Ventiladores)"

    if lsmod | grep -q '^nct6687'; then
        print_ok "nct6687 ya está cargado — omitiendo instalación"
        return
    fi

    print_info "Instalando nct6687d desde AUR..."
    if ! yay -S --noconfirm nct6687d-dkms-git 2>/dev/null && \
       ! yay -S --noconfirm nct6687d 2>/dev/null; then
        print_info "AUR falló, instalando desde fuente (Fred78290/nct6687d)..."
        rm -rf "$NCT_TMP"
        git clone https://github.com/Fred78290/nct6687d.git "$NCT_TMP"
        (cd "$NCT_TMP" && make && sudo make install)
        rm -rf "$NCT_TMP"
    fi

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

    # FIX: descargar nct6683 de la sesión actual antes de cargar
    # nct6687 — el blacklist solo aplica en el próximo boot, así que
    # sin esto había conflicto de recursos con el chip de sensores
    # en la sesión en curso.
    if lsmod | grep -q '^nct6683'; then
        print_info "Descargando nct6683 de la sesión actual..."
        sudo modprobe -r nct6683 2>/dev/null || \
            print_warn "No se pudo descargar nct6683 en caliente — quedará activo hasta el reboot"
    fi

    print_info "Reconstruyendo initramfs..."
    sudo mkinitcpio -P

    print_ok "nct6687 configurado — totalmente efectivo después del reboot"

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
    print_header "3/4 — Variables de Entorno para Gaming"

    ENV_FILE="/etc/environment"

    print_info "Aplicando variables de entorno en $ENV_FILE..."

    # FIX: respaldo único y con timestamp, sin pisar un backup previo.
    if [ ! -f "${ENV_FILE}.bc250.orig.bak" ]; then
        sudo cp "$ENV_FILE" "${ENV_FILE}.bc250.orig.bak" 2>/dev/null || true
        print_info "Respaldo original guardado en ${ENV_FILE}.bc250.orig.bak"
    fi

    # Remover entradas previas del BC250 si existen (evita duplicados)
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
    print_info "Estas variables aplican a todos los juegos del sistema (requiere reboot o re-login)"
    print_warn "Para Steam, también puedes añadir por juego: ENABLE_VK_NULLVRS_1=1 RADV_DEBUG=nohiz %command%"
}

# ────────────────────────────────────────────────────────────
# 4. PARÁMETROS TTM (VRAM/GTT) — vía /etc/default/limine
# ────────────────────────────────────────────────────────────
# FIX/AGREGADO: en sistemas CachyOS con Limine, el cmdline real
# vive en /etc/default/limine bajo KERNEL_CMDLINE[default]="...",
# NO en /etc/kernel/cmdline (que suele estar vacío o no usarse) y
# NO se edita /boot/limine.conf directamente (se regenera solo).
# Patrón validado contra redbeard1083/bc250-toolkit.
# ────────────────────────────────────────────────────────────
install_ttm_params() {
    print_header "4/4 — Parámetros TTM (VRAM/GTT)"

    local CONF="/etc/default/limine"

    if [ ! -f "$CONF" ]; then
        print_warn "No se encontró $CONF — ¿este sistema usa Limine? Omitiendo este paso."
        return
    fi

    if grep -q 'ttm\.pages_limit=' "$CONF"; then
        print_ok "ttm.pages_limit ya está configurado en $CONF — omitiendo"
        return
    fi

    # Backup no destructivo — solo si aún no existe uno
    if [ ! -f "${CONF}.bak" ]; then
        sudo cp "$CONF" "${CONF}.bak"
        print_info "Backup original guardado en ${CONF}.bak"
    fi

    print_info "Agregando ttm.pages_limit / ttm.page_pool_size a KERNEL_CMDLINE[default]..."
    sudo sed -i '/^KERNEL_CMDLINE\[default\]/ s/"$/ ttm.pages_limit=3959290 ttm.page_pool_size=3959290"/' "$CONF"

    print_info "Regenerando /boot/limine.conf..."
    sudo limine-update

    print_ok "Parámetros ttm agregados — efectivo después del reboot"
    print_info "Verifica después de reiniciar con: cat /proc/cmdline | grep ttm"
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
    echo -e "  ✓ Parámetros ttm (VRAM/GTT) en /etc/default/limine"
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
    check_hardware
    prime_sudo
    check_yay

    install_governor
    install_nct6687
    install_env_vars
    install_ttm_params
    show_summary
}

main "$@"
