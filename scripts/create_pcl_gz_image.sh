#!/bin/bash
# 在 PE 上对 sut-target-os 分区打 partclone 镜像（*.pcl.gz）
# 用法: ./create_pcl_gz_image.sh -o <镜像名>
# 产物: <镜像名>-next.pcl.gz（当前目录）

set -euo pipefail

TARGET_LABEL="sut-target-os"
PCL_DIR="${HOME}/pcl_image"
IMAGE_TAG="next"
OWNER_USER="${PCL_OWNER:-amd}"

# --- PE 环境检查（禁止在 SUT 上打包正在运行的根或误操作）---
# 实验室可靠判据：当前根分区 PARTLABEL 必须为 PE
# （无通用 which pe 命令；勿用 GRUB_DISTRIBUTOR，部分节点未设 PE-LNX-CI）
require_pe() {
  local root_src partlabel
  root_src=$(findmnt -n -o SOURCE /) || {
    echo "ERROR: cannot resolve root device" >&2
    exit 1
  }
  partlabel=$(lsblk -no PARTLABEL "${root_src}" 2>/dev/null | tr -d '[:space:]')
  if [[ "${partlabel}" != "PE" ]]; then
    echo "ERROR: must run on PE (root PARTLABEL=PE)." >&2
    echo "       current root=${root_src} PARTLABEL='${partlabel:-<empty>}'" >&2
    echo "       if PARTLABEL=sut-target-os you are on SUT — reboot to PE first." >&2
    exit 1
  fi
  echo "OK: running on PE (root=${root_src})"
}

# Resolve the block device that backs /
_root_dev=$(findmnt -n -o SOURCE /)
if [[ "${_root_dev}" =~ /dev/nvme ]]; then
  BLK_DEV=$(echo "${_root_dev}" | sed -r 's/p[0-9]+$//')
  PART_PREFIX="${BLK_DEV}p"
else
  BLK_DEV="${_root_dev%%[0-9]*}"
  PART_PREFIX="${BLK_DEV}"
fi

purge_stale_artifacts() {
  mkdir -p "${PCL_DIR}"
  rm -f "${PCL_DIR}"/*-next.pcl "${PCL_DIR}"/*-next.pcl.gz.sha1 2>/dev/null || true
  # 当前目录半成品（上次 Ctrl+C 残留）
  rm -f ./*-next.pcl 2>/dev/null || true
}

# Locate the labeled OS partition, shrink FS, then emit a compressed pcl
build_pcl_archive() {
  local part_idx out_file part_dev

  part_idx=$(sudo parted "${BLK_DEV}" -l 2>/dev/null | awk -v lbl="${TARGET_LABEL}" '$0 ~ lbl { print $1; exit }')
  if [[ -z "${part_idx}" ]]; then
    echo "ERROR: partition with PARTLABEL/Name '${TARGET_LABEL}' not found on ${BLK_DEV}" >&2
    exit 1
  fi

  out_file="${1}-${IMAGE_TAG}.pcl"
  part_dev="${PART_PREFIX}${part_idx}"

  if [[ ! -b "${part_dev}" ]]; then
    echo "ERROR: ${part_dev} is not a block device" >&2
    exit 1
  fi

  # 源分区不能是当前根
  if [[ "$(findmnt -n -o SOURCE /)" == "${part_dev}" ]]; then
    echo "ERROR: refusing to clone current root ${part_dev}" >&2
    exit 1
  fi

  # 未挂载才能 e2fsck/resize/partclone
  if findmnt "${part_dev}" >/dev/null 2>&1; then
    echo "ERROR: ${part_dev} is mounted; umount it first" >&2
    exit 1
  fi

  echo "Cloning ${part_dev} -> ${out_file}.gz ..."
  sudo e2fsck -f -y "${part_dev}"
  # 关闭 metadata_csum（兼容部分 partclone）；无输入时约 5s 后自动继续
  sudo tune2fs -O ^metadata_csum "${part_dev}" || true
  sudo resize2fs -M "${part_dev}"

  sudo rm -f "${out_file}"
  if ! sudo partclone.ext4 -c -s "${part_dev}" -o "${out_file}"; then
    echo "Partclone fail." >&2
    rm -f "${out_file}"
    exit 1
  fi
  echo "Partclone successfully!"

  if id "${OWNER_USER}" >/dev/null 2>&1; then
    sudo chown "${OWNER_USER}:${OWNER_USER}" "${out_file}"
  else
    echo "WARN: user ${OWNER_USER} not found; skip chown" >&2
  fi
  gzip -f "${out_file}"
  echo "Output: $(pwd)/${out_file}.gz"
  ls -lh "${out_file}.gz"
}

show_help() {
  echo "Usage: $0 -o <os_image_name>"
  echo "  Must run on PE (root PARTLABEL=PE)."
  echo "  Options:"
  echo "    -o   OS image name (required), e.g. ubuntu26.04-minimal"
  echo "    -h   Help"
  echo "  Env:"
  echo "    PCL_OWNER  chown user after clone (default: amd)"
  exit 2
}

# --- entry ---
os_name=""
while getopts ":ho:" opt; do
  case "${opt}" in
    o) os_name="${OPTARG}" ;;
    h|?) show_help ;;
  esac
done

[[ -z "${os_name}" ]] && show_help

require_pe
purge_stale_artifacts
build_pcl_archive "${os_name}"
