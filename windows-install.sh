#!/bin/bash

# Update and install dependencies
apt update -y && apt upgrade -y
apt install grub2 wimtools ntfs-3g -y

# Get disk size and convert to MB
disk_size=$(lsblk -b -n -o SIZE /dev/sda | head -n 1)
disk_size_mb=$((disk_size / 1024 / 1024))

# Calculate partition size (25% of total size)
part_size_mb=$((disk_size_mb / 4))

# Create GPT partition table
parted /dev/sda --script -- mklabel gpt

# Create two partitions
parted /dev/sda --script -- mkpart primary ntfs 1MiB ${part_size_mb}MiB
parted /dev/sda --script -- mkpart primary ntfs $((${part_size_mb} + 1))MiB $((${part_size_mb} * 2))MiB

# Inform kernel of partition changes
partprobe /dev/sda

# Format the partitions
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

echo "NTFS partitions created"

# Mount partitions
mkdir -p /mnt /root/windisk
mount /dev/sda1 /mnt
mount /dev/sda2 /root/windisk

# Check available space
available_space=$(df /mnt --output=avail | tail -1)
if [ $available_space -lt 500000 ]; then
    echo "Not enough space on /mnt"
    exit 1
fi

# Install GRUB
grub-install --root-directory=/mnt /dev/sda

# Edit GRUB configuration
mkdir -p /mnt/boot/grub
cat <<EOF > /mnt/boot/grub/grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Download Windows ISO
wget -O /root/windisk/win10.iso "https://bit.ly/4i40x0h"
mkdir -p /root/windisk/winfile
mount -o loop /root/windisk/win10.iso /root/windisk/winfile

# Verify ISO mount
if [ ! -d "/root/windisk/winfile/sources" ]; then
    echo "Failed to mount Windows ISO"
    exit 1
fi

# Copy files
rsync -avz --progress /root/windisk/winfile/* /mnt || { echo "File transfer failed"; exit 1; }

# Unmount and prepare VirtIO
umount /root/windisk/winfile
wget -O /root/windisk/virtio.iso "https://bit.ly/4d1g7Ht"
mount -o loop /root/windisk/virtio.iso /root/windisk/winfile

mkdir -p /mnt/sources/virtio
rsync -avz --progress /root/windisk/winfile/* /mnt/sources/virtio || { echo "VirtIO transfer failed"; exit 1; }

# Update boot.wim
cd /mnt/sources
if [ -f "boot.wim" ]; then
    echo 'add virtio /virtio_drivers' > cmd.txt
    wimlib-imagex update boot.wim 2 < cmd.txt || { echo "Failed to update boot.wim"; exit 1; }
else
    echo "boot.wim not found"
    exit 1
fi

# Cleanup and reboot
umount /mnt
umount /root/windisk
reboot
