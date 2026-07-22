// SZ 实验室 Pipeline 辅助 —— 用 Jenkins HTTP API，不碰 Jenkins.get()（免 Script Approval）
// 调用前需设置（Jenkinsfile withCredentials）:
//   JENKINS_URL（Controller 通常已注入）
//   JENKINS_USER / JENKINS_TOKEN

def _jenkinsUrl() {
  def u = env.JENKINS_URL ?: env.SZ_JENKINS_URL ?: ''
  if (!u) {
    error('JENKINS_URL is not set (set Jenkins Location, or pass SZ_JENKINS_URL / param JENKINS_BASE_URL)')
  }
  return u.endsWith('/') ? u : (u + '/')
}

def _curlAuth() {
  if (!env.JENKINS_USER || !env.JENKINS_TOKEN) {
    error('JENKINS_USER/JENKINS_TOKEN required (create credentials jenkins-api)')
  }
  return "-u '${env.JENKINS_USER}:${env.JENKINS_TOKEN}'"
}

def _computerJson(String nodeName) {
  // 节点名勿特殊字符时直接用；避免 URLEncoder 再触发沙箱
  def url = "${_jenkinsUrl()}computer/${nodeName}/api/json?tree=offline,temporarilyOffline"
  def json = sh(
    script: "curl -fsSk ${_curlAuth()} '${url}'",
    returnStdout: true
  ).trim()
  return json
}

def _isOfflineJson(String json) {
  if (json.contains('"offline":true')) {
    return true
  }
  if (json.contains('"offline":false')) {
    return false
  }
  error("unexpected computer api json: ${json}")
}

def waitForNodeOffline(String nodeName, int timeoutSec = 180) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil(initialRecurrencePeriod: 5000) {
      def json = _computerJson(nodeName)
      def off = _isOfflineJson(json)
      echo "wait offline ${nodeName}: offline=${off} raw=${json}"
      return off
    }
  }
}

def waitForNodeOnline(String nodeName, int timeoutSec = 900) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil(initialRecurrencePeriod: 5000) {
      def json = _computerJson(nodeName)
      def off = _isOfflineJson(json)
      echo "wait online ${nodeName}: offline=${off}"
      return !off
    }
  }
}

def reconnectNode(String nodeName) {
  def base = _jenkinsUrl()
  def auth = _curlAuth()
  sh """
    set +e
    CRUMB_JSON=\$(curl -fsSk ${auth} '${base}crumbIssuer/api/json' 2>/dev/null)
    CRUMB_HDR=""
    if echo "\$CRUMB_JSON" | grep -q crumbRequestField; then
      FIELD=\$(echo "\$CRUMB_JSON" | sed -n 's/.*"crumbRequestField":"\\([^"]*\\)".*/\\1/p')
      CRUMB=\$(echo "\$CRUMB_JSON" | sed -n 's/.*"crumb":"\\([^"]*\\)".*/\\1/p')
      CRUMB_HDR="-H \${FIELD}:\${CRUMB}"
    fi
    curl -fsSk -X POST ${auth} \$CRUMB_HDR '${base}computer/${nodeName}/launchSlaveAgent' \\
      || curl -fsSk -X POST ${auth} \$CRUMB_HDR '${base}computer/${nodeName}/reconnect' \\
      || true
  """
}

def partlabelOnNode(String expected = '') {
  def out = sh(
    script: 'lsblk -no PARTLABEL "$(findmnt -n -o SOURCE /)" | tr -d "[:space:]"',
    returnStdout: true
  ).trim()
  if (expected && out != expected) {
    error("PARTLABEL=${out}, expected ${expected}")
  }
  return out
}

return this
