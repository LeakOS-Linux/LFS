#!/bin/bash

# LFS Build Script - Optimized with error handling and logging
# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variabel global
package_name=""
package_ext=""
LOG_FILE="/sources/build.log"

# Fungsi untuk logging
log() {
    echo -e "$1" | tee -a $LOG_FILE
}

# Fungsi untuk mengecek error
check_error() {
    if [ $? -ne 0 ]; then
        log "${RED}ERROR: Gagal membangun $package_name pada langkah: $1${NC}"
        log "${RED}Periksa log di $LOG_FILE${NC}"
        exit 1
    fi
}

begin() {
    package_name=$1
    package_ext=$2
    
    log "${GREEN}========================================${NC}"
    log "${GREEN}Memulai build $package_name pada $(date)${NC}"
    log "${GREEN}========================================${NC}"
    
    # Cek apakah file ada
    if [ ! -f "$package_name.$package_ext" ]; then
        log "${RED}ERROR: File $package_name.$package_ext tidak ditemukan!${NC}"
        exit 1
    fi
    
    # Ekstrak dengan deteksi otomatis
    case $package_ext in
        tar.xz|txz)
            tar -xJf $package_name.$package_ext
            ;;
        tar.gz|tgz)
            tar -xzf $package_name.$package_ext
            ;;
        tar.bz2|tbz)
            tar -xjf $package_name.$package_ext
            ;;
        tar)
            tar -xf $package_name.$package_ext
            ;;
        zip)
            unzip $package_name.$package_ext
            ;;
        *)
            log "${RED}Format ekstensi tidak dikenal: $package_ext${NC}"
            exit 1
            ;;
    esac
    check_error "Ekstraksi file"
    
    # Cek apakah direktori berhasil dibuat
    if [ ! -d "$package_name" ]; then
        log "${RED}ERROR: Direktori $package_name tidak ditemukan setelah ekstraksi!${NC}"
        exit 1
    fi
    
    cd $package_name
    log "${BLUE}Masuk ke direktori: $(pwd)${NC}"
}

finish() {
    log "${GREEN}Selesai membangun $package_name pada $(date)${NC}"
    log "${GREEN}----------------------------------------${NC}"
    
    cd /sources
    if [ -d "$package_name" ]; then
        rm -rf $package_name
        log "${YELLOW}Membersihkan direktori $package_name${NC}"
    fi
}

# Fungsi untuk menjalankan perintah dengan logging
run_cmd() {
    local cmd="$1"
    local desc="$2"
    
    log "${BLUE}Running: $desc${NC}"
    log "${YELLOW}Command: $cmd${NC}"
    
    eval $cmd >> $LOG_FILE 2>&1
    local status=$?
    
    if [ $status -ne 0 ]; then
        log "${RED}ERROR: Gagal menjalankan: $desc${NC}"
        log "${RED}Status: $status${NC}"
        exit 1
    fi
    
    log "${GREEN}✓ Success: $desc${NC}"
}

# Fungsi untuk menampilkan progress
show_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    echo -ne "\r${BLUE}Progress: ["
    for ((i=0; i<percent/2; i++)); do echo -n "#"; done
    for ((i=percent/2; i<50; i++)); do echo -n " "; done
    echo -e "] $percent% ($current/$total)${NC}"
}

# Mulai build
log "${GREEN}========================================${NC}"
log "${GREEN}    MEMULAI BUILD LFS CHROOT          ${NC}"
log "${GREEN}========================================${NC}"
log "${YELLOW}Log akan disimpan di: $LOG_FILE${NC}"
log ""

# Pindah ke direktori sources
cd /sources || exit 1

# Check if sources directory is accessible
if [ ! -w /sources ]; then
    log "${RED}ERROR: /sources tidak dapat diakses atau tidak memiliki izin tulis!${NC}"
    exit 1
fi

# Hitung total packages
TOTAL_PACKAGES=7
CURRENT=0

# ==================== GETTEXT ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gettext-0.21 tar.xz

