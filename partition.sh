#!/bin/bash
export LFS=/mnt/lfs
# Periksa apakah script dijalankan dengan hak akses root
if [ "$(id -u)" -ne 0 ]; then
    echo "Harus dijalankan sebagai root!"
    exit 1
fi

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
            
            # Buat partisi extended untuk sisa partisi
            EXTENDED_START=""
            EXTENDED_END=""
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
    mkdir -pv /mnt/lfs
    mount $PARTITION_LFS /mnt/lfs
    
    # Mount home jika ada
    if [ -n "$PARTITION_HOME" ]; then
        mkdir -pv /mnt/lfs/home
        mount $PARTITION_HOME /mnt/lfs/home
    fi
    
    # Mount boot jika ada
    if [ -n "$PARTITION_BOOT" ]; then
        mkdir -pv /mnt/lfs/boot
        mount $PARTITION_BOOT /mnt/lfs/boot
    fi
}

# Fungsi untuk update fstab
update_fstab() {
    echo -e "${GREEN}Menambahkan entri ke /etc/fstab...${NC}"
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # Tambahkan root
    echo "# LFS Root Partition" >> /etc/fstab
    echo "$PARTITION_LFS  /mnt/lfs  ext4  defaults  0  1" >> /etc/fstab
    
    # Tambahkan home jika ada
    if [ -n "$PARTITION_HOME" ]; then
        echo "# LFS Home Partition" >> /etc/fstab
        echo "$PARTITION_HOME  /mnt/lfs/home  ext4  defaults  0  2" >> /etc/fstab
    fi
    
    # Tambahkan boot jika ada
    if [ -n "$PARTITION_BOOT" ]; then
        echo "# LFS Boot Partition" >> /etc/fstab
        echo "$PARTITION_BOOT  /mnt/lfs/boot  ext4  defaults  0  2" >> /etc/fstab
    fi
    
    # Tambahkan swap jika ada
    if [ -n "$PARTITION_SWAP" ]; then
        echo "# LFS Swap Partition" >> /etc/fstab
        echo "$PARTITION_SWAP  swap  swap  defaults  0  0" >> /etc/fstab
    fi
}

# Fungsi untuk menampilkan ringkasan
show_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}           PARTISI TELAH SELESAI          ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo "Disk: $DISK"
    echo "Tipe Partisi: $PART_TYPE"
    echo ""
    echo "Partisi yang dibuat:"
    lsblk $DISK
    echo ""
    echo "Informasi mount:"
    df -h | grep -E "(/mnt/lfs|$PARTITION_LFS)"
    echo ""
    echo "Fstab telah diupdate:"
    tail -10 /etc/fstab
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

# Tampilkan hasil
show_summary

echo ""
echo -e "${GREEN}LFS siap digunakan! Partisi telah terpasang di /mnt/lfs${NC}"
echo "Untuk memulai LFS, jalankan:"
echo "  cd /mnt/lfs"
echo "  dan ikuti panduan LFS selanjutnya."
echo ""
echo -e "${YELLOW}Catatan untuk MBR:${NC}"
echo "- MBR hanya mendukung maksimal 4 partisi primary"
echo "- Jika partisi > 4, akan dibuat extended dengan logical partitions"
echo "- Boot flag telah diset pada partisi root"
