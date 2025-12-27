#!/bin/bash
set -e

VMID=111
VMNAME="k8s-v2"
STORAGE="nvme-local"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_PATH="/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img"
SSH_KEYS="$HOME/authorized_keys"

echo "=== Cleaning up existing VM ${VMID} ==="
qm stop ${VMID} 2>/dev/null || true
qm destroy ${VMID} --purge 2>/dev/null || true

echo "=== Downloading cloud image ==="
if [ ! -f "${IMAGE_PATH}" ]; then
  wget -O "${IMAGE_PATH}" "${IMAGE_URL}"
fi

echo "=== Creating VM template ${VMID} ==="
qm create ${VMID} --name "${VMNAME}" \
  --memory 32768 \
  --cores 8 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --efidisk ${STORAGE}:0,pre-enrolled-keys=1 \
  --agent enabled=1 \
  --net0 virtio,bridge=vmbr0 \
  --net1 virtio,bridge=vmbr1 \
  --net2 virtio,bridge=vmbr0,tag=100 

echo "=== Importing and resizing disk ==="
qm set ${VMID} --scsi0 ${STORAGE}:0,import-from=${IMAGE_PATH}
qm resize ${VMID} scsi0 100G

echo "=== Adding cloud-init drive ==="
qm set ${VMID} --scsi1 ${STORAGE}:cloudinit

echo "=== Configuring boot order ==="
qm set ${VMID} --boot order=scsi0

echo "=== Configuring cloud-init ==="
qm set ${VMID} --ciuser admin
qm set ${VMID} --cipassword 'Admin123!'
qm set ${VMID} --sshkeys "${SSH_KEYS}"
qm set ${VMID} --ipconfig0 ip=192.168.1.111/24,gw=192.168.1.1,ip6=auto
qm set ${VMID} --ipconfig1 ip=192.168.16.21/24,ip6=auto
qm set ${VMID} --ipconfig2 ip=192.168.100.11/24,ip6=auto
qm set ${VMID} --ciupgrade 1
qm set ${VMID} --nameserver 192.168.1.1
qm set ${VMID} --tags ubuntu,24.04,cloudinit
# qm set ${VMID}  --serial0 socket --vga serial0

echo "=== Regenerating cloud-init ==="

# Find disk path
DISK=$(pvesm path ${STORAGE}:vm-${VMID}-disk-2)
echo "Using disk ${DISK}"

# Re-enable cloud-init and set credentials
virt-customize -a "$DISK" \
  --run-command 'rm -f /etc/cloud/cloud-init.disabled' \
  --run-command 'systemctl enable cloud-init cloud-init-local cloud-config cloud-final' \
  --run-command 'cloud-init clean' \
  --run-command 'useradd -m -s /bin/bash -g admin -G sudo admin 2>/dev/null || usermod -aG sudo admin' \
  --run-command 'echo "admin ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/admin' 

qm cloudinit update ${VMID}

echo "=== Starting VM ==="
qm start ${VMID}