run_cmd "./configure --disable-shared" "Configuring Gettext"
run_cmd "make -j$(nproc)" "Building Gettext"
run_cmd "cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin" "Installing Gettext binaries"

finish

# ==================== BISON ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin bison-3.8.2 tar.xz

run_cmd "./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2" "Configuring Bison"
run_cmd "make -j$(nproc)" "Building Bison"
run_cmd "make install" "Installing Bison"

finish

# ==================== PERL ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin perl-5.36.0 tar.xz

run_cmd "sh Configure -des -Dprefix=/usr -Dvendorprefix=/usr -Dprivlib=/usr/lib/perl5/5.36/core_perl -Darchlib=/usr/lib/perl5/5.36/core_perl -Dsitelib=/usr/lib/perl5/5.36/site_perl -Dsitearch=/usr/lib/perl5/5.36/site_perl -Dvendorlib=/usr/lib/perl5/5.36/vendor_perl -Dvendorarch=/usr/lib/perl5/5.36/vendor_perl" "Configuring Perl"
run_cmd "make -j$(nproc)" "Building Perl"
run_cmd "make install" "Installing Perl"

finish

# ==================== LIBFFI ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin libffi-3.4.2 tar.xz

# Konfigurasi generic tanpa optimasi spesifik CPU
run_cmd "./configure --prefix=/usr \
            --disable-static \
            --disable-exec-static-tramp \
            --libdir=/usr/lib" "Configuring Libffi"

run_cmd "make -j$(nproc)" "Building Libffi"
run_cmd "make install" "Installing Libffi"

finish

# ==================== PYTHON ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin Python-3.10.6 tar.xz

# Fix Python build for LFS
run_cmd "./configure --prefix=/usr --enable-shared --without-ensurepip --with-system-ffi" "Configuring Python"
run_cmd "make -j$(nproc)" "Building Python"
run_cmd "make install" "Installing Python"

# Create symlinks for Python
log "${BLUE}Creating Python symlinks...${NC}"
ln -sf python3 /usr/bin/python
ln -sf python3-config /usr/bin/python-config

finish


# ==================== TEXINFO ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin texinfo-6.8 tar.xz

run_cmd "./configure --prefix=/usr" "Configuring Texinfo"
run_cmd "make -j$(nproc)" "Building Texinfo"
run_cmd "make install" "Installing Texinfo"

# Install info files
log "${BLUE}Installing info files...${NC}"
make TEXMF=/usr/share/texmf install-tex >> $LOG_FILE 2>&1 || log "${YELLOW}Warning: install-tex failed${NC}"

finish

# ==================== UTIL-LINUX ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin util-linux-2.38.1 tar.xz

# Create hwclock directory
mkdir -pv /var/lib/hwclock

run_cmd "./configure ADJTIME_PATH=/var/lib/hwclock/adjtime --libdir=/usr/lib --with-ncurses --with-terminfo --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv --disable-runuser --disable-pylibmount --disable-static --without-python runstatedir=/run" "Configuring Util-linux"

run_cmd "make -j$(nproc)" "Building Util-linux"
run_cmd "make install" "Installing Util-linux"

finish

# ==================== SELESAI ====================
log "${GREEN}========================================${NC}"
log "${GREEN}    BUILD LFS CHROOT SELESAI!          ${NC}"
log "${GREEN}========================================${NC}"
log "${YELLOW}Total paket yang dibangun: $TOTAL_PACKAGES${NC}"
log "${YELLOW}Log lengkap: $LOG_FILE${NC}"
log ""
log "${BLUE}Paket yang telah diinstall:${NC}"
log "  - Gettext-0.21 (msgfmt, msgmerge, xgettext)"
log "  - Bison-3.8.2"
log "  - Perl-5.36.0"
log "  - Python-3.10.6"
log "  - Texinfo-6.8"
log "  - Util-linux-2.38.1"
log ""
log "${GREEN}Lanjutkan ke langkah selanjutnya di panduan LFS.${NC}"
