#!/usr/bin/env bash
#
# ==============================================================================
# LYNX - AUDITOR DE SEGURIDAD PASIVO Y RED (DEBIAN 12/13 / UBUNTU)  -  v3
# AUTOR: ARTURO MATA
# EMAIL: ARTURO.MATA@GMAIL.COM
# Revisa: sysctl, firewall (iptables-legacy / iptables-nft / nftables / fwbuilder),
#         stack de red, SSH, usuarios y permisos.
# Genera un reporte en pantalla y guarda evidencias en un .txt (sin colores).
#
# Uso:   sudo ./lynx.sh        (ayuda: ./lynx.sh --help)
# Vars:  REPORT_DIR=/ruta   directorio base (por defecto: /var/lib/lynx/<host>)
#        LYNX_FLAT=1        no añade subdirectorio por host
#        ES_ROUTER=1        el host enruta a proposito: ip_forward=1 se marca N/A
#        SIN_EVIDENCIAS=1   no guarda volcados crudos (solo el reporte)
#        SKIP_SLOW=1        omite inventarios con find (SUID, world-writable, huerfanos)
#        TIMEOUT_FIND=60    segundos maximos por inventario find
#
# Es pasivo: solo lee (/proc, iptables-*-save, nft list ruleset, archivos, apt -s).
# Escribe unicamente: el reporte (600), el directorio lynx_evidencias_<fecha>/ (700) y
# los archivos de hash SHA-256. Las secciones 1-6 puntuan; la 7 es informativa.
# ==============================================================================
# Copyright 2026 Arturo Mata - JØKΣR
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
umask 077

LYNX_VERSION="3.0"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")_$$

# Directorio de trabajo por defecto: histórico persistente bajo FHS.
# Se puede sobrescribir con REPORT_DIR=/otra/ruta (útil para CI o pruebas).
REPORT_DIR_DEFAULT="/var/lib/lynx"
REPORT_DIR="${REPORT_DIR:-$REPORT_DIR_DEFAULT}"

# Subdirectorio por host: permite centralizar auditorías de varios servidores
# en un mismo directorio si se sincroniza (rsync, NFS, etc.).
# Se sanitiza el nombre por si hostname devuelve cadenas vacías o con
# caracteres raros (contenedores mal configurados).
HOSTNAME_SHORT=$(hostname -s 2>/dev/null | tr -cd 'a-zA-Z0-9-_.')
[[ -z "$HOSTNAME_SHORT" ]] && HOSTNAME_SHORT="unknown"

if [[ "${LYNX_FLAT:-0}" == "1" ]]; then
    REPORT_DIR="${REPORT_DIR}"
else
    REPORT_DIR="${REPORT_DIR}/${HOSTNAME_SHORT}"
fi

REPORT_FILE="${REPORT_DIR}/lynx_reporte_${TIMESTAMP}.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PUNTOS_ACTUALES=0
PUNTOS_MAXIMOS=0
TOTAL_CHECKS=0
FALLOS=()

# ------------------------------------------------------------------------------
# Utilidades generales
# ------------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------------------
# Inicializa el directorio de reportes de forma idempotente:
#   - Lo crea la primera vez.
#   - Si ya existe, NO lo borra ni lo sobrescribe: solo verifica permisos.
#   - Seguro de ejecutar en cada auditoría recurrente.
# ------------------------------------------------------------------------------
init_report_dir() {
    # Si ya existe, no hacemos nada destructivo: solo verificamos permisos.
    if [[ -d "$REPORT_DIR" ]]; then
        local mode owner
        mode=$(stat -c %a "$REPORT_DIR" 2>/dev/null)
        owner=$(stat -c %U "$REPORT_DIR" 2>/dev/null)
        if [[ "$mode" != "750" && "$mode" != "700" && "$mode" != "755" ]]; then
            echo "[i] Aviso: $REPORT_DIR tiene permisos $mode (recomendado 750)." >&2
        fi
        if [[ "$owner" != "root" ]]; then
            echo "[i] Aviso: $REPORT_DIR pertenece a '$owner' (recomendado root)." >&2
        fi
        return 0
    fi

    # Primera ejecución: crear la estructura completa.
    if ! mkdir -p "$REPORT_DIR" 2>/dev/null; then
        echo "[!] No se puede crear $REPORT_DIR. Use REPORT_DIR=/otra/ruta" >&2
        exit 1
    fi

    # root:adm 750 es el estándar para /var/lib con datos sensibles:
    # root escribe, el grupo adm puede leer sin necesitar sudo.
    chown root:adm "$REPORT_DIR" 2>/dev/null || chown root:root "$REPORT_DIR" 2>/dev/null
    chmod 750 "$REPORT_DIR"

    echo "[i] Directorio de reportes creado: $REPORT_DIR"
}

# Salida dual: consola con color / archivo sin secuencias ANSI
log() {
    printf '%b\n' "$1"
    printf '%b\n' "$1" | sed 's/\x1B\[[0-9;]*[mK]//g' >> "$REPORT_FILE"
}

# Codigos de retorno de los checks: 0 = PASS, 77 = N/A (otorga puntos), otro = FAIL
check_item() {
    local desc="$1" peso="$2" rc=0
    shift 2
    PUNTOS_MAXIMOS=$((PUNTOS_MAXIMOS + peso))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    "$@" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0) PUNTOS_ACTUALES=$((PUNTOS_ACTUALES + peso))
           log "[${GREEN}PASS${NC}] +${peso} pts | $desc" ;;
        77) PUNTOS_ACTUALES=$((PUNTOS_ACTUALES + peso))
           log "[${YELLOW}N/A ${NC}] +${peso} pts | $desc (no aplica)" ;;
        *) FALLOS+=("$desc")
           log "[${RED}FAIL${NC}]   0 pts | $desc" ;;
    esac
}

