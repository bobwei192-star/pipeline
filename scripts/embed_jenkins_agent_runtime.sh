#!/usr/bin/env bash
# 层 1：向 sut-target-os（p4）注入 Jenkins Agent 运行时（不含 secret）
# 身份由 p3 /shared/lab/agent/node.env 提供（set_jnlp_agent.sh）
#
#   ./embed_jenkins_agent_runtime.sh -i 172.31.8.5 -v          # 开发机 SSH 到 PE（推荐）
#   ./embed_jenkins_agent_runtime.sh --local -v                 # PE 本机（root 或 SSH 回环提权）
#
# 完成后：update-grub → reboot 进 SUT 验证 → create_pcl_gz_image.sh

set -euo pipefail

WRAPPER=1
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

if [[ "${1:-}" == "--embed-body" ]]; then
  WRAPPER=0
  shift
fi

if [[ "${WRAPPER}" -eq 0 ]]; then
  set -euo pipefail
  : "${MNT:?}" "${TARGET_LABEL:?}" "${JENKINS_API_URL:?}" "${AGENT_USER:?}"
  JA_COMMON="${JA_COMMON:?}"
  # shellcheck disable=SC1090
  source "${JA_COMMON}"

  die() { echo "ERROR: $*" >&2; exit 1; }
  info() { echo "==> $*"; }

  export JENKINS_AGENT_USER="${AGENT_USER}"
  export JENKINS_AGENT_WORKDIR="${AGENT_WORKDIR:?}"
  export JENKINS_API_URL="${JENKINS_API_URL%/}/"
  export JENKINS_AGENT_URL="${JENKINS_API_URL}"
  ja_apply_agent_config_defaults

  require_pe() {
    [[ "${FORCE_PE:-0}" == "1" ]] && return 0
    local pl
    pl=$(lsblk -no PARTLABEL "$(findmnt -n -o SOURCE /)" 2>/dev/null | tr -d '[:space:]')
    [[ "${pl}" == "PE" ]] || die "must run on PE (PARTLABEL=PE), got '${pl:-empty}'"
    info "confirmed PE"
  }

  cleanup_mounts() {
    # 只卸 chroot 专用挂载；勿 bind 宿主 /dev/pts 再 umount（会卸掉 PE 的 devpts）
    for p in "${MNT}/dev/pts" "${MNT}/dev" "${MNT}/proc" "${MNT}/sys" "${MNT}"; do
      mountpoint -q "${p}" 2>/dev/null && umount "${p}" 2>/dev/null || true
    done
  }

  mount_chroot_fs() {
    mkdir -p "${MNT}/dev/pts" "${MNT}/proc" "${MNT}/sys"
    mountpoint -q "${MNT}/dev" || mount --bind /dev "${MNT}/dev"
    mountpoint -q "${MNT}/proc" || mount --bind /proc "${MNT}/proc"
    mountpoint -q "${MNT}/sys" || mount --bind /sys "${MNT}/sys"
    # chroot 内单独挂 devpts（不要 bind 宿主 /dev/pts，否则 cleanup umount 会破坏 PE PTY）
    if ! mountpoint -q "${MNT}/dev/pts"; then
      mount -t devpts -o gid=5,mode=620,ptmxmode=666 devpts "${MNT}/dev/pts"
    fi
    cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf" 2>/dev/null || true
  }

  SUT_DEV=""
  resolve_sut() {
    SUT_DEV=$(lsblk -lnpo NAME,PARTLABEL | awk -v l="${TARGET_LABEL}" '$2==l {print $1; exit}')
    [[ -n "${SUT_DEV}" && -b "${SUT_DEV}" ]] || die "PARTLABEL=${TARGET_LABEL} not found"
    [[ "$(findmnt -n -o SOURCE /)" != "${SUT_DEV}" ]] || die "refusing: ${SUT_DEV} is current root"
    info "target ${SUT_DEV} → ${MNT}"
  }

  mount_root() {
    mkdir -p "${MNT}"
    if findmnt -n "${SUT_DEV}" >/dev/null 2>&1; then
      local t
      t=$(findmnt -n -o TARGET "${SUT_DEV}")
      [[ "${t}" == "${MNT}" ]] || umount "${SUT_DEV}" || die "cannot umount ${SUT_DEV} from ${t}"
    fi
    mountpoint -q "${MNT}" || mount "${SUT_DEV}" "${MNT}"
    mount_chroot_fs
  }

  require_pe
  resolve_sut
  trap cleanup_mounts EXIT
  mount_root
  ja_embed_sut_runtime "${MNT}"
  ja_add_fstab_shared "${MNT}"
  cleanup_mounts
  trap - EXIT
  info "layer-1 embed complete"
  exit 0
