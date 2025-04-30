#!/bin/bash
set -e

ARCH=$1

PULUMI_VERSION=3.112.0
TERRAFORM_VERSION=1.6.6
ANSIBLE_VERSION=7.5.0

mkdir -p offline-iac/plugins/{pulumi,terraform,ansible}

# ------------------------------
# Pulumi CLI
for OS in linux darwin windows; do
  OUT_OS=$OS
  [[ "$OS" == "darwin" ]] && OUT_OS="macos"
  curl -L -o offline-iac/tools/${OUT_OS}/${ARCH}/pulumi-${PULUMI_VERSION}.tar.gz \
    https://get.pulumi.com/releases/sdk/pulumi-v${PULUMI_VERSION}-${OS}-${ARCH}.tar.gz
done

# Pulumi Plugins
pulumi plugin install resource aws v6.50.0
pulumi plugin install resource gcp v6.62.0
pulumi plugin install resource azure v5.60.0
pulumi plugin install resource alicloud v1.157.0 || true
cp -r ~/.pulumi/plugins/* offline-iac/plugins/pulumi/

# ------------------------------
# Terraform CLI
for OS in linux darwin windows; do
  OUT_OS=$OS
  [[ "$OS" == "darwin" ]] && OUT_OS="macos"
  curl -L -o offline-iac/tools/${OUT_OS}/${ARCH}/terraform.zip \
    https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip
done

# 本地 Terraform CLI 解压用于 provider 初始化
mkdir -p tmp-tf
curl -L -o tmp-tf/terraform.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip
unzip -o tmp-tf/terraform.zip -d tmp-tf/
export PATH=$PWD/tmp-tf:$PATH

# 创建 Terraform 配置用于 provider 缓存
cat > main.tf <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.39.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "5.19.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.74.0"
    }
    alicloud = {
      source  = "aliyun/alicloud"
      version = "1.213.0"
    }
  }
}

provider "aws" {}
provider "google" {}
provider "azurerm" {}
provider "alicloud" {}
EOF

# 初始化 Terraform provider 插件（联网）
mkdir -p terraform-provider-cache
terraform init -plugin-dir=terraform-provider-cache || true
cp -r terraform-provider-cache/* offline-iac/plugins/terraform/ || true
rm -f main.tf

# ------------------------------
# Ansible pip wheels
python3 -m pip download ansible==${ANSIBLE_VERSION} -d offline-iac/tools/linux/${ARCH}/ --only-binary=:all:
python3 -m pip download ansible==${ANSIBLE_VERSION} -d offline-iac/tools/macos/${ARCH}/ --only-binary=:all:
python3 -m pip download ansible==${ANSIBLE_VERSION} -d offline-iac/tools/windows/${ARCH}/ --only-binary=:all:

# Ansible Collections
ansible-galaxy collection download amazon.aws -p offline-iac/plugins/ansible
ansible-galaxy collection download google.cloud -p offline-iac/plugins/ansible
ansible-galaxy collection download azure.azcollection -p offline-iac/plugins/ansible
ansible-galaxy collection download alicloud.cloud -p offline-iac/plugins/ansible || true
