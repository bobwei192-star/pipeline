#!/usr/bin/env bash
# 从 Pipeline 控制端 SSH 到测试机，切换 GRUB 并 reboot（确保 Slave 进 PE 或 SUT）
#   ./ensure_slave_in_pe.sh -i 172.31.8.5 -v              # → PE（默认菜单 0）
#   ./ensure_slave_in_pe.sh -i 172.31.8.5 -o sut         # → SUT 26.04（GRUB_SUT_ENTRY）

set -euo pipefail

SSH_TARGET=""
SSH_USER="${PE_SSH_USER:-amd}"
SSH_PASS="${PE_SSH_PASS:-}"
MODE=""
GRUB_PE_ENTRY="${GRUB_PE_ENTRY:-0}"
GRUB_SUT_ENTRY="${GRUB_SUT_ENTRY:-osprober-gnulinux-simple-c0b61a7e-8069-47df-8f09-2fa33abb81ac}"
PE_PART_DEV="${PE_PART_DEV:-/dev/nvme0n1p2}"
WAIT_SSH_SEC="${WAIT_SSH_SEC:-600}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Usage: ensure_slave_in_pe.sh -i <IP> (-v | -o sut) [options]

  -v          next boot → PE (grub entry 0 on PE /boot)
  -o sut      next boot → SUT target OS (GRUB_SUT_ENTRY)
  -u / -p     SSH credentials (or PE_SSH_USER / PE_SSH_PASS)
  --grub-sut ID   override SUT menu entry id
  --wait SEC  wait for SSH after reboot (default 600)
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) SSH_TARGET="$2"; shift 2 ;;
    -u) SSH_USER="$2"; shift 2 ;;
    -p) SSH_PASS="$2"; shift 2 ;;
    -v) MODE="pe"; shift ;;
    -o) MODE="sut"; shift 2 ;;
    --grub-sut) GRUB_SUT_ENTRY="$2"; shift 2 ;;
    --wait) WAIT_SSH_SEC="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown: $1" ;;
  esac
done

[[ -n "${SSH_TARGET}" && -n "${MODE}" ]] || usage
[[ -n "${SSH_PASS}" ]] || die "SSH password required (-p or PE_SSH_PASS)"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15)

ssh_run() {
  sshpass -p "${SSH_PASS}" ssh -T "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" "$@"
}

remote_reboot_script() {
  local target="$1"
  cat <<REMOTE
set -euo pipefail
PASS='${SSH_PASS}'
PE_DEV='${PE_PART_DEV}'
GRUB_PE='${GRUB_PE_ENTRY}'
GRUB_SUT='${GRUB_SUT_ENTRY}'
TARGET='${target}'

sudo_cmd() {
  if [[ \$(id -u) -eq 0 ]]; then "\$@"; else printf '%s\n' "\${PASS}" | sudo -S -p '' "\$@"; fi
}

partlabel=\$(lsblk -no PARTLABEL "\$(findmnt -n -o SOURCE /)" | tr -d '[:space:]')
boot_dir=/boot

grub_reboot_pe() {
  sudo_cmd grub-reboot --boot-directory="\${boot_dir}" "\${GRUB_PE}"
}

grub_reboot_sut() {
  sudo_cmd grub-reboot --boot-directory="\${boot_dir}" "\${GRUB_SUT}"
}

if [[ "\${partlabel}" == "PE" ]]; then
  boot_dir=/boot
else
  # 当前在 SUT：GRUB 在 PE 分区
  sudo_cmd mkdir -p /mnt/pe_boot
  if ! mountpoint -q /mnt/pe_boot; then
    sudo_cmd mount "\${PE_DEV}" /mnt/pe_boot
  fi
  boot_dir=/mnt/pe_boot/boot
fi

case "\${TARGET}" in
  pe)  grub_reboot_pe ;;
  sut) grub_reboot_sut ;;
  *) echo "bad target"; exit 1 ;;
esac

sudo_cmd sync
sudo_cmd reboot
REMOTE
}

wait_ssh() {
  local deadline=$((SECONDS + WAIT_SSH_SEC))
  info "waiting for SSH ${SSH_USER}@${SSH_TARGET} (up to ${WAIT_SSH_SEC}s)"
  while (( SECONDS < deadline )); do
    if sshpass -p "${SSH_PASS}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" true 2>/dev/null; then
      info "SSH is up"
      return 0
    fi
    sleep 10
  done
  die "SSH not reachable after reboot"
}

command -v sshpass >/dev/null || die "sshpass required on Pipeline agent"

info "reboot ${SSH_TARGET} → ${MODE}"
ssh_run "bash -s" <<< "$(remote_reboot_script "${MODE}")"
sleep 15
wait_ssh
