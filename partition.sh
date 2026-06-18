#!/bin/bash

# Periksa apakah script dijalankan dengan hak akses root
if [ "$(id -u)" -ne 0 ]; then
    echo "Harus dijalankan sebagai root!"
    exit 1
fi

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set LFS variable
export LFS=/mnt/lfs

# Variabel global untuk partisi
PARTITION_SWAP=""
PARTITION_LFS=""
PARTITION_HOME=""
PARTITION_BOOT=""

# Fungsi untuk mendeteksi disk yang tersedia
detect_disks() {
    echo -e "${GREEN}Mendeteksi disk yang tersedia...${NC}"
    DISKS=()
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/vd[a-z] /dev/hd[a-z]; do
        if [ -b "$disk" ]; then
            # Skip disk yang sudah memiliki partisi LFS
            if ! mount | grep -q "$disk"; then
                DISKS+=("$disk")
            fi
        fi
    done
    
    if [ ${#DISKS[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada disk yang terdeteksi!${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Disk yang terdeteksi:${NC}"
    for i in "${!DISKS[@]}"; do
        SIZE=$(lsblk -d -o SIZE ${DISKS[$i]} | tail -1)
        MODEL=$(lsblk -d -o MODEL ${DISKS[$i]} | tail -1)
        echo "$((i+1)). ${DISKS[$i]} - $SIZE - $MODEL"
    done
}

# Fungsi untuk memilih disk
select_disk() {
    detect_disks
    echo ""
    read -p "Pilih nomor disk yang akan digunakan [1-${#DISKS[@]}]: " choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#DISKS[@]} ]; then
        echo -e "${RED}Pilihan tidak valid!${NC}"
        exit 1
    fi
    
    DISK="${DISKS[$((choice-1))]}"
    echo -e "${GREEN}Disk yang dipilih: $DISK${NC}"
}

# Fungsi untuk memilih tipe partisi
select_partition_type() {
    echo ""
    echo -e "${YELLOW}Pilih tipe partisi:${NC}"
    echo "1. GPT (UEFI) - Direkomendasikan untuk sistem modern"
    echo "2. MBR (BIOS) - Untuk sistem lama atau kompatibilitas"
    echo ""
    read -p "Pilihan [1/2]: " PART_TYPE
    
    case $PART_TYPE in
        1)
            PART_TYPE="gpt"
            echo -e "${GREEN}Menggunakan GPT${NC}"
            ;;
        2)
            PART_TYPE="msdos"
            echo -e "${GREEN}Menggunakan MBR (msdos)${NC}"
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid! Menggunakan GPT sebagai default${NC}"
            PART_TYPE="gpt"
            ;;
    esac
}

# Fungsi untuk menampilkan konfigurasi partisi
show_partition_plan() {
    echo ""
    echo -e "${YELLOW}=== RENCANA PARTISI ===${NC}"
    echo "Disk: $DISK"
    echo "Tipe Partisi: $PART_TYPE"
    echo "LFS Directory: $LFS"
    echo "Partisi yang akan dibuat:"
    
    PART_NUM=1
    if [ "$CREATE_SWAP" = "y" ] || [ "$CREATE_SWAP" = "Y" ]; then
        echo "  - ${DISK}${PART_NUM}: Swap (${SWAP_SIZE}G)"
        ((PART_NUM++))
    fi
    
    echo "  - ${DISK}${PART_NUM}: Root (/) - ${LFS_SIZE}G (ext4)"
    ((PART_NUM++))
    
    if [ "$CREATE_HOME" = "y" ] || [ "$CREATE_HOME" = "Y" ]; then
        echo "  - ${DISK}${PART_NUM}: Home (/home) - ${HOME_SIZE}G (ext4)"
        ((PART_NUM++))
    fi
    
    if [ "$CREATE_BOOT" = "y" ] || [ "$CREATE_BOOT" = "Y" ]; then
        echo "  - ${DISK}${PART_NUM}: Boot (/boot) - ${BOOT_SIZE}G (ext4)"
        ((PART_NUM++))
    fi
    
    echo ""
    read -p "Lanjutkan dengan partisi ini? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Dibatalkan oleh user.${NC}"
        exit 0
    fi
}

