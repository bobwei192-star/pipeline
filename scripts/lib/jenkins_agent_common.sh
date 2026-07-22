# Jenkins Agent 安装公共逻辑（PE 直连 / SUT 读 p3）
# 被 set_jnlp_agent.sh、embed_jenkins_agent_runtime.sh source 或注入到远程 shell。
#
# 约定环境变量（调用方设置）：
#   JENKINS_API_URL, JENKINS_AGENT_URL / JENKINS_AGENT_URL_PE
#   JENKINS_AGENT_USER, JENKINS_AGENT_WORKDIR
#   AGENT_INSECURE, AGENT_WEBSOCKET
#   JENKINS_CONTROLLER_IP, JENKINS_TLS_HOSTNAME
#   SUT_TOOL_PARTLABEL, SUT_AGENT_IDENTITY_SUBDIR, SUT_TOOL_MOUNT_IN_SUT
# 可选：SUDO_PASS（非 root 时）、ROOT_PREFIX（chroot 根，如 /mnt/p4）

ja_die() { echo "ERROR: $*" >&2; exit 1; }

ja_sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif sudo -n true 2>/dev/null; then
    sudo "$@"
  elif [[ -n "${SUDO_PASS:-}" ]]; then
    printf '%s\n' "${SUDO_PASS}" | sudo -S -p '' "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

ja_resolve_agent_url_pe() {
  local url="${1:?}" tls_host="${2:-devopsagent.local}"
  python3 - "${url}" "${tls_host}" <<'PY'
import re, sys
from urllib.parse import urlparse, urlunparse
url, tls_host = sys.argv[1], sys.argv[2]
p = urlparse(url)
host = p.hostname or ""
if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}", host) and tls_host:
    netloc = tls_host
    if p.port:
        netloc = f"{tls_host}:{p.port}"
    p = p._replace(netloc=netloc)
print(urlunparse(p).rstrip("/") + "/")
PY
}

