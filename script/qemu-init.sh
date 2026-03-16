#!/bin/sh

echo "Mounting essential filesystems"
mount -t proc proc /proc
mount -t sysfs sys /sys
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts
mkdir -p /dev/shm
mount -t tmpfs tmpfs /dev/shm
mount -t tmpfs tmpfs /tmp
chmod 1777 /tmp
mount -t tmpfs tmpfs /run
mkdir -p /run/dbus
mkdir -p /run/user/0
chmod 700 /run/user/0
mount -t tmpfs tmpfs /var/tmp

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "Setting up hostname and machine-id for D-Bus"
echo "electron-test" > /etc/hostname
hostname electron-test
echo "127.0.0.1 electron-test" >> /etc/hosts
cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id

echo "Configuring network"
# QEMU user-mode networking provides DHCP at 10.0.2.2 and DNS at 10.0.2.3
# net.ifnames=0 kernel param means the interface is eth0
if command -v ip >/dev/null 2>&1; then
	ip link set lo up
	ip link set eth0 up
	if command -v dhclient >/dev/null 2>&1; then
		dhclient eth0
	else
		ip addr add 10.0.2.15/24 dev eth0
		ip route add default via 10.0.2.2
	fi
elif command -v ifconfig >/dev/null 2>&1; then
	ifconfig lo up
	ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
	route add default gw 10.0.2.2
else
	echo "WARNING: No ip or ifconfig found, trying sysfs for network config"
	# Minimal fallback: write directly to sysfs to bring interfaces up
	echo 1 > /sys/class/net/lo/flags 2>/dev/null || true
	echo 1 > /sys/class/net/eth0/flags 2>/dev/null || true
fi
# Configure DNS resolver (QEMU SLIRP DNS forwarder)
echo "nameserver 10.0.2.3" > /etc/resolv.conf
echo "Network configuration complete"

echo "Setting system clock"
date -s "$(cat /host-time)"

export XDG_RUNTIME_DIR=/run/user/0

echo "Starting entrypoint"
echo "System: $(uname -s) $(uname -r) $(uname -m), page size: $(getconf PAGESIZE) bytes"
sudo chown -R builduser:builduser /home/builduser
ls -la /home/builduser/src/out/Default/electron
cd /home/builduser/src/electron
node script/yarn.js install --immutable
runuser -u builduser -- xvfb-run script/actions/run-tests.sh script/yarn.js test --skipYarnInstall --runners=main --trace-uncaught --enable-logging --files spec/api-app-spec.ts
EXIT_CODE=$?
echo "Test execution finished with exit code $EXIT_CODE"
echo $EXIT_CODE > /exit-code
sync

echo "Powering off"
# poweroff -f bypasses the init system (this script IS pid 1) and
# directly invokes the reboot() syscall, causing QEMU to exit immediately.
poweroff -f
