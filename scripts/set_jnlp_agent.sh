#!/usr/bin/env bash
# 测试机入网：Jenkins 建节点 + PE Agent（p2）+ p3 node.env（层 2，SUT 刷盘后仍保留）
#
# 用法:
#   ./set_jnlp_agent.sh -i 172.31.8.5              # IP 从 sut_lab_nodes.registry 解析节点名
#   ./set_jnlp_agent.sh -i 172.31.8.5 -n SUT-003 -v
#   ./set_jnlp_agent.sh --list-registry
#   ./set_jnlp_agent.sh -i 172.31.8.5 --skip-p3   # 仅 PE，不写 sut-tool
#
# 配置: pipeline/.env + pipeline/sut_lab_nodes.registry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PIPELINE_ROOT}/.env}"
JA_LIB="${SCRIPT_DIR}/lib/jenkins_agent_common.sh"

SSH_USER=""
SSH_PASS=""
SSH_TARGET=""
NODE_NAME=""
RECREATE_NODE=0
FORCE_PE=0
SKIP_P3=0
LIST_REGISTRY=0
VERBOSE=0
WAIT_ONLINE_SEC=180
REGISTRY_FILE=""

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
vinfo() { [[ "${VERBOSE}" -eq 1 ]] && echo "    $*" || true; }

usage() {
  cat <<'EOF'
Usage: set_jnlp_agent.sh -i <PE_IP> [options]

  入网 = Jenkins 节点 + PE Agent（p2）+ sut-tool 上 node.env（p3，供 SUT OS 刷盘后自启 Agent）

Options:
  -i IP              测试机 PE IP（须在 sut_lab_nodes.registry 中有对应节点名，或用 -n）
  -n NAME            Jenkins 节点名（覆盖 registry）
  -u USER            SSH 用户（覆盖 .env）
  -p PASS            SSH 密码（覆盖 .env）
  --recreate-node    若节点已存在则先删再建（secret 会变，须回填 registry）
  --skip-p3          不写入 sut-tool（p3）node.env
  --force-pe         不校验 PARTLABEL=PE
  --list-registry    打印 sut_lab_nodes.registry 并退出
  --wait SEC         等待 Agent online 秒数（默认 180）
  -v                 详细日志
  -h                 帮助

台账: pipeline/sut_lab_nodes.registry（NODE_NAME <TAB> PE_IP [<TAB> SECRET_HEX]）
环境: pipeline/.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) SSH_TARGET="$2"; shift 2 ;;
    -n) NODE_NAME="$2"; shift 2 ;;
    -u) SSH_USER="$2"; shift 2 ;;
    -p) SSH_PASS="$2"; shift 2 ;;
    --recreate-node) RECREATE_NODE=1; shift ;;
    --skip-p3) SKIP_P3=1; shift ;;
    --list-registry) LIST_REGISTRY=1; shift ;;
    --force-pe) FORCE_PE=1; shift ;;
    --wait) WAIT_ONLINE_SEC="$2"; shift 2 ;;
    -v) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "${LIST_REGISTRY}" -eq 1 ]] || [[ -n "${SSH_TARGET}" ]] || { usage; die "missing -i <IP> (or use --list-registry)"; }

