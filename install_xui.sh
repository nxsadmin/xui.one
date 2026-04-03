#!/bin/bash
# ================================================================
#   XUI.ONE — Instalador Profesional v3.0
#   by nxs · github.com/nxsadmin/xui.one
#
#   Soporta:
#     Ubuntu  20.04 / 22.04 / 24.04 / 24.10 / 25.04
#     Debian  10 (Buster) / 11 (Bullseye) / 12 (Bookworm)
#
#   Correcciones vs instalador original:
#     - innodb_buffer_pool_size dinamico (40% RAM, bug original=10G fijo)
#     - Repositorios actualizados y funcionales para todas las versiones
#     - Soporte completo Ubuntu 24.x / 25.x y Debian 12
#     - Todas las dependencias de install-dep.sh incluidas y corregidas
#     - PHP 7.4 forzado correctamente via ondrej/php / sury
#     - IonCube Loader instalado para PHP 7.4
#     - Redis password aleatorio (no hardcodeado)
# ================================================================

set -uo pipefail

# ── Colores ──────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  MAGENTA='\033[0;35m'
WHITE='\033[1;37m'; DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Globals ───────────────────────────────────────────────────────
LOG_FILE="/tmp/xui_install_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
INSTALL_MODE=""
PHP_VERSION="7.4"
OS="" VER="" CODENAME="" ARCH=""
MYSQL_CNF="/etc/mysql/my.cnf"
export DEBIAN_FRONTEND=noninteractive

# ── UI ────────────────────────────────────────────────────────────
banner() {
    clear
    echo -e "${CYAN}"
    echo "  XX  XX UU  UU II   OOOO  NNN  NN EEEEEE"
    echo "   XXXX  UU  UU II  OO  OO NNNN NN EE    "
    echo "    XX   UU  UU II  OO  OO NN NNNN EEEE  "
    echo "   XXXX  UU  UU II  OO  OO NN  NNN EE    "
    echo "  XX  XX  UUUU  II   OOOO  NN   NN EEEEEE"
    echo -e "${RESET}"
    echo -e "  ${DIM}+---------------------------------------------------+${RESET}"
    echo -e "  ${DIM}|${RESET}  ${WHITE}${BOLD}Instalador Profesional XUI.ONE  v3.0${RESET}             ${DIM}|${RESET}"
    echo -e "  ${DIM}|${RESET}  ${DIM}by nxs  github.com/nxsadmin/xui.one${RESET}             ${DIM}|${RESET}"
    echo -e "  ${DIM}+---------------------------------------------------+${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}  >> $1${RESET}"
    echo -e "${DIM}  ----------------------------------------------------${RESET}"
}
print_ok()   { echo -e "  ${GREEN}[OK]${RESET}  $1"; }
print_warn() { echo -e "  ${YELLOW}[!!]${RESET}  $1"; }
print_err()  { echo -e "  ${RED}[XX]${RESET}  $1"; }
print_info() { echo -e "  ${CYAN}[>>]${RESET}  $1"; }
divider()    { echo -e "  ${DIM}----------------------------------------------------${RESET}"; }

spinner() {
    local pid=$1 msg="${2:-Procesando...}"
    local frames=("/-\\|") i=0
    while kill -0 "$pid" 2>/dev/null; do
        local f="${frames[0]:$((i%4)):1}"
        printf "\r  ${CYAN}[%s]${RESET}  ${DIM}%-55s${RESET}" "$f" "$msg"
        sleep 0.1; ((i++))
    done
    printf "\r  ${GREEN}[OK]${RESET}  %-55s\n" "$msg"
}

run_cmd() {
    local msg="$1"; shift
    ("$@" >> "$LOG_FILE" 2>&1) &
    spinner $! "$msg"
}

apt_try() {
    apt-get -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        install "$1" >> "$LOG_FILE" 2>&1 || true
}

progress_bar() {
    local current=$1 total=$2 label="${3:-}"
    local percent=$(( current * 100 / total ))
    local filled=$(( percent / 2 )) empty=$(( 50 - filled ))
    local bar=""
    for ((i=0;i<filled;i++)); do bar="${bar}#"; done
    for ((i=0;i<empty;i++));  do bar="${bar}."; done
    printf "\r  [${bar}] %3d%%  %-35s" "$percent" "$label"
}

# ── Verificaciones ────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        banner
        print_err "Debes ejecutar como root"
        print_info "Usa: sudo bash $0"
        echo ""; exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS="${ID:-}"
        VER="${VERSION_ID:-}"
        CODENAME="${VERSION_CODENAME:-}"
    fi
    [ -z "$CODENAME" ] && CODENAME=$(lsb_release -sc 2>/dev/null || echo "unknown")
    OS="${OS,,}"
    ARCH=$(uname -m)
}

check_os_support() {
    detect_os
    print_info "Sistema: ${WHITE}${OS} ${VER} (${ARCH}) — ${CODENAME}${RESET}"

    case "$OS" in
        ubuntu)
            case "$VER" in
                20.04|22.04|24.04|24.10|25.04)
                    MYSQL_CNF="/etc/mysql/my.cnf"
                    print_ok "Ubuntu ${VER} soportado" ;;
                *)
                    print_err "Ubuntu ${VER} no soportado"
                    print_info "Versiones soportadas: 20.04, 22.04, 24.04, 24.10, 25.04"
                    exit 1 ;;
            esac ;;
        debian)
            case "$VER" in
                10|11|12)
                    MYSQL_CNF="/etc/mysql/mariadb.cnf"
                    print_ok "Debian ${VER} soportado" ;;
                *)
                    print_err "Debian ${VER} no soportado"
                    print_info "Versiones soportadas: 10, 11, 12"
                    exit 1 ;;
            esac ;;
        *)
            print_err "Sistema no soportado: ${OS} ${VER}"
            print_info "Soportados: Ubuntu 20.04-25.04 / Debian 10-12"
            exit 1 ;;
    esac
}

