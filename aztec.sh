#!/usr/bin/env bash
set -euo pipefail

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "本脚本必须以 root 权限运行。"
  exit 1
fi

# 定义常量
MIN_DOCKER_VERSION="20.10"
MIN_COMPOSE_VERSION="1.29.2"
AZTEC_CLI_URL="https://install.aztec.network"
DATA_DIR="$(pwd)/data"

# 函数：打印信息
print_info() {
  echo "$1"
}

# 函数：检查命令是否存在
check_command() {
  command -v "$1" &> /dev/null
}

# 函数：比较版本号
version_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# 函数：安装依赖
install_package() {
  local pkg=$1
  print_info "安装 $pkg..."
  apt-get install -y "$pkg"
}

# 更新 apt 源（只执行一次）
update_apt() {
  if [ -z "${APT_UPDATED:-}" ]; then
    print_info "更新 apt 源..."
    apt-get update
    APT_UPDATED=1
  fi
}

# 检查并安装 Docker
install_docker() {
  if check_command docker; then
    local version
    version=$(docker --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    if version_ge "$version" "$MIN_DOCKER_VERSION"; then
      print_info "Docker 已安装，版本 $version，满足要求（>= $MIN_DOCKER_VERSION）。"
      return
    else
      print_info "Docker 版本 $version 过低（要求 >= $MIN_DOCKER_VERSION），将重新安装..."
    fi
  else
    print_info "未找到 Docker，正在安装..."
  fi

  update_apt
  install_package "apt-transport-https ca-certificates curl gnupg-agent software-properties-common"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  update_apt
  install_package "docker-ce docker-ce-cli containerd.io"
}

# 检查并安装 Docker Compose
install_docker_compose() {
  if check_command docker-compose; then
    local version
    version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    if version_ge "$version" "$MIN_COMPOSE_VERSION"; then
      print_info "Docker Compose 已安装，版本 $version，满足要求（>= $MIN_COMPOSE_VERSION）。"
      return
    else
      print_info "Docker Compose 版本 $version 过低（要求 >= $MIN_COMPOSE_VERSION），将重新安装..."
    fi
  else
    print_info "未找到 Docker Compose，正在安装..."
  fi

  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
}

# 检查并安装 Node.js
install_nodejs() {
  if check_command node; then
    print_info "Node.js 已安装。"
    return
  fi

  print_info "未找到 Node.js，正在安装最新版本..."
  curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
  update_apt
  install_package nodejs
}

# 安装 Aztec CLI
install_aztec_cli() {
  print_info "安装 Aztec CLI 并准备 alpha 测试网..."
  if ! curl -sL "$AZTEC_CLI_URL" | bash; then
    echo "Aztec CLI 安装失败。"
    exit 1
  fi

  export PATH="$HOME/.aztec/bin:$PATH"
  if ! check_command aztec-up; then
    echo "Aztec CLI 安装失败，未找到 aztec-up 命令。"
    exit 1
  fi

  aztec-up alpha-testnet
}

# 验证 RPC URL 格式
validate_url() {
  local url=$1
  local name=$2
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "错误：$name 格式无效，必须以 http:// 或 https:// 开头。"
    exit 1
  fi
}

# 函数：从私钥推导以太坊地址
derive_address_from_private_key() {
  local private_key=$1
  if ! check_command aztec-cli; then
    echo "错误：未找到 aztec-cli，无法推导地址。请确保 Aztec CLI 已安装。"
    exit 1
  fi
  # 使用 aztec-cli 获取地址
  local address
  address=$(aztec-cli get-account --private-key "$private_key" 2>/dev/null | grep -oP '0x[a-fA-F0-9]{40}' || echo "")
  if [ -z "$address" ]; then
    echo "错误：无法从私钥推导地址。请检查私钥格式或 aztec-cli 功能。"
    exit 1
  fi
  echo "$address"
}

# 主逻辑
main() {
  # 安装依赖
  install_docker
  install_docker_compose
  install_nodejs
  install_aztec_cli

  # 获取用户输入
  print_info "获取 RPC URL 的说明："
  print_info "  - L1 执行客户端（EL）RPC URL："
  print_info "    1. 在 https://dashboard.alchemy.com/ 获取 Sepolia 的 RPC (http://xxx)"
  print_info ""
  print_info "  - L1 共识（CL）RPC URL："
  print_info "    1. 在 https://drpc.org/ 获取 Sepolia 的 RPC (http://xxx)"
  print_info ""

  read -p " L1 执行客户端（EL）RPC URL： " ETH_RPC
  read -p " L1 共识（CL）RPC URL： " CONS_RPC
  read -p " 验证者私钥（0x 开头）： " VALIDATOR_PRIVATE_KEY
  BLOB_URL="" # 默认跳过 Blob Sink URL

  # 验证输入
  validate_url "$ETH_RPC" "L1 执行客户端（EL）RPC URL"
  validate_url "$CONS_RPC" "L1 共识（CL）RPC URL"

  # 从私钥推导地址
  print_info "从私钥推导钱包地址..."
  COINBASE_ADDRESS=$(derive_address_from_private_key "$VALIDATOR_PRIVATE_KEY")
  print_info "    → 钱包地址：$COINBASE_ADDRESS"

  # 获取公共 IP
  print_info "获取公共 IP..."
  PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
  print_info "    → $PUBLIC_IP"

  # 创建数据目录
  mkdir -p "$DATA_DIR"

  # 启动 Aztec 节点
  print_info "启动 Aztec 全节点..."
  START_COMMAND="aztec start --node --archiver --sequencer \
    --network alpha-testnet \
    --l1-rpc-urls \"$ETH_RPC\" \
    --l1-consensus-host-urls \"$CONS_RPC\" \
    --sequencer.validatorPrivateKey \"$VALIDATOR_PRIVATE_KEY\" \
    --sequencer.coinbase \"$COINBASE_ADDRESS\" \
    --p2p.p2pIp \"$PUBLIC_IP\" \
    --data-directory \"$DATA_DIR\""

  if [ -n "$BLOB_URL" ]; then
    START_COMMAND="$START_COMMAND --sequencer.blobSinkUrl \"$BLOB_URL\""
  fi

  # 执行启动命令
  if ! eval "$START_COMMAND"; then
    echo "启动 Aztec 节点失败，请检查日志或命令输出。"
    exit 1
  fi

  # 完成
  print_info "安装和启动完成！"
  print_info "  - 数据目录：$DATA_DIR"
  print_info "  - 检查节点状态：请查看命令行输出或相关日志"
}

# 执行主逻辑
main