ja_apply_agent_config_defaults() {
  JENKINS_API_URL="${JENKINS_API_URL%/}/"
  JENKINS_AGENT_URL="${JENKINS_AGENT_URL%/}/"
  JENKINS_AGENT_USER="${JENKINS_AGENT_USER:-amd}"
  JENKINS_AGENT_WORKDIR="${JENKINS_AGENT_WORKDIR:-/home/${JENKINS_AGENT_USER}/agent}"
  AGENT_WEBSOCKET="${AGENT_WEBSOCKET:-1}"
  JENKINS_TLS_HOSTNAME="${JENKINS_TLS_HOSTNAME:-devopsagent.local}"
  SUT_TOOL_PARTLABEL="${SUT_TOOL_PARTLABEL:-sut-tool}"
  SUT_AGENT_IDENTITY_SUBDIR="${SUT_AGENT_IDENTITY_SUBDIR:-lab/agent}"
  SUT_TOOL_MOUNT_IN_SUT="${SUT_TOOL_MOUNT_IN_SUT:-/shared}"
  AGENT_INSECURE="${AGENT_INSECURE:-0}"
  if [[ "${JENKINS_AGENT_URL}" == https://* ]]; then
    AGENT_INSECURE=1
  fi
  if [[ -z "${JENKINS_AGENT_URL_PE:-}" ]]; then
    JENKINS_AGENT_URL_PE="$(ja_resolve_agent_url_pe "${JENKINS_AGENT_URL}" "${JENKINS_TLS_HOSTNAME}")"
  fi
  JENKINS_CONTROLLER_IP="${JENKINS_CONTROLLER_IP:-$(python3 -c "from urllib.parse import urlparse; print(urlparse('${JENKINS_API_URL}').hostname or '')")}"
}

ja_build_java_exec_line() {
  # 输出完整 ExecStart 命令（不含 User=）
  local jar="$1" agent_url="$2" secret="$3" node_name="$4" workdir="$5"
  local line
  line="/usr/bin/java -jar ${jar} -url ${agent_url} -secret ${secret} -name ${node_name} -workDir ${workdir}"
  [[ "${AGENT_WEBSOCKET:-1}" == "1" ]] && line+=" -webSocket"
  [[ "${AGENT_INSECURE:-0}" == "1" ]] && line+=" -noCertificateCheck"
  printf '%s' "${line}"
}

ja_ensure_hosts() {
  local agent_url="${1:?}" controller_ip="${2:-}" root="${3:-}"
  local host
  local hosts_file="${root}/etc/hosts"
  [[ -n "${controller_ip}" ]] || return 0
  host="$(python3 -c "from urllib.parse import urlparse; print(urlparse('${agent_url}').hostname or '')")"
  [[ -n "${host}" && ! "${host}" =~ ^[0-9.]+$ ]] || return 0
  if grep -qE "^[[:space:]]*${controller_ip}[[:space:]]+${host}([[:space:]]|$)" "${hosts_file}" 2>/dev/null; then
    echo "hosts ok: ${controller_ip} ${host}"
    return 0
  fi
  if [[ -n "${root}" ]]; then
    printf '%s %s\n' "${controller_ip}" "${host}" >> "${hosts_file}"
  else
    ja_sudo_cmd bash -c "printf '%s %s\n' '${controller_ip}' '${host}' >> /etc/hosts"
  fi
  echo "added hosts: ${controller_ip} ${host}"
}

ja_install_apt_deps() {
  local root="${1:-}"
  local jre
  local -a jre_candidates=(
    openjdk-25-jre-headless
    openjdk-21-jre-headless
    openjdk-17-jre-headless
    openjdk-11-jre-headless
    default-jre-headless
  )

  if [[ -n "${root}" ]]; then
    if chroot "${root}" command -v java >/dev/null 2>&1; then
      echo "java already in chroot: $(chroot "${root}" java -version 2>&1 | head -1)"
      return 0
    fi
    chroot "${root}" apt-get update -qq
    for jre in "${jre_candidates[@]}"; do
      if chroot "${root}" env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -qq "${jre}" curl ca-certificates 2>/dev/null; then
        echo "installed ${jre} in chroot"
        return 0
      fi
    done
    ja_die "no JRE in chroot (tried: ${jre_candidates[*]})"
  fi

  if command -v java >/dev/null 2>&1; then
    echo "java already installed: $(java -version 2>&1 | head -1)"
    return 0
  fi
  command -v apt-get >/dev/null || ja_die "apt-get not found"
  ja_sudo_cmd apt-get update -qq
  for jre in "${jre_candidates[@]}"; do
    if ja_sudo_cmd DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      "${jre}" curl ca-certificates 2>/dev/null; then
      echo "installed ${jre}"
      return 0
    fi
  done
  ja_die "no JRE package found (tried: ${jre_candidates[*]})"
}

ja_download_agent_jar() {
  local jar_path="$1" api_url="${2:?}"
  local opts=(-fsSL)
  [[ "${AGENT_INSECURE:-0}" == "1" ]] && opts+=(-k)
  mkdir -p "$(dirname "${jar_path}")"
  curl "${opts[@]}" -o "${jar_path}" "${api_url}jnlpJars/agent.jar"
}

ja_render_node_env() {
  cat <<ENV
# Layer-2 Jenkins agent identity (persists across partclone on p4)
# Managed by pipeline agent scripts — do not bake into shared OS images
JENKINS_NODE_NAME=${JENKINS_NODE_NAME:?}
JENKINS_AGENT_SECRET=${JENKINS_AGENT_SECRET:?}
JENKINS_AGENT_URL=${JENKINS_AGENT_URL:?}
JENKINS_CONTROLLER_IP=${JENKINS_CONTROLLER_IP:-}
JENKINS_TLS_HOSTNAME=${JENKINS_TLS_HOSTNAME:-}
JENKINS_AGENT_USER=${JENKINS_AGENT_USER:?}
JENKINS_AGENT_WORKDIR=${JENKINS_AGENT_WORKDIR:?}
AGENT_WEBSOCKET=${AGENT_WEBSOCKET:-1}
AGENT_INSECURE=${AGENT_INSECURE:-1}
ENV
}

ja_install_sut_helper_scripts() {
  local lib_dir="$1"
  mkdir -p "${lib_dir}"

  cat > "${lib_dir}/prepare-env.sh" <<PREP
#!/bin/bash
set -euo pipefail
SHARED_MOUNT="${SUT_TOOL_MOUNT_IN_SUT}"
TOOL_LABEL="${SUT_TOOL_PARTLABEL}"
IDENTITY_REL="${SUT_AGENT_IDENTITY_SUBDIR}/node.env"
RUN_ENV=/run/jenkins-agent/env
AGENT_USER="${JENKINS_AGENT_USER}"

mkdir -p "\${SHARED_MOUNT}" /run/jenkins-agent
if ! mountpoint -q "\${SHARED_MOUNT}"; then
  dev=\$(lsblk -lnpo NAME,PARTLABEL | awk -v l="\${TOOL_LABEL}" '\$2==l {print \$1; exit}')
  [[ -n "\${dev}" ]] || { echo "ERROR: no PARTLABEL=\${TOOL_LABEL}" >&2; exit 1; }
  mount "\${dev}" "\${SHARED_MOUNT}"
fi
idf="\${SHARED_MOUNT}/\${IDENTITY_REL}"
[[ -f "\${idf}" ]] || { echo "ERROR: missing \${idf} (run set_jnlp_agent.sh)" >&2; exit 1; }
grep -v '^#' "\${idf}" | grep -v '^[[:space:]]*\$' > "\${RUN_ENV}"
chmod 600 "\${RUN_ENV}"
# shellcheck disable=SC1090
source "\${RUN_ENV}"
if [[ -n "\${JENKINS_CONTROLLER_IP:-}" && -n "\${JENKINS_TLS_HOSTNAME:-}" ]]; then
  if ! grep -qE "^\${JENKINS_CONTROLLER_IP}[[:space:]]+\${JENKINS_TLS_HOSTNAME}([[:space:]]|\$)" /etc/hosts 2>/dev/null; then
    printf '%s %s\n' "\${JENKINS_CONTROLLER_IP}" "\${JENKINS_TLS_HOSTNAME}" >> /etc/hosts
  fi
fi
chown "\${AGENT_USER}:\${AGENT_USER}" "\${RUN_ENV}" 2>/dev/null || true
echo "loaded \${idf}"
PREP

  cat > "${lib_dir}/run-agent.sh" <<'RUN'
#!/bin/bash
set -euo pipefail
# shellcheck disable=SC1091
source /run/jenkins-agent/env
: "${JENKINS_NODE_NAME:?}" "${JENKINS_AGENT_SECRET:?}" "${JENKINS_AGENT_URL:?}"
: "${JENKINS_AGENT_USER:?}" "${JENKINS_AGENT_WORKDIR:?}"
jar="/home/${JENKINS_AGENT_USER}/agent.jar"
[[ -f "${jar}" ]] || { echo "ERROR: missing ${jar}" >&2; exit 1; }
mkdir -p "${JENKINS_AGENT_WORKDIR}"
args=(-jar "${jar}" -url "${JENKINS_AGENT_URL}" -secret "${JENKINS_AGENT_SECRET}" \
  -name "${JENKINS_NODE_NAME}" -workDir "${JENKINS_AGENT_WORKDIR}")
[[ "${AGENT_WEBSOCKET:-1}" == "1" ]] && args+=(-webSocket)
[[ "${AGENT_INSECURE:-1}" == "1" ]] && args+=(-noCertificateCheck)
exec /usr/bin/java "${args[@]}"
RUN

  chmod 755 "${lib_dir}/prepare-env.sh" "${lib_dir}/run-agent.sh"
}

ja_write_systemd_unit_pe() {
  local root="${1:-}" exec_start="$2" agent_user="${3:?}" dest="${4:-}"
  local unit_path="${root}/etc/systemd/system/jenkins-agent.service"
  [[ -n "${dest}" ]] && unit_path="${dest}"
  mkdir -p "$(dirname "${unit_path}")"
  cat > "${unit_path}" <<UNIT
[Unit]
Description=Jenkins JNLP Agent (PE)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${agent_user}
Group=${agent_user}
WorkingDirectory=/home/${agent_user}
ExecStart=${exec_start}
Restart=on-failure
RestartSec=20
Environment=JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8

[Install]
WantedBy=multi-user.target
UNIT
}

ja_write_systemd_unit_sut() {
  local root="${1:-}" agent_user="${2:?}"
  local unit_path="${root}/etc/systemd/system/jenkins-agent.service"
  mkdir -p "$(dirname "${unit_path}")"
  cat > "${unit_path}" <<UNIT
[Unit]
Description=Jenkins Agent (SUT OS, identity from p3 node.env)
After=network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=simple
User=${agent_user}
Group=${agent_user}
ExecStartPre=+/usr/lib/jenkins-agent/prepare-env.sh
ExecStart=/usr/lib/jenkins-agent/run-agent.sh
Restart=on-failure
RestartSec=20
Environment=JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8

[Install]
WantedBy=multi-user.target
UNIT
  mkdir -p "${root}/etc/systemd/system/multi-user.target.wants"
  ln -sf ../jenkins-agent.service \
    "${root}/etc/systemd/system/multi-user.target.wants/jenkins-agent.service"
}

ja_systemd_enable_live() {
  ja_sudo_cmd systemctl unmask jenkins-agent.service 2>/dev/null || true
  ja_sudo_cmd rm -f /etc/systemd/system/jenkins-agent.service
  ja_sudo_cmd install -m 644 "${1}" /etc/systemd/system/jenkins-agent.service
  if [[ -L /etc/systemd/system/jenkins-agent.service ]]; then
    ja_die "jenkins-agent.service is still masked symlink"
  fi
  ja_sudo_cmd systemctl daemon-reload
  ja_sudo_cmd systemctl enable jenkins-agent.service
  ja_sudo_cmd systemctl restart jenkins-agent.service
}

# ── 高层：PE 上完整安装（secret 内联 unit）────────────────────────
ja_deploy_pe_agent() {
  : "${JENKINS_NODE_NAME:?}" "${JENKINS_AGENT_SECRET:?}"
  : "${JENKINS_AGENT_URL_PE:?}" "${JENKINS_API_URL:?}"
  local agent_home="/home/${JENKINS_AGENT_USER}"
  id "${JENKINS_AGENT_USER}" >/dev/null 2>&1 || ja_die "user ${JENKINS_AGENT_USER} not found"
  ja_ensure_hosts "${JENKINS_AGENT_URL_PE}" "${JENKINS_CONTROLLER_IP}" ""
  ja_install_apt_deps ""
  ja_download_agent_jar "${agent_home}/agent.jar" "${JENKINS_API_URL}"
  local exec_start
  exec_start="$(ja_build_java_exec_line \
    "${agent_home}/agent.jar" "${JENKINS_AGENT_URL_PE}" "${JENKINS_AGENT_SECRET}" \
    "${JENKINS_NODE_NAME}" "${JENKINS_AGENT_WORKDIR}")"
  local unit_tmp
  unit_tmp="$(mktemp)"
  ja_write_systemd_unit_pe "" "${exec_start}" "${JENKINS_AGENT_USER}" "${unit_tmp}"
  ja_sudo_cmd mkdir -p "${JENKINS_AGENT_WORKDIR}"
  ja_sudo_cmd chown -R "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" "${agent_home}" "${JENKINS_AGENT_WORKDIR}"
  ja_systemd_enable_live "${unit_tmp}"
  rm -f "${unit_tmp}"
  ja_sudo_cmd systemctl is-active jenkins-agent.service
}

# ── 高层：p4 chroot 注入 SUT 运行时（无 secret）──────────────────
ja_embed_sut_runtime() {
  local root="${1:?}"
  : "${JENKINS_API_URL:?}" "${JENKINS_AGENT_USER:?}" "${JENKINS_AGENT_WORKDIR:?}"
  chroot "${root}" id "${JENKINS_AGENT_USER}" >/dev/null 2>&1 \
    || ja_die "user ${JENKINS_AGENT_USER} missing in ${root}"
  ja_install_apt_deps "${root}"
  ja_download_agent_jar "${root}/home/${JENKINS_AGENT_USER}/agent.jar" "${JENKINS_API_URL}"
  chroot "${root}" chown "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" \
    "/home/${JENKINS_AGENT_USER}/agent.jar"
  ja_install_sut_helper_scripts "${root}/usr/lib/jenkins-agent"
  ja_write_systemd_unit_sut "${root}" "${JENKINS_AGENT_USER}"
  mkdir -p "${root}${JENKINS_AGENT_WORKDIR}"
  chroot "${root}" chown -R "${JENKINS_AGENT_USER}:${JENKINS_AGENT_USER}" \
    "/home/${JENKINS_AGENT_USER}" "${JENKINS_AGENT_WORKDIR}" 2>/dev/null || true
}

ja_add_fstab_shared() {
  local root="${1:-}"
  local fstab="${root}/etc/fstab"
  local dev uuid
  dev=$(lsblk -lnpo NAME,PARTLABEL | awk -v l="${SUT_TOOL_PARTLABEL}" '$2==l {print $1; exit}')
  uuid=$(blkid -s UUID -o value "${dev}" 2>/dev/null || true)
  [[ -n "${uuid}" ]] || return 0
  grep -q "${SUT_TOOL_MOUNT_IN_SUT}" "${fstab}" 2>/dev/null && return 0
  echo "UUID=${uuid}  ${SUT_TOOL_MOUNT_IN_SUT}  ext4  defaults,nofail  0  2" >> "${fstab}"
}
