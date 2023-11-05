# Raspberry PI 4 Boot Partition

## Boot Installation

### Getting the boot files
It's recommended to install the boot files directly from Raspberry PI Foundation's official repository.
The boot for Raspberry PI is very different from a normal computer boot and requires proprietary firmware, so it's better to stick with official instructions for this step.
That being said, clone the official precompiled kernel repository maintained by RPI Foundation:
```sh
git clone -b stable --depth 1 https://github.com/raspberrypi/firmware.git
```
Enter the source folder and make sure that it is up to date:
```sh
cd linux
git pull
```
This must be up to date with RPI Foudation's remote so that we can compile the kernel with custom options later on.

## Kernel Compilation
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
This must be up to date with RPI Foudation's remote so that we can utilize their precompiled kernel modules later on.

### Configuring the kernel
Use RPI Foundation's makescript to generate the default kernel configuration. After that, run menuconfig to edit it as you wish:
```sh
make bcm2711_defconfig
make menuconfig
```
The Gentoo profile used later on is Hardened + SELinux, so make sure AppArmor and SELinux security features are enabled in the final configuration.

### Compiling the kernel
Based on the compilation setup described earlier, I don't need to worry about memory usage during the compilation.
That being said, I spawn 4 compiler jobs in order to obtain maximum CPU utilization:
```sh
time make -j4 Image modules dtbs
```
Compile times for kernel v6.1.x in this setup usually range from 20 to 30 minutes, depending on the configuration.

## Kernel Installation
