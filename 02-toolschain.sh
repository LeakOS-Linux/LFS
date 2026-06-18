#!/bin/bash
# [+] Author: LynxSaiko
# LFS Build Script with Enhanced Logging and Libffi Support

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variabel global
export LFS=/mnt/lfs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH="$LFS/tools/bin:/bin:/usr/bin:$PATH"
unset CXX CC AR AS LD RANLIB STRIP

package_name=""
package_ext=""
LOG_FILE="$LFS/sources/build.log"

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
    
    # Pindah ke direktori sources LFS
    cd $LFS/sources || exit 1
    
    # Cek apakah file ada
    if [ ! -f "$package_name.$package_ext" ]; then
        log "${RED}ERROR: File $LFS/sources/$package_name.$package_ext tidak ditemukan!${NC}"
        log "${YELLOW}Pastikan file ada di $LFS/sources/${NC}"
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
    
    cd $LFS/sources
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

# ==================== PREPARATION ====================
log "${GREEN}========================================${NC}"
log "${GREEN}    MEMULAI BUILD LFS TOOLCHAIN        ${NC}"
log "${GREEN}========================================${NC}"
log "${YELLOW}LFS Directory: $LFS${NC}"
log "${YELLOW}LFS Target: $LFS_TGT${NC}"
log "${YELLOW}Log akan disimpan di: $LOG_FILE${NC}"
log ""

# Check if LFS is mounted
if ! mount | grep -q "$LFS"; then
    log "${RED}ERROR: $LFS tidak ter-mount!${NC}"
    log "${YELLOW}Mount LFS terlebih dahulu:${NC}"
    log "  mount $LFS"
    log "  mount $LFS/home  # jika ada"
    log "  mount $LFS/boot  # jika ada"
    exit 1
fi

# Check if sources directory exists
if [ ! -d "$LFS/sources" ]; then
    log "${RED}ERROR: $LFS/sources tidak ditemukan!${NC}"
    log "${YELLOW}Buat direktori sources terlebih dahulu:${NC}"
    log "  mkdir -pv $LFS/sources"
    exit 1
fi

# Check if sources directory is writable
if [ ! -w "$LFS/sources" ]; then
    log "${RED}ERROR: $LFS/sources tidak dapat ditulis!${NC}"
    exit 1
fi

# Hitung total packages
TOTAL_PACKAGES=19
CURRENT=0

cd $LFS/sources

# ==================== 5.2. BINUTILS PASS 1 ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin binutils-2.39 tar.xz

run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "../configure --prefix=$LFS/tools --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --enable-gprofng=no --disable-werror" "Configuring Binutils Pass 1"
run_cmd "make -j$(nproc)" "Building Binutils Pass 1"
run_cmd "make install" "Installing Binutils Pass 1"

finish

# ==================== 5.3. GCC PASS 1 ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gcc-12.2.0 tar.xz

run_cmd "tar -xf ../mpfr-4.1.0.tar.xz" "Extracting MPFR"
run_cmd "mv -v mpfr-4.1.0 mpfr" "Moving MPFR"
run_cmd "tar -xf ../gmp-6.2.1.tar.xz" "Extracting GMP"
run_cmd "mv -v gmp-6.2.1 gmp" "Moving GMP"
run_cmd "tar -xf ../mpc-1.2.1.tar.gz" "Extracting MPC"
run_cmd "mv -v mpc-1.2.1 mpc" "Moving MPC"

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    log "${YELLOW}Applied x86_64 lib64 fix${NC}"
  ;;
esac

run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "../configure --target=$LFS_TGT --prefix=$LFS/tools --with-glibc-version=2.36 --with-sysroot=$LFS --with-newlib --without-headers --disable-nls --disable-shared --disable-multilib --disable-decimal-float --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++" "Configuring GCC Pass 1"
run_cmd "make -j$(nproc)" "Building GCC Pass 1"
run_cmd "make install" "Installing GCC Pass 1"

cd ..
run_cmd "cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \`dirname \$($LFS_TGT-gcc -print-libgcc-file-name)\`/install-tools/include/limits.h" "Installing limits.h"

finish

# ==================== 5.4. LINUX API HEADERS ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin linux-5.10.195 tar.xz

