# archinstall.sh
The script I use to speed up a dual boot Windows 10/Arch Linux install process for a Thinkpad X1 Carbon gen 3.

# Usage
Prior to using this script Windows 10 must already be installed and it's boot partition must be larger than 100MB. A boot partition size of 512MB, as recommended by the [ArchWiki Installation Guide](https://wiki.archlinux.org/index.php/installation_guide), seems to be sufficient. Once booted into the Arch Linux Live CD/USB, go ahead and:
````
wget https://github.com/crusopaul/archinstall/raw/master/archinstall.sh
chmod +x archinstall.sh
./archinstall.sh preinstall
````