fi

# ── Wrapper（从开发机或 PE 调用）──────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PIPELINE_ROOT}/.env}"
JA_LIB="${SCRIPT_DIR}/lib/jenkins_agent_common.sh"

SSH_TARGET=""
SSH_USER=""
SSH_PASS=""
RUN_LOCAL=0
FORCE_PE=0
VERBOSE=0
MNT="${MNT:-/mnt/p4}"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Usage: embed_jenkins_agent_runtime.sh [options]

  向 p4 注入 Agent 运行时（无 secret）；SUT 启动读 p3 node.env。

Options:
  -i IP       SSH 到 PE 执行
  --local     在 PE 本机执行（自动提权；sudo PTY 坏时用 SSH 回环）
  --mnt PATH  p4 挂载点（默认 /mnt/p4）
  --force-pe  跳过 PE 检查
  -u / -p     SSH 凭据
  -v          详细
  -h          帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) SSH_TARGET="$2"; shift 2 ;;
    -u) SSH_USER="$2"; shift 2 ;;
    -p) SSH_PASS="$2"; shift 2 ;;
    --local) RUN_LOCAL=1; shift ;;
    --mnt) MNT="$2"; shift 2 ;;
    --force-pe) FORCE_PE=1; shift ;;
    -v) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown: $1" ;;
  esac
done

[[ "${RUN_LOCAL}" -eq 1 || -n "${SSH_TARGET}" ]] || { usage; die "use -i <IP> or --local"; }

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE}"
  [[ -f "${JA_LIB}" ]] || die "missing ${JA_LIB}"
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
  # shellcheck disable=SC1090
  source "${JA_LIB}"
  : "${JENKINS_API_URL:?}"
  export JENKINS_AGENT_URL="${JENKINS_AGENT_URL:-${JENKINS_API_URL}}"
  ja_apply_agent_config_defaults
  TARGET_LABEL="${TARGET_LABEL:-sut-target-os}"
}

run_embed_remote() {
  local remote_script="/tmp/embed_jenkins_agent_runtime.sh"
  local remote_lib="/tmp/jenkins_agent_common.sh"
  command -v sshpass >/dev/null 2>&1 || die "sshpass required for SSH embed"
  sshpass -p "${SSH_PASS}" scp "${SSH_OPTS[@]}" \
    "${SCRIPT_PATH}" "${SSH_USER}@${SSH_TARGET}:${remote_script}"
  sshpass -p "${SSH_PASS}" scp "${SSH_OPTS[@]}" \
    "${JA_LIB}" "${SSH_USER}@${SSH_TARGET}:${remote_lib}"
  # -T：远程非交互；sudo -S 从 stdin 读密码，不依赖本机 PTY（PE 上 devpts 损坏时仍可用）
  sshpass -p "${SSH_PASS}" ssh -T "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" \
    "chmod +x ${remote_script} ${remote_lib} && \
     printf '%s\n' '${SSH_PASS}' | sudo -S -p '' \
      MNT='${MNT}' \
      TARGET_LABEL='${TARGET_LABEL}' \
      JENKINS_API_URL='${JENKINS_API_URL}' \
      AGENT_USER='${JENKINS_AGENT_USER}' \
      AGENT_WORKDIR='${JENKINS_AGENT_WORKDIR}' \
      AGENT_INSECURE='${AGENT_INSECURE}' \
      AGENT_WEBSOCKET='${AGENT_WEBSOCKET}' \
      SUT_TOOL_PARTLABEL='${SUT_TOOL_PARTLABEL}' \
      SUT_AGENT_IDENTITY_SUBDIR='${SUT_AGENT_IDENTITY_SUBDIR}' \
      SUT_TOOL_MOUNT_IN_SUT='${SUT_TOOL_MOUNT_IN_SUT}' \
      FORCE_PE='${FORCE_PE}' \
      JA_COMMON='${remote_lib}' \
      bash ${remote_script} --embed-body"
}

run_embed_body_local_root() {
  local -a embed_env=(
    MNT="${MNT}" TARGET_LABEL="${TARGET_LABEL}" JENKINS_API_URL="${JENKINS_API_URL}"
    AGENT_USER="${JENKINS_AGENT_USER}" AGENT_WORKDIR="${JENKINS_AGENT_WORKDIR}"
    AGENT_INSECURE="${AGENT_INSECURE}" AGENT_WEBSOCKET="${AGENT_WEBSOCKET}"
    SUT_TOOL_PARTLABEL="${SUT_TOOL_PARTLABEL}" SUT_AGENT_IDENTITY_SUBDIR="${SUT_AGENT_IDENTITY_SUBDIR}"
    SUT_TOOL_MOUNT_IN_SUT="${SUT_TOOL_MOUNT_IN_SUT}" FORCE_PE="${FORCE_PE}" JA_COMMON="${JA_LIB}"
  )
  env "${embed_env[@]}" bash "${SCRIPT_PATH}" --embed-body
}

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15
  -o PreferredAuthentications=password -o PubkeyAuthentication=no)

