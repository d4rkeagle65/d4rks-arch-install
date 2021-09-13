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
ai_hostname=$(dialog --stdout --clear --inputbox "Enter the hostname:" 8 38)
ai_username=$(dialog --stdout --clear --inputbox "Enter your account name:" 8 38)
ai_password=$(dialog --stdout --clear --passwordbox "Enter your password:" 8 38)
ai_password2=$(dialog --stdout --clear --passwordbox "Confirm your password:" 8 38)

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
if [ $ping_cancelled -eq 1]; then
	echo "Ctrl+C Detected."
	exit;
fi


