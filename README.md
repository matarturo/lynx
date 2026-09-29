# Lynx

**Auditor pasivo de seguridad y red para Debian y Ubuntu.**

Lynx es un **script de Bash** que revisa, en modo solo lectura, la configuración de seguridad de un servidor Debian/Ubuntu: parámetros del kernel, firewall (iptables-legacy, iptables-nft, nftables y scripts de **Firewall Builder / fwbuilder**), SSH, cuentas de usuario y permisos críticos. Muestra un reporte en pantalla, calcula un puntaje y guarda evidencias verificables con hash SHA-256 para el auditor.

> **Alcance:** Lynx es una herramienta de revisión rápida, no una certificación. Evalúa 29 controles puntuables y no reemplaza a un análisis completo de cumplimiento (por ejemplo, CIS Benchmark con OpenSCAP o CIS-CAT). Ver [Limitaciones](#limitaciones).

---

## Datos básicos

| | |
|---|---|
| **Nombre** | Lynx |
| **Versión** | 3.0 |
| **Lenguaje** | Bash (5.x recomendado; mínimo 4.4) |
| **Sistemas objetivo** | Debian 12 / 13 y derivados, Ubuntu (LTS recientes) |
| **Privilegios** | Requiere `root` (lee `/etc/shadow`, reglas de firewall y configuración de kernel) |
| **Naturaleza** | Pasivo: no modifica configuración, no instala ni elimina paquetes |
| **Salida** | Reporte `.txt` sin colores, directorio de evidencias y hashes SHA-256 |
| **Licencia** | *Por definir* (añade un archivo `LICENSE` antes de publicar) |

### Estado de las pruebas

- Verificado con `bash -n` y `shellcheck` sin advertencias.
- Ejecutado de extremo a extremo en Ubuntu 24.04 (entorno de pruebas sin systemd, iptables, nft ni sshd). Los análisis de firewall se probaron con volcados simulados de fwbuilder, iptables-legacy, iptables-nft y nftables nativo.
- **Pendiente:** validación en servidores Debian 13 reales. Ejecútalo primero en un equipo de prueba.

---

## Qué revisa

### Secciones que puntúan (100 puntos, 29 controles)

| # | Sección | Peso | Ejemplos de controles |
|---|---|---|---|
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

### Variables de entorno

| Variable | Efecto |
|---|---|
| `REPORT_DIR=/ruta` | Directorio donde se guardan el reporte y las evidencias (por defecto, el directorio actual) |
| `ES_ROUTER=1` | El equipo enruta a propósito: `ip_forward=1` se marca como N/A en lugar de fallo |
| `SIN_EVIDENCIAS=1` | No guarda volcados crudos; solo genera el reporte |
| `SKIP_SLOW=1` | Omite los inventarios con `find` (SUID, world-writable, huérfanos) |
| `TIMEOUT_FIND=60` | Segundos máximos por inventario con `find` (por defecto 60) |

### Ejemplos


# Auditoría estándar, guardando los resultados en un directorio propio

```bash
sudo mkdir -p /var/lib/lynx && sudo REPORT_DIR=/var/lib/lynx ./lynx.sh
```
# Revisión rápida (sin inventarios lentos ni evidencias crudas)
```bash
sudo SKIP_SLOW=1 SIN_EVIDENCIAS=1 ./lynx.sh
```
# Servidor que actúa como router/firewall de red

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

## ¿Quién puede usarlo? (público objetivo)

- **Administradores de sistemas y equipos de infraestructura** que necesitan una revisión rápida y repetible de servidores Debian/Ubuntu.
- **Auditores internos y consultores de seguridad** que requieren evidencia con hash de la configuración de red, firewall, cuentas y permisos.
- **Equipos con firewalls legados basados en fwbuilder**, especialmente durante migraciones de iptables-legacy a nftables, donde es fácil dejar reglas en un backend distinto del esperado.
- **Equipos DevSecOps y de operaciones** que quieran integrar un chequeo pasivo en revisiones periódicas.
- **Estudiantes y docentes** de seguridad informática y administración de Linux, como ejemplo de controles de hardening explicados en el propio código.

**Conocimientos necesarios:** manejo básico de la terminal, uso de `sudo` y nociones de firewall (iptables/nftables) para interpretar los resultados.

**No es adecuado como única evidencia** si necesitas demostrar cumplimiento formal (CIS, ISO 27001, PCI DSS, etc.): úsalo como complemento, no como sustituto.

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

## Contribuir

Las contribuciones son bienvenidas: abre un *issue* para reportar errores o proponer controles y un *pull request* para cambios de código. Antes de enviarlo:

```bash
bash -n lynx.sh
shellcheck lynx.sh
```

Mantén el carácter **pasivo** del script: los controles nuevos deben ser de solo lectura.

## 📜 Licencia

LYNX se distribuye bajo la **Apache License 2.0**.

Esto significa que puedes usar, copiar, modificar, distribuir y vender el software libremente, siempre que incluyas una copia de la licencia, conserves los avisos de copyright y atribución, e incluyas una copia del archivo `NOTICE` si el proyecto lo contiene.

Además, la Apache License 2.0 incluye una **concesión explícita de patentes**, lo que te protege frente a posibles reclamaciones por parte de contribuidores.

El software se proporciona **"tal cual"**, sin garantía de ningún tipo.

Consulta [`LICENSE`](LICENSE) y [`NOTICE`](NOTICE) para conocer los términos completos.