load_env() {
  [[ -f "${ENV_FILE}" ]] || die "env file not found: ${ENV_FILE}"
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
  [[ -f "${JA_LIB}" ]] || die "missing ${JA_LIB}"
  # shellcheck disable=SC1090
  source "${JA_LIB}"

  : "${JENKINS_USER:?JENKINS_USER required in .env}"
  : "${JENKINS_TOKEN:?JENKINS_TOKEN required in .env}"
  : "${JENKINS_API_URL:?JENKINS_API_URL required in .env}"
  : "${JENKINS_AGENT_URL:?JENKINS_AGENT_URL required in .env}"

  ja_apply_agent_config_defaults
  JENKINS_NODE_LABELS="${JENKINS_NODE_LABELS:-pe bare-metal lab}"
  JENKINS_NODE_EXECUTORS="${JENKINS_NODE_EXECUTORS:-1}"

  SUT_LAB_REGISTRY_FILE="${SUT_LAB_REGISTRY_FILE:-sut_lab_nodes.registry}"
  if [[ "${SUT_LAB_REGISTRY_FILE}" != /* ]]; then
    SUT_LAB_REGISTRY_FILE="${PIPELINE_ROOT}/${SUT_LAB_REGISTRY_FILE}"
  fi
  SUT_TOOL_MOUNT_ON_PE="${SUT_TOOL_MOUNT_ON_PE:-/mnt/sut-tool}"
  REGISTRY_FILE="${SUT_LAB_REGISTRY_FILE}"
}

# ── SUT lab registry (node name + IP [+ secret]) ─────────────────

registry_list() {
  [[ -f "${REGISTRY_FILE}" ]] || die "registry not found: ${REGISTRY_FILE}"
  echo "# registry: ${REGISTRY_FILE}"
  python3 - "${REGISTRY_FILE}" <<'PY'
import sys
path = sys.argv[1]
print(f"{'NODE':<12} {'PE_IP':<16} {'SECRET':<12}")
print("-" * 44)
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.replace("\t", " ").split()
        if len(parts) < 2:
            continue
        name, ip = parts[0], parts[1]
        sec = parts[2] if len(parts) > 2 else ""
        sec_disp = (sec[:8] + "...") if len(sec) >= 8 else "(fetch on provision)"
        print(f"{name:<12} {ip:<16} {sec_disp}")
PY
}

registry_lookup() {
  local mode="$1" value="$2"
  [[ -f "${REGISTRY_FILE}" ]] || return 1
  REGISTRY_LOOKUP_NODE="" REGISTRY_LOOKUP_IP="" REGISTRY_LOOKUP_SECRET=""
  eval "$(python3 - "${REGISTRY_FILE}" "${mode}" "${value}" <<'PY'
import sys
path, mode, value = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.replace("\t", " ").split()
        if len(parts) < 2:
            continue
        rows.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ""))
found = None
if mode == "ip":
    for name, ip, sec in rows:
        if ip == value:
            found = (name, ip, sec)
            break
elif mode == "name":
    for name, ip, sec in rows:
        if name == value:
            found = (name, ip, sec)
            break
if not found:
    sys.exit(1)
name, ip, sec = found
def q(s):
    return s.replace("'", "'\\''")
print(f"REGISTRY_LOOKUP_NODE='{q(name)}'")
print(f"REGISTRY_LOOKUP_IP='{q(ip)}'")
print(f"REGISTRY_LOOKUP_SECRET='{q(sec)}'")
PY
)" || return 1
  return 0
}

resolve_from_registry() {
  REGISTRY_LOOKUP_SECRET=""
  if [[ ! -f "${REGISTRY_FILE}" ]]; then
    vinfo "registry missing: ${REGISTRY_FILE} (use -n or copy sut_lab_nodes.registry.example)"
    return 0
  fi

  if [[ -n "${SSH_TARGET}" ]] && registry_lookup ip "${SSH_TARGET}"; then
    if [[ -z "${NODE_NAME}" ]]; then
      NODE_NAME="${REGISTRY_LOOKUP_NODE}"
      info "registry: ${SSH_TARGET} → node ${NODE_NAME}"
    elif [[ "${NODE_NAME}" != "${REGISTRY_LOOKUP_NODE}" ]]; then
      die "registry maps ${SSH_TARGET} → ${REGISTRY_LOOKUP_NODE}, but -n ${NODE_NAME} was given"
    fi
  elif [[ -n "${NODE_NAME}" ]] && registry_lookup name "${NODE_NAME}"; then
    if [[ -z "${SSH_TARGET}" ]]; then
      SSH_TARGET="${REGISTRY_LOOKUP_IP}"
      info "registry: ${NODE_NAME} → IP ${SSH_TARGET}"
    elif [[ "${SSH_TARGET}" != "${REGISTRY_LOOKUP_IP}" ]]; then
      die "registry maps ${NODE_NAME} → ${REGISTRY_LOOKUP_IP}, but -i ${SSH_TARGET} was given"
    fi
  fi
}

require_local_tools() {
  command -v curl >/dev/null || die "curl not found"
  command -v sshpass >/dev/null || die "sshpass not found (sudo apt install sshpass)"
  command -v python3 >/dev/null || die "python3 not found"
}

# ── Jenkins REST API ─────────────────────────────────────────────

JENKINS_CRUMB=""
JENKINS_CRUMB_FIELD=""

jenkins_curl() {
  local method="$1"; shift
  local url="$1"; shift
  local extra=()
  if [[ -n "${JENKINS_CRUMB}" && -n "${JENKINS_CRUMB_FIELD}" ]]; then
    extra+=(-H "${JENKINS_CRUMB_FIELD}: ${JENKINS_CRUMB}")
  fi
  curl -sS -f -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    -X "${method}" "${extra[@]}" "$@" "${url}"
}

jenkins_curl_allow_fail() {
  local method="$1"; shift
  local url="$1"; shift
  local extra=()
  if [[ -n "${JENKINS_CRUMB}" && -n "${JENKINS_CRUMB_FIELD}" ]]; then
    extra+=(-H "${JENKINS_CRUMB_FIELD}: ${JENKINS_CRUMB}")
  fi
  curl -sS -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    -X "${method}" "${extra[@]}" "$@" "${url}" || true
}

fetch_crumb() {
  local json
  json="$(curl -sS -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    "${JENKINS_API_URL}crumbIssuer/api/json" 2>/dev/null || true)"
  if [[ -z "${json}" || "${json}" == *"Not Found"* ]]; then
    vinfo "crumb issuer disabled"
    return 0
  fi
  JENKINS_CRUMB="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('crumb',''))" <<<"${json}")"
  JENKINS_CRUMB_FIELD="$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('crumbRequestField',''))" <<<"${json}")"
  vinfo "crumb ok field=${JENKINS_CRUMB_FIELD}"
}

jenkins_node_exists() {
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    "${JENKINS_API_URL}computer/${NODE_NAME}/api/json")"
  [[ "${code}" == "200" ]]
}

jenkins_delete_node() {
  info "delete existing Jenkins node: ${NODE_NAME}"
  jenkins_curl POST "${JENKINS_API_URL}computer/${NODE_NAME}/doDelete" >/dev/null
  sleep 2
}

jenkins_create_node() {
  if jenkins_node_exists; then
    if [[ "${RECREATE_NODE}" -eq 1 ]]; then
      jenkins_delete_node
    else
      info "Jenkins node already exists: ${NODE_NAME} (reuse)"
      return 0
    fi
  fi

  info "create Jenkins node: ${NODE_NAME}"
  local json payload
  json="$(NODE_NAME="${NODE_NAME}" SSH_TARGET="${SSH_TARGET}" \
    JENKINS_AGENT_WORKDIR="${JENKINS_AGENT_WORKDIR}" JENKINS_NODE_LABELS="${JENKINS_NODE_LABELS}" \
    JENKINS_NODE_EXECUTORS="${JENKINS_NODE_EXECUTORS}" \
    python3 - <<'PY'
import json, os
print(json.dumps({
    "name": os.environ["NODE_NAME"],
    "nodeDescription": f"PE JNLP agent on {os.environ['SSH_TARGET']}",
    "numExecutors": os.environ.get("JENKINS_NODE_EXECUTORS", "1"),
    "remoteFS": os.environ["JENKINS_AGENT_WORKDIR"],
    "labelString": os.environ["JENKINS_NODE_LABELS"],
    "mode": "NORMAL",
    "retentionStrategy": {
        "stapler-class": "hudson.slaves.RetentionStrategy$Always",
        "$class": "hudson.slaves.RetentionStrategy$Always",
    },
    "launcher": {
        "stapler-class": "hudson.slaves.JNLPLauncher",
        "$class": "hudson.slaves.JNLPLauncher",
    },
    "nodeProperties": {"stapler-class-bag": "true"},
}))
PY
)"

  payload="name=${NODE_NAME}&type=hudson.slaves.DumbSlave"
  payload+=$(python3 -c "import urllib.parse,sys; print('&json='+urllib.parse.quote(sys.stdin.read()))" <<<"${json}")

  local resp code extra=()
  resp="$(mktemp)"
  if [[ -n "${JENKINS_CRUMB}" && -n "${JENKINS_CRUMB_FIELD}" ]]; then
    extra+=(-H "${JENKINS_CRUMB_FIELD}: ${JENKINS_CRUMB}")
  fi
  code="$(curl -sS -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    -X POST "${extra[@]}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-binary "${payload}" \
    -o "${resp}" -w '%{http_code}' \
    "${JENKINS_API_URL}computer/doCreateItem")" || die "Jenkins create node request failed"

  if [[ "${code}" != "200" && "${code}" != "302" ]]; then
    vinfo "Jenkins response (${code}): $(head -c 500 "${resp}")"
    rm -f "${resp}"
    die "Jenkins create node failed HTTP ${code}"
  fi
  rm -f "${resp}"
}

jenkins_fetch_jnlp() {
  local url jnlp
  for url in \
    "${JENKINS_API_URL}computer/${NODE_NAME}/jenkins-agent.jnlp" \
    "${JENKINS_API_URL}computer/${NODE_NAME}/slave-agent.jnlp"; do
    jnlp="$(curl -sS -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" "${url}" 2>/dev/null || true)"
    if [[ -n "${jnlp}" && "${jnlp}" == *"<argument>"* ]]; then
      echo "${jnlp}"
      return 0
    fi
  done
  return 1
}

jenkins_get_agent_secret() {
  local jnlp secret
  jnlp="$(jenkins_fetch_jnlp)" || die "failed to fetch agent jnlp for ${NODE_NAME}"

  secret="$(NODE_NAME="${NODE_NAME}" python3 -c "
import re, os, sys
text = sys.stdin.read()
node = os.environ.get('NODE_NAME', '')
args = re.findall(r'<argument>([^<]+)</argument>', text)
# 优先找 32+ 位 hex secret（Jenkins 2.x 常见格式）
for a in reversed(args):
    a = a.strip()
    if re.fullmatch(r'[a-f0-9]{32,}', a, re.I):
        print(a)
        sys.exit(0)
# 三段式：url, name, secret
if len(args) >= 3 and args[1].strip() == node:
    print(args[2].strip())
    sys.exit(0)
# 旧两段式：url, secret
if len(args) >= 2:
    print(args[1].strip())
    sys.exit(0)
sys.exit(1)
" <<< "${jnlp}")" || die "cannot parse agent secret from jnlp"

  [[ -n "${secret}" && "${secret}" != "${NODE_NAME}" ]] || die "invalid agent secret (got node name?)"
  echo "${secret}"
}

jenkins_wait_online() {
  local deadline=$((SECONDS + WAIT_ONLINE_SEC))
  info "wait Jenkins node online (timeout ${WAIT_ONLINE_SEC}s)..."
  while (( SECONDS < deadline )); do
    local json offline
    json="$(curl -sS -k -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
      "${JENKINS_API_URL}computer/${NODE_NAME}/api/json?tree=offline")" || true
    offline="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('offline', True))" <<<"${json}" 2>/dev/null || echo True)"
    if [[ "${offline}" == "False" ]]; then
      info "✓ node ${NODE_NAME} is online"
      return 0
    fi
    sleep 5
  done
  die "node ${NODE_NAME} not online after ${WAIT_ONLINE_SEC}s"
}

# ── SSH to PE ───────────────────────────────────────────────────

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=15
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
)

ssh_try() {
  local user="$1" pass="$2"
  shift 2
  sshpass -p "${pass}" ssh "${SSH_OPTS[@]}" "${user}@${SSH_TARGET}" "$@"
}

detect_ssh_auth() {
  if [[ -n "${SSH_USER}" && -n "${SSH_PASS}" ]]; then
    ssh_try "${SSH_USER}" "${SSH_PASS}" "echo ok" >/dev/null \
      && { info "SSH ok: ${SSH_USER}@${SSH_TARGET}"; return 0; }
    die "SSH failed with -u/-p overrides"
  fi

  local creds=(
    "${PE_SSH_USER:-amd}:${PE_SSH_PASS:-amdyes}"
    "${PE_SSH_FALLBACK_USER:-jenkins}:${PE_SSH_FALLBACK_PASS:-0}"
    "zs:amdyes"
  )
  local entry u p
  for entry in "${creds[@]}"; do
    u="${entry%%:*}"
    p="${entry#*:}"
    if ssh_try "${u}" "${p}" "echo ok" >/dev/null 2>&1; then
      SSH_USER="${u}"
      SSH_PASS="${p}"
      info "SSH ok: ${SSH_USER}@${SSH_TARGET}"
      return 0
    fi
    if [[ "${VERBOSE}" -eq 1 ]]; then
      vinfo "SSH try failed: ${u}@${SSH_TARGET}: $(ssh_try "${u}" "${p}" "echo ok" 2>&1 | tail -1)"
    else
      vinfo "SSH try failed: ${u}@${SSH_TARGET}"
    fi
  done
  die "cannot SSH to ${SSH_TARGET} (tried amd/amdyes, jenkins/0, zs/amdyes)"
}

ssh_run() {
  ssh_try "${SSH_USER}" "${SSH_PASS}" "$@"
}

resolve_node_name() {
  if [[ -n "${NODE_NAME}" ]]; then
    return 0
  fi
  if registry_lookup ip "${SSH_TARGET}" 2>/dev/null; then
    NODE_NAME="${REGISTRY_LOOKUP_NODE}"
    info "Jenkins node name (registry): ${NODE_NAME}"
    return 0
  fi
  local host
  host="$(ssh_run "hostname -s 2>/dev/null || hostname" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "${host}" ]]; then
    NODE_NAME="${host}"
    info "Jenkins node name (hostname): ${NODE_NAME}"
  else
    NODE_NAME="PE-${SSH_TARGET//./-}"
    info "Jenkins node name (fallback): ${NODE_NAME}"
  fi
  vinfo "tip: add '${NODE_NAME}\t${SSH_TARGET}' to ${SUT_LAB_REGISTRY_FILE}"
}

verify_pe() {
  [[ "${FORCE_PE}" -eq 1 ]] && { info "skip PE PARTLABEL check (--force-pe)"; return 0; }
  local partlabel
  partlabel="$(ssh_run 'lsblk -no PARTLABEL "$(findmnt -n -o SOURCE /)" 2>/dev/null | tr -d "[:space:]"' || true)"
  if [[ "${partlabel}" == "PE" ]]; then
    info "confirmed PARTLABEL=PE on ${SSH_TARGET}"
    return 0
  fi
  die "root PARTLABEL='${partlabel:-<empty>}' (expected PE). Boot into PE or use --force-pe"
}

deploy_agent_on_pe() {
  local secret="$1"
  local lib_content
  info "deploy agent on PE via SSH (${SSH_USER}@${SSH_TARGET})"
  lib_content="$(< "${JA_LIB}")"

  ssh_try "${SSH_USER}" "${SSH_PASS}" "bash -s" <<REMOTE
${lib_content}
set -euo pipefail
export JENKINS_NODE_NAME='${NODE_NAME}'
export JENKINS_AGENT_SECRET='${secret}'
export JENKINS_AGENT_URL_PE='${JENKINS_AGENT_URL_PE}'
export JENKINS_API_URL='${JENKINS_API_URL}'
export JENKINS_CONTROLLER_IP='${JENKINS_CONTROLLER_IP}'
export JENKINS_AGENT_USER='${JENKINS_AGENT_USER}'
export JENKINS_AGENT_WORKDIR='${JENKINS_AGENT_WORKDIR}'
export AGENT_INSECURE='${AGENT_INSECURE}'
export AGENT_WEBSOCKET='${AGENT_WEBSOCKET}'
export SUDO_PASS='${SSH_PASS}'
ja_deploy_pe_agent
echo "PE agent service started"
REMOTE
}

provision_p3_identity() {
  local secret="$1"
  local lib_content
  info "provision p3 identity (sut-tool → ${SUT_AGENT_IDENTITY_SUBDIR}/node.env)"
  lib_content="$(< "${JA_LIB}")"

  ssh_try "${SSH_USER}" "${SSH_PASS}" "bash -s" <<REMOTE
${lib_content}
set -euo pipefail
export JENKINS_NODE_NAME='${NODE_NAME}'
export JENKINS_AGENT_SECRET='${secret}'
export JENKINS_AGENT_URL='${JENKINS_AGENT_URL_PE}'
export JENKINS_CONTROLLER_IP='${JENKINS_CONTROLLER_IP}'
export JENKINS_TLS_HOSTNAME='${JENKINS_TLS_HOSTNAME}'
export JENKINS_AGENT_USER='${JENKINS_AGENT_USER}'
export JENKINS_AGENT_WORKDIR='${JENKINS_AGENT_WORKDIR}'
export AGENT_INSECURE='${AGENT_INSECURE}'
export AGENT_WEBSOCKET='${AGENT_WEBSOCKET}'
export SUT_TOOL_PARTLABEL='${SUT_TOOL_PARTLABEL}'
export SUT_AGENT_IDENTITY_SUBDIR='${SUT_AGENT_IDENTITY_SUBDIR}'
export SUT_TOOL_MOUNT_ON_PE='${SUT_TOOL_MOUNT_ON_PE}'
export SUDO_PASS='${SSH_PASS}'

tool_dev="\$(lsblk -lnpo NAME,PARTLABEL | awk -v l="\${SUT_TOOL_PARTLABEL}" '\$2==l {print \$1; exit}')"
[[ -n "\${tool_dev}" && -b "\${tool_dev}" ]] || ja_die "PARTLABEL=\${SUT_TOOL_PARTLABEL} not found"

ja_sudo_cmd mkdir -p "\${SUT_TOOL_MOUNT_ON_PE}"
if ! mountpoint -q "\${SUT_TOOL_MOUNT_ON_PE}"; then
  ja_sudo_cmd mount "\${tool_dev}" "\${SUT_TOOL_MOUNT_ON_PE}"
  echo "mounted \${tool_dev} → \${SUT_TOOL_MOUNT_ON_PE}"
fi

identity_dir="\${SUT_TOOL_MOUNT_ON_PE}/\${SUT_AGENT_IDENTITY_SUBDIR}"
ja_sudo_cmd mkdir -p "\${identity_dir}"
env_tmp="\$(mktemp)"
ja_render_node_env > "\${env_tmp}"
ja_sudo_cmd install -m 600 -o root -g root "\${env_tmp}" "\${identity_dir}/node.env"
rm -f "\${env_tmp}"
echo "wrote \${identity_dir}/node.env"
ls -la "\${identity_dir}/node.env"

mountpoint -q "\${SUT_TOOL_MOUNT_ON_PE}" && ja_sudo_cmd umount "\${SUT_TOOL_MOUNT_ON_PE}" || true
REMOTE
}

preflight_jenkins_api() {
  info "check Jenkins API: ${JENKINS_API_URL}"
  jenkins_curl GET "${JENKINS_API_URL}api/json?tree=mode" >/dev/null \
    || die "Jenkins API unreachable. Check JENKINS_API_URL / token / network"
  info "✓ Jenkins API ok"
}

main() {
  load_env
  require_local_tools

  if [[ "${LIST_REGISTRY}" -eq 1 ]]; then
    REGISTRY_FILE="${SUT_LAB_REGISTRY_FILE}"
    registry_list
    exit 0
  fi

  resolve_from_registry
  preflight_jenkins_api
  fetch_crumb

  detect_ssh_auth
  resolve_node_name
  verify_pe

  jenkins_create_node
  SECRET="$(jenkins_get_agent_secret)"
  vinfo "agent secret: ${SECRET:0:8}..."

  if [[ -n "${REGISTRY_LOOKUP_SECRET:-}" && "${REGISTRY_LOOKUP_SECRET}" != "${SECRET}" ]]; then
    vinfo "WARN: registry secret differs from Jenkins; using Jenkins API value"
  fi

  if [[ "${SKIP_P3}" -eq 0 ]]; then
    provision_p3_identity "${SECRET}"
  else
    info "skip p3 node.env (--skip-p3)"
  fi

  deploy_agent_on_pe "${SECRET}"
  jenkins_wait_online

  cat <<EOF

Done.
  Node:     ${NODE_NAME}
  PE IP:    ${SSH_TARGET}
  SSH:      ${SSH_USER}@${SSH_TARGET}
  Agent:    ${JENKINS_AGENT_USER} (workdir ${JENKINS_AGENT_WORKDIR})
  Service:  jenkins-agent.service on PE (p2)
  p3 env:   ${SUT_AGENT_IDENTITY_SUBDIR}/node.env on PARTLABEL=${SUT_TOOL_PARTLABEL}
            (SUT 刷盘后读此文件自启 Agent；与 PE 共用同一 node 名与 secret)

Update registry (optional, for documentation / offline reprovision):
  ${NODE_NAME}\t${SSH_TARGET}\t${SECRET}

Verify on PE:
  ssh ${SSH_USER}@${SSH_TARGET} 'sudo systemctl status jenkins-agent --no-pager'

Verify on Jenkins:
  ${JENKINS_API_URL}computer/${NODE_NAME}/
EOF
}

main "$@"