# Fungsi untuk membuat partisi menggunakan parted
create_partitions() {
    echo -e "${GREEN}Membuat partisi pada $DISK...${NC}"
    
    # Hapus semua partisi yang ada (jika ada)
    echo "Menghapus semua partisi yang ada..."
    parted -s $DISK mklabel $PART_TYPE
    
    # Counter untuk nomor partisi
    PART_NUM=1
    
    # Untuk MBR, maksimal 4 partisi primary
    if [ "$PART_TYPE" = "msdos" ]; then
        TOTAL_PARTS=0
        [ "$CREATE_SWAP" = "y" ] && ((TOTAL_PARTS++))
        ((TOTAL_PARTS++)) # root
        [ "$CREATE_HOME" = "y" ] && ((TOTAL_PARTS++))
        [ "$CREATE_BOOT" = "y" ] && ((TOTAL_PARTS++))
        
        if [ $TOTAL_PARTS -gt 4 ]; then
            echo -e "${RED}PERINGATAN: MBR hanya mendukung maksimal 4 partisi primary!${NC}"
            echo "Partisi akan dibuat dengan 3 primary + 1 extended"
        fi
    fi
    
    # Buat partisi swap jika diminta
    if [ "$CREATE_SWAP" = "y" ] || [ "$CREATE_SWAP" = "Y" ]; then
        echo "Membuat partisi swap (${SWAP_SIZE}G)..."
        if [ "$PART_TYPE" = "gpt" ]; then
            parted -s $DISK mkpart primary linux-swap 0% ${SWAP_SIZE}G
            parted -s $DISK set $PART_NUM swap on
        else
            # MBR
            parted -s $DISK mkpart primary linux-swap 0% ${SWAP_SIZE}G
            parted -s $DISK set $PART_NUM swap on
        fi
        PARTITION_SWAP="${DISK}${PART_NUM}"
        ((PART_NUM++))
    fi
    
    # Buat partisi root (LFS)
    START_POS="0%"
    if [ "$CREATE_SWAP" = "y" ] || [ "$CREATE_SWAP" = "Y" ]; then
        START_POS="${SWAP_SIZE}G"
    fi
    
    echo "Membuat partisi root (${LFS_SIZE}G)..."
    END_POS="${START_POS}+${LFS_SIZE}G"
    parted -s $DISK mkpart primary ext4 $START_POS $END_POS
    PARTITION_LFS="${DISK}${PART_NUM}"
    ((PART_NUM++))
    
    # Untuk MBR, jika total partisi > 4, buat extended
    if [ "$PART_TYPE" = "msdos" ] && [ $TOTAL_PARTS -gt 4 ]; then
        # Buat extended partition
        echo "Membuat extended partition untuk partisi tambahan..."
        EXTENDED_START="$END_POS"
        parted -s $DISK mkpart extended $EXTENDED_START 100%
        EXTENDED_PART="${DISK}${PART_NUM}"
        ((PART_NUM++))
        
        # Reset PART_NUM untuk logical partitions
        LOGICAL_NUM=5
    fi
    
    # Buat partisi home jika diminta
    if [ "$CREATE_HOME" = "y" ] || [ "$CREATE_HOME" = "Y" ]; then
        START_POS="$END_POS"
        END_POS="${START_POS}+${HOME_SIZE}G"
        echo "Membuat partisi home (${HOME_SIZE}G)..."
        
        if [ "$PART_TYPE" = "gpt" ]; then
            parted -s $DISK mkpart primary ext4 $START_POS $END_POS
            PARTITION_HOME="${DISK}${PART_NUM}"
            ((PART_NUM++))
        else
            # MBR - jika ada extended, buat logical
            if [ -n "$EXTENDED_PART" ]; then
                parted -s $DISK mkpart logical ext4 $START_POS $END_POS
                PARTITION_HOME="${DISK}${LOGICAL_NUM}"
                ((LOGICAL_NUM++))
            else
                parted -s $DISK mkpart primary ext4 $START_POS $END_POS
                PARTITION_HOME="${DISK}${PART_NUM}"
                ((PART_NUM++))
            fi
        fi
    fi
    
    # Buat partisi boot jika diminta
    if [ "$CREATE_BOOT" = "y" ] || [ "$CREATE_BOOT" = "Y" ]; then
        START_POS="$END_POS"
        END_POS="${START_POS}+${BOOT_SIZE}G"
        echo "Membuat partisi boot (${BOOT_SIZE}G)..."
        
        if [ "$PART_TYPE" = "gpt" ]; then
            parted -s $DISK mkpart primary ext4 $START_POS $END_POS
            PARTITION_BOOT="${DISK}${PART_NUM}"
            ((PART_NUM++))
        else
            # MBR - jika ada extended, buat logical
            if [ -n "$EXTENDED_PART" ]; then
                parted -s $DISK mkpart logical ext4 $START_POS $END_POS
                PARTITION_BOOT="${DISK}${LOGICAL_NUM}"
                ((LOGICAL_NUM++))
            else
                parted -s $DISK mkpart primary ext4 $START_POS $END_POS
                PARTITION_BOOT="${DISK}${PART_NUM}"
                ((PART_NUM++))
            fi
        fi
    fi
    
    # Untuk MBR, set boot flag pada partisi root
    if [ "$PART_TYPE" = "msdos" ]; then
        echo "Setting boot flag pada partisi root..."
        parted -s $DISK set 1 boot on
    fi
    
    echo "Menunggu kernel memperbarui partisi..."
    sleep 3
    partprobe $DISK
}

