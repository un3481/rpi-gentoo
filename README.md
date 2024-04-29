# rpi-gentoo

My Raspberry PI 4 gentoo system.

## Software

I use Open-RC, Netifrc, PipeWire, Sway-WM, Doas, and my own shell scripts.

I do not use Systemd, Elogind, NetworkManager, GNOME, KDE or any desktop environment.

I try not to use anything that:
  1. is bloated.
  2. tries to be too clever.
  3. is a NSA honeypot (except well...).

## Kernel

I use the official kernel, modules, bootloader and firmware provided by Raspberry-Pi Foundation that can be downloaded [here](https://github.com/raspberrypi/firmware).

Sources from Raspberry-Pi Foundation can be found [here](https://github.com/raspberrypi/linux).

Manually configuring the linux kernel to run properly on a Raspberry-Pi felt too much like reinventing the wheel.
