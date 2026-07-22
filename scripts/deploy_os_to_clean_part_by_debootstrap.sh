#!/bin/bash
# 在 PE 上用 debootstrap 把精简 Ubuntu 装进 sut-target-os（分区 4）
# 对应文档: docs/手动部署os到sut-target-os分区并制作镜像.md （操作前自检 ~ §2.15）
#
# 用法示例:
#   sudo ./deploy_os_to_clean_part_by_debootstrap.sh -y
#   sudo ./deploy_os_to_clean_part_by_debootstrap.sh -y -c resolute \
#        -m http://mirrors.aliyun.com/ubuntu -H SUT-003
#
# 本脚本不执行 update-grub / grub-reboot / 打包；装完后请按文档第三、四步手动或另脚本完成。

set -euo pipefail

TARGET_LABEL="sut-target-os"
ESP_LABEL="ESP"
MNT="${MNT:-/mnt/p4}"

CODENAME="${CODENAME:-resolute}"          # 26.04
MIRROR="${MIRROR:-http://mirrors.aliyun.com/ubuntu}"
HOSTNAME_SUT="${HOSTNAME_SUT:-SUT-003}"
USER_NAME="${USER_NAME:-amd}"
USER_PASS="${USER_PASS:-amdyes}"
DO_MKFS=1
ASSUME_YES=0
EXTRA_PKGS="linux-generic openssh-server sudo netplan.io network-manager iputils-ping grub-efi-amd64-bin efibootmgr systemd-resolved"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

require_pe() {
  local root_src partlabel
  root_src=$(findmnt -n -o SOURCE /) || die "cannot resolve root device"
  partlabel=$(lsblk -no PARTLABEL "${root_src}" 2>/dev/null | tr -d '[:space:]')
  [[ "${partlabel}" == "PE" ]] || die "must run on PE (root PARTLABEL=PE), got '${partlabel:-<empty>}' (root=${root_src})"
  info "OK: running on PE (root=${root_src})"
}

resolve_disk_layout() {
  local root_src
  root_src=$(findmnt -n -o SOURCE /)
  if [[ "${root_src}" =~ /dev/nvme ]]; then
    DISK=$(echo "${root_src}" | sed -r 's/p[0-9]+$//')
    PART_PREFIX="${DISK}p"
  else
    DISK="${root_src%%[0-9]*}"
    PART_PREFIX="${DISK}"
  fi

  # 按 PARTLABEL 找 sut-target-os / ESP（不写死 p4/p1，兼容编号差异）
  SUT_DEV=$(lsblk -lnpo NAME,PARTLABEL | awk -v l="${TARGET_LABEL}" '$2==l {print $1; exit}')
  ESP_DEV=$(lsblk -lnpo NAME,PARTLABEL | awk -v l="${ESP_LABEL}" '$2==l {print $1; exit}')

  [[ -n "${SUT_DEV}" && -b "${SUT_DEV}" ]] || die "block device with PARTLABEL=${TARGET_LABEL} not found"
  [[ -n "${ESP_DEV}" && -b "${ESP_DEV}" ]] || die "block device with PARTLABEL=${ESP_LABEL} not found"
  [[ "$(findmnt -n -o SOURCE /)" != "${SUT_DEV}" ]] || die "refusing to install onto current root ${SUT_DEV}"

  info "DISK=${DISK}"
  info "SUT_DEV=${SUT_DEV} (label=${TARGET_LABEL})"
  info "ESP_DEV=${ESP_DEV} (label=${ESP_LABEL})"
}

ensure_debootstrap() {
  if ! command -v debootstrap >/dev/null 2>&1; then
    info "installing debootstrap"
    apt-get update -y
    apt-get install -y debootstrap
  fi
  command -v debootstrap >/dev/null || die "debootstrap not available"
  info "debootstrap: $(command -v debootstrap)"
}