run_cmd "make mrproper" "Cleaning Linux source"
run_cmd "make headers" "Building headers"
run_cmd "find usr/include -type f ! -name '*.h' -delete" "Removing non-header files"
run_cmd "cp -rv usr/include $LFS/usr" "Installing Linux headers"

finish

# ==================== 5.5. GLIBC ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin glibc-2.36 tar.xz

case $(uname -m) in
    i?86)   run_cmd "ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3" "Creating ld-lsb symlink" ;;
    x86_64) run_cmd "ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64" "Creating ld-linux symlink"
            run_cmd "ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3" "Creating ld-lsb symlink" ;;
esac

run_cmd "patch -Np1 -i ../glibc-2.36-fhs-1.patch" "Applying FHS patch"
run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "echo 'rootsbindir=/usr/sbin' > configparms" "Setting rootsbindir"
run_cmd "../configure --prefix=/usr --host=$LFS_TGT --build=\$(../scripts/config.guess) --enable-kernel=3.2 --with-headers=$LFS/usr/include libc_cv_slibdir=/usr/lib" "Configuring Glibc"
run_cmd "make -j$(nproc)" "Building Glibc"
run_cmd "make DESTDIR=$LFS install" "Installing Glibc"
run_cmd "sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd" "Fixing ldd"
run_cmd "echo 'int main(){}' | gcc -xc -" "Testing Glibc"
readelf -l a.out | grep ld-linux
run_cmd "rm -v a.out" "Removing test file"
run_cmd "$LFS/tools/libexec/gcc/$LFS_TGT/12.2.0/install-tools/mkheaders" "Installing headers"

finish

# ==================== 5.6. LIBSTDC++ ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gcc-12.2.0 tar.xz

run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "../libstdc++-v3/configure --host=$LFS_TGT --build=\$(../config.guess) --prefix=/usr --disable-multilib --disable-nls --disable-libstdcxx-pch --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/12.2.0" "Configuring Libstdc++"
run_cmd "make -j$(nproc)" "Building Libstdc++"
run_cmd "make DESTDIR=$LFS install" "Installing Libstdc++"
run_cmd "rm -v $LFS/usr/lib/lib{stdc++,stdc++fs,supc++}.la" "Removing .la files"

finish

# ==================== 6.2. M4 ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin m4-1.4.19 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring M4"
run_cmd "make -j$(nproc)" "Building M4"
run_cmd "make DESTDIR=$LFS install" "Installing M4"

finish

# ==================== 6.3. NCURSES ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin ncurses-6.3 tar.gz

run_cmd "sed -i s/mawk// configure" "Fixing configure"
run_cmd "mkdir build" "Creating build directory"
pushd build
run_cmd "../configure" "Configuring ncurses build"
run_cmd "make -C include" "Building ncurses include"
run_cmd "make -C progs tic" "Building tic"
popd
run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(./config.guess) --mandir=/usr/share/man --with-manpage-format=normal --with-shared --without-normal --with-cxx-shared --without-debug --without-ada --disable-stripping --enable-widec" "Configuring Ncurses"
run_cmd "make -j$(nproc)" "Building Ncurses"
run_cmd "make DESTDIR=$LFS TIC_PATH=\$(pwd)/build/progs/tic install" "Installing Ncurses"
run_cmd "echo 'INPUT(-lncursesw)' > $LFS/usr/lib/libncurses.so" "Creating libncurses symlink"

finish

# ==================== 6.4. BASH ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin bash-5.1.16 tar.gz

run_cmd "./configure --prefix=/usr --build=\$(support/config.guess) --host=$LFS_TGT --without-bash-malloc" "Configuring Bash"
run_cmd "make -j$(nproc)" "Building Bash"
run_cmd "make DESTDIR=$LFS install" "Installing Bash"
run_cmd "ln -sv bash $LFS/bin/sh" "Creating sh symlink"

finish

# ==================== 6.5. COREUTILS ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin coreutils-9.1 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess) --enable-install-program=hostname --enable-no-install-program=kill,uptime" "Configuring Coreutils"
run_cmd "make -j$(nproc)" "Building Coreutils"
run_cmd "make DESTDIR=$LFS install" "Installing Coreutils"
run_cmd "mv -v $LFS/usr/bin/chroot $LFS/usr/sbin" "Moving chroot"
run_cmd "mkdir -pv $LFS/usr/share/man/man8" "Creating man8 directory"
run_cmd "mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8" "Moving chroot man page"
run_cmd "sed -i 's/\"1\"/\"8\"/' $LFS/usr/share/man/man8/chroot.8" "Fixing chroot man page"

