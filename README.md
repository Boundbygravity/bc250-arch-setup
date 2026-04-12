# AMD BC250 — Arch Linux Post-Install Setup

## ¿Qué hace este script?

| Componente | Descripción |
|---|---|
| **Cyan Skillfish Governor SMU** | Instala y configura el governor con escalado dinámico 350–2200 MHz |
| **Driver nct6687** | Habilita sensores y control PWM de ventiladores |
| **Variables de entorno** | Configura optimizaciones de RADV para gaming |


---

## Instalación

```bash
# Opción 1 — Directo desde GitHub
curl -fsSL https://raw.githubusercontent.com/Boundbygravity/bc250-arch-setup/main/bc250-setup.sh | bash

# Opción 2 — Clonar y ejecutar
git clone https://github.com/Boundbygravity/bc250-arch-setup.git
cd bc250-arch-setup
chmod +x bc250-setup.sh
./bc250-setup.sh
```

> ⚠️ No ejecutes como root. El script pedirá `sudo` cuando sea necesario.

---

## Lo que instala

### 1. Cyan Skillfish Governor SMU

Instala [`cyan-skillfish-governor-smu`](https://github.com/filippor/cyan-skillfish-governor/tree/smu) desde AUR y aplica una configuración optimizada con:

- Punto de idle a **350 MHz @ 700mV** — bajo consumo en reposo
- Escalado dinámico hasta **2200 MHz**
- Thermal throttling a **83°C**, recovery a **73°C**
- 13 puntos de frecuencia para escala suave

```toml
[[safe-points]]
frequency = 350
voltage = 700

# ... hasta ...

[[safe-points]]
frequency = 2200
voltage = 1050
```

### 2. Driver nct6687

Instala el módulo [`nct6687d`](https://github.com/Fred78290/nct6687d) que reemplaza al `nct6683` del kernel (solo lectura) para habilitar control PWM real de ventiladores.

Permite usar herramientas como:
- `sensors` para monitoreo de temperatura
- `CoolerControl` para curvas de ventilador con GUI
- Scripts de control manual por sysfs

### 3. Variables de entorno

Agrega a `/etc/environment`:

```bash
ENABLE_VK_NULLVRS_1=1          # Fix Fragment Shading Rate para BC250
RADV_DEBUG=nohiz               # Mejora estabilidad en gaming (Mesa 25.1+)
RADV_PERFTEST=nggc             # Optimización Next-Gen Geometry Compression
radv_enable_unified_heap_on_apu=1  # Mejor manejo de memoria unificada
```

---

## Verificación post-instalación

Después del reboot:

```bash
# Estado del governor
systemctl status cyan-skillfish-governor-smu

# Temperatura y frecuencia en tiempo real
watch -n 1 sensors

# Frecuencia GPU actual
cat /sys/class/drm/card1/device/pp_dpm_sclk
```

**Valores esperados en idle:**
- GPU: ~350 MHz
- Voltaje: ~699 mV
- Temperatura: ~43°C
- Consumo: ~29W

---

## Comandos útiles

```bash
# Monitoreo en tiempo real
watch -n 1 sensors

# Logs del governor
journalctl -u cyan-skillfish-governor-smu -f

# Temperatura y frecuencia GPU en gaming
watch -n 1 "sensors | grep -E 'edge|sclk|PPT'"

# Estado de todos los servicios BC250
systemctl list-units | grep -i "cyan\|governor"
```

---

## Hardware adicional recomendado

Para mejores temperaturas combinar con:

- **Ventilador principal:** Arctic P12 Pro (alta presión estática)
- **Backplate VRAM:** Thermal pads 1.5mm (frontal) y 2.0mm (trasero) + ventilador 80mm
- **Pasta térmica:** Arctic MX-6 o PTM7950

Ver guía completa de cooling: [elektricm.github.io/amd-bc250-docs/hardware/cooling](https://elektricm.github.io/amd-bc250-docs/hardware/cooling/)

---

## Recursos

- 📖 [Documentación BC250](https://elektricm.github.io/amd-bc250-docs/)
- 🔧 [Script base eabarriosTGC](https://github.com/eabarriosTGC/BC250--ARCH)
- ⚙️ [Governor SMU (filippor)](https://github.com/filippor/cyan-skillfish-governor/tree/smu)
- 🌡️ [Driver nct6687 (Fred78290)](https://github.com/Fred78290/nct6687d)
- 💬 [Discord comunidad BC250](https://discord.gg/bc250)

---

## Licencia

MIT
