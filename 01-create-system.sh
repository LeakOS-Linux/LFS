#!/bin/bash
# [+] Author: LynxSaiko
# Pastikan variabel $LFS sudah diset
export LFS=/mnt/lfs
if [ -z "$LFS" ]; then
  echo "Variabel \$LFS belum diset. Jalankan: export LFS=/mnt/lfs"
  exit 1
fi

echo "Membuat direktori utama..."
mkdir -pv $LFS/{etc,var} \
         $LFS/usr/{bin,lib,sbin} \
         $LFS/{dev,proc,sys,run,root,srv,tools}

# Buat symlink untuk direktori bin, lib, sbin ke dalam root
echo "Membuat symlink /bin, /lib, /sbin ke /usr"
for i in bin lib sbin; do
  ln -sv usr/$i $LFS/$i
done

# Buat lib64 jika arsitektur x86_64
if [ "$(uname -m)" = "x86_64" ]; then
  echo "Membuat direktori lib64 untuk sistem 64-bit"
  mkdir -pv $LFS/lib64
fi

echo "Struktur direktori dasar LFS berhasil dibuat di: $LFS"