# ------------------------------------------------------------------------------
# Lectura de sysctl directamente desde /proc/sys (no requiere el binario sysctl)
# ------------------------------------------------------------------------------
sv_get() {
    local path="/proc/sys/${1//.//}"
    [[ -r "$path" ]] || return 1
    cat "$path"
}
sv_eq() { local v; v=$(sv_get "$1") || return 1; [[ "$v" == "$2" ]]; }
sv_ge() { local v; v=$(sv_get "$1") || return 1; [[ "$v" =~ ^[0-9]+$ ]] && (( v >= $2 )); }

ipv6_enabled() {
    [[ -e /proc/net/if_inet6 ]] && [[ "$(sv_get net.ipv6.conf.all.disable_ipv6 2>/dev/null)" != "1" ]]
}
sv6_eq() { ipv6_enabled || return 77; sv_eq "$1" "$2"; }

chk_accept_redirects() {
    sv_eq net.ipv4.conf.all.accept_redirects 0 && sv_eq net.ipv4.conf.default.accept_redirects 0
}
chk_ip_forward() {
    [[ "${ES_ROUTER:-0}" == "1" ]] && return 77
    sv_eq net.ipv4.ip_forward 0
}

# ------------------------------------------------------------------------------
# Recoleccion de reglas de firewall (solo lectura), por backend:
#   iptables-legacy  -> iptables-legacy-save   (solo si hay tablas cargadas)
#   iptables-nft     -> iptables-nft-save      (traduce a nftables)
#   nftables nativo  -> nft list ruleset       (incluye lo de iptables-nft)
# fwbuilder genera scripts que invocan "iptables" con "-m state --state ...";
# segun /etc/alternatives eso termina en legacy o en nft, por eso se leen ambos.
# ------------------------------------------------------------------------------
IPT4_LEG=""; IPT4_NFT=""; IPT4_GEN=""
IPT6_LEG=""; IPT6_NFT=""; IPT6_GEN=""
NFT_RS=""; ALL4=""; ALL6=""; FILT4=""

# Extrae solo las lineas de una tabla (ej. filter) de un volcado iptables-save
ipt_table() { awk -v t="$2" '/^\*/ {cur=substr($0,2)} cur==t' <<<"$1"; }

collect_firewall() {
    if have iptables-legacy-save && [[ -n "$(cat /proc/net/ip_tables_names 2>/dev/null)" ]]; then
        IPT4_LEG=$(iptables-legacy-save 2>/dev/null)
    fi
    if have ip6tables-legacy-save && [[ -n "$(cat /proc/net/ip6_tables_names 2>/dev/null)" ]]; then
        IPT6_LEG=$(ip6tables-legacy-save 2>/dev/null)
    fi
    if have iptables-nft-save;  then IPT4_NFT=$(iptables-nft-save 2>/dev/null);   fi
    if have ip6tables-nft-save; then IPT6_NFT=$(ip6tables-nft-save 2>/dev/null); fi
    # Sistemas antiguos sin variantes -legacy/-nft
    if ! have iptables-legacy-save && ! have iptables-nft-save && have iptables-save; then
        IPT4_GEN=$(iptables-save 2>/dev/null)
    fi
    if ! have ip6tables-legacy-save && ! have ip6tables-nft-save && have ip6tables-save; then
        IPT6_GEN=$(ip6tables-save 2>/dev/null)
    fi
    if have nft; then NFT_RS=$(nft list ruleset 2>/dev/null); fi

    ALL4="${IPT4_LEG}"$'\n'"${IPT4_NFT}"$'\n'"${IPT4_GEN}"
    ALL6="${IPT6_LEG}"$'\n'"${IPT6_NFT}"$'\n'"${IPT6_GEN}"
    FILT4=$(ipt_table "$ALL4" filter)
}

# --- Analizadores -------------------------------------------------------------
# Regla stateful en formato iptables-save: acepta ESTABLISHED y RELATED con
# "-m conntrack --ctstate" o con el modulo antiguo "-m state --state" (fwbuilder)
ipt_stateful() {
    awk '/^-A / && /-j ACCEPT/ {
            if (match($0, /(--ctstate|--state) [A-Z,]+/)) {
                t = substr($0, RSTART, RLENGTH)
                if (t ~ /ESTABLISHED/ && t ~ /RELATED/) f = 1
            }
         } END { exit !f }' <<<"$1"
}
# Regla stateful en nftables: "ct state established,related accept"
nft_stateful() {
    awk '/ct state/ && /established/ && /related/ && /accept/ { f = 1 } END { exit !f }' <<<"$1"
}
# Hay reglas reales en nft (se ignoran las lineas de declaracion de hook/policy)
nft_has_rules() {
    grep -v 'hook' <<<"$NFT_RS" | grep -Eq '\b(accept|drop|reject|jump|goto|masquerade|dnat|snat|redirect)\b'
}
# Reglas IPv6 en tablas ip6 / inet de nft
nft_v6_rules() {
    awk '/^table (ip6|inet) / {t=1; next}
         /^table / {t=0}
         t && !/hook/ && /(accept|drop|reject|jump|goto)/ {f=1}
         END { exit !f }' <<<"$NFT_RS"
}
# La ultima regla de la cadena termina en DROP/REJECT, siguiendo saltos a cadenas
# de usuario (patron tipico de fwbuilder: -A INPUT -j RULE_N ... -A RULE_N -j DROP)
chain_terminal_deny() {
    local dump="$1" chain="$2" depth="${3:-0}" last tgt re_deny re_jump
    (( depth > 5 )) && return 1
    last=$(awk -v c="$chain" '$1=="-A" && $2==c {l=$0} END{print l}' <<<"$dump")
    [[ -n "$last" ]] || return 1
    re_deny="^-A ${chain} -j (DROP|REJECT)( |\$)"
    re_jump="^-A ${chain} -j ([A-Za-z0-9_.-]+)\$"
    if [[ "$last" =~ $re_deny ]]; then return 0; fi
    if [[ "$last" =~ $re_jump ]]; then
        tgt="${BASH_REMATCH[1]}"
        case "$tgt" in ACCEPT|RETURN|LOG) return 1 ;; esac
        chain_terminal_deny "$dump" "$tgt" $((depth + 1))
        return $?
    fi
    return 1
}