cleanup_mounts() {
  # 尽量卸干净，失败不阻断 exit trap 的其它清理
  for p in "${MNT}/dev/pts" "${MNT}/dev" "${MNT}/proc" "${MNT}/sys" "${MNT}/boot/efi" "${MNT}"; do
    if mountpoint -q "${p}" 2>/dev/null; then
      umount "${p}" 2>/dev/null || umount -l "${p}" 2>/dev/null || true
    fi
  done
}

confirm_or_exit() {
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    return 0
  fi
  echo
  echo "About to debootstrap ${CODENAME} onto ${SUT_DEV}"
  echo "  mirror=${MIRROR}"
  echo "  hostname=${HOSTNAME_SUT} user=${USER_NAME} mkfs=${DO_MKFS}"
  if [[ "${DO_MKFS}" -eq 1 ]]; then
    echo "  WARNING: mkfs.ext4 will ERASE all data on ${SUT_DEV}"
  fi
  read -r -p "Continue? [y/N] " ans
  [[ "${ans}" == "y" || "${ans}" == "Y" ]] || die "aborted by user"
}

format_and_mount() {
  mkdir -p "${MNT}"
  if findmnt "${SUT_DEV}" >/dev/null 2>&1; then
    info "umount ${SUT_DEV}"
    umount "${SUT_DEV}" || die "cannot umount ${SUT_DEV}"
  fi

  if [[ "${DO_MKFS}" -eq 1 ]]; then
    info "mkfs.ext4 -F -L ${TARGET_LABEL} ${SUT_DEV}"
    mkfs.ext4 -F -L "${TARGET_LABEL}" "${SUT_DEV}"
  fi

  info "mount ${SUT_DEV} -> ${MNT}"
  mount "${SUT_DEV}" "${MNT}"
  df -h "${MNT}"
}

run_debootstrap() {
  info "debootstrap --arch=amd64 ${CODENAME} ${MNT} ${MIRROR}"
  debootstrap --arch=amd64 "${CODENAME}" "${MNT}" "${MIRROR}"
}

bind_and_dns() {
  mount --bind /dev "${MNT}/dev"
  mount --bind /proc "${MNT}/proc"
  mount --bind /sys "${MNT}/sys"
  mount --bind /dev/pts "${MNT}/dev/pts"
  cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf"
}

write_fstab() {
  local esp_uuid root_uuid
  esp_uuid=$(blkid -s UUID -o value "${ESP_DEV}")
  root_uuid=$(blkid -s UUID -o value "${SUT_DEV}")
  [[ -n "${esp_uuid}" && -n "${root_uuid}" ]] || die "failed to read UUIDs"

  info "ESP_UUID=${esp_uuid}"
  info "ROOT_UUID=${root_uuid}"

  cat > "${MNT}/etc/fstab" <<EOF
# ESP (${ESP_DEV})
UUID=${esp_uuid}  /boot/efi  vfat  umask=0077  0  1
# root ${TARGET_LABEL} (${SUT_DEV})
UUID=${root_uuid}  /          ext4  defaults    0  1
EOF
  cat "${MNT}/etc/fstab"
}

