# Raspberry PI 4 Boot Partition

## Boot Installation
Boot installation refers to copying the boot files into the boot partition, this includes the kernel and config files, as well as copying the kernel modules into the proper directory in your system.
Following these instructions correctly should result in a bootable and fully functional Raspberry PI device.

### Getting the boot files
It's recommended to install the boot files directly from Raspberry PI Foundation's official repository.
The boot for Raspberry PI is very different from a normal computer boot and requires proprietary firmware, so it's better to stick with official instructions for this step.
That being said, clone the official precompiled kernel repository maintained by RPI Foundation:
```sh
git clone -b stable --depth 1 https://github.com/raspberrypi/firmware.git
```
Enter the source folder and make sure that it is up to date:
```sh
cd firmware
git pull
```
This repository must be up to date with remote so we can compile the kernel with custom options later on.

### Replacing the kernel and modules
Follow these instructions corretly, otherwise you may end up with an unbootable system.
Mount the boot partition:
```sh
mount /dev/mmcblk0p1 /boot
```
Delete all files from boot partition:
```sh
rm -rf /boot/*
```
Copy the RPI Foundation precompiled boot files into boot partition:
```sh
cp -r boot/* /boot/
```
Copy the RPI Foundation precompiled kernel modules into proper folder in your system:
```sh
cp -r modules/* /lib/modules/
```
And it's done.

### Editing fstab
Your system may be unbootable now if you didn't configure your fstab file properly.
The follwoing instructions assume that this repository is in "~/Projects/rpi-gentoo".
To make sure that fstab is correct, you can get a working copy for the Raspberry PI from this repo's "etc" folder.
Copy the working fstab into "/etc/fstab":
```sh
cp ~/Projects/rpi-gentoo/etc/fstab /etc/fstab 
```
If you don't follow the above step correctly you may end up with an unbootable system.

### Copy the patch files
The system should now be bootable, but some important functionalities will be missing.
The follwoing instructions assume that this repository is in "~/Projects/rpi-gentoo".
In order to enable GPU, DRM, Overclocking and other tweaks, copy the boot config files into boot folder:
```sh
cp ~/Projects/rpi-gentoo/boot/config.txt /boot/config.txt
cp ~/Projects/rpi-gentoo/boot/cmdline.txt /boot/cmdline.txt 
```
Now your screen resolution should work and DRM drivers should be enabled.

## Custom Kernel Compilation
Kernel compilation refers to generating a new kernel image from source.
These instructions should only be followed if the previous ones where successfull and you have a bootable and fully functional Raspberry PI device.
It's recommended that the kernel is compiled in a reasonably powerful machine and not in the Raspberry PI itself.
In my case, I use a VPS to do the job. The VPS is from Oracle's Always-Free plan. It has 4 Ampere A1 ARM CPUs with 3.0GHz each and 24GB of RAM, so memory is not an issue in this setup.

### Getting the source
It's recommended to compile the kernel from Raspberry PI Foundation's official sources.
We can be sure that the kernel in their sources is supported by Raspberry PI 4 and they also provide makescripts that generate the default configuration needed for Raspberry PI to work. This saves a lot of time in kernel configuration later on.
That being said, clone the official kernel repository maintained by RPI Foundation:
```sh
git clone -b stable --depth 1 https://github.com/raspberrypi/linux.git 
```
Enter the source folder and make sure that it is up to date:
```sh
cd linux
git pull
```
This repository must be up to date with remote so we can utilize the precompiled kernel modules we installed in the previous steps.

### Configuring the kernel
Use RPI Foundation's makescript to generate the default kernel configuration. After that, run menuconfig to edit it as you wish:
```sh
make bcm2711_defconfig
make menuconfig
```
For example, the Gentoo profile I use is Hardened + SELinux, so I have to make sure AppArmor and SELinux security features are enabled in the custom configuration.

### Compiling the kernel
Based on the setup I described earlier, I don't need to worry about memory usage during the compilation.
That being said, I spawn 4 compiler jobs in order to obtain maximum CPU utilization:
```sh
time make -j4 Image modules dtbs
```
If you need to compile in a machine with less than 8GB of memory definetely reduce "j4" to a value that doesn't exaust your system resources.
Compile times for kernel v6.1.x in this setup usually range from 20 to 30 minutes, depending on the configuration I use.

## Custom Kernel Installation
The following instructions assume that you followed all above steps correctly and that you compiled a kernel with the same version as the modules youre using.

### Pre-Installation
Assuming that the compilation was made in the folder "~/Projects/linux" in the VPS, run the following commands on the Raspberry PI.
Copy the file from the VPS (replace <user> and <host> with the remote user and host):
```sh
scp <user>@<host>:~/Projects/linux/arch/arm64/boot/Image ~/Projects/kernel8.img
```
If you did not use a VPS the above step is unnecessary, instead just copy the image file to a folder of your choice.
Also, before proceeding, you need to mount boot partition:
```sh
mount /dev/mmcblk0p1 /boot
```

### Replacing the kernel image
Take a backup of the old kernel (kernel8.img is for ARM64): 
```sh
mv /boot/kernel8.img /boot/kernel8.img.old
```
Finally, copy the new kernel image into boot folder:
```sh
cp ~/Projects/kernel8.img /boot/kernel8.img
```
And it's done.

### Reboot
You should now be able to reboot your Raspberry PI and use the new kernel.
```sh
reboot
```

