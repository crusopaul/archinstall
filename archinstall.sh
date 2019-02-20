#!/bin/bash
# Created 2/14/19
# Written by Paul Caruso

# Some global variables for color styling
STATUS="\033[38;5;208m"
INSTRUCTION="\033[38;5;45m"
INPUT="\033[38;5;141m"
GOOD="\033[38;5;40m"
NOTE="\033[38;5;220m"
BAD="\033[38;5;9m"
RESET="\033[0m"

# Acknoledgement check
userAck () {
	echo -e "${INPUT}Press enter if you understand...${RESET}"
	read
}

# Verifies a UEFI boot
verifyUEFI () {
	echo -en "${STATUS}Checking boot mode...\t"
	if [ -d /sys/firmware/efi/efivars ]
	then
		echo -e "${GOOD}UEFI"
		echo -e "Correct boot mode verified${RESET}"
	else 
		echo -e "${BAD}Legacy${RESET}"
		echo -e "${BAD}Aborting...${RESET}"
		exit 1
	fi
}

# Verifies and makes WiFi connection
wifiConf() {
	echo -e "${STATUS}Checking Wifi connection feasability...${RESET}"
	
	# Check for existence of kernel module
	if [ -n "$(lspci -v | grep $1)" ]
	then
		echo -e "${GOOD}\t\"$1\" Kernel Module exists...${RESET}"
	else
		echo -e "${BAD}\tNo \"$1\" Kernel Module exists${RESET}"
		echo -e "${BAD}Aborting...${RESET}"
		exit 1
	fi
	
	# Check for loaded module
	if [ -n "$(dmesg | grep $1)" ]
	then
		echo -e "${GOOD}\t\"$1\" Kernel Module is loaded${RESET}"
	else
		echo -e "${BAD}\t\"$1\" Kernel Module is not loaded...${RESET}"
		echo -e "${BAD}Aborting...${RESET}"
		exit 1
	fi
	
	# Connect to network
	echo -e "${STATUS}\tConnecting to a WiFi Network...${RESET}"
	sleep 5
	connected="no"
	while [ "$connected" != "yes" ]
	do
		wifi-menu
		sleep 10
		ip addr show
		echo -en "\n${INPUT}Is WiFi connected? (yes/no): ${RESET}"
		read connected
	done
	echo -e "${GOOD}WiFi is connected${RESET}"
}