# Fungsi untuk memformat partisi
format_partitions() {
    echo -e "${GREEN}Memformat partisi...${NC}"
    
    # Format swap jika ada
    if [ -n "$PARTITION_SWAP" ]; then
        echo "Memformat swap pada $PARTITION_SWAP..."
        mkswap $PARTITION_SWAP
        swapon $PARTITION_SWAP
    fi
    
    # Format root partition
    echo "Memformat root pada $PARTITION_LFS dengan ext4..."
    mkfs.ext4 -F $PARTITION_LFS
    
    # Format home partition jika ada
    if [ -n "$PARTITION_HOME" ]; then
        echo "Memformat home pada $PARTITION_HOME dengan ext4..."
        mkfs.ext4 -F $PARTITION_HOME
    fi
    
    # Format boot partition jika ada
    if [ -n "$PARTITION_BOOT" ]; then
        echo "Memformat boot pada $PARTITION_BOOT dengan ext4..."
        mkfs.ext4 -F $PARTITION_BOOT
    fi
}

# Fungsi untuk mount partitions
mount_partitions() {
    echo -e "${GREEN}Mounting partitions...${NC}"
    
    # Mount root
    mkdir -pv $LFS
    mount $PARTITION_LFS $LFS
    
    # Mount home jika ada
    if [ -n "$PARTITION_HOME" ]; then
        mkdir -pv $LFS/home
        mount $PARTITION_HOME $LFS/home
    fi
    
    # Mount boot jika ada
    if [ -n "$PARTITION_BOOT" ]; then
        mkdir -pv $LFS/boot
        mount $PARTITION_BOOT $LFS/boot
    fi
}

