#!/bin/bash

# Update and upgrade the system
apt update -y && apt upgrade -y

# Install necessary packages
apt install grub2 wimtools ntfs-3g -y

# Get the disk size in GB and convert to MB
disk_size_gb=100  # You have a 100 GB disk, so set this directly
disk_size_mb=$((disk_size_gb * 1024))

# Calculate partition sizes
part1_size_mb=$((80 * 1024))  # 80 GB for the first partition
part2_size_mb=$((10 * 1024))  # 10 GB for the second partition
free_space_mb=$((disk_size_mb - part1_size_mb - part2_size_mb))  # Free space (10 GB)

# Create GPT partition table
parted /dev/sda --script -- mklabel gpt

# Create two partitions:
# Partition 1: 80 GB for Windows installer
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part1_size_mb}MB

# Partition 2: 10 GB for additional space
parted /dev/sda --script -- mkpart primary ntfs ${part1_size_mb}MB $((part1_size_mb + part2_size_mb))MB

# Inform kernel of partition table changes
partprobe /dev/sda

sleep 30

# Format the partitions to NTFS
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

echo "NTFS partitions created"

# Create a new GPT partition table using gdisk
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda

# Mount the first partition for Windows installation
mount /dev/sda1 /mnt

# Prepare directory for the Windows disk
cd ~
mkdir windisk

# Mount the second partition
mount /dev/sda2 windisk

# Install GRUB on the disk
grub-install --root-directory=/mnt /dev/sda

# Create GRUB configuration file for Windows installer
cd /mnt/boot/grub
cat <<EOF > grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Download Windows ISO
cd /root/windisk
mkdir winfile

# Download the Windows 2022 ISO (Windows 10/11 ISO URL used for the example)
#Win10    http://bit.ly/4fLnOSY
#Win10-1  https://anonvids.com/win10.iso
wget -O win2022.iso --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" "http://bit.ly/4fLnOSY"


# Mount the Windows ISO
mount -o loop win2022.iso winfile

# Copy Windows files to the first partition
rsync -avz --progress winfile/* /mnt

# Unmount the ISO
umount winfile

# Download VirtIO drivers
wget -O virtio.iso https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

# Mount the VirtIO ISO
mount -o loop virtio.iso winfile

# Create directory for VirtIO drivers
mkdir /mnt/sources/virtio

# Copy VirtIO drivers to the first partition
rsync -avz --progress winfile/* /mnt/sources/virtio

# Update boot.wim to add VirtIO drivers
cd /mnt/sources
touch cmd.txt
echo 'add virtio /virtio_drivers' >> cmd.txt
wimlib-imagex update boot.wim 2 < cmd.txt

# Reboot to finalize setup
reboot