# Partions a specified device
partition () {
	# Let user choose a disk
	disk=""
	while [[ ! -e $disk && -z "$disk" ]]
	do
		fdisk -l
		echo -en "${INPUT}Choose an available device to partition: ${RESET}"
		read disk
	done
	
	# Partition the disk
	diskRootNum=0
	while [ $diskRootNum -eq 0 ]
	do
		fdisk -l $disk
		echo -en "${INPUT}Please choose the number for your new linux partition: ${RESET}"
		read diskRootNum
	done
	diskBootNum=0
	if [ $# -eq 3 ]
	then
		while [ $diskBootNum -eq 0 ]
		do
			fdisk -l $disk
			echo -en "${INPUT}Please choose the number of the windows boot partition: ${RESET}"
			read diskBootNum
		done
	fi
	echo -e "${STATUS}Partitioning...${RESET}"
	sgdisk -n=$diskRootNum:0:0 -t=$diskRootNum:8304 $disk
	if [ $# -eq 3 ]
	then
		eval "$1=\"$disk\""
		eval "$2=$diskRootNum"
		eval "$3=$diskBootNum"
	fi
	echo -e "${GOOD}Partitioning successful${RESET}"
}

# Formats the DISK partitions
format () {
	# Format root as ext4
	echo -e "${STATUS}Formatting /...${RESET}"
	if [ $# -eq 1 ]
	then
		mkfs.ext4 $1
	else
		mkfs.ext4 ${DISK}$DISKROOTNUM
	fi
	echo -e "${GOOD}Formatting sucessful${RESET}"
}

# Mount the DISK
mountDisk () {
	# Mounting procedure
	echo -e "${STATUS}Mounting install disk...${RESET}"
	
	# Mount root
	echo -e "${STATUS}\tMounting /mnt${RESET}"
	if [ $# -eq 2 ]
	then
		mount $1 /mnt
	else
		mount ${DISK}$DISKROOTNUM /mnt
	fi
	
	# Make and mount boot
	echo -e "${STATUS}\tMaking and Mounting /mnt/boot${RESET}"
	mkdir /mnt/boot
	if [ $# -eq 2 ]
	then
		mount -t vfat $2 /mnt/boot
	else
		mount -t vfat ${DISK}$DISKBOOTNUM /mnt/boot
	fi
	echo -e "${GOOD}Mount sucessful${RESET}"
}

# Select some good mirrors
selectMirrors () {
	# Fetch reflector
	echo -e "${STATUS}Fetching reflector to sort mirrors by rate...${RESET}"
	pacman -Sy
	pacman -S --noconfirm reflector
	echo -e "${GOOD}Got reflector${RESET}"
	
	# Sort mirrors
	echo -e "${STATUS}Sorting mirrors...${RESET}"
	reflector --country 'United States' --sort rate --save /etc/pacman.d/mirrorlist -n 5
	echo -e "${GOOD}Optimal mirrors selected${RESET}"
}

# Install the base
installBase () {
	# Send it
	echo -e "${STATUS}Installing base and base-devel. This might take a while...${RESET}"
	pacstrap /mnt base base-devel
	mkdir /mnt/etc/pacman.d/mirrorlist
	cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
	echo -e "${GOOD}base and base-devel installed${RESET}"
}

# Configuration :(
configSys () {
	# Fstab
	echo -e "${STATUS}Generating fstab file...${RESET}"
	genfstab -U /mnt > /mnt/etc/fstab
	echo -e "${GOOD}Fstab generated${RESET}"
	
	# Chroot
	# All the following commands need to be chroot'd
	
	# Time zone
	echo -e "${STATUS}Setting time zone...${RESET}"
	arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
	arch-chroot /mnt hwclock --systohc
	echo -e "${GOOD}Time set${RESET}"
	
	# Localization
	echo -e "${STATUS}Setting localization...${RESET}"
	echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
	echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
	arch-chroot /mnt locale-gen
	echo -e "${GOOD}Localization set${RESET}"
	
	
	# Network Configuration
	echo -en "${INPUT}Please choose a hostname: ${RESET}"
	read hostname
	echo $hostname > /mnt/etc/hostname 
	echo -e "${GOOD}Hostname set${RESET}"
	echo -e "${STATUS}Fetching/configuring proper network client and updating repo and settings...${RESET}"
	echo -ne "\n[repo-ck]\nServer = http://repo-ck.com/\$arch\n\n" >> /mnt/etc/pacman.conf
	echo -e "${STATUS}Forced mirror update on install location${RESET}"
	arch-chroot /mnt pacman -Sy
	echo -e "${GOOD}Mirrors up to date${RESET}"
	arch-chroot /mnt pacman-key --init
	arch-chroot /mnt pacman-key --populate archlinux
	arch-chroot /mnt pacman-key -r 5EE46C4C
	arch-chroot /mnt pacman-key --lsign-key 5EE46C4C
	arch-chroot /mnt pacman -S --noconfirm networkmanager network-manager-applet polkit
	if [ -n "$(systemctl --type=service | grep netctl)" ]
	then
		arch-chroot /mnt systemctl disable netctl
	fi
	arch-chroot /mnt systemctl enable NetworkManager
	arch-chroot /mnt touch /etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	echo "polkit.addRule(function(action, subject) {" > /mnt/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	echo -e "  if (action.id.indexOf(\"org.freedesktop.NetworkManager.\") == 0 && subject.isInGroup(\"network\")) {" >> /mnt/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	echo "    return polkit.Result.YES;" >> /mnt/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	echo "  }" >> /mnt/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	echo "});" >> /mnt/etc/polkit-1/rules.d/50-org.freedesktop.NetworkManager.rules
	arch-chroot /mnt pacman -Rss netctl
	echo -e "${GOOD}Network is finally usable${RESET}"
	
	# A little mkinitcpio tweaking for plymouth
	echo -e "${INSTRUCTION}Please manually add sd-plymouth after \"base udev\" or \"base systemd\" to HOOKS=()${RESET}"
	userAck
	arch-chroot /mnt nano /etc/mkinitcpio.conf
	echo -e "${INSTRUCTION}Please manually add i915 to MODULES=()${RESET}"
	userAck
	arch-chroot /mnt nano /etc/mkinitcpio.conf
	echo -e "${NOTE}NOTE: You must run mkinitcpio after installing plymouth!${RESET}"
	userAck
}

# Set up GRUB as the bootloader
setupGRUB () {
	# Get GRUB installed and set up
	echo -e "${STATUS}Fetching GRUB...${RESET}"
	arch-chroot /mnt pacman -S --noconfirm grub efibootmgr intel-ucode os-prober
	echo -e "${GOOD}GRUB fetched${RESET}"
	echo -e "${STATUS}Installing GRUB to disk...${RESET}"
	arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
	echo -e "${GOOD}GRUB installed${RESET}"
	echo -e "${STATUS}Configuring GRUB...${RESET}"
	arch-chroot /mnt sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/g" /etc/default/grub
	arch-chroot /mnt sed -i "s/#GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=\"true\"/g" /etc/default/grub
	arch-chroot /mnt sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"quiet splash loglevel=3 rd.udev.log-priority=3 vt.global_cursor_default=0 net.ifnames=0\"/g" /etc/default/grub
	arch-chroot /mnt sed -i "s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/g" /etc/default/grub
	echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub
	echo -e "${INSTRUCTION}Please manually check grub configuration${RESET}"
	userAck
	arch-chroot /mnt nano /etc/default/grub
	echo -e "${STATUS}Fetching an optimized kernel for GRUB...${RESET}"
	arch-chroot /mnt pacman -Sy
	arch-chroot /mnt pacman -S ck-broadwell
	echo -e "${GOOD}Linux-ck-broadwell fetched${RESET}"
	echo -e "${STATUS}Making GRUB configuration file${RESET}"
	echo -e "${NOTE}Go ahead and ignore warnings from GRUB${RESET}"
	fsuuid=$(grub-probe -t fs_uuid -d $1)
	echo -e "menuentry \"Windows 10\" {" >> /mnt/etc/grub.d/40_custom
	echo -e "insmod part_gpt" >> /mnt/etc/grub.d/40_custom
	echo -e "insmod fat" >> /mnt/etc/grub.d/40_custom
	echo -e "insmod search_fs_uuid" >> /mnt/etc/grub.d/40_custom
	echo -e "insmod chain" >> /mnt/etc/grub.d/40_custom
	echo -e "search --fs-uuid --no-floppy --set=root $fsuuid" >> /mnt/etc/grub.d/40_custom
	echo -e "chainloader (\${root})/EFI/Microsoft/Boot/bootmgfw.efi" >> /mnt/etc/grub.d/40_custom
	echo -e "}" >> /mnt/etc/grub.d/40_custom
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
	arch-chroot /mnt cp /boot/EFI/GRUB/grubx64.efi /boot/EFI/Boot/bootx64.efi
	echo -e "${GOOD}GRUB is now usable${RESET}"
}

# Special configuration
miscConf () {
	echo -e "${STATUS}Patching a potential audio issue for the thinkpad...${RESET}"
	echo "blacklist snd_hda_codec_realtek" > /etc/modprobe.d/blacklist.conf
	echo -e "${GOOD}Audio issue patched${RESET}"
	echo -e "${STATUS}Installing additional packages...${RESET}"
	arch-chroot /mnt pacman -S xf86-input-libinput xf86-video-intel xorg-xbacklight fprintd ntfs-3g reflector i3-wm i3status dmenu conky lightdm lightdm-webkit2-greeter feh xfce4-terminal thunar wget xorg-xserver ttf-droid
	echo -e "${STATUS}Adding a default user...${RESET}"
	echo -en "${INPUT}Choose a username: ${RESET}"
	username=""
	while [ -z $username ]
	do
		read username
	done
	arch-chroot /mnt useradd -m -G network,sys -g wheel $username
	echo -e "${GOOD}$username added${RESET}"
	echo -e "${INPUT}Now set the password for $username...${RESET}"
	arch-chroot /mnt passwd $username
	arch-chroot /mnt sed -i "s/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /etc/sudoers
	echo -e "${STATUS}Fetching a Real Package Manager...${RESET}"
	arch-chroot /mnt wget https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz
	arch-chroot /mnt tar -xzf yay.tar.gz
	arch-chroot /mnt rm yay.tar.gz
	arch-chroot /mnt mv yay/PKGBUILD .
	arch-chroot /mnt mv yay /home/$username
	arch-chroot /mnt chown -R ${username} /home/${username}/yay
	arch-chroot /mnt chgrp -R wheel /home/${username}/yay
	arch-chroot /mnt chown -R 777 /home/${username}/yay
	arch-chroot /mnt sudo -u $username makepkg -s BUILDDIR=/home/${username}/yay PKGDEST=/home/${username}/yay SRCDEST=/home/${username}/yay SRCPKGDEST=/home/${username}/yay
	arch-chroot /mnt pacman -U /home/${username}/yay/yay-9.1.0-1-x86_64.pkg.tar.xz
	arch-chroot /mnt rm PKGBUILD
	arch-chroot /mnt rm -R /home/${username}/yay
	echo -e "${GOOD}yay installed${RESET}"
	echo -e "${STATUS}Getting Plymouth...${RESET}"
	arch-chroot /mnt sudo -u $username yay -S plymouth
	echo -e "${GOOD}Plymouth installed${RESET}"
	echo -e "${STATUS}Configuring Plymouth service...${RESET}"
	arch-chroot /mnt systemctl enable lightdm-plymouth
	arch-chroot /mnt sed -i "s/ShowDelay=.*/ShowDelay=0/g" /etc/plymouth/plymouthd.conf
	arch-chroot /mnt mkinitcpio -p linux linux-ck
	echo -e "${GOOD}Plymouth configured${RESET}"
	echo -e "${STATUS}Configuring lightdm${RESET}"
	arch-chroot /mnt sed -i "s/^#user-session=.*/user-session=i3/g" /etc/lightdm/lightdm.conf
	arch-chroot /mnt sed -i "s/^#greeter-session=.*/greeter-session=lightdm-webkit2-greeter/g" /etc/lightdm/lightdm.conf
	echo -e "${GOOD}lightdm configured${RESET}"
	echo -e "${NOTE}A usable font for xfce4-terminal must manually be chosen${RESET}"
	echo -e "${NOTE}droid sans mono is a recommendation${RESET}"
	echo -e "${NOTE}i3-status was also installed just so that the default i3 configuration could be used${RESET}"
	echo -e "${NOTE}Feel free to delete it when conky is usable${RESET}"
	echo -e "${GOOD}Miscellaneous configuration performed${RESET}"
	echo -e "${INSTRUCTION}Go ahead an reboot into your new Archlinux install${RESET}"
}

# Does the preinstallation procedure
preinstall () {
	# Some globals to pass
	DISK=""
	DISKROOTNUM=0
	DISKBOOTNUM=0
	
	# Verify the boot mode
	verifyUEFI
	
	# Connect to the Internet
	wifiConf $1
	
	# Update the system clock
	timedatectl set-ntp true
	
	# Partition the disk
	partition DISK DISKROOTNUM DISKBOOTNUM
	
	# Format the partitions
	format
	
	# Mount the file systems
	mountDisk
	
	# Select the mirrors
	selectMirrors
	
	# Install the base packages
	installBase
	
	# Configure the system
	configSys
	
	# Initramfs... Already done in this case but commenting for giggles?
	# mkinitcpio -p linux
	
	# Set root password
	echo "Please set a password for root..."
	arch-chroot /mnt passwd root
	
	# Boot loader
	setupGRUB ${DISK}$DISKBOOTNUM
	
	# Misc configuration
	miscConf
}

# Command line usage help
usage () {
	# Print the help
	echo -e "archinstall is a program that aids in the installation of archlinux"
	echo -e ""
	echo -e "Usage: archinstall module [options]"
	echo -e "Available modules are as follows..."
	echo -e "\tpreinstall:"
	echo -e "\t\tRuns through all the proceeding preinstall modules"
	echo -e "\t\tand performs a full installation as per Paul's"
	echo -e "\t\tStandards. Requires argument for WiFi Kernel"
	echo -e "\t\tModule name."
	echo -e "\tverifyUEFI:"
	echo -e "\t\tChecks to make sure that archiso is booted in UEFI."
	echo -e "\twifiConf:"
	echo -e "\t\tConnects to Wifi. Requires argument for WiFi"
	echo -e "\t\tKernel Module name."
	echo -e "\tupdateSysClock:"
	echo -e "\t\tUpdates system clock."
	echo -e "\tpartition"
	echo -e "\t\tPartitions the root directory."
	echo -e "\tformat"
	echo -e "\t\tFormats the root directory. Requires argument for"
	echo -e "\t\troot partition as a special device."
	echo -e "\tmountDisk:"
	echo -e "\t\tMounts root and boot. Requires arguments for root"
	echo -e "\t\tand boot partitions as special devices."
	echo -e "\tselectMirrors:"
	echo -e "\t\tUses reflector to sort pacman mirrors."
	echo -e "\tinstallBase:"
	echo -e "\t\tInstalls base and base-devel."
	echo -e "\tconfigSys:"
	echo -e "\t\tDoes a lot of configuration."
	echo -e "All of the following modules need the install partitions correctly"
	echo -e "mounted at /mnt. It's suggested to make sure that mountDisk is used"
	echo -e "before using the follwoing modules."
	echo -e "\tmkinitcpio:"
	echo -e "\t\tRebuilds initramfs. Requires argument for kernel"
	echo -e "\t\tname."
	echo -e "\tsetRootPass:"
	echo -e "\t\tSets the root password."
	echo -e "\tsetupGRUB:"
	echo -e "\t\tSets GRUB up. Requires argument for windows boot partition"
	echo -e "\tmiscConf:"
	echo -e "\t\tDoes some miscellaneous configuration."
	echo -e ""
}

#### The "main" part of this script ####
if [[ $1 = "preinstall" && $# -eq 2 ]]
then
	preinstall $2
	exit
elif [[ $1 = "verifyUEFI" && $# -eq 1 ]]
then
	verifyUEFI
elif [[ $1 = "wifiConf" && $# -eq 2 ]]
then  
	wifiConf $2
elif [[ $1 = "updateSysClock" && $# -eq 1 ]]
then
	timedatectl set-ntp true
elif [[ $1 = "partition" && $# -eq 1 ]]
then
	partition
elif [[ $1 = "format" && $# -eq 2 ]]
then
	format $2
elif [[ $1 = "mountDisk" && $# -eq 3 ]]
then
	mountDisk $2 $3
elif [[ $1 = "selectMirrors" && $# -eq 1 ]]
then
	selectMirrors
elif [[ $1 = "installBase" && $# -eq 1 ]]
then
	installBase
elif [[ $1 = "configSys" && $# -eq 1 ]]
then
	configSys
elif [[ $1 = "mkinitcpio" && $# -eq 2 ]]
then
	arch-chroot /mnt mkinitcpio -p $2
elif [[ $1 = "setRootPass" && $# -eq 1 ]]
then
	echo -e "${INPUT}Please set a password for root...${RESET}"
	arch-chroot /mnt passwd root
elif [[ $1 = "setupGRUB" && $# -eq 2 ]]
then
	setupGRUB $2
elif [[ $1 = "miscConf" && $# -eq 1 ]]
then
	miscConf
else
	usage
fi
exit 0