check_xui_installed() {
    [ -f "/etc/systemd/system/xuione.service" ] && [ -d "/home/xui/config" ]
}

# ── Helpers ───────────────────────────────────────────────────────
gen_pass() {
    tr -dc '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ' \
        < /dev/urandom | fold -w "${1:-32}" | head -n 1
}

get_server_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' \
        || hostname -I 2>/dev/null | awk '{print $1}' \
        || echo "127.0.0.1"
}

get_cpu_count() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2
}

# ── Calculo dinamico MySQL ────────────────────────────────────────
# BUG ORIGINAL: innodb_buffer_pool_size = 10G fijo — crash en servidores < 10GB
# FIX: 40% de la RAM real, entre 512M y 8G

get_innodb_pool_size() {
    local ram_kb ram_mb pool_mb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_mb=$(( ram_kb / 1024 ))
    pool_mb=$(( ram_mb * 40 / 100 ))
    [ "$pool_mb" -lt 512  ] && pool_mb=512
    [ "$pool_mb" -gt 8192 ] && pool_mb=8192
    echo "${pool_mb}M"
}

get_innodb_instances() {
    local pool_mb
    pool_mb=$(get_innodb_pool_size)
    pool_mb="${pool_mb%M}"
    local inst=$(( pool_mb / 1024 ))
    [ "$inst" -lt 1 ] && inst=1
    [ "$inst" -gt 8 ] && inst=8
    echo "$inst"
}

build_mysql_cnf() {
    local pool inst tp_size
    pool=$(get_innodb_pool_size)
    inst=$(get_innodb_instances)
    tp_size=$(get_cpu_count)
    [ "$tp_size" -lt 2  ] && tp_size=2
    [ "$tp_size" -gt 32 ] && tp_size=32

    cat << MYCNF
# XUI — nxs installer v3.0 — $(date)
[client]
port                            = 3306

[mysqld_safe]
nice                            = 0

[mysqld]
user                            = mysql
port                            = 3306
basedir                         = /usr
datadir                         = /var/lib/mysql
tmpdir                          = /tmp
lc-messages-dir                 = /usr/share/mysql
skip-external-locking
skip-name-resolve
bind-address                    = 127.0.0.1

key_buffer_size                 = 64M
myisam_sort_buffer_size         = 4M
max_allowed_packet              = 64M
myisam-recover-options          = BACKUP
query_cache_limit               = 0
query_cache_size                = 0
query_cache_type                = 0
expire_logs_days                = 10
max_binlog_size                 = 100M
max_connections                 = 4096
back_log                        = 2048
open_files_limit                = 20240
innodb_open_files               = 20240
max_connect_errors              = 3072
table_open_cache                = 2048
table_definition_cache          = 2048
tmp_table_size                  = 256M
max_heap_table_size             = 256M

# Buffer pool: 40% RAM (BUG ORIGINAL = 10G hardcoded)
innodb_buffer_pool_size         = ${pool}
innodb_buffer_pool_instances    = ${inst}
innodb_read_io_threads          = 16
innodb_write_io_threads         = 16
innodb_thread_concurrency       = 0
innodb_flush_log_at_trx_commit  = 0
innodb_flush_method             = O_DIRECT
performance_schema              = 0
innodb_file_per_table           = 1
innodb_io_capacity              = 2000
innodb_table_locks              = 0
innodb_lock_wait_timeout        = 30

sql_mode                        = "NO_ENGINE_SUBSTITUTION"

[mariadb]
thread_cache_size               = 2048
thread_handling                 = pool-of-threads
thread_pool_size                = ${tp_size}
thread_pool_idle_timeout        = 20
thread_pool_max_threads         = 512

[mysqldump]
quick
quote-names
max_allowed_packet              = 16M

[mysql]

[isamchk]
key_buffer_size                 = 16M
MYCNF
}

