#!/bin/bash
set -e

# 检测平台
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# 标准化平台
if [[ "$OS" == "darwin" ]]; then
  PLATFORM="macos"
elif [[ "$OS" == "linux" ]]; then
  PLATFORM="linux"
else
  echo "[ERROR] Unsupported OS: $OS"
  exit 1
fi

# 标准化架构
case "$ARCH" in
  x86_64)
    ARCH_DIR="amd64"
    ;;
  arm64|aarch64)
    ARCH_DIR="arm64"
    ;;
  *)
    echo "[ERROR] Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "[INFO] Detected OS: $PLATFORM, Arch: $ARCH_DIR"
BIN_DIR="/usr/local/bin"

# 安装 Pulumi
echo "[INFO] Installing Pulumi..."
tar -xzf tools/${PLATFORM}/${ARCH_DIR}/pulumi-*.tar.gz -C /tmp/
sudo cp /tmp/pulumi*/pulumi $BIN_DIR
sudo chmod +x $BIN_DIR/pulumi

# 安装 Terraform
echo "[INFO] Installing Terraform..."
unzip -o tools/${PLATFORM}/${ARCH_DIR}/terraform.zip -d /tmp/
sudo cp /tmp/terraform $BIN_DIR
sudo chmod +x $BIN_DIR/terraform

# 安装 Ansible (离线 pip)
echo "[INFO] Installing Ansible offline via pip..."
PIP_BIN=$(command -v pip3 || command -v pip)
if [[ -z "$PIP_BIN" ]]; then
  echo "[ERROR] pip or pip3 not found. Please install Python pip first." >&2
  exit 1
fi
$PIP_BIN install --no-index --find-links=tools/${PLATFORM}/${ARCH_DIR} ansible

# 验证安装结果
echo "[INFO] Verifying installations..."
$BIN_DIR/pulumi version || true
$BIN_DIR/terraform version || true
ansible --version || true

echo "[DONE] Offline installation complete."
