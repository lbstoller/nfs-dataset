#!/bin/bash
#
# Setup a simple NFS server on /nfs
#
# This script is derived from Jonathan Ellithorpe's Cloudlab profile at
# https://github.com/jdellithorpe/cloudlab-generic-profile. Thanks!
#
. /etc/emulab/paths.sh

HOSTNAME=$(hostname --short)

#
# The storage partition is mounted on /nfs, if you change this, you
# must change profile.py also.
#
NFSDIR="/nfs"

#
# The name of the nfs network. If you change this, you must change
# profile.py also.
#
NFSNETNAME="nfsLan"

#
# The name of the "prepare" for image snapshot hook.
#
HOOKNAME="$BINDIR/prepare.pre.d/nfs-server.sh"

#
# If exports entry already exists, no need to do anything. 
#
if egrep -q "^$NFSDIR" /etc/exports; then
    exit 0
fi

if ! (grep -q $HOSTNAME-$NFSNETNAME /etc/hosts); then
    echo "$HOSTNAME-$NFSNETNAME is not in /etc/hosts"
    exit 1
fi

# === Software dependencies that need to be installed. ===
# Common utilities
echo ""
echo "Installing NFS packages"
apt-get update
apt-get --assume-yes install nfs-kernel-server nfs-common

# Make the file system rwx by all.
chmod 777 $NFSDIR

echo ""
echo "Setting up NFS exports"
#
# Export the NFS server directory to the subnet so that all clients
# can mount it.  To do that, we need the subnet. Grab that from
# /etc/hosts, and assume a netmask of 255.255.255.0, which will be
# fine 99.9% of the time.
#
NFSIP=`grep -i $HOSTNAME-$NFSNETNAME /etc/hosts | awk '{print $1}'`
NFSNET=`echo $NFSIP | awk -F. '{printf "%s.%s.%s.0", $1, $2, $3}'`

echo "$NFSDIR $NFSNET/24(rw,sync,no_root_squash)" >> /etc/exports

# Make sure we start RPCbind to listen on the right interfaces.
echo "OPTIONS=\"-l -h 127.0.0.1 -h $NFSIP\"" > /etc/default/rpcbind

# We want to allow rpcinfo to operate from the clients.
sed -i.bak -e "s/^rpcbind/#rpcbind/" /etc/hosts.deny

#
# Create prepare hook to remove the fstab line before we take the
# image snapshot. It will get recreated at reboot after image snapshot.
# Remove the hook script too, we do not want it in the new image, and
# it will get recreated as well at reboot. 
#
if [ ! -e $HOOKNAME ]; then
    cat <<EOF > $HOOKNAME
    sed -i.bak -e "/^$NFSDIR/d" /etc/exports
    sed -i.bak -e "s/^#rpcbind/rpcbind/" /etc/hosts.deny
    echo "OPTIONS=\"-l -h 127.0.0.1\"" > /etc/default/rpcbind
    rm -f $HOOKNAME
    exit 0
EOF
    chmod +x $HOOKNAME
fi

echo ""
# The install above starts the server.
# Stop it since we have to restart rpcbind with new options.
echo "Stopping NFS services"
/etc/init.d/nfs-kernel-server stop
sleep 1

echo "Restarting rpcbind"
/etc/init.d/rpcbind stop
sleep 1
/etc/init.d/rpcbind start
sleep 1

echo "Starting NFS services"
/etc/init.d/nfs-kernel-server start

# Give it time to start-up
sleep 5

