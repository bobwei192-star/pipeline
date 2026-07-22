// SZ 实验室 Pipeline 辅助（load 后调用）
// 沙箱下首次跑需管理员批准签名（见下方注释）。

import jenkins.model.Jenkins

def _computer(String nodeName) {
  // Jenkins.get() 比 getInstance 更规范；仍需 Script Approval 一次
  def node = Jenkins.get().getNode(nodeName)
  if (node == null && nodeName == 'built-in') {
    return Jenkins.get().getComputer('')
  }
  return node?.toComputer()
}

def waitForNodeOffline(String nodeName, int timeoutSec = 180) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil(initialRecurrencePeriod: 5000) {
      def c = _computer(nodeName)
      echo "wait offline ${nodeName}: computer=${c != null} offline=${c?.offline}"
      return (c == null || c.offline)
    }
  }
}

def waitForNodeOnline(String nodeName, int timeoutSec = 900) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil(initialRecurrencePeriod: 5000) {
      def c = _computer(nodeName)
      def ok = (c != null && c.online)
      echo "wait online ${nodeName}: online=${ok}"
      return ok
    }
  }
}

def reconnectNode(String nodeName) {
  def c = _computer(nodeName)
  if (c == null) {
    error("Jenkins node not found: ${nodeName}")
  }
  c.connect(false)
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
