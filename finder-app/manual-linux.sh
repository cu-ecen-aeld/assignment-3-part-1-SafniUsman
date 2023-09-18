#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE mrproper  # clean
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE defconfig # use default configuration

    make -j4 ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE all   # build kernel
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE modules   # build modules
    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE dtbs      # build devicetree
fi

echo "Adding the Image in outdir"
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/Image

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories
mkdir rootfs && cd rootfs && \
	mkdir -p bin dev home etc lib lib64 proc sys sbin tmp usr/bin usr/lib usr/sbin var/log && \
	sudo chown -R root:root *

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # Configure busybox
    make distclean
    make defconfig
else
    cd busybox
fi

# TODO: Make and install busybox
sudo bash -c "PATH=$PATH make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE"
sudo bash -c "PATH=$PATH make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE install"

echo "Library dependencies"
cd ${OUTDIR}/rootfs
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter"
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library"

# TODO: Add library dependencies to rootfs
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
sudo cp ${SYSROOT}/lib/ld-linux-aarch64.so.* ${OUTDIR}/rootfs/lib
sudo cp ${SYSROOT}/lib64/libc.so.* ${OUTDIR}/rootfs/lib64
sudo cp ${SYSROOT}/lib64/libm.so.* ${OUTDIR}/rootfs/lib64
sudo cp ${SYSROOT}/lib64/libresolv.so.* ${OUTDIR}/rootfs/lib64
echo "library dependencies added to rootfs"

# TODO: Make device nodes
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

# TODO: Clean and build the writer utility
cd $FINDER_APP_DIR
make clean
make CROSS_COMPILE=$CROSS_COMPILE all

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
sudo -s cp -a writer ${OUTDIR}/rootfs/home/
sudo -s cp -a finder.sh ${OUTDIR}/rootfs/home/
sudo -s cp -a finder-test.sh ${OUTDIR}/rootfs/home/
sudo -s cp -a autorun-qemu.sh ${OUTDIR}/rootfs/home/
sudo -s cp -ra ../conf ${OUTDIR}/rootfs/home/conf

# TODO: Chown the root directory
sudo chown -R root:root ${OUTDIR}/rootfs

# TODO: Create initramfs.cpio.gz
cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ../initramfs.cpio
cd ..
gzip -f initramfs.cpio
mkimage -A arm -O linux -T ramdisk -d initramfs.cpio.gz uRamdisk