# Fungsi untuk update fstab
update_fstab() {
    echo -e "${GREEN}Menambahkan entri ke /etc/fstab...${NC}"
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Tambahkan root
    echo "# LFS Root Partition" >> /etc/fstab
    echo "$PARTITION_LFS  $LFS  ext4  defaults  0  1" >> /etc/fstab
    
    # Tambahkan home jika ada
    if [ -n "$PARTITION_HOME" ]; then
        echo "# LFS Home Partition" >> /etc/fstab
        echo "$PARTITION_HOME  $LFS/home  ext4  defaults  0  2" >> /etc/fstab
    fi
    
    # Tambahkan boot jika ada
    if [ -n "$PARTITION_BOOT" ]; then
        echo "# LFS Boot Partition" >> /etc/fstab
        echo "$PARTITION_BOOT  $LFS/boot  ext4  defaults  0  2" >> /etc/fstab
    fi
    
    # Tambahkan swap jika ada
    if [ -n "$PARTITION_SWAP" ]; then
        echo "# LFS Swap Partition" >> /etc/fstab
        echo "$PARTITION_SWAP  swap  swap  defaults  0  0" >> /etc/fstab
    fi
}

# Fungsi untuk membuat file environment LFS dengan dynamic mount
create_lfs_environment() {
    echo -e "${GREEN}Membuat environment file untuk LFS...${NC}"
    
    # Buat file .bashrc untuk LFS
    cat > $LFS/.bashrc << "EOF"
set +h
umask 022
# LFS Environment
export LFS=/mnt/lfs
export LC_ALL=POSIX
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH=/tools/bin:/bin:/usr/bin
export MAKEFLAGS='-j$(nproc)'
export LFS LC_ALL LFS_TGT
EOF

    # Buat file profile untuk LFS
    cat > $LFS/.profile << "EOF"
set +h
umask 022
# LFS Profile
export LFS=/mnt/lfs
export LC_ALL=POSIX
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH=/tools/bin:/bin:/usr/bin
export MAKEFLAGS='-j$(nproc)
export LFS LC_ALL LFS_TGT
EOF

    # Buat file environment dengan fungsi mount/umount otomatis
    cat > /root/lfs_env.sh << EOF
#!/bin/bash
# LFS Environment Variables - Generated by LFS Partition Script
# Date: $(date)

export LFS=/mnt/lfs
export LC_ALL=POSIX
export LFS_TGT=\$(uname -m)-lfs-linux-gnu
export PATH=/tools/bin:/bin:/usr/bin
export MAKEFLAGS='-j$(nproc)'

# Partisi yang digunakan
PARTITION_LFS="$PARTITION_LFS"
PARTITION_SWAP="$PARTITION_SWAP"
PARTITION_HOME="$PARTITION_HOME"
PARTITION_BOOT="$PARTITION_BOOT"

# Function untuk mount LFS
mount_lfs() {
    echo "Mounting LFS partitions..."
    
    # Mount root
    if ! mount | grep -q "\$PARTITION_LFS"; then
        mount -v -t ext4 \$PARTITION_LFS \$LFS
    else
        echo "Root partition already mounted"
    fi
    
    # Mount home jika ada
    if [ -n "\$PARTITION_HOME" ]; then
        if ! mount | grep -q "\$PARTITION_HOME"; then
            mkdir -pv \$LFS/home
            mount -v -t ext4 \$PARTITION_HOME \$LFS/home
        else
            echo "Home partition already mounted"
        fi
    fi
    
    # Mount boot jika ada
    if [ -n "\$PARTITION_BOOT" ]; then
        if ! mount | grep -q "\$PARTITION_BOOT"; then
            mkdir -pv \$LFS/boot
            mount -v -t ext4 \$PARTITION_BOOT \$LFS/boot
        else
            echo "Boot partition already mounted"
        fi
    fi
    
    # Enable swap jika ada
    if [ -n "\$PARTITION_SWAP" ]; then
        if ! swapon --show | grep -q "\$PARTITION_SWAP"; then
            swapon -v \$PARTITION_SWAP
        else
            echo "Swap already enabled"
        fi
    fi
    
    echo "LFS mounted successfully!"
    df -h | grep -E "(\$LFS|\$PARTITION_LFS|\$PARTITION_HOME|\$PARTITION_BOOT)"
}

# Function untuk unmount LFS
umount_lfs() {
    echo "Unmounting LFS partitions..."
    
    # Disable swap jika ada
    if [ -n "\$PARTITION_SWAP" ]; then
        if swapon --show | grep -q "\$PARTITION_SWAP"; then
            swapoff -v \$PARTITION_SWAP
        fi
    fi
    
    # Unmount boot jika ada
    if [ -n "\$PARTITION_BOOT" ]; then
        if mount | grep -q "\$PARTITION_BOOT"; then
            umount -v \$LFS/boot
        fi
    fi
    
    # Unmount home jika ada
    if [ -n "\$PARTITION_HOME" ]; then
        if mount | grep -q "\$PARTITION_HOME"; then
            umount -v \$LFS/home
        fi
    fi
    
    # Unmount root
    if mount | grep -q "\$PARTITION_LFS"; then
        umount -v \$LFS
    fi
    
    echo "LFS unmounted successfully!"
}

# Function untuk cek status mount
status_lfs() {
    echo "=== LFS Status ==="
    echo "LFS Directory: \$LFS"
    echo ""
    echo "Partisi:"
    echo "  Root: \$PARTITION_LFS"
    [ -n "\$PARTITION_SWAP" ] && echo "  Swap: \$PARTITION_SWAP"
    [ -n "\$PARTITION_HOME" ] && echo "  Home: \$PARTITION_HOME"
    [ -n "\$PARTITION_BOOT" ] && echo "  Boot: \$PARTITION_BOOT"
    echo ""
    echo "Mount status:"
    df -h | grep -E "(\$LFS|\$PARTITION_LFS|\$PARTITION_HOME|\$PARTITION_BOOT)" || echo "  No LFS partitions mounted"
    echo ""
    echo "Swap status:"
    swapon --show || echo "  No swap enabled"
}

echo -e "\033[0;32m=========================================\033[0m"
echo -e "\033[0;32m      LFS ENVIRONMENT LOADED           \033[0m"
echo -e "\033[0;32m=========================================\033[0m"
echo "LFS=\$LFS"
echo "LFS_TGT=\$LFS_TGT"
echo ""
echo -e "\033[1;33mFungsi tersedia:\033[0m"
echo "  mount_lfs  - Mount semua partisi LFS (auto-detect if already mounted)"
echo "  umount_lfs - Unmount semua partisi LFS (safe unmount)"
echo "  status_lfs - Cek status mount LFS"
echo ""
echo -e "\033[1;33mPartisi yang digunakan:\033[0m"
echo "  Root: \$PARTITION_LFS"
[ -n "\$PARTITION_SWAP" ] && echo "  Swap: \$PARTITION_SWAP"
[ -n "\$PARTITION_HOME" ] && echo "  Home: \$PARTITION_HOME"
[ -n "\$PARTITION_BOOT" ] && echo "  Boot: \$PARTITION_BOOT"
echo -e "\033[0;32m=========================================\033[0m"
EOF

    # Update .bashrc root untuk auto-load LFS environment
    if ! grep -q "lfs_env.sh" /root/.bashrc; then
        echo "# Load LFS environment" >> /root/.bashrc
        echo "if [ -f /root/lfs_env.sh ]; then" >> /root/.bashrc
        echo "    source /root/lfs_env.sh" >> /root/.bashrc
        echo "fi" >> /root/.bashrc
    fi

    # Buat symlink yang berguna
    ln -sf $LFS /lfs
    
    chmod +x /root/lfs_env.sh
}