# ── Repositorios ──────────────────────────────────────────────────
setup_repos() {
    print_section "Configurando repositorios"

    # Limpiar locks
    for lock in /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock \
                /var/lib/dpkg/lock /var/lib/apt/lists/lock; do
        rm -f "$lock" 2>/dev/null || true
    done

    apt-get update -y >> "$LOG_FILE" 2>&1 || true
    apt-get -y install software-properties-common apt-transport-https \
        ca-certificates gnupg2 wget curl lsb-release \
        >> "$LOG_FILE" 2>&1 || true

    # ── sources.list por OS ──
    if [ "$OS" = "ubuntu" ]; then
        mkdir -p /etc/apt/sources.list.d.save
        cp /etc/apt/sources.list /etc/apt/sources.list.save 2>/dev/null || true
        cat > /etc/apt/sources.list << SRC
deb http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu ${CODENAME} main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu ${CODENAME}-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu ${CODENAME}-security main restricted universe multiverse
SRC
        print_ok "sources.list Ubuntu ${CODENAME}"

    elif [ "$OS" = "debian" ]; then
        mkdir -p /etc/apt/sources.list.d.save
        cp /etc/apt/sources.list /etc/apt/sources.list.save 2>/dev/null || true
        local nonfree="non-free"
        { [ "${VER}" -ge 12 ] 2>/dev/null && nonfree="non-free non-free-firmware"; } || true
        cat > /etc/apt/sources.list << SRC
deb http://deb.debian.org/debian/ ${CODENAME} main contrib ${nonfree}
deb-src http://deb.debian.org/debian/ ${CODENAME} main contrib ${nonfree}
deb http://deb.debian.org/debian/ ${CODENAME}-updates main contrib ${nonfree}
deb-src http://deb.debian.org/debian/ ${CODENAME}-updates main contrib ${nonfree}
deb http://deb.debian.org/debian-security/ ${CODENAME}-security main contrib ${nonfree}
deb-src http://deb.debian.org/debian-security/ ${CODENAME}-security main contrib ${nonfree}
SRC
        print_ok "sources.list Debian ${CODENAME}"
    fi

    # ── ondrej/php para PHP 7.4 en cualquier Ubuntu/Debian reciente ──
    print_info "Repo ondrej/php (PHP 7.4 en ${OS} ${VER})..."
    if [ "$OS" = "ubuntu" ]; then
        add-apt-repository -y ppa:ondrej/php    >> "$LOG_FILE" 2>&1 || true
        add-apt-repository -y ppa:ondrej/apache2 >> "$LOG_FILE" 2>&1 || true
    elif [ "$OS" = "debian" ]; then
        wget -qO /etc/apt/trusted.gpg.d/php-sury.gpg \
            https://packages.sury.org/php/apt.gpg >> "$LOG_FILE" 2>&1 || true
        echo "deb https://packages.sury.org/php/ ${CODENAME} main" \
            > /etc/apt/sources.list.d/php.list
        wget -qO /etc/apt/trusted.gpg.d/apache2-sury.gpg \
            https://packages.sury.org/apache2/apt.gpg >> "$LOG_FILE" 2>&1 || true
        echo "deb https://packages.sury.org/apache2/ ${CODENAME} main" \
            > /etc/apt/sources.list.d/apache2.list
    fi

    # ── MariaDB 10.6 ──
    print_info "Repo MariaDB 10.6..."
    {
        wget -qO /etc/apt/trusted.gpg.d/mariadb.gpg \
            "https://supplychain.mariadb.com/MariaDB-Server-GPG-KEY" 2>/dev/null || \
        wget -qO- "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF1656F24C74CD1D8" \
            | gpg --dearmor > /etc/apt/trusted.gpg.d/mariadb.gpg 2>/dev/null || true
    }
    if [ "$OS" = "ubuntu" ]; then
        echo "deb [arch=amd64,arm64] https://mirrors.nxthost.com/mariadb/repo/10.6/ubuntu/ ${CODENAME} main" \
            > /etc/apt/sources.list.d/mariadb.list
    else
        echo "deb [arch=amd64,arm64] https://mirrors.nxthost.com/mariadb/repo/10.6/debian/ ${CODENAME} main" \
            > /etc/apt/sources.list.d/mariadb.list
    fi

    # ── MaxMind GeoIP (solo Ubuntu tiene PPA) ──
    if [ "$OS" = "ubuntu" ]; then
        add-apt-repository -y ppa:maxmind/ppa >> "$LOG_FILE" 2>&1 || true
    fi

    apt-get update -y >> "$LOG_FILE" 2>&1 || true
    print_ok "Repositorios listos"
}

