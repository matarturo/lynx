# Lynx

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![ShellCheck](https://github.com/matarturo/lynx/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/matarturo/lynx/actions/workflows/shellcheck.yml)
[![Version](https://img.shields.io/badge/version-3.0-green.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu-informational.svg)]()
[![Bash](https://img.shields.io/badge/bash-4.4%2B-89e051.svg)]()

**Auditor pasivo de seguridad y red para Debian y Ubuntu.**

Lynx es un **script de Bash** que revisa, en modo solo lectura, la configuración de seguridad de un servidor Debian/Ubuntu: parámetros del kernel, firewall (iptables-legacy, iptables-nft, nftables y scripts de **Firewall Builder / fwbuilder**), SSH, cuentas de usuario y permisos críticos. Muestra un reporte en pantalla, calcula un puntaje y guarda evidencias verificables con hash SHA-256 para el auditor.

> **Alcance:** Lynx es una herramienta de revisión rápida, no una certificación. Evalúa 29 controles puntuables y no reemplaza a un análisis completo de cumplimiento (por ejemplo, CIS Benchmark con OpenSCAP o CIS-CAT). Ver [Limitaciones](#limitaciones).

---

<details>
<summary>Índice</summary>

- [¿Por qué Lynx?](#por-qué-lynx)
- [Datos básicos](#datos-básicos)
- [Qué revisa](#qué-revisa)
- [Descarga](#descarga)
- [Instalación](#instalación)
- [Uso](#uso)
- [Salida y cómo interpretarla](#salida-y-cómo-interpretarla)
- [Público objetivo](#quién-puede-usarlo-público-objetivo)
- [Limitaciones](#limitaciones)
- [Seguridad de los datos generados](#seguridad-de-los-datos-generados)
- [Contribuir](#contribuir)
- [Licencia](#-licencia)

</details>

---

## ¿Por qué Lynx?

- **Pasivo por diseño:** no modifica configuración, no instala paquetes, no reinicia servicios. Ejecutable en producción sin miedo.
- **Evidencias verificables:** cada auditoría genera un reporte con SHA-256 y volcados crudos, listo para adjuntar a un informe.
- **Cubre el rincón que otros ignoran:** detecta reglas huérfanas entre `iptables-legacy`, `iptables-nft` y `nftables`, incluyendo las que genera **fwbuilder** — el caso típico tras una migración mal hecha.

---

## Datos básicos

|---|---|
| **Nombre** | Lynx |
| **Versión** | 3.0 |
| **Lenguaje** | Bash (5.x recomendado; mínimo 4.4) |
| **Sistemas objetivo** | Debian 12 / 13 y derivados, Ubuntu (LTS recientes) |
| **Sistemas validados** | Debian 13 (trixie) — ver [Sistemas validados](#sistemas-validados) |
| **Privilegios** | Requiere `root` (lee `/etc/shadow`, reglas de firewall y configuración de kernel) |
| **Naturaleza** | Pasivo: no modifica configuración, no instala ni elimina paquetes |
| **Salida** | Reporte `.txt` sin colores, evidencias crudas y hashes SHA-256, en `/var/lib/lynx/<host>/` |
| **Licencia** | [Apache License 2.0](LICENSE) |

## Sistemas validados

Lynx se ha probado en los siguientes sistemas. Solo se marca como
**validado** aquel en el que se ha ejecutado una auditoría completa de
extremo a extremo con resultados verificables.

### ✅ Validado en sistema real

| Sistema | Versión | Kernel probado | Notas |
|------------------------|----|---------------------|---------------------------------------------------------------------------------------------------------------------|
| **Debian 13 (trixie)** | 13 | 6.12.96+deb13-amd64 | Ejecución completa con `systemd`, `ufw`, `nftables` y Docker activos. Los 29 controles se ejecutaron correctamente. |

### 🟡 Compatible (probado parcialmente)

| Sistema | Versión | Estado |
|---|---|---|
| **Ubuntu 24.04 LTS (Noble)** | 24.04 | Ejecutado en entorno de pruebas sin `systemd`, `iptables`, `nft` ni `sshd`. Los análisis de firewall se validaron con volcados simulados de `fwbuilder`, `iptables-legacy`, `iptables-nft` y `nftables` nativo. |
| **Debian 12 (bookworm)** | 12 | Probado con los mismos volcados simulados que Ubuntu 24.04. Los defaults del kernel y las rutas de configuración son muy similares a Debian 13. |

### ⚪ Teóricamente compatible (no probado)

- Ubuntu 22.04 LTS (Jammy) y 24.04 LTS (Noble).
- Debian 11 (bullseye) y 12 (bookworm).
- Derivados de Debian/Ubuntu con `systemd` y `apt`: Linux Mint, Pop!_OS, Proxmox VE, Kali Linux, Parrot OS.

En estos sistemas Lynx debería funcionar sin cambios, pero **no se ha
verificado la ejecución completa**. Si lo pruebas, abre un issue con el
resultado y añadimos el sistema a la lista de validados.

### ❌ No soportado

Lynx está diseñado específicamente para Debian y sus derivados. **No
está pensado para**:

- RHEL, Fedora, CentOS, Rocky Linux, AlmaLinux, openSUSE, Arch Linux.
- Sistemas sin `systemd` (Devuan, Alpine, Void, contenedores minimalistas).
- Sistemas sin `apt`.

No es que "no funcione", es que **muchos controles dependen de rutas,
paquetes y convenciones específicas de Debian/Ubuntu** (`/etc/apt/`,
`/etc/modprobe.d/`, `apt-get`, `dpkg-query`, UIDs de sistema <1000,
grupo `adm`, etc.). En otras distribuciones los resultados pueden ser
incorrectos o directamente falsos.

### Reportar compatibilidad

Si has ejecutado Lynx en un sistema que no aparece como validado,
cuéntanoslo abriendo un issue con:

- Distribución y versión (`cat /etc/os-release`).
- Versión del kernel (`uname -r`).
- Puntuación obtenida y controles que dieron resultados inesperados.
- Cualquier mensaje de error o comportamiento raro.

Con esa información actualizamos la tabla.

### Estado de las pruebas

- Verificado con `bash -n` y `shellcheck` sin advertencias.
- Ejecutado de extremo a extremo en Ubuntu 24.04 (entorno de pruebas sin systemd, iptables, nft ni sshd). Los análisis de firewall se probaron con volcados simulados de fwbuilder, iptables-legacy, iptables-nft y nftables nativo.
- **Pendiente:** validación en servidores Debian 13 reales. Ejecútalo primero en un equipo de prueba.

---

## Qué revisa

### Secciones que puntúan (100 puntos, 29 controles)

| # | Sección | Peso | Ejemplos de controles |
|---|---------|------|-----------------------|
| 1 | Parámetros del kernel (sysctl) | 30 | SYN cookies, redirecciones ICMP (IPv4/IPv6), source routing, rp_filter, kptr_restrict, dmesg_restrict, ptrace_scope, ASLR, suid_dumpable |
| 2 | Stack de red | 10 | conntrack cargado, IP forwarding, bridge-nf-call-iptables (si hay bridges) |
| 3 | Firewall | 25 | Reglas cargadas, regla *stateful* ESTABLISHED,RELATED, INPUT/FORWARD con política DROP, filtrado IPv6 |
| 4 | SSH y hardening | 15 | `PermitRootLogin`, `PasswordAuthentication`, módulos de red obsoletos bloqueados, core dumps limitados |
| 5 | Usuarios y privilegios | 10 | Un solo UID 0, sin contraseñas vacías, cuentas de sistema sin shell interactiva |
| 6 | Permisos críticos | 10 | `/etc/shadow`, `/etc/passwd`, directorios world-writable sin sticky bit |

### Sección 7: información y evidencias

Datos de apoyo para el auditor: puertos en escucha y procesos, cuentas con login, `sudoers` con `NOPASSWD`, miembros del grupo `docker`, contraseñas que nunca expiran, estado de servicios (auditd, rsyslog, fail2ban, unattended-upgrades…), sincronización de hora, AppArmor/SELinux, actualizaciones pendientes (simulación con `apt-get -s`), opciones de montaje de `/tmp`, `/var/tmp`, `/dev/shm` y `/home`, paquetes de servicios inseguros (telnet, rsh, nis, tftp, xinetd) e inventarios de archivos SUID/SGID, world-writable y sin propietario.

### Soporte para firewalls legacy y fwbuilder

Lynx lee las reglas desde **los tres backends** (`iptables-legacy-save`, `iptables-nft-save` y `nft list ruleset`), porque en Debian moderno el binario `iptables` puede apuntar a uno u otro y las reglas de un backend no se ven desde el otro. Además:

- Reconoce reglas *stateful* con `-m state --state` (formato que genera fwbuilder), con `-m conntrack --ctstate` y con `ct state` de nftables.
- Sigue saltos a cadenas de usuario (`-A INPUT -j RULE_N` … `-A RULE_N -j DROP`) para detectar una denegación final aunque la política sea ACCEPT.
- Detecta el paquete `fwbuilder`, los scripts `*.fw` generados y su carga al arranque, avisa si hay reglas en legacy y nft a la vez, y alerta si hay reglas cargadas sin mecanismo de persistencia tras un reinicio.

---

## Descarga

**Con git:**

```bash
git clone https://github.com/matarturo/lynx.git
cd lynx
```

**Solo el script, con wget o curl:**

```bash
wget https://raw.githubusercontent.com/matarturo/lynx/main/lynx.sh
# o
curl -fsSLO https://raw.githubusercontent.com/matarturo/lynx/main/lynx.sh
```

Como el script se ejecuta con privilegios de root, **revisa su contenido antes de ejecutarlo** (`less lynx.sh`) y no lo canalices directamente a `sudo bash`.

---

## Instalación

Lynx no tiene dependencias que instalar: usa herramientas presentes en Debian/Ubuntu (`bash`, `awk`, `grep`, `sed`, `find`, `stat`). Las herramientas opcionales (`ss`/`ip`, `iptables`, `nft`, `sshd`, `dpkg`, `apt-get`) se usan si existen; si falta alguna, el control correspondiente se marca como fallo o se omite.

### Opción A: ejecutar sin instalar

```bash
chmod +x lynx.sh
sudo ./lynx.sh
```

Si el directorio está en un sistema de archivos montado con `noexec`, ejecútalo con `sudo bash lynx.sh`.

### Opción B: instalar en el sistema

```bash
sudo install -m 0750 -o root -g root lynx.sh /usr/local/sbin/lynx-audit
sudo lynx-audit --version
```

> **Atención con el nombre:** en Debian y Ubuntu existe un navegador web en modo texto llamado `lynx` (paquete `lynx`). Por eso, en la opción B el ejecutable se instala como **`lynx-audit`**, para no sustituir ni chocar con ese programa.

**Desinstalar:**

```bash
sudo rm /usr/local/sbin/lynx-audit
```

---

## Uso

```bash
sudo ./lynx.sh                # auditoría completa
./lynx.sh --help              # ayuda (no requiere root)
./lynx.sh --version           # versión
```

## Variables de entorno

| Variable | Efecto |
|---|---|
| `REPORT_DIR=/ruta` | Directorio donde se guardan el reporte y las evidencias (por defecto, el directorio actual) |
| `ES_ROUTER=1` | El equipo enruta a propósito: `ip_forward=1` se marca como N/A en lugar de fallo |
| `SIN_EVIDENCIAS=1` | No guarda volcados crudos; solo genera el reporte |
| `SKIP_SLOW=1` | Omite los inventarios con `find` (SUID, world-writable, huérfanos) |
| `TIMEOUT_FIND=60` | Segundos máximos por inventario con `find` (por defecto 60) |

---

# Ejemplo de salida

A continuación, un fragmento de una auditoría real (datos anonimizados) sobre un servidor Debian 12 que ya había sido endurecido previamente. Los códigos ANSI de color del terminal se eliminan al escribir el archivo `.txt`, así que el reporte se ve tal cual:

```
====================================================================
  LYNX v3.0 - AUDITORÍA PASIVA DE SEGURIDAD, RED Y PRIVILEGIOS
  Fecha: mié 30 sep 2026 14:32:07 UTC | Host: srv-web-01
====================================================================

---> 1. AUDITANDO PARÁMETROS KERNEL (SYSCTL)
[PASS] +4 pts | Protección contra SYN Flood (tcp_syncookies=1)
[PASS] +3 pts | Bloqueo de redirecciones ICMP IPv4 (all y default = 0)
[PASS] +3 pts | Enrutamiento de origen deshabilitado (accept_source_route=0)
[PASS] +3 pts | RPFilter activado (anti IP spoofing, rp_filter>=1)
[PASS] +3 pts | Ocultamiento de punteros de kernel (kptr_restrict>=1)
[FAIL]   0 pts | Restricción de acceso a dmesg (dmesg_restrict>=1)
[FAIL]   0 pts | Restricción de PTRACE a no privilegiados (yama.ptrace_scope>=1)
[PASS] +2 pts | Bloqueo de redirecciones ICMP IPv6 (accept_redirects=0)
[PASS] +2 pts | No enviar redirecciones ICMP (send_redirects=0)
[PASS] +2 pts | ASLR completo (randomize_va_space=2)
[PASS] +2 pts | Sin core dumps de binarios SUID (fs.suid_dumpable=0)

---> 2. AUDITANDO STACK DE RED (CONNTRACK / FORWARDING / BRIDGE)
[PASS] +4 pts | Módulo conntrack (stateful) cargado en el kernel
[PASS] +3 pts | IP Forwarding desactivado (host puro; use ES_ROUTER=1 si enruta)
[N/A ] +3 pts | Si hay bridges: bridge-nf-call-iptables=1 (no aplica)

  [i] Bridging / Bonding (informativo, no puntua):
      - Bridges : ninguno
      - Bonds   : ninguno

---> 3. AUDITANDO FIREWALL (IPTABLES LEGACY, IPTABLES-NFT, NFTABLES)
[PASS] +5 pts | Reglas de firewall cargadas en el kernel (cualquier backend)
[PASS] +7 pts | Regla stateful ESTABLISHED,RELATED (conntrack, state o nft ct state)
[PASS] +7 pts | INPUT con política DROP/REJECT o regla final de denegación
[PASS] +3 pts | FORWARD con política DROP/REJECT (o forwarding desactivado)
[PASS] +3 pts | IPv6 filtrado por firewall (o IPv6 deshabilitado)

  [i] Backends de firewall detectados:
      - Binario iptables       : /usr/sbin/xtables-nft-multi
      - Reglas iptables-legacy : 0 (IPv4) / 0 (IPv6)
      - Reglas iptables-nft    : 12 (IPv4) / 6 (IPv6)
      - nftables (ruleset)     : con reglas
  [i] fwbuilder:
      - Paquete instalado      : no
      - Scripts .fw generados  : ninguno encontrado
      - Arranque persistente   : servicio systemd: nftables (enabled)

  [i] Persistencia del firewall (¿se cargan las reglas al reiniciar?):
      - servicio systemd: nftables (enabled)

---> 4. AUDITANDO SSH Y HARDENING GENERAL
[PASS] +4 pts | SSH: root sin contraseña (PermitRootLogin no / prohibit-password)
[PASS] +4 pts | SSH: autenticación por contraseña deshabilitada
[FAIL]   0 pts | Módulos de red obsoletos bloqueados con 'install' (dccp, rds, tipc)
[FAIL]   0 pts | Core dumps limitados (limits.conf hard core 0 o coredump Storage=none)

---> 5. AUDITANDO USUARIOS, CUENTAS Y PRIVILEGIOS
[PASS] +3 pts | Sin cuentas adicionales con UID 0 (solo root)
[PASS] +3 pts | Sin contraseñas vacías en /etc/shadow
[PASS] +4 pts | Cuentas de sistema (UID<1000) con shell no interactiva

  [i] Resumen informativo de usuarios:
      - Miembros del grupo sudo: deploy

---> 6. AUDITANDO PERMISOS DE ARCHIVOS Y DIRECTORIOS CRÍTICOS
[PASS] +3 pts | /etc/shadow: propietario root y modo 640 o más estricto
[PASS] +3 pts | /etc/passwd: propietario root y modo 644 o más estricto
[FAIL]   0 pts | Sin directorios world-writable sin sticky bit en /etc, /var, /usr
      Directorios encontrados (máx. 5):
        - /var/www/uploads

---> 7. EVIDENCIAS E INFORMACIÓN COMPLEMENTARIA (no puntúa)

  [i] Sistema:
      - SO     : Debian GNU/Linux 12 (bookworm)
      - Kernel : 6.1.0-25-amd64 | up 47 days, 3 hours

  [i] Puertos en escucha: 4 en total, 1 expuesto en todas las interfaces:
      - tcp LISTEN 0.0.0.0:22     users:(("sshd",pid=812,fd=3))
      - tcp LISTEN 127.0.0.1:5432 users:(("postgres",pid=1043,fd=7))
      - tcp LISTEN 127.0.0.1:8080 users:(("node",pid=2211,fd=18))
      - tcp LISTEN [::1]:5432     users:(("postgres",pid=1043,fd=6))

  [i] Usuarios y privilegios:
      - Cuentas con shell de login: root deploy
      - Cuentas con contraseña que nunca expira (maxdias=99999): 2

  [i] Servicios de seguridad y soporte (activo / habilitado):
      - ssh: active / enabled
      - auditd: inactive / disabled
      - rsyslog: active / enabled
      - fail2ban: active / enabled
      - unattended-upgrades: active / enabled
      - nftables: active / enabled
      - Journald persistente : sí
      - Hora sincronizada    : sí

  [i] Control de acceso obligatorio:
      - AppArmor: activo

  [i] Parches:
      - Paquetes con actualización pendiente: 7 (de seguridad: 2) según caché apt de hace 1 día(s)
      - ALERTA: hay actualizaciones de seguridad pendientes.
      - unattended-upgrades: instalado

  [i] Opciones de montaje (nodev, nosuid, noexec):
      - /tmp: montaje propio | opciones que faltan: ninguna
      - /var/tmp: montaje propio | opciones que faltan: ninguna
      - /dev/shm: montaje propio | opciones que faltan: ninguna
      - /home: hereda de / | opciones que faltan: nodev nosuid

  [i] Paquetes de servicios inseguros instalados (telnet, rsh, nis, tftp, xinetd...): ninguno

  [i] Inventarios de archivos (sistemas de archivos locales, límite 60s c/u):
      - Binarios SUID/SGID          : 18
      - Archivos world-writable     : 2
      - Archivos sin propietario    : 0

  [i] Evidencias crudas en: ./lynx_evidencias_20260930_143207
      Contienen datos sensibles (sudoers, procesos, reglas de firewall): proteja o cifre el directorio.

====================================================================
 PUNTUACIÓN DE AUDITORÍA: 83 / 100 (83%)  -  29 controles evaluados
====================================================================
 Controles fallidos:
   - Restricción de acceso a dmesg (dmesg_restrict>=1)
   - Restricción de PTRACE a no privilegiados (yama.ptrace_scope>=1)
   - Módulos de red obsoletos bloqueados con 'install' (dccp, rds, tipc)
   - Core dumps limitados (limits.conf hard core 0 o coredump Storage=none)
   - Sin directorios world-writable sin sticky bit en /etc, /var, /usr

 CUMPLIMIENTO: MEDIO - hay omisiones a corregir
 Nota: el puntaje cubre solo 29 controles pasivos. Parches, AppArmor, auditd, sudoers y
       servicios expuestos se listan en la sección 7 como información (no puntúan). No equivale
       a una certificación de hardening.
====================================================================
 Reporte guardado en: ./lynx_reporte_20260930_143207.txt

Manifiesto de evidencias: ./lynx_evidencias_20260930_143207/SHA256SUMS
SHA-256 del reporte: 7c1a3e9f8b04d2e5a6f18c93b7e2d40a9f5c8b1e6d3a7f2c4e9b6a8d1f3c5e70  (archivo: ./lynx_reporte_20260930_143207.txt.sha256)
```

## Cómo interpretar este ejemplo

- **Sección 1 (24/30):** casi todo bien. Los dos fallos (`dmesg_restrict`, `ptrace_scope`) son hallazgos habituales en Debian 12 recién instalado: se activan añadiendo dos líneas a `/etc/sysctl.d/`.
- **Sección 2 (10/10):** el control de bridges se marca **N/A** porque el host no tiene bridges; **suma puntos** al no aplicar.
- **Sección 3 (25/25):** firewall unificado en `nftables`, con persistencia por systemd. Este es el escenario al que se llega tras migrar bien desde `iptables-legacy`.
- **Sección 4 (8/15):** `PermitRootLogin` y `PasswordAuthentication` correctos, pero faltan bloqueos de módulos y límite de core dumps.
- **Sección 5 (10/10):** cuentas de sistema sin shell interactiva y sin UID 0 duplicados.
- **Sección 6 (6/10):** `/var/www/uploads` sin sticky bit. Un solo directorio, pero baja el puntaje a MEDIO.
- **Sección 7:** toda la información complementaria (puertos, servicios, parches, montajes, inventarios) se **guarda como evidencia** con su SHA-256, pero **no puntúa**.

El ejemplo ilustra dos cosas importantes de Lynx:

1. **83 % no es "bueno", es MEDIO.** La herramienta no regala puntaje: exige cumplir el control completo.
2. **Los N/A suman**, no restan. Lynx premia los controles que no aplican al perfil del servidor, en lugar de penalizar a quien no los necesita.

---

## Auditoría estándar, guardando los resultados en un directorio propio

```bash
sudo mkdir -p /var/lib/lynx && sudo REPORT_DIR=/var/lib/lynx ./lynx.sh
```
### Revisión rápida (sin inventarios lentos ni evidencias crudas)
```bash
sudo SKIP_SLOW=1 SIN_EVIDENCIAS=1 ./lynx.sh
```
### Servidor que actúa como router/firewall de red

```bash
sudo ES_ROUTER=1 ./lynx.sh
```
---

## Salida y cómo interpretarla

Cada ejecución genera, en `REPORT_DIR`:

```
lynx_reporte_<fecha>.txt          # reporte completo, sin códigos de color (permisos 600)
lynx_reporte_<fecha>.txt.sha256   # hash del reporte
lynx_evidencias_<fecha>/          # volcados crudos (permisos 700)
├── SHA256SUMS                    # hash de cada evidencia
├── nft_ruleset.txt, iptables_*_save.txt, sshd_config_efectiva.txt, sysctl_completo.txt
├── sudoers.txt, usuarios_con_login.txt, puertos_escucha.txt, paquetes_instalados.txt
├── inventario_suid_sgid.txt, ...
└── fwbuilder/                    # copia de los scripts .fw encontrados
```

**Resultado de cada control:**

| Marca | Significado |
|---|---|
| `PASS` | Cumple; suma sus puntos |
| `FAIL` | No cumple; 0 puntos |
| `N/A` | No aplica (por ejemplo, IPv6 deshabilitado o `sshd` no instalado); suma sus puntos |

**Nivel de cumplimiento:** 85 % o más = ALTO · 60 % a 84 % = MEDIO · menos de 60 % = BAJO. Este nivel solo se refiere a los controles evaluados.

**Verificar la integridad de una auditoría:**

```bash
sha256sum -c lynx_reporte_<fecha>.txt.sha256
cd lynx_evidencias_<fecha> && sha256sum -c SHA256SUMS
```

---

## ¿Quién puede usarlo?

- **Administradores de sistemas y equipos de infraestructura** que necesitan una revisión rápida y repetible de servidores Debian/Ubuntu.
- **Auditores internos y consultores de seguridad** que requieren evidencia con hash de la configuración de red, firewall, cuentas y permisos.
- **Equipos con firewalls legados basados en fwbuilder**, especialmente durante migraciones de iptables-legacy a nftables, donde es fácil dejar reglas en un backend distinto del esperado.
- **Equipos DevSecOps y de operaciones** que quieran integrar un chequeo pasivo en revisiones periódicas.
- **Estudiantes y docentes** de seguridad informática y administración de Linux, como ejemplo de controles de hardening explicados en el propio código.

**Conocimientos necesarios:** manejo básico de la terminal, uso de `sudo` y nociones de firewall (iptables/nftables) para interpretar los resultados.

**No es adecuado como única evidencia** si necesitas demostrar cumplimiento formal (CIS, ISO 27001, PCI DSS, etc.): úsalo como complemento, no como sustituto.

---


## 🔵 Comparación honesta con otras herramientas

---

## Lynx frente a otras herramientas
```markdown
| Herramienta | Enfoque | Cuándo usarla |
|---|---|---|
| **Lynx** | 29 controles, evidencias con hash, firewalls legacy + fwbuilder | Revisión rápida, pre-auditoría, migraciones de firewall |
| Lynis | Auditoría general más amplia, sin foco en firewalls legacy | Primera pasada de hardening |
| OpenSCAP / CIS-CAT | Cumplimiento formal CIS/STIG | Certificación, reporting regulatorio |
| auditd + osquery | Monitorización continua | Producción, forense |
```
Lynx **complementa** estas herramientas; no las sustituye.

---

## Códigos de salida

```markdown
| Código | Significado |
|---|---|
| `0` | Auditoría completada, puntaje ≥ 85 % |
| `1` | Auditoría completada, puntaje entre 60 % y 84 % |
| `2` | Auditoría completada, puntaje < 60 % |
| `3` | Error de ejecución (permisos, dependencias, etc.) |
```
---

## Limitaciones

- **Cobertura acotada:** 29 controles puntuables. No evalúan filesystems y particionado, políticas de contraseñas y PAM, la mayoría de los parámetros de `sshd`, auditd, logging ni integridad de archivos. Parches, AppArmor, auditd y sudoers se listan como información, pero no puntúan.
- **No es una certificación CIS.** Algunos controles se parecen a recomendaciones del CIS Benchmark, pero difieren en criterios (por ejemplo, Lynx acepta `PermitRootLogin prohibit-password`, mientras CIS exige `no`).
- **Debian 13:** los análisis están probados con datos simulados; falta validación en equipos reales.
- **sshd:** si `sshd -T` falla, Lynx lee `sshd_config` de forma estática y no interpreta bloques `Match`.
- **Parches:** el conteo depende de la caché de apt; Lynx no ejecuta `apt update` porque sería una acción activa. Avisa cuando la caché es antigua.
- **Inventarios con `find`:** pueden tardar en discos grandes; se limitan por tiempo y el resultado puede quedar incompleto (queda indicado en el archivo).
- **Detección de fwbuilder:** es heurística (busca la cadena "Firewall Builder" en scripts `*.fw` y de arranque).
- **Falsos positivos posibles:** un equipo que enruta a propósito falla `ip_forward` salvo que uses `ES_ROUTER=1`. Los controles reflejan buenas prácticas generales, no la política de tu organización.

---

## Seguridad de los datos generados

Las evidencias contienen información sensible: reglas de firewall, procesos en escucha, configuración de `sudoers`, listas de usuarios, llaves SSH autorizadas (solo conteo y permisos) y paquetes instalados. Lynx **no** copia hashes de contraseñas. Aun así, protege el directorio de evidencias, cífralo antes de enviarlo por canales no seguros y elimínalo cuando ya no sea necesario.

---

## Uso responsable

Ejecuta Lynx únicamente en sistemas propios o con autorización expresa del propietario. Aunque la herramienta solo lee información, la auditoría de sistemas ajenos sin permiso puede ser ilegal en tu jurisdicción. El software se ofrece "tal cual", sin garantías.

---

## Roadmap

- [ ] Validación en Debian 13 real
- [ ] Códigos de salida para CI
- [ ] Salida en JSON (`--format=json`)
- [ ] Cobertura de `auditd` y PAM
- [ ] Envío opcional del reporte por correo electrónico 

---

## Contribuir

Las contribuciones son bienvenidas: abre un *issue* para reportar errores o proponer controles y un *pull request* para cambios de código. Antes de enviarlo:

```bash
bash -n lynx.sh
shellcheck lynx.sh
```

Mantén el carácter **pasivo** del script: los controles nuevos deben ser de solo lectura.

---

## 📜 Licencia

LYNX se distribuye bajo la **Apache License 2.0**.

Esto significa que puedes usar, copiar, modificar, distribuir y vender el software libremente, siempre que incluyas una copia de la licencia, conserves los avisos de copyright y atribución, e incluyas una copia del archivo `NOTICE` si el proyecto lo contiene.

Además, la Apache License 2.0 incluye una **concesión explícita de patentes**, lo que te protege frente a posibles reclamaciones por parte de contribuidores.

El software se proporciona **"tal cual"**, sin garantía de ningún tipo.

Consulta [`LICENSE`](LICENSE) y [`NOTICE`](NOTICE) para conocer los términos completos.