finish

# ==================== 6.6. DIFFUTILS ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin diffutils-3.8 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT" "Configuring Diffutils"
run_cmd "make -j$(nproc)" "Building Diffutils"
run_cmd "make DESTDIR=$LFS install" "Installing Diffutils"

finish

# ==================== 6.7. FILE ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin file-5.42 tar.gz

run_cmd "mkdir build" "Creating build directory"
pushd build
run_cmd "../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib" "Configuring file build"
run_cmd "make -j$(nproc)" "Building file"
popd
run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(./config.guess)" "Configuring File"
run_cmd "make FILE_COMPILE=\$(pwd)/build/src/file" "Building File"
run_cmd "make DESTDIR=$LFS install" "Installing File"
run_cmd "rm -v $LFS/usr/lib/libmagic.la" "Removing .la file"

finish

# ==================== 6.8. FINDUTILS ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin findutils-4.9.0 tar.xz

run_cmd "./configure --prefix=/usr --localstatedir=/var/lib/locate --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring Findutils"
run_cmd "make -j$(nproc)" "Building Findutils"
run_cmd "make DESTDIR=$LFS install" "Installing Findutils"

finish

# ==================== 6.9. GAWK ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gawk-5.1.1 tar.xz

run_cmd "sed -i 's/extras//' Makefile.in" "Fixing Makefile"
run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring Gawk"
run_cmd "make -j$(nproc)" "Building Gawk"
run_cmd "make DESTDIR=$LFS install" "Installing Gawk"

finish

# ==================== 6.10. GREP ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin grep-3.7 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT" "Configuring Grep"
run_cmd "make -j$(nproc)" "Building Grep"
run_cmd "make DESTDIR=$LFS install" "Installing Grep"

finish

# ==================== 6.11. GZIP ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gzip-1.12 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT" "Configuring Gzip"
run_cmd "make -j$(nproc)" "Building Gzip"
run_cmd "make DESTDIR=$LFS install" "Installing Gzip"

finish

# ==================== 6.12. MAKE ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin make-4.3 tar.gz

run_cmd "./configure --prefix=/usr --without-guile --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring Make"
run_cmd "make -j$(nproc)" "Building Make"
run_cmd "make DESTDIR=$LFS install" "Installing Make"

finish

# ==================== 6.13. PATCH ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin patch-2.7.6 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring Patch"
run_cmd "make -j$(nproc)" "Building Patch"
run_cmd "make DESTDIR=$LFS install" "Installing Patch"

finish

# ==================== 6.14. SED ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin sed-4.8 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT" "Configuring Sed"
run_cmd "make -j$(nproc)" "Building Sed"
run_cmd "make DESTDIR=$LFS install" "Installing Sed"

finish

# ==================== 6.15. TAR ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin tar-1.34 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess)" "Configuring Tar"
run_cmd "make -j$(nproc)" "Building Tar"
run_cmd "make DESTDIR=$LFS install" "Installing Tar"

finish

# ==================== 6.16. XZ ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin xz-5.2.6 tar.xz

run_cmd "./configure --prefix=/usr --host=$LFS_TGT --build=\$(build-aux/config.guess) --disable-static --docdir=/usr/share/doc/xz-5.2.6" "Configuring Xz"
run_cmd "make -j$(nproc)" "Building Xz"
run_cmd "make DESTDIR=$LFS install" "Installing Xz"
run_cmd "rm -v $LFS/usr/lib/liblzma.la" "Removing .la file"

finish

# ==================== 6.17. BINUTILS PASS 2 ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin binutils-2.39 tar.xz

run_cmd "sed '6009s/\$add_dir//' -i ltmain.sh" "Fixing ltmain.sh"
run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "../configure --prefix=/usr --build=\$(../config.guess) --host=$LFS_TGT --disable-nls --enable-shared --enable-gprofng=no --disable-werror --enable-64-bit-bfd" "Configuring Binutils Pass 2"
run_cmd "make -j$(nproc)" "Building Binutils Pass 2"
run_cmd "make DESTDIR=$LFS install" "Installing Binutils Pass 2"
run_cmd "rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes}.{a,la}" "Removing .a and .la files"