configure_in_chroot() {
  info "chroot configure (packages, user, ssh, netplan)"
  # 把变量传入 chroot
  cat > "${MNT}/root/bootstrap-config.sh" <<'EOS'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "${HOSTNAME_SUT}" > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

if ! grep -qE "^127\.0\.1\.1[[:space:]]+${HOSTNAME_SUT}\$" /etc/hosts 2>/dev/null; then
  echo "127.0.1.1 ${HOSTNAME_SUT}" >> /etc/hosts
fi

apt-get update
# shellcheck disable=SC2086
apt-get install -y ${EXTRA_PKGS}

if ! id "${USER_NAME}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${USER_NAME}"
fi
echo "${USER_NAME}:${USER_PASS}" | chpasswd
usermod -aG sudo "${USER_NAME}"
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"
chmod 440 "/etc/sudoers.d/${USER_NAME}"

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || true

mkdir -p /etc/netplan
cat > /etc/netplan/01-netcfg.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    all-en:
      match:
        name: "en*"
      dhcp4: true
    all-eth:
      match:
        name: "eth*"
      dhcp4: true
EOF
chmod 600 /etc/netplan/01-netcfg.yaml

ls -1 /boot/vmlinuz-* /boot/initrd.img-*
EOS
  chmod +x "${MNT}/root/bootstrap-config.sh"

  chroot "${MNT}" /bin/bash -c "
    export HOSTNAME_SUT='${HOSTNAME_SUT}'
    export USER_NAME='${USER_NAME}'
    export USER_PASS='${USER_PASS}'
    export EXTRA_PKGS='${EXTRA_PKGS}'
    /root/bootstrap-config.sh
  "
  rm -f "${MNT}/root/bootstrap-config.sh"
}

verify_boot_files() {
  shopt -s nullglob
  local vmlinuz=( "${MNT}"/boot/vmlinuz-* )
  local initrd=( "${MNT}"/boot/initrd.img-* )
  shopt -u nullglob
  [[ ${#vmlinuz[@]} -gt 0 && ${#initrd[@]} -gt 0 ]] \
    || die "kernel/initrd missing under ${MNT}/boot — install failed"
  info "boot files OK:"
  ls -lh "${vmlinuz[@]}" "${initrd[@]}"
}

show_help() {
  cat <<EOF
Usage: sudo $0 [options]

Automate debootstrap install of Ubuntu onto PARTLABEL=${TARGET_LABEL} while on PE.
Does NOT run update-grub / grub-reboot / create_pcl_gz_image.sh.

Options:
  -y              Assume yes (required for non-interactive CI)
  -c CODENAME     Ubuntu codename (default: ${CODENAME}; 26.04=resolute, 24.04=noble)
  -m MIRROR       Apt mirror (default: ${MIRROR})
  -H HOSTNAME     Target hostname (default: ${HOSTNAME_SUT})
  -u USER         Login user (default: ${USER_NAME})
  -p PASSWORD     Login password (default: ${USER_PASS})
  --skip-mkfs     Do not format target partition (reuse existing ext4)
  -h              Help

Env overrides: CODENAME MIRROR HOSTNAME_SUT USER_NAME USER_PASS MNT
EOF
  exit 2
}

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y) ASSUME_YES=1; shift ;;
    -c) CODENAME="$2"; shift 2 ;;
    -m) MIRROR="$2"; shift 2 ;;
    -H) HOSTNAME_SUT="$2"; shift 2 ;;
    -u) USER_NAME="$2"; shift 2 ;;
    -p) USER_PASS="$2"; shift 2 ;;
    --skip-mkfs) DO_MKFS=0; shift ;;
    -h|--help) show_help ;;
    *) die "unknown option: $1 (try -h)" ;;
  esac
done

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo $0 ...)"

require_pe
resolve_disk_layout
ensure_debootstrap
confirm_or_exit

trap cleanup_mounts EXIT

format_and_mount
run_debootstrap
bind_and_dns
write_fstab
configure_in_chroot
verify_boot_files

info "unmounting"
cleanup_mounts
trap - EXIT

cat <<EOF

============================================================
debootstrap install finished.
  target : ${SUT_DEV}
  release: ${CODENAME}
  user   : ${USER_NAME} / (password you set)
  next   :
    1) sudo sed -i ... GRUB_DISABLE_OS_PROBER=false   # if needed
    2) sudo update-grub
    3) sudo grub-reboot <index-of-p4-menu>
    4) sudo reboot   # verify SSH, then back to PE
    5) ./create_pcl_gz_image.sh -o <name>
  see: docs/手动部署os到sut-target-os分区并制作镜像.md 第三/四步
============================================================
EOF