detect_ssh() {
  if [[ -n "${SSH_USER}" && -n "${SSH_PASS}" ]]; then
    sshpass -p "${SSH_PASS}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" true
    info "SSH ok: ${SSH_USER}@${SSH_TARGET}"
    return 0
  fi
  local u p entry
  for entry in "${PE_SSH_USER:-amd}:${PE_SSH_PASS:-amdyes}" \
               "${PE_SSH_FALLBACK_USER:-jenkins}:${PE_SSH_FALLBACK_PASS:-0}"; do
    u="${entry%%:*}"; p="${entry#*:}"
    if sshpass -p "${p}" ssh "${SSH_OPTS[@]}" "${u}@${SSH_TARGET}" true 2>/dev/null; then
      SSH_USER="${u}"; SSH_PASS="${p}"
      info "SSH ok: ${SSH_USER}@${SSH_TARGET}"
      return 0
    fi
  done
  die "SSH failed: ${SSH_TARGET}"
}

run_embed_local() {
  local lip pass="${PE_SSH_PASS:-amdyes}"

  if [[ "$(id -u)" -eq 0 ]]; then
    run_embed_body_local_root
    return
  fi

  if printf '%s\n' "${pass}" | sudo -S -p '' true 2>/dev/null; then
    info "elevate via sudo -S"
    local -a embed_env=(
      MNT="${MNT}" TARGET_LABEL="${TARGET_LABEL}" JENKINS_API_URL="${JENKINS_API_URL}"
      AGENT_USER="${JENKINS_AGENT_USER}" AGENT_WORKDIR="${JENKINS_AGENT_WORKDIR}"
      AGENT_INSECURE="${AGENT_INSECURE}" AGENT_WEBSOCKET="${AGENT_WEBSOCKET}"
      SUT_TOOL_PARTLABEL="${SUT_TOOL_PARTLABEL}" SUT_AGENT_IDENTITY_SUBDIR="${SUT_AGENT_IDENTITY_SUBDIR}"
      SUT_TOOL_MOUNT_IN_SUT="${SUT_TOOL_MOUNT_IN_SUT}" FORCE_PE="${FORCE_PE}" JA_COMMON="${JA_LIB}"
    )
    printf '%s\n' "${pass}" | sudo -S -p '' env "${embed_env[@]}" \
      bash "${SCRIPT_PATH}" --embed-body
    return
  fi

  if command -v sshpass >/dev/null 2>&1; then
    lip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -n "${lip}" ]] || lip="127.0.0.1"
    SSH_TARGET="${lip}"
    SSH_USER="${USER:-${PE_SSH_USER:-amd}}"
    SSH_PASS="${pass}"
    if sshpass -p "${SSH_PASS}" ssh "${SSH_OPTS[@]}" "${SSH_USER}@${SSH_TARGET}" true 2>/dev/null; then
      info "local sudo PTY broken; SSH loopback to ${SSH_USER}@${SSH_TARGET}"
      run_embed_remote
      return
    fi
  fi

  lip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  die "无法在 PE 上提权（sudo PTY 损坏）。

请改用开发机执行（此前已验证可行）:
  ./embed_jenkins_agent_runtime.sh -i ${lip:-172.31.8.5} -v

或在 PE 安装 sshpass 后重试 --local（自动 SSH 回环提权）。"
}

main() {
  load_env
  if [[ "${RUN_LOCAL}" -eq 1 ]]; then
    info "embed on local PE"
    run_embed_local
  else
    detect_ssh
    info "embed on ${SSH_TARGET} via SSH"
    run_embed_remote
  fi

  cat <<EOF

Done (layer 1 — p4 Agent runtime, no secret in image).

Next steps (on PE, see docs/手动debootstrap… §第三步):
  1. sudo update-grub
  2. sudo grub-reboot <SUT-26.04-menu-index>
  3. sudo reboot → verify: systemctl status jenkins-agent (on SUT)
  4. Jenkins UI: SUT-003 online (target OS)
  5. reboot back to PE → ./create_pcl_gz_image.sh -o ubuntu26.04-minimal

Prerequisite: p3 node.env must exist (set_jnlp_agent.sh).
EOF
}

main "$@"
