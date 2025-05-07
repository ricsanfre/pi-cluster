FROM ubuntu:24.04

RUN mkdir -p /build
WORKDIR /build

RUN apt-get update
RUN apt download shim-signed grub-efi-amd64-signed grub-common
RUN  dpkg-deb --fsys-tarfile shim-signed*deb | tar x ./usr/lib/shim/shimx64.efi -O > /build/bootx64.efi
RUN dpkg-deb --fsys-tarfile grub-efi-amd64-signed*deb | tar x ./usr/lib/grub/x86_64-efi-signed/grubnetx64.efi.signed -O > /build/grubx64.efi
RUN dpkg-deb --fsys-tarfile grub-common*deb | tar x ./usr/share/grub/unicode.pf2 -O > /build/unicode.pf2
RUN apt download pxelinux syslinux-common
RUN dpkg-deb --fsys-tarfile pxelinux*deb | tar x ./usr/lib/PXELINUX/pxelinux.0 -O > /build/pxelinux.0
RUN dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/ldlinux.c32 -O > /build/ldlinux.c32
RUN dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/menu.c32 -O > /build/menu.c32
RUN dpkg-deb --fsys-tarfile syslinux-common*deb | tar x ./usr/lib/syslinux/modules/bios/libutil.c32 -O > /build/libutil.c32

RUN rm /build/*.deb