# Fungsi untuk menampilkan ringkasan
show_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}           PARTISI TELAH SELESAI          ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo "Disk: $DISK"
    echo "Tipe Partisi: $PART_TYPE"
    echo "LFS Directory: $LFS"
    echo ""
    echo "Partisi yang dibuat:"
    lsblk $DISK
    echo ""
    echo "Informasi mount:"
    df -h | grep -E "($LFS|$PARTITION_LFS|$PARTITION_HOME|$PARTITION_BOOT)"
    echo ""
    echo "Fstab telah diupdate:"
    tail -10 /etc/fstab
    echo ""
    echo -e "${BLUE}Environment LFS:${NC}"
    echo "  - File environment: /root/lfs_env.sh"
    echo "  - Symlink: /lfs -> $LFS"
    echo "  - Auto-load sudah ditambahkan ke /root/.bashrc"
    echo ""
    echo -e "${YELLOW}Partisi yang terdeteksi di environment:${NC}"
    echo "  Root: $PARTITION_LFS"
    [ -n "$PARTITION_SWAP" ] && echo "  Swap: $PARTITION_SWAP"
    [ -n "$PARTITION_HOME" ] && echo "  Home: $PARTITION_HOME"
    [ -n "$PARTITION_BOOT" ] && echo "  Boot: $PARTITION_BOOT"
    echo ""
    echo -e "${YELLOW}Untuk menggunakan environment LFS:${NC}"
    echo "  source /root/lfs_env.sh"
    echo "  atau logout dan login kembali (sebagai root)"
    echo ""
    echo -e "${YELLOW}Fungsi yang tersedia:${NC}"
    echo "  mount_lfs   - Mount semua partisi LFS"
    echo "  umount_lfs  - Unmount semua partisi LFS"
    echo "  status_lfs  - Cek status mount LFS"
    echo -e "${GREEN}=========================================${NC}"
}

