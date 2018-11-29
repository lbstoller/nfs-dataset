#!/bin/bash
#
# Setup NFS client and mount server.
#
# This script is derived from Jonathan Ellithorpe's Cloudlab profile at
# https://github.com/jdellithorpe/cloudlab-generic-profile. Thanks!
#
. /etc/emulab/paths.sh

HOSTNAME=$(hostname --short)

#
# The storage partition is mounted on /nfs, if you change this, you
# have to change profile.py also.
#
NFSDIR="/nfs"

#
# The name of the nfs server. If you change these, you have to
# change profile.py also.
#
NFSNETNAME="nfsLan"
NFSSERVER="nfs-$NFSNETNAME"

#
# The name of the "prepare" for image snapshot hook.
#
HOOKNAME="$BINDIR/prepare.pre.d/nfs-client.sh"

#
# If fstab entry already exists, no need to do anything. 
#
if grep -q $NFSSERVER /etc/fstab; then
    exit 0
fi

# === Software dependencies that need to be installed. ===
echo ""
echo "Installing NFS packages"
apt-get update
apt-get --assume-yes install nfs-common

# Create the local mount directory.
if [ ! -e $NFSDIR ]; then
    mkdir $NFSDIR
fi
chmod 777 $NFSDIR

echo ""
echo "Setting up NFS client"
echo "$NFSSERVER:$NFSDIR $NFSDIR nfs rw,bg,sync,hard,intr 0 0" >> /etc/fstab

#
# Create prepare hook to remove the fstab line before we take the
# image snapshot. It will get recreated at reboot after image snapshot.
# Remove the hook script too, we do not want it in the new image, and
# it will get recreated as well at reboot. 
#
if [ ! -e $HOOKNAME ]; then
    cat <<EOF > $HOOKNAME
    sed -i.bak -e "/^$NFSSERVER/d" /etc/fstab
    rm -f $HOOKNAME
    exit 0
EOF
    chmod +x $HOOKNAME
fi

echo ""
echo "Waiting for NFS server to complete setup"
# Wait until nfs is properly set up. 
while ! (rpcinfo -s $NFSSERVER | grep -q nfs); do
  sleep 2
done

#
# Run the mount. It is a background mount, so will keep trying until
# the server is up, which it already should be, 
#
if ! (mount $NFSDIR) ; then
    exit 1
fi

#
# But do not exit until the mount is made, in case there is another
# script after this one, that depends on the mount really being there.
#
while ! (findmnt $NFSDIR); do
    echo "Waiting for NFS mount of $NFSDIR ..."
    sleep 2
done

exit 0


