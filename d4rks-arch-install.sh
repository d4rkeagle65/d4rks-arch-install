#!/usr/bin/env bash

LOGFILENAME=arch-install.log
LOGFILE=/root/${LOGFILENAME}
exec > >(tee -i ${LOGFILE})
exec 2>&1

# Remounts cowspace with 1G of space for the extra packages we need to setup the env
mount -o remount,size=1G /run/archiso/cowspace

pacman -Syy
yes | pacman -Sy pacman-contrib dialog git make

# Prompts
EMAIL='dhardin@hardinsolutions.net'
FNAME='David'
LNAME='Hardin'
#ai_hostname=$(dialog --stdout --clear --inputbox "Enter the hostname:" 8 38)
#ai_username=$(dialog --stdout --clear --inputbox "Enter your account name:" 8 38)
ai_password=$(dialog --stdout --clear --passwordbox "Enter your password:" 8 38)
ai_password2=$(dialog --stdout --clear --passwordbox "Confirm your password:" 8 38)

ai_hostname=dhardin-arch01a
ai_username=dhardin

if [[ ! $ai_password = $ai_password2 ]]; then
	echo "Password did not match confirmation."
	exit
fi

ai_devicelist=$(lsblk -dlpnx size -o name,size | grep -Ev "boot|rpmb|loop|sr0" | tac)
ai_devicelist_count=$(echo $ai_devicelist | wc -l)
if [[ $ai_devicelist_count = 1 ]]; then
	ai_device=$(echo $ai_devicelist | cut -d' ' -f1)
elif [[ $ai_devicelist_count = 0 ]]; then
	echo "Unable to find disk device."
	exit;
else 
	ai_device=$(dialog --stdout --clear --menu "Select installation disk" 0 0 0 ${ai_devicelist})
fi

if [[ $ai_device =~ "nvme" ]]; then
	ai_partIdent="p"
fi

clear

if ! ping -c 1 "google.com" >/dev/null 2>&1; then
	echo "Cant connect to the internet."
	exit;
fi

# Waits for IP to be assigned from DHCP, keeps checking and looping until google.com is pingable.
ping_cancelled=0
until ping -c1 "google.com" >/dev/null 2>&1; do :; done &
trap "kill $!; ping_cancelled=1" SIGINT
wait $!
trap - SIGINT
if [ $ping_cancelled -eq 1 ]; then
	echo "Ctrl+C Detected."
	exit;
fi

cpu_arch=$(lscpu | grep Architecture | cut -d':' -f2 | sed 's/ *//g')
if [[ $cpu_arch = "x86_64" ]]; then
	mirrorlist_url="https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4&use_mirror_status=on"
else
	echo "Unable to identify cpu architecture for mirrorlist url."
	exit;
fi

cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.rank
curl -s ${mirrorlist_url} -o /root/mirrorlist.new
sed -e 's/^#Server/Server/' -e '/^#/d' -i /root/mirrorlist.new
rm /etc/pacman.d/mirrorlist
rankmirrors -n 5 /root/mirrorlist.new > /etc/pacman.d/mirrorlist
pacman -Syy

# Wipes the selected disk and sets up the 4 partitions
sgdisk -og $ai_device
sgdisk -n 1:2048:4095 -c 1:"BIOS Boot Partition" -t 1:ef02 $ai_device
sgdisk -n 2:4096:2101247 -c 2:"EFI System Partition" -t 2:ef00 $ai_device
sgdisk -n 3:2101248:6295551 -c 3:"Linux /boot" -t 3:8300 $ai_device
ENDSECTOR=`sgdisk -E $ai_device`
sgdisk -n 4:6295552:$ENDSECTOR -c 4:"Linux LVM" -t 4:8e00 $ai_device
sgdisk -p $ai_device
sleep 5

# Setup LVM volumes
pvcreate ${ai_device}${ai_partIdent}4
vgcreate vol ${ai_device}${ai_partIdent}4
lvcreate -L 1G vol -n swap
lvcreate -l 100%FREE vol -n root

# Format file systems
mkfs.fat -F32 ${ai_device}${ai_partIdent}2
mkfs.ext4 -F ${ai_device}${ai_partIdent}3
mkfs.ext4 -F /dev/mapper/vol-root
mkswap /dev/mapper/vol-swap

# Mount the filesystems
mount /dev/mapper/vol-root /mnt
mkdir /mnt/boot
mount ${ai_device}${ai_partIdent}3 /mnt/boot
mkdir /mnt/boot/efi
mount ${ai_device}${ai_partIdent}2 /mnt/boot/efi
swapon /dev/mapper/vol-swap

pkgs=`tr '\n' ' ' < ./pacstrap-pkgs-initial.txt`
pacstrap /mnt `echo $pkgs`

cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
genfstab -U -p /mnt > /mnt/etc/fstab

mkdir /mnt/hostrun
mount --bind /run /mnt/hostrun

