#!/bin/bash
set -e

# ============================================================
# 🧩 setup-k3s-cluster.sh
# Version: v1.2.10
# Last Updated: 2025-03-14
#
# 🔄 Change Log:
# - v1.0.0: 初始版本
# - v1.1.0: 精简 agent 参数
# - v1.1.2: master 允许调度 pod，taint 可选
# - v1.1.3: 修复 Cilium Helm 冲突
# - v1.1.4: 加入 fixed 参数清理旧环境
# - v1.1.5: 最小化 Cilium 部署配置
# - v1.1.6: Cilium 调整为可选安装，通过 --with-cilium 启用
# - v1.2.0: 支持 cluster-cidr/service-cidr 自定义
# - v1.2.3: helm uninstall cilium 增强
# - v1.2.4: fixed 模式支持更多接口清理
# - v1.2.6: 添加 INSTALL_CILIUM 环境变量，适配资源受限场景
# - v1.2.7: 支持国内/国际网络智能判断，默认 get.k3s.io
# - v1.2.8: 网络智能判断、国内加速镜像源、结构优化
# - v1.2.9: 增加函数模块化、完整注释、提升可读性与维护性
# ✅ v1.2.10: 引入 --system-default-registry 参数以避免 docker.io 超时问题
# ============================================================

ROLE=$1
INSTALL_CILIUM=false

print_usage() {
  echo "Usage:"
  echo "  $0 init"
  echo "  $0 fixed"
  echo "  $0 server <EGRESS_EXTERNAL_IP> [SERVER_NODE_IP] [FLANNEL_IFACE] [K3S_TOKEN] [CLUSTER_CIDR] [SERVICE_CIDR] [ADD_TAINT=true|false] [--with-cilium]"
  echo "  $0 agent <SERVER_NODE_IP> <K3S_TOKEN>"
  exit 1
}

is_in_china() {
  local cn_score=0 global_score=0
  for host in www.baidu.com www.aliyun.com www.163.com; do ping -c 1 -W 1 $host &>/dev/null && ((cn_score++)); done
  for host in www.cloudflare.com www.wikipedia.org www.google.com; do ping -c 1 -W 1 $host &>/dev/null && ((global_score++)); done
  [[ $cn_score -ge $global_score ]]
}

optimize_system() {
  fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  cat <<EOF >/etc/sysctl.d/k3s.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
net.ipv4.ip_forward=1
EOF
  sysctl --system
  systemctl disable --now snapd motd-news.service rsyslog apport ufw || true
  apt purge -y cloud-init lxd lxc unattended-upgrades || yum remove -y cloud-init || true
  echo "✅ 系统优化完成"
  exit 0
}

clean_environment() {
  /usr/local/bin/k3s-uninstall.sh || true
  /usr/local/bin/k3s-agent-uninstall.sh || true
  rm -rf /etc/rancher /opt/rancher ~/.kube || true
  helm uninstall cilium cilium-crds -n kube-system || true
  kubectl delete ns cilium-secrets --ignore-not-found
  kubectl delete crd $(kubectl get crd | grep cilium | awk '{print $1}') --ignore-not-found || true
  kubectl taint nodes -l node.cilium.io/agent-not-ready:NoSchedule- || true
  for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(flannel|cilium|cilium_|cilium@|cilium_vxlan)' | sed 's/@.*//'); do
    ip link set $iface down || true
    ip link delete $iface || true
  done
  echo "✅ 清理完成"
  exit 0
}

install_cilium() {
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm repo add cilium https://helm.cilium.io && helm repo update
  cat <<EOF >cilium-egress-values.yaml
routingMode: native
ipv4NativeRoutingCIDR: "10.42.0.0/16"
kubeProxyReplacement: false
enableIPv4Masquerade: true
nodePort:
  enabled: true
bpf:
  masquerade: true
ipam:
  mode: kubernetes
egressGateway:
  enabled: true
  installRoutes: true
endpointRoutes:
  enabled: true
cni:
  exclusive: false
envoy:
  enabled: false
proxy:
  enabled: false
l7Proxy: false
hubble:
  enabled: false
operator:
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: 20m
      memory: 30Mi
    limits:
      cpu: 100m
      memory: 128Mi
resources:
  requests:
    cpu: 20m
    memory: 50Mi
  limits:
    cpu: 100m
    memory: 128Mi
EOF
  helm upgrade --install cilium cilium/cilium -n kube-system --set installCRDs=true -f cilium-egress-values.yaml --wait
  kubectl label node $(hostname) egress-gateway=true --overwrite
  echo "✅ Cilium 安装完成"
}