# ===== MAIN PROGRAM =====

echo -e "${GREEN}=== SCRIPT PARTISI OTOMATIS UNTUK LFS ===${NC}"
echo ""

# Pilih disk
select_disk

# Pilih tipe partisi
select_partition_type

# Tanyakan konfigurasi partisi
echo ""
echo -e "${YELLOW}Konfigurasi Partisi:${NC}"

read -p "Buat partisi swap? [y/N]: " CREATE_SWAP
if [[ "$CREATE_SWAP" =~ ^[Yy]$ ]]; then
    read -p "Ukuran swap (GB) [2]: " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-2}
fi

read -p "Ukuran partisi root/LFS (GB) [20]: " LFS_SIZE
LFS_SIZE=${LFS_SIZE:-20}

read -p "Buat partisi /home terpisah? [y/N]: " CREATE_HOME
if [[ "$CREATE_HOME" =~ ^[Yy]$ ]]; then
    read -p "Ukuran home (GB) [10]: " HOME_SIZE
    HOME_SIZE=${HOME_SIZE:-10}
fi

read -p "Buat partisi /boot terpisah? [y/N]: " CREATE_BOOT
if [[ "$CREATE_BOOT" =~ ^[Yy]$ ]]; then
    read -p "Ukuran boot (GB) [1]: " BOOT_SIZE
    BOOT_SIZE=${BOOT_SIZE:-1}
fi

# Tampilkan rencana partisi
show_partition_plan

# Eksekusi pembuatan partisi
create_partitions
format_partitions
mount_partitions
update_fstab

# Buat environment LFS
create_lfs_environment

# Tampilkan hasil
show_summary

echo ""
echo -e "${GREEN}LFS siap digunakan!${NC}"
echo ""
echo "Langkah selanjutnya:"
echo "1. Source environment: source /root/lfs_env.sh"
echo "2. Mulai build LFS: cd $LFS"
echo "3. Ikuti panduan di: https://www.linuxfromscratch.org/lfs/view/stable/"
echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "- Gunakan 'mount_lfs' untuk mount semua partisi (sudah otomatis detect jika sudah ter-mount)"
echo "- Gunakan 'umount_lfs' untuk unmount semua partisi (safe unmount)"
echo "- Gunakan 'status_lfs' untuk cek status mount"
echo "- File source code akan diletakkan di $LFS/sources"