# --- Checks de firewall -------------------------------------------------------
chk_fw_rules_loaded() { grep -q '^-A ' <<<"$ALL4" || nft_has_rules; }
chk_fw_stateful()     { ipt_stateful "$FILT4" || nft_stateful "$NFT_RS"; }
chk_fw_input_deny() {
    grep -Eq '^:INPUT (DROP|REJECT)' <<<"$FILT4" && return 0
    chain_terminal_deny "$FILT4" INPUT && return 0
    grep -Eq 'hook input .*policy drop' <<<"$NFT_RS"
}
chk_fw_forward_deny() {
    [[ "$(sv_get net.ipv4.ip_forward 2>/dev/null)" == "0" ]] && return 77
    grep -Eq '^:FORWARD (DROP|REJECT)' <<<"$FILT4" && return 0
    chain_terminal_deny "$FILT4" FORWARD && return 0
    grep -Eq 'hook forward .*policy drop' <<<"$NFT_RS"
}
chk_fw_ipv6() {
    ipv6_enabled || return 77
    grep -Eq '^(-A |:INPUT (DROP|REJECT))' <<<"$ALL6" && return 0
    nft_v6_rules
}

# --- Checks de stack de red ---------------------------------------------------
chk_conntrack() {
    [[ -d /sys/module/nf_conntrack || -d /sys/module/ip_conntrack ]] \
        || [[ -e /proc/sys/net/netfilter/nf_conntrack_max ]]
}
chk_bridge_nf() {
    compgen -G '/sys/class/net/*/bridge' >/dev/null || return 77
    sv_eq net.bridge.bridge-nf-call-iptables 1
}

# --- SSH ----------------------------------------------------------------------
SSHD_T=""
sshd_get() {
    local k="$1" v=""
    if [[ -n "$SSHD_T" ]]; then
        v=$(awk -v k="$k" 'tolower($1)==k {print tolower($2); exit}' <<<"$SSHD_T")
    else
        # Respaldo si "sshd -T" falla (ej. falta /run/sshd): lectura estatica.
        # Limitacion: no interpreta bloques Match.
        v=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null \
            | awk -v k="$k" '/^[[:space:]]*#/ {next} tolower($1)==k {print tolower($2); exit}')
    fi
    printf '%s' "$v"
}
chk_ssh_root() {
    have sshd || return 77
    local v; v=$(sshd_get permitrootlogin); v="${v:-prohibit-password}"
    [[ "$v" =~ ^(no|prohibit-password|without-password|forced-commands-only)$ ]]
}
chk_ssh_passwd() {
    have sshd || return 77
    local v; v=$(sshd_get passwordauthentication); v="${v:-yes}"
    [[ "$v" == "no" ]]
}

# --- Hardening general --------------------------------------------------------
# Un "blacklist" no impide cargar el modulo manualmente; "install X /bin/true" si.
chk_modules_blocked() {
    local m
    for m in dccp rds tipc; do
        grep -RqsE "^[[:space:]]*install[[:space:]]+${m}[[:space:]]+(/usr)?/bin/(true|false)" \
            /etc/modprobe.d /usr/lib/modprobe.d /lib/modprobe.d 2>/dev/null || return 1
    done
    return 0
}
chk_coredumps() {
    grep -RqsE '^[[:space:]]*\*[[:space:]]+hard[[:space:]]+core[[:space:]]+0' \
        /etc/security/limits.conf /etc/security/limits.d 2>/dev/null && return 0
    grep -RqsiE '^[[:space:]]*Storage[[:space:]]*=[[:space:]]*none' \
        /etc/systemd/coredump.conf /etc/systemd/coredump.conf.d 2>/dev/null
}

# --- Usuarios -----------------------------------------------------------------
chk_uid0_unico()   { awk -F: '$3==0 {c++} END {exit !(c==1)}' /etc/passwd; }
chk_sin_pass_vacia() { awk -F: '$2=="" {f=1} END {exit f}' /etc/shadow; }
# En Debian, sync/shutdown/halt tienen shells especiales por diseno: se toleran.
chk_shells_sistema() {
    awk -F: '$3<1000 && $1!="root" && $7 !~ /(nologin|false|\/bin\/sync|\/sbin\/halt|\/sbin\/shutdown)$/ {f=1} END {exit f}' /etc/passwd
}

# --- Permisos -----------------------------------------------------------------
chk_perm_shadow() {
    [[ "$(stat -c %U /etc/shadow)" == "root" ]] && [[ "$(stat -c %a /etc/shadow)" =~ ^(0|400|600|640)$ ]]
}
chk_perm_passwd() {
    [[ "$(stat -c %U /etc/passwd)" == "root" ]] && [[ "$(stat -c %a /etc/passwd)" =~ ^(400|444|600|640|644)$ ]]
}
WW_LIST=""
# Se ignoran directorios con sticky bit (ej. /var/tmp, /var/crash): son normales
chk_worldwritable() {
    WW_LIST=$(find /etc /var /usr -xdev -maxdepth 3 -type d -perm -0002 ! -perm -1000 2>/dev/null | head -5)
    [[ -z "$WW_LIST" ]]
}

# --- Informativos -------------------------------------------------------------
count_rules() { local n; n=$(grep -c '^-A ' <<<"$1"); printf '%s' "${n:-0}"; }

