#!/usr/bin/env bash
# CI Deploy OS：在 PE 上将本地 .pcl.gz 刷写到 sut-target-os（p4）
# 用法:
#   ./deploy_os_in_ci.sh -f /home/amd/ubuntu26.04-minimal-next.pcl.gz
#   ./deploy_os_in_ci.sh -o ubuntu26.04-minimal   # → ~/ubuntu26.04-minimal-next.pcl.gz

set -euo pipefail

TARGET_LABEL="${TARGET_LABEL:-sut-target-os}"
IMAGE_TAG="${IMAGE_TAG:-next}"
PCL_GZ=""
OS_NAME=""
KEEP_PCL="${KEEP_PCL:-1}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Usage: deploy_os_in_ci.sh -f <path.pcl.gz>
       deploy_os_in_ci.sh -o <os_name>   # reads ~/<os_name>-next.pcl.gz

  Must run on PE (PARTLABEL=PE), typically via Jenkins node(SUT-xxx).
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f) PCL_GZ="$2"; shift 2 ;;
    -o) OS_NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1" ;;
  esac
done

if [[ -n "${OS_NAME}" && -z "${PCL_GZ}" ]]; then
  PCL_GZ="${HOME}/${OS_NAME}-${IMAGE_TAG}.pcl.gz"
fi
[[ -n "${PCL_GZ}" ]] || usage
[[ -f "${PCL_GZ}" ]] || die "image not found: ${PCL_GZ}"

require_pe() {
  local pl root_src
  root_src=$(findmnt -n -o SOURCE /)
  pl=$(lsblk -no PARTLABEL "${root_src}" 2>/dev/null | tr -d '[:space:]')
  [[ "${pl}" == "PE" ]] || die "must run on PE, got PARTLABEL='${pl:-empty}'"
  info "confirmed PE (root=${root_src})"
}

resolve_sut_dev() {
  SUT_DEV=$(lsblk -lnpo NAME,PARTLABEL | awk -v l="${TARGET_LABEL}" '$2==l {print $1; exit}')
  [[ -n "${SUT_DEV}" && -b "${SUT_DEV}" ]] || die "PARTLABEL=${TARGET_LABEL} not found"
  [[ "$(findmnt -n -o SOURCE /)" != "${SUT_DEV}" ]] || die "refusing: ${SUT_DEV} is current root"
  info "target ${SUT_DEV}"
}

sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif [[ -n "${SUDO_PASS:-}" ]]; then
    # CI / agent 无 TTY：从 SUDO_PASS 读密码（Jenkins withCredentials 注入）
    printf '%s\n' "${SUDO_PASS}" | sudo -S -p '' "$@"
  elif sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    die "sudo needs password: set SUDO_PASS or configure NOPASSWD"
  fi
}

ensure_partclone() {
  command -v partclone.ext4 >/dev/null && return 0
  info "installing partclone..."
  sudo_cmd apt-get update -qq
  sudo_cmd DEBIAN_FRONTEND=noninteractive apt-get install -y -qq partclone
}

restore_partition() {
  local pcl="${PCL_GZ%.gz}"
  sudo_cmd umount "${SUT_DEV}" 2>/dev/null || true
  if findmnt "${SUT_DEV}" >/dev/null 2>&1; then
    die "${SUT_DEV} still mounted"
  fi

  # 若磁盘上已有同名 .pcl，但比 .gz 旧，必须删掉，否则会刷错「旧包」
  if [[ -f "${pcl}" && -f "${PCL_GZ}" ]]; then
    if [[ "${pcl}" -ot "${PCL_GZ}" ]]; then
      info "stale ${pcl} older than ${PCL_GZ}; removing before decompress"
      rm -f "${pcl}"
    fi
  fi

  if [[ ! -f "${pcl}" ]]; then
    info "decompress ${PCL_GZ}"
    gzip -dk "${PCL_GZ}"
  else
    info "using existing ${pcl}"
  fi
  [[ -f "${pcl}" ]] || die "missing ${pcl}"

  info "partclone restore ${pcl} -> ${SUT_DEV}"
  sudo_cmd partclone.ext4 -r -s "${pcl}" -o "${SUT_DEV}"

  info "e2fsck + resize2fs"
  sudo_cmd e2fsck -yf "${SUT_DEV}"
  sudo_cmd resize2fs -f "${SUT_DEV}"

  if [[ "${KEEP_PCL}" != "1" ]]; then
    rm -f "${pcl}"
  fi
  info "restore complete"
}

require_pe
resolve_sut_dev
ensure_partclone
restore_partition