finish

# ==================== 6.18. GCC PASS 2 ====================
((CURRENT++))
show_progress $CURRENT $TOTAL_PACKAGES
begin gcc-12.2.0 tar.xz

run_cmd "tar -xf ../mpfr-4.1.0.tar.xz" "Extracting MPFR"
run_cmd "mv -v mpfr-4.1.0 mpfr" "Moving MPFR"
run_cmd "tar -xf ../gmp-6.2.1.tar.xz" "Extracting GMP"
run_cmd "mv -v gmp-6.2.1 gmp" "Moving GMP"
run_cmd "tar -xf ../mpc-1.2.1.tar.gz" "Extracting MPC"
run_cmd "mv -v mpc-1.2.1 mpc" "Moving MPC"

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
    log "${YELLOW}Applied x86_64 lib64 fix${NC}"
  ;;
esac

run_cmd "sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in" "Fixing thread header"
run_cmd "mkdir -v build" "Creating build directory"
cd build
run_cmd "../configure --build=\$(../config.guess) --host=$LFS_TGT --target=$LFS_TGT LDFLAGS_FOR_TARGET=-L\$PWD/\$LFS_TGT/libgcc --prefix=/usr --with-build-sysroot=$LFS --enable-initfini-array --disable-nls --disable-multilib --disable-decimal-float --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --enable-languages=c,c++" "Configuring GCC Pass 2"
run_cmd "make -j$(nproc)" "Building GCC Pass 2"
run_cmd "make DESTDIR=$LFS install" "Installing GCC Pass 2"
run_cmd "ln -sv gcc $LFS/usr/bin/cc" "Creating cc symlink"

finish

# ==================== SELESAI ====================
log ""
log "${GREEN}========================================${NC}"
log "${GREEN}    BUILD LFS TOOLCHAIN SELESAI!      ${NC}"
log "${GREEN}========================================${NC}"
log "${YELLOW}Total paket yang dibangun: $TOTAL_PACKAGES${NC}"
log "${YELLOW}Log lengkap: $LOG_FILE${NC}"
log ""
log "${BLUE}Toolchain yang telah diinstall ke $LFS:${NC}"
log "  - Binutils (Pass 1 & 2)"
log "  - GCC (Pass 1 & 2)"
log "  - Linux API Headers"
log "  - Glibc"
log "  - Libstdc++"
log "  - M4"
log "  - Ncurses"
log "  - Bash"
log "  - Coreutils"
log "  - Diffutils"
log "  - File"
log "  - Findutils"
log "  - Gawk"
log "  - Grep"
log "  - Gzip"
log "  - Make"
log "  - Patch"
log "  - Sed"
log "  - Tar"
log "  - Xz"
log ""
log "${GREEN}Verifikasi instalasi:${NC}"
log "  ls -l $LFS/usr/bin/ | grep -E '(gcc|ld|bash|make|perl|python)'"
log "  ls -l $LFS/tools/bin/"
log ""
log "${YELLOW}Langkah selanjutnya:${NC}"
log "  1. Masuk ke chroot:"
log "     chroot $LFS /usr/bin/env -i HOME=/root TERM=\"$TERM\" PS1='(lfs chroot) \\u:\\w\\$ ' PATH=/usr/bin:/usr/sbin /bin/bash --login"
log "  2. Lanjutkan dengan build paket-paket berikutnya di chroot"
log ""

# ==================== VERIFICATION ====================
log "${BLUE}Verifikasi instalasi...${NC}"

# Check if binaries exist
verify_binary() {
    local binary=$1
    local path=$2
    if [ -f "$LFS$path/$binary" ] || [ -f "$LFS$path/$binary" ]; then
        log "${GREEN}✓ $binary terinstall${NC}"
    else
        log "${YELLOW}⚠ $binary tidak ditemukan${NC}"
    fi
}

verify_binary "ld" "/usr/bin"
verify_binary "gcc" "/usr/bin"
verify_binary "bash" "/bin"
verify_binary "make" "/usr/bin"
verify_binary "sed" "/usr/bin"
verify_binary "grep" "/usr/bin"
verify_binary "tar" "/usr/bin"

log ""
log "${GREEN}========================================${NC}"
log "${GREEN}    SCRIPT SELESAI!                    ${NC}"
log "${GREEN}========================================${NC}"