info_firewall() {
    local alt fwb_f fwb_b
    alt=$(readlink -f "$(command -v iptables 2>/dev/null)" 2>/dev/null)
    log "\n  [i] Backends de firewall detectados:"
    log "      - Binario iptables       : ${alt:-no instalado}"
    log "      - Reglas iptables-legacy : $(count_rules "$IPT4_LEG") (IPv4) / $(count_rules "$IPT6_LEG") (IPv6)"
    log "      - Reglas iptables-nft    : $(count_rules "$IPT4_NFT") (IPv4) / $(count_rules "$IPT6_NFT") (IPv6)"
    if have nft; then
        if nft_has_rules; then log "      - nftables (ruleset)     : con reglas"
        else                   log "      - nftables (ruleset)     : sin reglas"; fi
    else
        log "      - nftables (ruleset)     : binario 'nft' no instalado"
    fi
    if [[ "$(count_rules "$IPT4_LEG")" -gt 0 ]] && { [[ "$(count_rules "$IPT4_NFT")" -gt 0 ]] || nft_has_rules; }; then
        log "      - ${YELLOW}AVISO:${NC} hay reglas en legacy Y en nft a la vez; conviene unificar el backend."
    fi

    # fwbuilder
    detect_fwbuilder
    fwb_f=$(paste -sd' ' <<<"$FWB_FILES"); fwb_b=$(paste -sd' ' <<<"$FWB_BOOT")
    log "\n  [i] fwbuilder:"
    log "      - Paquete instalado      : ${FWB_PKG:-no}"
    log "      - Scripts .fw generados  : ${fwb_f:-ninguno encontrado}"
    log "      - Arranque persistente   : ${fwb_b:-no detectado (revisar como se cargan las reglas al reiniciar)}"
    if [[ -n "$FWB_FILES$FWB_BOOT" ]] && ! chk_fw_rules_loaded; then
        log "      - ${RED}ALERTA:${NC} hay scripts fwbuilder pero NO hay reglas cargadas (¿falta el binario iptables o no se ejecuto el script?)."
    fi
}

info_red() {
    log "\n  [i] Bridging / Bonding (informativo, no puntua):"
    local br bonds
    br=$(compgen -G '/sys/class/net/*/bridge' | awk -F/ '{print $5}' | tr '\n' ' ')
    bonds=$(ls /proc/net/bonding 2>/dev/null | tr '\n' ' ')
    log "      - Bridges : ${br:-ninguno}"
    log "      - Bonds   : ${bonds:-ninguno}"
}

# ------------------------------------------------------------------------------
# DETECCION DE FWBUILDER (globales usadas por info_firewall y por las evidencias)
# ------------------------------------------------------------------------------
FWB_PKG=""; FWB_FILES=""; FWB_BOOT=""
detect_fwbuilder() {
    if dpkg-query -W -f='${Status}' fwbuilder 2>/dev/null | grep -q 'install ok installed'; then
        FWB_PKG=$(dpkg-query -W -f='${Version}' fwbuilder 2>/dev/null)
    fi
    FWB_FILES=$(find /etc /root /opt /usr/local -maxdepth 4 -type f -name '*.fw' 2>/dev/null \
                | while read -r f; do grep -qs 'Firewall Builder' "$f" && echo "$f"; done | head -5)
    FWB_BOOT=$(grep -rlsI 'Firewall Builder' /etc/init.d /etc/network /etc/systemd/system /etc/rc.local 2>/dev/null | head -5)
}

