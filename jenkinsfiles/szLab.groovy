// SZ 实验室 Pipeline 辅助（load 后调用）
//   def sz = load 'pipeline/jenkinsfiles/szLab.groovy'

def waitForNodeOffline(String nodeName, int timeoutSec = 180) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil {
      def c = jenkins.model.Jenkins.instance.getNode(nodeName)?.toComputer()
      c == null || c.offline
    }
  }
}

def waitForNodeOnline(String nodeName, int timeoutSec = 900) {
  timeout(time: timeoutSec, unit: 'SECONDS') {
    waitUntil {
      def c = jenkins.model.Jenkins.instance.getNode(nodeName)?.toComputer()
      c != null && c.online
    }
  }
}

def reconnectNode(String nodeName) {
  def c = jenkins.model.Jenkins.instance.getNode(nodeName)?.toComputer()
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