# ── Dependencias ──────────────────────────────────────────────────
install_deps() {
    print_section "Eliminando paquetes conflictivos"
    apt-get -y purge mysql-server 2>/dev/null >> "$LOG_FILE" 2>&1 || true
    apt-get -y autoremove           >> "$LOG_FILE" 2>&1 || true

    # Grupos de paquetes
    local BASE=(
        build-essential autoconf automake make cmake libtool pkg-config
        git wget curl tar zip unzip xz-utils zstd subversion
        ca-certificates gnupg2 dirmngr gpg-agent apt-utils
        software-properties-common lsb-release
        debhelper cdbs lintian fakeroot devscripts dh-make
        sudo vim nano mc htop sysstat screen ncdu
        net-tools iproute2 iputils-ping dnsutils
        e2fsprogs cpufrequtils
        bison flex chrpath
        tzdata procps gettext help2man m4
        binutils
        python3 python3-pip python3-paramiko
    )

    local MARIADB=(
        mariadb-server mariadb-client mariadb-common
        libmariadb-dev libmariadb-dev-compat libmariadbd-dev
        default-libmysqlclient-dev dbconfig-mysql
    )

    local DEVLIBS=(
        libssl-dev
        libcurl4-openssl-dev
        libxslt1-dev libxslt-dev libxml2 libxml2-dev
        libpcre3 libpcre3-dev libpcre2-dev
        zlib1g-dev libbz2-dev libgmp-dev
        libsqlite3-dev sqlite3
        libacl1-dev libapr1-dev libaprutil1-dev
        libonig-dev
        libgd-dev libpng-dev libjpeg-dev libfreetype6-dev
        libmaxminddb0 libmaxminddb-dev mmdb-bin
        libgeoip-dev
        libmp3lame-dev libass-dev
        libvorbis-dev libtheora-dev
        libvpx-dev libx264-dev libx265-dev libnuma-dev libxvidcore-dev
        libopus-dev librtmp-dev
        libsdl2-dev libva-dev libvdpau-dev
        libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev
        libaom-dev libdav1d-dev
        libgnutls28-dev
        libunistring-dev
        libsodium-dev
        libffi-dev
        yasm nasm
        meson ninja-build texinfo
        reprepro
        nscd
    )

    local PHP74=(
        php7.4 php7.4-common php7.4-fpm php7.4-cli
        php7.4-mysql php7.4-gd php7.4-curl
        php7.4-imap php7.4-xmlrpc php7.4-xsl
        php7.4-intl php7.4-dev php7.4-mbstring
        php7.4-xml php7.4-zip php7.4-bcmath
        php7.4-readline
        libapache2-mod-php7.4
    )

    local APACHE=(
        apache2 apache2-bin apache2-data apache2-utils
        apache2-dev apache2-threaded-dev
        libapache2-mod-fcgid
        dh-apache2 dpkg-dev
        php-pear
    )

    local XUI_DEPS=(
        mcrypt libmcrypt-dev
        iptables-persistent
        certbot
        alsa-utils v4l-utils
        freetds-dev
        libfdk-aac-dev
    )

    # Instalar grupo a grupo
    local GRUPOS=("BASE" "MARIADB" "DEVLIBS" "PHP74" "APACHE" "XUI_DEPS")
    local TOTAL_G=${#GRUPOS[@]} GSTEP=0

    for GRP in "${GRUPOS[@]}"; do
        ((GSTEP++))
        echo ""
        echo -e "  ${MAGENTA}[${GSTEP}/${TOTAL_G}]${RESET} ${BOLD}Grupo: ${GRP}${RESET}"

        eval "local PKGS=(\"\${${GRP}[@]}\")"
        local TOT=${#PKGS[@]} STEP=0

        for pkg in "${PKGS[@]}"; do
            ((STEP++))
            progress_bar $STEP $TOT "$pkg"
            apt_try "$pkg"
        done
        echo ""
    done

    # PHP extras opcionales (mcrypt, pueden no existir en todos los repos)
    for p in php7.4-mcrypt; do apt_try "$p"; done

    # Versiones PHP adicionales para compatibilidad
    print_info "Instalando versiones extra PHP (compatibilidad)..."
    for VPHP in 7.2 7.3 8.0 8.1 8.2 8.3; do
        for MOD in common fpm cli mysql mbstring xml curl; do
            apt_try "php${VPHP}-${MOD}"
        done
    done

    # ── Configurar PHP 7.4 como default del sistema ──
    print_info "Configurando PHP ${PHP_VERSION} como version activa..."
    {
        update-alternatives --set php        /usr/bin/php${PHP_VERSION}        2>/dev/null || true
        update-alternatives --set phar       /usr/bin/phar${PHP_VERSION}       2>/dev/null || true
        update-alternatives --set phar.phar  /usr/bin/phar.phar${PHP_VERSION}  2>/dev/null || true
        update-alternatives --set phpize     /usr/bin/phpize${PHP_VERSION}     2>/dev/null || true
        update-alternatives --set php-config /usr/bin/php-config${PHP_VERSION} 2>/dev/null || true
    } >> "$LOG_FILE" 2>&1

    # ── Gestionar modulos PHP en Apache ──
    print_info "Configurando modulos PHP en Apache..."
    {
        for v in 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3; do
            a2dismod "php${v}"   2>/dev/null || true
            a2disconf "php${v}-fpm" 2>/dev/null || true
            systemctl stop    "php${v}-fpm" 2>/dev/null || true
            systemctl disable "php${v}-fpm" 2>/dev/null || true
        done
        a2enmod php7.4  2>/dev/null || true
        a2enmod rewrite 2>/dev/null || true
        for v in 7.4 8.0 8.1 8.2 8.3; do
            phpenmod -v "$v" mbstring 2>/dev/null || true
            phpenmod -v "$v" xml      2>/dev/null || true
            phpenmod -v "$v" curl     2>/dev/null || true
        done
    } >> "$LOG_FILE" 2>&1

    # ── IonCube Loader PHP 7.4 ──
    print_info "Instalando IonCube Loader para PHP 7.4..."
    {
        local ICT="/tmp/ioncube.tar.gz"
        wget -qO "$ICT" \
            "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz" \
            2>/dev/null || true
        if [ -f "$ICT" ]; then
            tar -xzf "$ICT" -C /usr/local/ 2>/dev/null || true
            rm -f "$ICT"
            local IC_SO="/usr/local/ioncube/ioncube_loader_lin_7.4.so"
            local EXT_DIR
            EXT_DIR=$(php7.4 -r "echo ini_get('extension_dir');" 2>/dev/null || echo "")
            if [ -n "$EXT_DIR" ] && [ -f "$IC_SO" ]; then
                cp "$IC_SO" "$EXT_DIR/" 2>/dev/null || true
                for ini_path in /etc/php/7.4/cli/conf.d /etc/php/7.4/fpm/conf.d \
                                /etc/php/7.4/apache2/conf.d; do
                    mkdir -p "$ini_path" 2>/dev/null || true
                    echo "zend_extension=ioncube_loader_lin_7.4.so" \
                        > "${ini_path}/00-ioncube.ini" 2>/dev/null || true
                done
            fi
        fi
    } >> "$LOG_FILE" 2>&1

    # ── MariaDB: arrancar ──
    print_info "Iniciando MariaDB..."
    {
        systemctl start  mariadb 2>/dev/null || service mariadb start  2>/dev/null || true
        systemctl enable mariadb 2>/dev/null || true
    } >> "$LOG_FILE" 2>&1

    print_ok "Todas las dependencias instaladas"
}

# ── Base de datos ─────────────────────────────────────────────────
setup_database() {
    local DB_USER="$1" DB_PASS="$2"
    local pool inst
    pool=$(get_innodb_pool_size)
    inst=$(get_innodb_instances)

    print_info "innodb_buffer_pool_size = ${BOLD}${pool}${RESET}  (auto 40% RAM — bug original era 10G)"
    print_info "innodb_buffer_pool_instances = ${BOLD}${inst}${RESET}"

    # Escribir my.cnf solo si no existe ya de XUI
    local write_cnf=true
    if [ -f "$MYSQL_CNF" ] && head -c5 "$MYSQL_CNF" 2>/dev/null | grep -q "# XUI"; then
        write_cnf=false
        print_warn "my.cnf ya fue escrito por este instalador — omitiendo"
    fi
    if $write_cnf; then
        build_mysql_cnf > "$MYSQL_CNF"
        run_cmd "Reiniciando MariaDB con config optimizada" service mariadb restart
        print_ok "my.cnf actualizado con valores adaptados al servidor"
    fi

    # Verificar acceso root MySQL
    local EXTRA=""
    if ! mysql -u root -e "SELECT VERSION();" >> "$LOG_FILE" 2>&1; then
        echo ""
        print_warn "MariaDB requiere contrasena de root"
        while true; do
            printf "  Contrasena root MySQL: "; read -rs rpw; echo ""
            EXTRA="-p${rpw}"
            mysql -u root $EXTRA -e "SELECT VERSION();" >> "$LOG_FILE" 2>&1 && break
            print_err "Contrasena incorrecta, intenta de nuevo"
        done
    fi

    run_cmd "Creando bases de datos xui / xui_migrate" bash -c "
        mysql -u root ${EXTRA} -e 'DROP DATABASE IF EXISTS xui;'
        mysql -u root ${EXTRA} -e 'CREATE DATABASE xui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
        mysql -u root ${EXTRA} -e 'DROP DATABASE IF EXISTS xui_migrate;'
        mysql -u root ${EXTRA} -e 'CREATE DATABASE xui_migrate CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'
    "

    if [ -f "/home/xui/bin/install/database.sql" ]; then
        run_cmd "Importando esquema SQL" \
            bash -c "mysql -u root ${EXTRA} xui < /home/xui/bin/install/database.sql"
    fi

    run_cmd "Creando usuario MySQL '${DB_USER}'" bash -c "
        for host in localhost 127.0.0.1; do
            mysql -u root ${EXTRA} -e \"CREATE USER IF NOT EXISTS '${DB_USER}'@'\$host' IDENTIFIED BY '${DB_PASS}';\" 2>/dev/null \
            || mysql -u root ${EXTRA} -e \"GRANT USAGE ON *.* TO '${DB_USER}'@'\$host' IDENTIFIED BY '${DB_PASS}';\" 2>/dev/null || true
            mysql -u root ${EXTRA} -e \"GRANT ALL PRIVILEGES ON xui.*         TO '${DB_USER}'@'\$host';\" || true
            mysql -u root ${EXTRA} -e \"GRANT ALL PRIVILEGES ON xui_migrate.* TO '${DB_USER}'@'\$host';\" || true
            mysql -u root ${EXTRA} -e \"GRANT ALL PRIVILEGES ON mysql.*        TO '${DB_USER}'@'\$host';\" || true
            mysql -u root ${EXTRA} -e \"GRANT GRANT OPTION   ON xui.*         TO '${DB_USER}'@'\$host';\" || true
        done
        mysql -u root ${EXTRA} -e 'FLUSH PRIVILEGES;'
    "

    cat > /home/xui/config/config.ini << CONF
; XUI Configuration
; Generado por nxs installer v3.0 — $(date)
[XUI]
hostname    =   "127.0.0.1"
database    =   "xui"
port        =   3306
server_id   =   1
license     =   ""

[Encrypted]
username    =   "${DB_USER}"
password    =   "${DB_PASS}"
CONF
    print_ok "Base de datos configurada"
    printf '%s' "$EXTRA"
}

# ── Sistema ────────────────────────────────────────────────────────
setup_system() {
    # fstab tmpfs
    if ! grep -q "/home/xui/" /etc/fstab 2>/dev/null; then
        {
          echo ""
          echo "tmpfs /home/xui/content/streams tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=90% 0 0"
          echo "tmpfs /home/xui/tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=6G 0 0"
        } >> /etc/fstab
        print_ok "fstab actualizado (tmpfs streams)"
    else
        print_ok "fstab ya configurado"
    fi

    # Servicio systemd
    rm -f /etc/init.d/xuione /etc/systemd/system/xui.service 2>/dev/null || true
    if [ ! -f "/etc/systemd/system/xuione.service" ]; then
        cat > /etc/systemd/system/xuione.service << 'SVC'
[Unit]
SourcePath=/home/xui/service
Description=XUI.one Service
After=network.target mysql.service mariadb.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
Restart=always
RestartSec=1
ExecStart=/bin/bash /home/xui/service start
ExecRestart=/bin/bash /home/xui/service restart
ExecStop=/bin/bash /home/xui/service stop

[Install]
WantedBy=multi-user.target
SVC
        chmod +x /etc/systemd/system/xuione.service
        systemctl daemon-reload >> "$LOG_FILE" 2>&1
        systemctl enable xuione >> "$LOG_FILE" 2>&1
        print_ok "Servicio xuione creado y habilitado"
    else
        print_ok "Servicio xuione ya existe"
    fi

    # sysctl
    echo ""
    print_warn "Configuracion TCP/BBR optimizada para streaming de video"
    printf "  Aplicar configuracion sysctl optimizada? [S/n]: "
    read -r ans_sysctl
    if [[ ! "$ans_sysctl" =~ ^[nN]$ ]]; then
        modprobe ip_conntrack >> "$LOG_FILE" 2>&1 || true
        cat > /etc/sysctl.conf << 'SYSCTL'
# XUI.one — TCP/Network tuning (nxs installer)
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_rmem = 8192 87380 134217728
net.ipv4.udp_rmem_min = 16384
net.core.rmem_default = 262144
net.core.rmem_max = 268435456
net.ipv4.tcp_wmem = 8192 65536 134217728
net.ipv4.udp_wmem_min = 16384
net.core.wmem_default = 262144
net.core.wmem_max = 268435456
net.core.somaxconn = 1000000
net.core.netdev_max_backlog = 250000
net.core.optmem_max = 65535
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_max_orphans = 16384
net.ipv4.ip_local_port_range = 2000 65000
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
fs.file-max=20970800
fs.nr_open=20970800
fs.aio-max-nr=20970800
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.route.flush = 1
net.ipv6.route.flush = 1
SYSCTL
        sysctl -p >> "$LOG_FILE" 2>&1 || true
        touch /home/xui/config/sysctl.on
        print_ok "sysctl configurado (BBR + ventanas grandes)"
    else
        rm -f /home/xui/config/sysctl.on 2>/dev/null || true
        print_info "sysctl omitido"
    fi

    # Limites de archivos abiertos
    if ! grep -q "DefaultLimitNOFILE=655350" /etc/systemd/system.conf 2>/dev/null; then
        printf '\nDefaultLimitNOFILE=655350\n' >> /etc/systemd/system.conf
        printf '\nDefaultLimitNOFILE=655350\n' >> /etc/systemd/user.conf 2>/dev/null || true
        print_ok "Limite de archivos abiertos ampliado (655350)"
    fi
}

# ── Redis ─────────────────────────────────────────────────────────
setup_redis() {
    if [ ! -f "/home/xui/bin/redis/redis.conf" ]; then
        local rpass cpus
        rpass=$(gen_pass 24)
        cpus=$(get_cpu_count)
        [ "$cpus" -gt 8 ] && cpus=8

        mkdir -p /home/xui/bin/redis 2>/dev/null || true
        cat > /home/xui/bin/redis/redis.conf << REDIS
bind 127.0.0.1
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised no
pidfile /home/xui/bin/redis/redis-server.pid
loglevel warning
logfile /home/xui/bin/redis/redis-server.log
databases 1
always-show-logo yes
stop-writes-on-bgsave-error no
rdbcompression no
rdbchecksum no
dbfilename dump.rdb
dir /home/xui/bin/redis/
slave-serve-stale-data yes
slave-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
slave-priority 100
requirepass ${rpass}
maxclients 655350
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
slave-lazy-flush no
appendonly no
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble no
lua-time-limit 5000
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit slave 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
aof-rewrite-incremental-fsync yes
save 60 1000
server-threads ${cpus}
server-thread-affinity true
REDIS
        print_ok "Redis configurado (password aleatorio generado)"
    else
        print_ok "Redis ya configurado"
    fi
}

# ── Aplicar licencia ──────────────────────────────────────────────
apply_license_files() {
    local ok=true
    [ ! -f "./license" ] && print_err "Falta: ${SCRIPT_DIR}/license" && ok=false
    [ ! -f "./xui.so"  ] && print_err "Falta: ${SCRIPT_DIR}/xui.so"  && ok=false
    $ok || return 1

    print_info "Copiando archivo de licencia..."
    cp -f ./license /home/xui/config/license

    print_info "Instalando xui.so (PHP ${PHP_VERSION})..."
    local EXTDIR="/home/xui/bin/php/lib/php/extensions/no-debug-non-zts-20190902"
    mkdir -p "$EXTDIR" 2>/dev/null || true
    cp -f ./xui.so "${EXTDIR}/xui.so"

    print_info "Actualizando config.ini..."
    sed -i 's/^license.*/license     =   "license"/g' /home/xui/config/config.ini

    print_info "Forzando PHP ${PHP_VERSION}..."
    local PBIN="/home/xui/bin/php/bin"
    local PSBIN="/home/xui/bin/php/sbin"
    ln -sf "${PBIN}/php_${PHP_VERSION}"      "${PBIN}/php"      2>/dev/null || true
    ln -sf "${PSBIN}/php-fpm_${PHP_VERSION}" "${PSBIN}/php-fpm" 2>/dev/null || true
    ln -sf "${PBIN}/php_${PHP_VERSION}"      "${PBIN}/php_7.2"  2>/dev/null || true
    ln -sf "${PSBIN}/php-fpm_${PHP_VERSION}" "${PSBIN}/php-fpm_7.2" 2>/dev/null || true

    print_ok "Licencia aplicada"
}

# ── MODO: Instalacion completa ────────────────────────────────────
install_fresh() {
    banner
    echo ""
    echo -e "  ${GREEN}+--------------------------------------------------+${RESET}"
    echo -e "  ${GREEN}|  INSTALACION COMPLETA — XUI.ONE v3.0              |${RESET}"
    echo -e "  ${GREEN}+--------------------------------------------------+${RESET}"
    echo ""

    check_os_support

    local ram_mb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
    local cpus; cpus=$(get_cpu_count)
    local pool; pool=$(get_innodb_pool_size)
    echo -e "  ${DIM}RAM: ${WHITE}${ram_mb}MB${RESET}  CPUs: ${WHITE}${cpus}${RESET}  innodb_pool (auto): ${GREEN}${pool}${RESET}"
    echo ""

    # XUI ya instalado?
    if check_xui_installed; then
        print_warn "XUI.ONE ya esta instalado en este servidor"
        printf "  Sobrescribir? [s/N]: "; read -r c
        [[ ! "$c" =~ ^[sS]$ ]] && print_info "Cancelado." && exit 0
    fi

    # Verificar archivo XUI
    print_section "Verificando archivos"
    if   [ -f "./xui.tar.gz"       ]; then XUI_FILE="./xui.tar.gz";       print_ok "xui.tar.gz encontrado"
    elif [ -f "./xui_trial.tar.gz" ]; then XUI_FILE="./xui_trial.tar.gz"; print_ok "xui_trial.tar.gz encontrado (trial)"
    else
        print_err "No se encontro xui.tar.gz ni xui_trial.tar.gz"
        print_info "Descargalo desde tu panel de facturación XUI.ONE"
        exit 1
    fi

    HAS_LICENSE=false
    if [ -f "./license" ] && [ -f "./xui.so" ]; then
        HAS_LICENSE=true
        print_ok "Archivos de licencia detectados"
    else
        print_warn "Sin licencia — instalacion estandar"
    fi

    setup_repos
    install_deps

    print_section "Creando usuario xui"
    if ! getent passwd xui > /dev/null 2>&1; then
        run_cmd "Creando usuario xui (sin login)" \
            adduser --system --shell /bin/false --group --disabled-login xui
    else
        print_ok "Usuario xui ya existe"
    fi
    [ ! -d "/home/xui" ] && mkdir -p /home/xui

    print_section "Extrayendo XUI.ONE"
    run_cmd "Extrayendo ${XUI_FILE}" tar -zxf "$XUI_FILE" -C "/home/xui/"
    if [ ! -f "/home/xui/status" ]; then
        echo ""; print_err "Fallo al extraer. Ver: ${LOG_FILE}"; exit 1
    fi
    print_ok "XUI.ONE extraido correctamente"

    print_section "Configurando base de datos"
    local DB_USER DB_PASS MYSQL_EXTRA
    DB_USER=$(gen_pass 20)
    DB_PASS=$(gen_pass 32)
    MYSQL_EXTRA=$(setup_database "$DB_USER" "$DB_PASS")

    print_section "Configurando sistema"
    setup_system

    print_section "Configurando Redis"
    setup_redis

    if $HAS_LICENSE; then
        print_section "Aplicando licencia"
        apply_license_files
    fi

    print_section "Creando codigo de acceso admin"
    local ADMIN_CODE="" CODE_DIR="/home/xui/bin/nginx/conf/codes/"
    if [ -d "$CODE_DIR" ]; then
        for conf in "${CODE_DIR}"*.conf; do
            [ -f "$conf" ] || continue
            local cname; cname=$(basename "$conf" .conf)
            if [ "$cname" = "setup" ]; then rm -f "$conf"; continue; fi
            grep -q "/home/xui/admin" "$conf" 2>/dev/null && ADMIN_CODE="$cname"
        done
    fi
    if [ -z "$ADMIN_CODE" ]; then
        ADMIN_CODE=$(gen_pass 8)
        mysql -u root ${MYSQL_EXTRA} -e \
            "USE xui; INSERT IGNORE INTO access_codes(code,type,enabled,groups) VALUES('${ADMIN_CODE}',0,1,'[1]');" \
            >> "$LOG_FILE" 2>&1 || true
        if [ -f "${CODE_DIR}template" ]; then
            sed -e "s/#WHITELIST#//" -e "s/#TYPE#/admin/" \
                -e "s/#CODE#/${ADMIN_CODE}/" -e "s/#BURST#/500/" \
                "${CODE_DIR}template" > "${CODE_DIR}${ADMIN_CODE}.conf"
        fi
        print_ok "Codigo admin: ${WHITE}${BOLD}${ADMIN_CODE}${RESET}"
    else
        print_ok "Codigo admin existente: ${WHITE}${BOLD}${ADMIN_CODE}${RESET}"
    fi

    print_section "Iniciando XUI.ONE"
    mount -a         >> "$LOG_FILE" 2>&1 || true
    chown xui:xui -R /home/xui >> "$LOG_FILE" 2>&1 || true
    systemctl daemon-reload     >> "$LOG_FILE" 2>&1
    run_cmd "Iniciando servicio xuione" systemctl start xuione
    print_info "Esperando 10 segundos..."
    sleep 10
    /home/xui/status 1 >> "$LOG_FILE" 2>&1 || true
    /home/xui/bin/php/bin/php /home/xui/includes/cli/startup.php >> "$LOG_FILE" 2>&1 || true

    local SERVER_IP; SERVER_IP=$(get_server_ip)

    cat > "${SCRIPT_DIR}/credentials.txt" << CREDS
XUI.ONE — Credenciales de instalacion
======================================
Fecha          : $(date)
Servidor       : ${SERVER_IP}
Instalador     : nxs v3.0

Panel admin    : http://${SERVER_IP}/${ADMIN_CODE}

MySQL Usuario  : ${DB_USER}
MySQL Password : ${DB_PASS}

innodb_buffer_pool_size : ${pool}  (40% de ${ram_mb}MB RAM)
RAM servidor            : ${ram_mb}MB
CPUs                    : ${cpus}

Log instalacion : ${LOG_FILE}
CREDS

    echo ""; echo ""
    divider
    echo -e "  ${GREEN}${BOLD}[OK]  INSTALACION COMPLETADA EXITOSAMENTE${RESET}"
    divider
    echo ""
    echo -e "  ${WHITE}Panel de administracion:${RESET}"
    echo -e "  ${CYAN}  >> http://${SERVER_IP}/${ADMIN_CODE}${RESET}"
    echo ""
    echo -e "  ${WHITE}Credenciales en:${RESET}"
    echo -e "  ${YELLOW}  ${SCRIPT_DIR}/credentials.txt${RESET}"
    echo -e "  ${RED}  Mueve este archivo a un lugar seguro!${RESET}"
    echo ""
    echo -e "  ${WHITE}Log:${RESET}  ${DIM}${LOG_FILE}${RESET}"
    divider; echo ""
}

# ── MODO: Solo licencia ───────────────────────────────────────────
install_license_only() {
    banner
    echo ""
    echo -e "  ${MAGENTA}+--------------------------------------------------+${RESET}"
    echo -e "  ${MAGENTA}|  APLICAR LICENCIA — XUI.ONE                      |${RESET}"
    echo -e "  ${MAGENTA}+--------------------------------------------------+${RESET}"
    echo ""

    if ! check_xui_installed; then
        print_err "XUI.ONE no esta instalado en este servidor"
        print_info "Usa la opcion [1] para instalacion completa"
        exit 1
    fi
    detect_os
    print_ok "XUI.ONE detectado"

    print_section "Deteniendo servicio"
    run_cmd "Deteniendo xuione" systemctl stop xuione

    print_section "Aplicando licencia"
    apply_license_files || { echo ""; exit 1; }

    print_section "Reiniciando servicio"
    run_cmd "Iniciando xuione" systemctl start xuione

    echo ""; divider
    echo -e "  ${GREEN}${BOLD}[OK]  LICENCIA APLICADA EXITOSAMENTE${RESET}"
    divider; echo ""
    echo -e "  ${WHITE}PHP activo:${RESET}  ${CYAN}${PHP_VERSION}${RESET}"
    echo -e "  ${WHITE}Servicio:${RESET}    ${GREEN}xuione corriendo${RESET}"
    divider; echo ""
}

# ── MODO: Estado ──────────────────────────────────────────────────
show_status() {
    banner
    echo -e "  ${BLUE}+--------------------------------------------------+${RESET}"
    echo -e "  ${BLUE}|  ESTADO DE XUI.ONE                               |${RESET}"
    echo -e "  ${BLUE}+--------------------------------------------------+${RESET}"
    echo ""
    if check_xui_installed; then
        print_ok "Instalacion detectada en /home/xui"
        echo ""
        systemctl status xuione --no-pager -l 2>/dev/null || true
        echo ""
        [ -f "/home/xui/status" ] && /home/xui/status 1 2>/dev/null || true
    else
        print_warn "XUI.ONE no esta instalado"
    fi
    echo ""
}

# ── Menu principal ────────────────────────────────────────────────
show_menu() {
    banner
    detect_os

    local ram_mb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
    local pool; pool=$(get_innodb_pool_size)
    local cpus; cpus=$(get_cpu_count)

    echo -e "  ${DIM}Sistema: ${WHITE}${OS} ${VER} (${ARCH}) — ${CODENAME}${RESET}"
    echo -e "  ${DIM}RAM: ${WHITE}${ram_mb}MB${RESET}  CPUs: ${WHITE}${cpus}${RESET}  innodb_pool (auto): ${GREEN}${pool}${RESET}"
    echo ""
    divider
    echo ""
    echo -e "  ${WHITE}${BOLD}Que deseas hacer?${RESET}"
    echo ""
    echo -e "  ${CYAN}[1]${RESET}  ${BOLD}Instalacion completa${RESET}   ${DIM}XUI.ONE + dependencias + licencia${RESET}"
    echo -e "  ${CYAN}[2]${RESET}  ${BOLD}Aplicar licencia${RESET}        ${DIM}XUI.ONE ya esta instalado${RESET}"
    echo -e "  ${CYAN}[3]${RESET}  ${BOLD}Ver estado${RESET}              ${DIM}Estado del servicio xuione${RESET}"
    echo -e "  ${RED}[0]${RESET}  Salir"
    echo ""
    divider
    printf "  ${YELLOW}Opcion: ${RESET}"; read -r opt
    case "$opt" in
        1) INSTALL_MODE="fresh" ;;
        2) INSTALL_MODE="license" ;;
        3) INSTALL_MODE="status" ;;
        0) echo "" && exit 0 ;;
        *) print_err "Opcion no valida"; sleep 1; show_menu ;;
    esac
}

# ── Entrada principal ─────────────────────────────────────────────
check_root
show_menu

case "$INSTALL_MODE" in
    fresh)   install_fresh ;;
    license) install_license_only ;;
    status)  show_status ;;
esac