main() {
  [[ "$ROLE" =~ ^(init|server|agent|fixed)$ ]] || print_usage
  for arg in "$@"; do [[ "$arg" == "--with-cilium" ]] && INSTALL_CILIUM=true; done

  case $ROLE in
    init)
      optimize_system
      ;;
    fixed)
      clean_environment
      ;;
    server)
      EGRESS_EXTERNAL_IP=$2
      SERVER_NODE_IP=${3:-$(hostname -I | awk '{print $1}')}
      FLANNEL_IFACE=${4:-""}
      K3S_TOKEN=$5
      CLUSTER_CIDR=$6
      SERVICE_CIDR=$7
      ADD_TAINT=${8:-false}

      [[ -z "$EGRESS_EXTERNAL_IP" ]] && { echo "❌ 缺少 EGRESS_EXTERNAL_IP"; print_usage; }

      if is_in_china; then
        echo "🌏 检测为中国网络，使用阿里云镜像"
        export INSTALL_K3S_MIRROR=cn
        SYSTEM_REGISTRY="--system-default-registry registry.cn-hangzhou.aliyuncs.com"
        INSTALL_K3S_URL="https://rancher-mirror.rancher.cn/k3s/k3s-install.sh"
      else
        SYSTEM_REGISTRY=""
        INSTALL_K3S_URL="https://get.k3s.io"
      fi

      INSTALL_K3S_EXEC="server --disable=traefik,servicelb,local-storage \
        --data-dir=/opt/rancher/k3s \
        --node-ip=${SERVER_NODE_IP} \
        --node-external-ip=${EGRESS_EXTERNAL_IP} \
        --advertise-address=${SERVER_NODE_IP} \
        ${SYSTEM_REGISTRY}"

      [[ -n "$FLANNEL_IFACE" ]] && INSTALL_K3S_EXEC+=" --flannel-iface=${FLANNEL_IFACE}"
      [[ -n "$K3S_TOKEN" ]] && INSTALL_K3S_EXEC+=" --token=${K3S_TOKEN}"
      [[ -n "$CLUSTER_CIDR" ]] && INSTALL_K3S_EXEC+=" --cluster-cidr=${CLUSTER_CIDR}"
      [[ -n "$SERVICE_CIDR" ]] && INSTALL_K3S_EXEC+=" --service-cidr=${SERVICE_CIDR}"

      curl -sfL ${INSTALL_K3S_URL} -o install_k3s.sh && chmod +x install_k3s.sh
      INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC" ./install_k3s.sh

      until kubectl get pods -A | grep -q "coredns.*Running"; do sleep 3; done
      mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
      export KUBECONFIG=~/.kube/config

      [[ "$INSTALL_CILIUM" == true ]] && install_cilium || echo "🚫 未启用 Cilium 安装"
      [[ "$ADD_TAINT" == true ]] && kubectl taint node $(hostname) node-role.kubernetes.io/master=:NoSchedule --overwrite

      echo -e "\n✅ Server 安装完成"
      ;;
    agent)
      SERVER_NODE_IP=$2
      K3S_TOKEN=$3
      [[ -z "$SERVER_NODE_IP" || -z "$K3S_TOKEN" ]] && print_usage
      NODE_IP=$(hostname -I | awk '{print $1}')
      INSTALL_K3S_EXEC="agent --server=https://${SERVER_NODE_IP}:6443 --node-ip=${NODE_IP} --token=${K3S_TOKEN}"
      curl -sfL https://get.k3s.io -o install_k3s.sh && chmod +x install_k3s.sh
      INSTALL_K3S_EXEC="$INSTALL_K3S_EXEC" ./install_k3s.sh
      echo "✅ Agent 安装完成"
      ;;
  esac
}

main "$@"
