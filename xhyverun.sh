#!/bin/sh

NFS_ROOT="${1:-$HOME}"

KERNEL=$(make -C vm xhyve_kernel)
INITRD=$(make -C vm xhyve_initrd)
CMDLINE="$(make -C vm xhyve_cmdline) docker-root.nfsroot=\"${NFS_ROOT}\""
HDD=$(make -C vm xhyve_hdd)
UUID=$(make -C vm xhyve_uuid)

ACPI="-A"
MEM="-m 1G"
#SMP="-c 2"
NET="-s 2:0,virtio-net"
if [ -n "${HDD}" ]; then
  IMG_HDD="-s 4,virtio-blk,${HDD}"
fi
PCI_DEV="-s 0:0,hostbridge -s 31,lpc"
LPC_DEV="-l com1,stdio"

if [ -n "${UUID}" ]; then
  if [ -x "bin/uuid2mac" ]; then
    MAC_ADDRESS=$(bin/uuid2mac ${UUID})
    if [ -n "${MAC_ADDRESS}" ]; then
      echo "${MAC_ADDRESS}" > vm/.mac_address
    else
      exit 1
    fi
  fi
  UUID="-U ${UUID}"
fi

EXPORTS=$(bin/vmnet_export.sh "${NFS_ROOT}")
if [ -n "${EXPORTS}" ]; then
  set -e
  sudo touch /etc/exports
  if ! grep -qs "^${EXPORTS}$" /etc/exports; then
    echo "${EXPORTS}" | sudo tee -a /etc/exports
  fi
  sudo nfsd checkexports || (echo "Please check your /etc/exports." >&2 && exit 1)
  sudo nfsd stop
  sudo nfsd start
  while ! rpcinfo -u localhost nfs > /dev/null 2>&1; do
    sleep 0.5
  done
  set +e
else
  echo "It seems your first run for xhyve with vmnet."
  echo "You can't use NFS shared folder at this time."
  echo "But it should be available at the next boot."
fi

while [ 1 ]; do
  xhyve $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET $IMG_CD $IMG_HDD $UUID -f kexec,$KERNEL,$INITRD,"$CMDLINE"
  if [ $? -ne 0 ]; then
    break
  fi
done

if [ -n "${EXPORTS}" ]; then
  sudo touch /etc/exports
  sudo sed -E -e "/^$(echo ${EXPORTS} | sed -e 's/\//\\\//g')\$/d" -i.bak /etc/exports
  sudo nfsd restart
fi
rm -f vm/.mac_address

exit 0