# ------------------------------------------------------------------------------
# PERSISTENCIA DEL FIREWALL: ¿las reglas cargadas ahora sobreviven a un reinicio?
# Informativo (no puntua): busca servicios habilitados, archivos de reglas
# persistentes, scripts de arranque y unidades systemd propias.
# ------------------------------------------------------------------------------
info_fw_persistencia() {
    local -a found=()
    local u f
    if have systemctl && [[ -d /run/systemd/system ]]; then
        for u in nftables netfilter-persistent ufw firewalld; do
            systemctl is-enabled "$u" >/dev/null 2>&1 && found+=("servicio systemd: $u (enabled)")
        done
        while read -r f; do
            [[ -n "$f" ]] && found+=("unidad systemd propia: $f")
        done < <(grep -lsE 'ExecStart=.*(iptables|ip6tables|nft[[:space:]])' /etc/systemd/system/*.service 2>/dev/null)
    fi
    for f in /etc/iptables/rules.v4 /etc/iptables/rules.v6; do
        [[ -s "$f" ]] && found+=("$f (iptables-persistent)")
    done
    for f in /etc/network/if-pre-up.d/* /etc/network/if-up.d/* /etc/rc.local; do
        if [[ -f "$f" ]] && grep -qsE 'iptables|ip6tables|nft[[:space:]]' "$f"; then
            found+=("script de arranque: $f")
        fi
    done
    while read -r f; do
        [[ -n "$f" ]] && found+=("fwbuilder: $f")
    done <<<"$FWB_BOOT"

    log "\n  [i] Persistencia del firewall (¿se cargan las reglas al reiniciar?):"
    if [[ "${#found[@]}" -gt 0 ]]; then
        for f in "${found[@]}"; do log "      - $f"; done
    else
        log "      - ningún mecanismo detectado"
        if chk_fw_rules_loaded; then
            log "      - ${RED}ALERTA:${NC} hay reglas cargadas pero sin mecanismo de persistencia; podrían perderse al reiniciar."
        fi
    fi
}

# ------------------------------------------------------------------------------
# EVIDENCIAS Y INFORMACION COMPLEMENTARIA PARA EL AUDITOR (no puntuan)
# Los volcados crudos se guardan en un directorio aparte (700), con SHA256SUMS.
# ------------------------------------------------------------------------------
EVID_DIR=""
init_evidence() {
    [[ "${SIN_EVIDENCIAS:-0}" == "1" ]] && return 0
    EVID_DIR="${REPORT_DIR}/lynx_evidencias_${TIMESTAMP}"
    # El timestamp incluye segundos, así que colisiones solo si se ejecuta
    # dos veces en el mismo segundo. En ese caso, mkdir falla y se avisa.
    if ! mkdir "$EVID_DIR" 2>/dev/null; then
        echo "[!] Ya existe $EVID_DIR (¿dos ejecuciones en el mismo segundo?)." >&2
        EVID_DIR=""
        return 1
    fi
    chmod 700 "$EVID_DIR"
}
# evid <nombre> <comando...> : guarda la salida del comando (o una nota si no existe)
evid() {
    [[ -n "$EVID_DIR" ]] || return 0
    local name="$1"; shift
    if ! have "$1"; then
        echo "# comando no disponible: $1" > "$EVID_DIR/$name.txt"
        return 0
    fi
    { echo "# \$ $*"; echo "# $(date -u +%Y-%m-%dT%H:%M:%SZ)"; "$@" 2>&1; } > "$EVID_DIR/$name.txt"
}
# evid_var <nombre> <contenido> : guarda contenido ya capturado (omite si esta vacio)
evid_var() {
    [[ -n "$EVID_DIR" && -n "${2:-}" ]] || return 0
    printf '%s\n' "$2" > "$EVID_DIR/$1.txt"
}
count_lines() { local n; n=$(grep -c '^[0-9]' <<<"$1"); printf '%s' "${n:-0}"; }

# --- Inventarios --------------------------------------------------------------
inv_login_users() {
    awk -F: '$7 !~ /(nologin|false|\/bin\/sync|\/sbin\/halt|\/sbin\/shutdown)$/ {printf "%s uid=%s shell=%s home=%s\n",$1,$3,$7,$6}' /etc/passwd
}
inv_sudoers() {
    local f
    for f in /etc/sudoers /etc/sudoers.d/*; do
        [[ -f "$f" ]] || continue
        echo "### $f"
        grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null
    done
}
# Envejecimiento de contrasenas SIN mostrar hashes (solo usuario y vigencia maxima)
inv_pass_aging() {
    awk -F: '$2 !~ /^[!*]/ && $2 != "" {printf "%s maxdias=%s ultimo_cambio_dias_epoch=%s\n",$1,$5,$3}' /etc/shadow
}
inv_authkeys() {
    local f n
    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
        [[ -f "$f" ]] || continue
        n=$(grep -cvE '^[[:space:]]*(#|$)' "$f")
        printf '%s perms=%s owner=%s llaves=%s\n' "$f" "$(stat -c %a "$f")" "$(stat -c %U "$f")" "$n"
    done
}
# Inventarios con find: solo sistemas de archivos locales, con limite de tiempo
find_local() {
    local -a mps=()
    mapfile -t mps < <(findmnt -rno TARGET -t ext2,ext3,ext4,xfs,btrfs,f2fs 2>/dev/null)
    [[ ${#mps[@]} -gt 0 ]] || mps=(/)
    local rc=0
    timeout "${TIMEOUT_FIND:-60}" find "${mps[@]}" -xdev "$@" 2>/dev/null || rc=$?
    (( rc == 124 )) && echo "# INVENTARIO INCOMPLETO: timeout de ${TIMEOUT_FIND:-60}s"
    return 0
}
inv_suid()    { find_local -type f \( -perm -4000 -o -perm -2000 \) -printf '%m %u:%g %p\n'; }
inv_wwfiles() { find_local -type f -perm -0002 -printf '%m %u:%g %p\n'; }
inv_unowned() { find_local \( -nouser -o -nogroup \) -printf '%m %u:%g %p\n'; }

pk_inseguros() {
    dpkg-query -W -f='${Package} ${db:Status-Status}\n' telnet telnetd inetutils-telnetd \
        rsh-client rsh-server nis ypbind talk talkd tftp tftpd xinetd 2>/dev/null \
        | awk '$2=="installed" {print $1}'
}
ntp_sync() {
    local v=""
    have timedatectl && v=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    case "$v" in yes) echo "sí" ;; no) echo "NO" ;; *) echo "n/d" ;; esac
}
info_mount() {
    local p="$1" tgt opts o miss="" origen
    # tail -1: si hay montajes apilados sobre la misma ruta, el efectivo es el ultimo
    tgt=$(findmnt -no TARGET -T "$p" 2>/dev/null | tail -1)
    opts=$(findmnt -no OPTIONS -T "$p" 2>/dev/null | tail -1)
    [[ -n "$tgt" ]] || { log "      - $p: sin datos"; return 0; }
    for o in nodev nosuid noexec; do [[ ",$opts," == *",$o,"* ]] || miss+="$o "; done
    if [[ "$tgt" == "$p" ]]; then origen="montaje propio"; else origen="hereda de $tgt"; fi
    log "      - $p: $origen | opciones que faltan: ${miss:-ninguna}"
}

seccion_complementaria() {
    local out n pub l g u f total sec stamp mt age aa

    # --- Sistema ---
    log "\n  [i] Sistema:"
    log "      - SO     : $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-desconocido}")"
    log "      - Kernel : $(uname -r) | $(uptime -p 2>/dev/null)"
    evid os_release cat /etc/os-release
    evid kernel uname -a
    evid uptime uptime
    evid paquetes_instalados dpkg-query -W -f='${Package}\t${Version}\n'

    # --- Red y puertos ---
    evid ip_direcciones ip -br addr
    evid ip_rutas_v4 ip route
    evid ip_rutas_v6 ip -6 route
    evid puertos_escucha ss -tulpn
    evid sysctl_completo sysctl -a
    if have ss; then
        n=$(ss -H -tuln 2>/dev/null | wc -l)
        pub=$(ss -H -tuln 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0|\[::\]|\*):/' | wc -l)
        log "\n  [i] Puertos en escucha: ${n} en total, ${pub} expuestos en todas las interfaces (proto local proceso):"
        while read -r l; do log "      - $l"; done < <(ss -H -tulpn 2>/dev/null | awk '{print $1, $5, $7}' | head -25)
    fi

    # --- Firewall: volcados crudos y scripts fwbuilder ---
    evid_var iptables_legacy_save   "$IPT4_LEG"
    evid_var ip6tables_legacy_save  "$IPT6_LEG"
    evid_var iptables_nft_save      "$IPT4_NFT"
    evid_var ip6tables_nft_save     "$IPT6_NFT"
    evid_var iptables_generic_save  "$IPT4_GEN"
    evid_var nft_ruleset            "$NFT_RS"
    evid iptables_alternativas update-alternatives --display iptables
    evid ufw_estado ufw status verbose
    if [[ -n "$EVID_DIR" && -n "$FWB_FILES" ]]; then
        mkdir -p "$EVID_DIR/fwbuilder"
        while read -r f; do
            [[ -f "$f" ]] && cp -p "$f" "$EVID_DIR/fwbuilder/$(tr '/' '_' <<<"$f")"
        done <<<"$FWB_FILES"
    fi

    # --- SSH ---
    evid_var sshd_config_efectiva "$SSHD_T"
    evid ssh_authorized_keys inv_authkeys

    # --- Usuarios y privilegios ---
    evid usuarios_con_login inv_login_users
    evid usuarios_uid0 awk -F: '$3==0 {print $1}' /etc/passwd
    evid grupos_privilegiados getent group sudo adm shadow docker
    evid sudoers inv_sudoers
    evid envejecimiento_contrasenas inv_pass_aging
    evid ultimos_accesos last -n 20 -w
    evid intentos_fallidos lastb -n 20 -w
    log "\n  [i] Usuarios y privilegios:"
    log "      - Cuentas con shell de login: $(inv_login_users | awk '{print $1}' | tr '\n' ' ')"
    n=$(inv_sudoers | grep -c 'NOPASSWD')
    if [[ "$n" -gt 0 ]]; then
        log "      - ${YELLOW}AVISO:${NC} sudoers con NOPASSWD en $n línea(s) (ver evidencia sudoers)."
    fi
    g=$(getent group docker 2>/dev/null | awk -F: '{print $4}')
    if [[ -n "${g:-}" ]]; then
        log "      - ${YELLOW}AVISO:${NC} miembros del grupo docker (equivale a root): $g"
    fi
    n=$(inv_pass_aging | grep -c 'maxdias=99999')
    log "      - Cuentas con contraseña que nunca expira (maxdias=99999): $n"

    # --- Servicios de seguridad y soporte ---
    evid servicios_activos systemctl list-units --type=service --state=running --no-pager
    evid servicios_habilitados systemctl list-unit-files --state=enabled --no-pager
    evid servicios_fallidos systemctl --failed --no-pager
    log "\n  [i] Servicios de seguridad y soporte (activo / habilitado):"
    if have systemctl && [[ -d /run/systemd/system ]]; then
        for u in ssh auditd rsyslog apparmor fail2ban unattended-upgrades cron chrony systemd-timesyncd nftables; do
            if systemctl list-unit-files "${u}.service" --no-legend 2>/dev/null | grep -q .; then
                log "      - $u: $(systemctl is-active "$u" 2>/dev/null) / $(systemctl is-enabled "$u" 2>/dev/null)"
            fi
        done
    else
        log "      - systemd no disponible en este sistema"
    fi
    if [[ -d /var/log/journal ]]; then g="sí"; else g="no (los logs de journald se pierden al reiniciar)"; fi
    log "      - Journald persistente : $g"
    log "      - Hora sincronizada    : $(ntp_sync)"

    # --- Control de acceso obligatorio ---
    aa=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
    if [[ "$aa" == "Y" ]]; then aa="activo"; else aa="NO activo"; fi
    log "\n  [i] Control de acceso obligatorio:"
    log "      - AppArmor: $aa"
    if have getenforce; then log "      - SELinux : $(getenforce 2>/dev/null)"; fi
    evid apparmor_estado aa-status

    # --- Parches (simulacion apt: no instala nada ni toma el lock) ---
    log "\n  [i] Parches:"
    if have apt-get; then
        out=$(apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null | grep '^Inst')
        evid_var actualizaciones_pendientes "$out"
        total=$(grep -c '^Inst' <<<"$out"); sec=$(grep -ci 'security' <<<"$out")
        stamp=/var/lib/apt/periodic/update-success-stamp
        [[ -e "$stamp" ]] || stamp=/var/lib/apt/lists
        mt=$(stat -c %Y "$stamp" 2>/dev/null)
        if [[ -n "$mt" ]]; then age=$(( ( $(date +%s) - mt ) / 86400 )); else age="?"; fi
        log "      - Paquetes con actualización pendiente: $total (de seguridad: $sec) según caché apt de hace $age día(s)"
        if [[ "$age" != "?" && "$age" -gt 7 ]]; then
            log "      - ${YELLOW}AVISO:${NC} la caché de apt es antigua; el conteo real puede ser mayor (apt update es una acción activa, no se ejecuta)."
        fi
        if [[ "$sec" -gt 0 ]]; then
            log "      - ${RED}ALERTA:${NC} hay actualizaciones de seguridad pendientes."
        fi
        if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q 'install ok installed'; then
            log "      - unattended-upgrades: instalado"
        else
            log "      - unattended-upgrades: no instalado"
        fi
    else
        log "      - apt-get no disponible"
    fi

    # --- Montajes ---
    evid montajes findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
    log "\n  [i] Opciones de montaje (nodev, nosuid, noexec):"
    for u in /tmp /var/tmp /dev/shm /home; do info_mount "$u"; done

    # --- Paquetes inseguros y cron ---
    evid cron_permisos stat -c '%a %U:%G %n' /etc/crontab /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly
    out=$(pk_inseguros | tr '\n' ' ')
    log "\n  [i] Paquetes de servicios inseguros instalados (telnet, rsh, nis, tftp, xinetd...): ${out:-ninguno}"
    if [[ -n "$out" ]]; then log "      - ${RED}ALERTA:${NC} conviene desinstalar: $out"; fi

    # --- Inventarios lentos (find) ---
    log "\n  [i] Inventarios de archivos (sistemas de archivos locales, límite ${TIMEOUT_FIND:-60}s c/u):"
    if [[ "${SKIP_SLOW:-0}" == "1" ]]; then
        log "      - omitidos (SKIP_SLOW=1)"
    else
        out=$(inv_suid);    evid_var inventario_suid_sgid "$out"
        log "      - Binarios SUID/SGID          : $(count_lines "$out")"
        out=$(inv_wwfiles); evid_var inventario_archivos_world_writable "$out"
        log "      - Archivos world-writable     : $(count_lines "$out")"
        out=$(inv_unowned); evid_var inventario_sin_propietario "$out"
        log "      - Archivos sin propietario    : $(count_lines "$out")"
    fi

    if [[ -n "$EVID_DIR" ]]; then
        log "\n  [i] Evidencias crudas en: ${EVID_DIR}"
        log "      ${YELLOW}Contienen datos sensibles (sudoers, procesos, reglas de firewall): proteja o cifre el directorio.${NC}"
    else
        log "\n  [i] Evidencias crudas deshabilitadas (SIN_EVIDENCIAS=1 o no se pudo crear el directorio)."
    fi
}

# Manifiesto de integridad: SHA-256 de cada evidencia y del reporte final.
# Se ejecuta al final y NO escribe en el reporte para no alterar su hash.
finalize_evidence() {
    local rdir rbase
    if [[ -n "$EVID_DIR" ]]; then
        ( cd "$EVID_DIR" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )
        echo "Manifiesto de evidencias: ${EVID_DIR}/SHA256SUMS"
    fi
    rdir=$(dirname "$REPORT_FILE"); rbase=$(basename "$REPORT_FILE")
    ( cd "$rdir" && sha256sum "$rbase" > "${rbase}.sha256" )
    echo "SHA-256 del reporte: $(cut -d' ' -f1 "${REPORT_FILE}.sha256")  (archivo: ${REPORT_FILE}.sha256)"
}

# ===== FIN DE FUNCIONES =====

# ==============================================================================
# EJECUCION
# ==============================================================================
case "${1:-}" in
    -h|--help)
        cat <<EOF
Lynx v${LYNX_VERSION} - auditor pasivo de seguridad y red (Debian / Ubuntu)

Uso:  sudo ./lynx.sh [--help | --version]

Variables de entorno:
  REPORT_DIR=/ruta   directorio base (defecto: /var/lib/lynx/<host>)
  LYNX_FLAT=1        no añade subdirectorio por host (guarda todo en REPORT_DIR)
  ES_ROUTER=1        el host enruta a proposito: ip_forward=1 se marca N/A
  SIN_EVIDENCIAS=1   no guarda volcados crudos (solo el reporte)
  SKIP_SLOW=1        omite inventarios con find (SUID, world-writable, huerfanos)
  TIMEOUT_FIND=60    segundos maximos por inventario find

Requiere root. Solo lee el sistema; escribe unicamente el reporte y las evidencias.
EOF
        exit 0 ;;
    -v|--version) echo "Lynx v${LYNX_VERSION}"; exit 0 ;;
    "") ;;
    *) echo "Opción desconocida: $1 (use --help)" >&2; exit 2 ;;
esac

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] Debe ejecutarse como root para auditar kernel, firewall, usuarios y sombras.${NC}" >&2
    exit 1
fi

init_report_dir

: > "$REPORT_FILE" || { echo "No se puede escribir en $REPORT_FILE" >&2; exit 1; }

init_evidence

log "${BLUE}====================================================================${NC}"
log "${BLUE}  LYNX v${LYNX_VERSION} - AUDITORÍA PASIVA DE SEGURIDAD, RED Y PRIVILEGIOS ${NC}"
log "${BLUE}  Fecha: $(date) | Host: $(hostname)${NC}"
log "${BLUE}====================================================================${NC}"

collect_firewall
if have sshd; then SSHD_T=$(sshd -T 2>/dev/null); fi

# ------------------------------------------------------------------------------
# 1. SYSCTL: PROTECCIÓN DEL KERNEL Y RED (PESO: 30)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 1. AUDITANDO PARÁMETROS KERNEL (SYSCTL)${NC}"

check_item "Protección contra SYN Flood (tcp_syncookies=1)" 4 \
    sv_eq net.ipv4.tcp_syncookies 1
check_item "Bloqueo de redirecciones ICMP IPv4 (all y default = 0)" 3 \
    chk_accept_redirects
check_item "Enrutamiento de origen deshabilitado (accept_source_route=0)" 3 \
    sv_eq net.ipv4.conf.all.accept_source_route 0
check_item "RPFilter activado (anti IP spoofing, rp_filter>=1)" 3 \
    sv_ge net.ipv4.conf.all.rp_filter 1
check_item "Ocultamiento de punteros de kernel (kptr_restrict>=1)" 3 \
    sv_ge kernel.kptr_restrict 1
check_item "Restricción de acceso a dmesg (dmesg_restrict>=1)" 3 \
    sv_ge kernel.dmesg_restrict 1
check_item "Restricción de PTRACE a no privilegiados (yama.ptrace_scope>=1)" 3 \
    sv_ge kernel.yama.ptrace_scope 1
check_item "Bloqueo de redirecciones ICMP IPv6 (accept_redirects=0)" 2 \
    sv6_eq net.ipv6.conf.all.accept_redirects 0
check_item "No enviar redirecciones ICMP (send_redirects=0)" 2 \
    sv_eq net.ipv4.conf.all.send_redirects 0
check_item "ASLR completo (randomize_va_space=2)" 2 \
    sv_eq kernel.randomize_va_space 2
check_item "Sin core dumps de binarios SUID (fs.suid_dumpable=0)" 2 \
    sv_eq fs.suid_dumpable 0

# ------------------------------------------------------------------------------
# 2. STACK DE RED: CONNTRACK, FORWARDING, BRIDGE (PESO: 10)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 2. AUDITANDO STACK DE RED (CONNTRACK / FORWARDING / BRIDGE)${NC}"

check_item "Módulo conntrack (stateful) cargado en el kernel" 4 \
    chk_conntrack
check_item "IP Forwarding desactivado (host puro; use ES_ROUTER=1 si enruta)" 3 \
    chk_ip_forward
check_item "Si hay bridges: bridge-nf-call-iptables=1 (el tráfico bridged pasa por el firewall)" 3 \
    chk_bridge_nf
info_red

# ------------------------------------------------------------------------------
# 3. FIREWALL: iptables-legacy / iptables-nft / nftables / fwbuilder (PESO: 25)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 3. AUDITANDO FIREWALL (IPTABLES LEGACY, IPTABLES-NFT, NFTABLES)${NC}"

check_item "Reglas de firewall cargadas en el kernel (cualquier backend)" 5 \
    chk_fw_rules_loaded
check_item "Regla stateful ESTABLISHED,RELATED (conntrack, state o nft ct state)" 7 \
    chk_fw_stateful
check_item "INPUT con política DROP/REJECT o regla final de denegación" 7 \
    chk_fw_input_deny
check_item "FORWARD con política DROP/REJECT (o forwarding desactivado)" 3 \
    chk_fw_forward_deny
check_item "IPv6 filtrado por firewall (o IPv6 deshabilitado)" 3 \
    chk_fw_ipv6
info_firewall
info_fw_persistencia

# ------------------------------------------------------------------------------
# 4. HARDENING DE SSH Y SISTEMA (PESO: 15)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 4. AUDITANDO SSH Y HARDENING GENERAL${NC}"

check_item "SSH: root sin contraseña (PermitRootLogin no / prohibit-password)" 4 \
    chk_ssh_root
check_item "SSH: autenticación por contraseña deshabilitada" 4 \
    chk_ssh_passwd
check_item "Módulos de red obsoletos bloqueados con 'install' (dccp, rds, tipc)" 4 \
    chk_modules_blocked
check_item "Core dumps limitados (limits.conf hard core 0 o coredump Storage=none)" 3 \
    chk_coredumps

# ------------------------------------------------------------------------------
# 5. USUARIOS Y PRIVILEGIOS (PESO: 10)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 5. AUDITANDO USUARIOS, CUENTAS Y PRIVILEGIOS${NC}"

check_item "Sin cuentas adicionales con UID 0 (solo root)" 3 \
    chk_uid0_unico
check_item "Sin contraseñas vacías en /etc/shadow" 3 \
    chk_sin_pass_vacia
check_item "Cuentas de sistema (UID<1000) con shell no interactiva" 4 \
    chk_shells_sistema

log "\n  [i] Resumen informativo de usuarios:"
for g in sudo wheel; do
    members=$(getent group "$g" 2>/dev/null | awk -F: '{print $4}')
    [[ -n "${members:-}" ]] && log "      - Miembros del grupo $g: $members"
done
ANOMALOUS_SHELLS=$(awk -F: '$3<1000 && $1!="root" && $7 !~ /(nologin|false|\/bin\/sync|\/sbin\/halt|\/sbin\/shutdown)$/ {print $1}' /etc/passwd | tr '\n' ' ')
if [[ -n "$ANOMALOUS_SHELLS" ]]; then
    log "      - ${RED}ALERTA:${NC} Cuentas de sistema con shell activa: $ANOMALOUS_SHELLS"
fi

# ------------------------------------------------------------------------------
# 6. PERMISOS CRÍTICOS (PESO: 10)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 6. AUDITANDO PERMISOS DE ARCHIVOS Y DIRECTORIOS CRÍTICOS${NC}"

check_item "/etc/shadow: propietario root y modo 640 o más estricto" 3 \
    chk_perm_shadow
check_item "/etc/passwd: propietario root y modo 644 o más estricto" 3 \
    chk_perm_passwd
check_item "Sin directorios world-writable sin sticky bit en /etc, /var, /usr" 4 \
    chk_worldwritable
if [[ -n "$WW_LIST" ]]; then
    log "      Directorios encontrados (máx. 5):"
    while read -r d; do log "        - $d"; done <<<"$WW_LIST"
fi

# ------------------------------------------------------------------------------
# 7. EVIDENCIAS E INFORMACIÓN COMPLEMENTARIA PARA EL AUDITOR (NO PUNTÚA)
# ------------------------------------------------------------------------------
log "\n${YELLOW}---> 7. EVIDENCIAS E INFORMACIÓN COMPLEMENTARIA (no puntúa)${NC}"
seccion_complementaria

# ------------------------------------------------------------------------------
# EVALUACIÓN FINAL
# ------------------------------------------------------------------------------
PORCENTAJE=$(( (PUNTOS_ACTUALES * 100) / PUNTOS_MAXIMOS ))

log "\n${BLUE}====================================================================${NC}"
log " PUNTUACIÓN DE AUDITORÍA: ${PUNTOS_ACTUALES} / ${PUNTOS_MAXIMOS} (${PORCENTAJE}%)  -  ${TOTAL_CHECKS} controles evaluados"
log "${BLUE}====================================================================${NC}"

if [[ "${#FALLOS[@]}" -gt 0 ]]; then
    log " Controles fallidos:"
    for f in "${FALLOS[@]}"; do log "   - $f"; done
    log ""
fi

if [ "$PORCENTAJE" -ge 85 ]; then
    log " CUMPLIMIENTO: ${GREEN}ALTO${NC} respecto a los controles evaluados"
elif [ "$PORCENTAJE" -ge 60 ]; then
    log " CUMPLIMIENTO: ${YELLOW}MEDIO${NC} - hay omisiones a corregir"
else
    log " CUMPLIMIENTO: ${RED}BAJO${NC} - brechas relevantes en kernel, firewall, permisos o cuentas"
fi
log " Nota: el puntaje cubre solo ${TOTAL_CHECKS} controles pasivos. Parches, AppArmor, auditd, sudoers y"
log "       servicios expuestos se listan en la sección 7 como información (no puntúan). No equivale"
log "       a una certificación de hardening."

log "${BLUE}====================================================================${NC}"
log " Reporte guardado en: ${REPORT_FILE}\n"
finalize_evidence
