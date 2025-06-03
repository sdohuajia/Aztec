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
AZTEC_DIR="/root/aztec"
DATA_DIR="/root/.aztec/alpha-testnet/data"

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
  if check_command docker-compose || docker compose version &> /dev/null; then
    local version
    version=$(docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || docker compose version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    if version_ge "$version" "$MIN_COMPOSE_VERSION"; then
      print_info "Docker Compose 已安装，版本 $version，满足要求（>= $MIN_COMPOSE_VERSION）。"
      return
    else
      print_info "Docker Compose 版本 $version 过低（要求 >= $MIN_COMPOSE_VERSION），将重新安装..."
    fi
  else
    print_info "未找到 Docker Compose，正在安装..."
  fi
  update_apt
  install_package docker-compose-plugin
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

# 验证 RPC URL 格式（检查是否以 http:// 或 https:// 开头）
validate_url() {
  local url=$1
  local name=$2
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "错误：$name 格式无效，必须以 http:// 或 https:// 开头。"
    exit 1
  fi
}

# 验证以太坊地址格式
validate_address() {
  local address=$1
  local name=$2
  if [[ ! "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "错误：$name 格式无效，必须是有效的以太坊地址（0x 开头的 40 位十六进制）。"
    exit 1
  fi
}

# 主逻辑：安装和启动 Aztec 节点
install_and_start_node() {
  # 清理旧配置
  print_info "清理旧的 Aztec 配置（如果存在）..."
  rm -rf "$AZTEC_DIR/.env" "$AZTEC_DIR/docker-compose.yml"
  docker stop aztec-sequencer 2>/dev/null || true
  docker rm aztec-sequencer 2>/dev/null || true

  # 安装依赖
  install_docker
  install_docker_compose
  install_nodejs
  install_aztec_cli

  # 创建 Aztec 配置目录
  print_info "创建 Aztec 配置目录 $AZTEC_DIR..."
  mkdir -p "$AZTEC_DIR"
  chmod -R 755 "$AZTEC_DIR"

  # 配置防火墙
  print_info "配置防火墙，开放端口 40400 和 8080..."
  ufw allow 40400/tcp >/dev/null 2>&1
  ufw allow 40400/udp >/dev/null 2>&1
  ufw allow 8080/tcp >/dev/null 2>&1
  print_info "防火墙状态："
  ufw status

  # 获取用户输入
  print_info "获取 RPC URL 和其他配置的说明："
  print_info "  - L1 执行客户端（EL）RPC URL："
  print_info "    1. 在 https://dashboard.alchemy.com/ 获取 Sepolia 的 RPC (http://xxx)"
  print_info ""
  print_info "  - L1 共识（CL）RPC URL："
  print_info "    1. 在 https://drpc.org/ 获取 Beacon Chain Sepolia 的 RPC (http://xxx)"
  print_info ""
  print_info "  - COINBASE：接收奖励的以太坊地址（格式：0x...）"
  print_info ""
  read -p " L1 执行客户端（EL）RPC URL： " ETH_RPC
  read -p " L1 共识（CL）RPC URL： " CONS_RPC
  read -p " 验证者私钥（0x 开头的 64 位十六进制）： " VALIDATOR_PRIVATE_KEY
  read -p " EVM钱包 地址（以太坊地址，0x 开头）： " COINBASE
  BLOB_URL="" # 默认跳过 Blob Sink URL

  # 验证输入
  validate_url "$ETH_RPC" "L1 执行客户端（EL）RPC URL"
  validate_url "$CONS_RPC" "L1 共识（CL）RPC URL"
  if [ -z "$VALIDATOR_PRIVATE_KEY" ]; then
    echo "错误：验证者私钥不能为空。"
    exit 1
  fi
  validate_address "$COINBASE" "COINBASE 地址"

  # 获取公共 IP
  print_info "获取公共 IP..."
  PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
  print_info "    → $PUBLIC_IP"

  # 生成 .env 文件
  print_info "生成 $AZTEC_DIR/.env 文件..."
  cat > "$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS="$ETH_RPC"
L1_CONSENSUS_HOST_URLS="$CONS_RPC"
P2P_IP="$PUBLIC_IP"
VALIDATOR_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
COINBASE="$COINBASE"
DATA_DIRECTORY="/data"
LOG_LEVEL="debug"
EOF
  if [ -n "$BLOB_URL" ]; then
    echo "BLOB_SINK_URL=\"$BLOB_URL\"" >> "$AZTEC_DIR/.env"
  fi
  chmod 600 "$AZTEC_DIR/.env"

  # 设置 BLOB_FLAG
  BLOB_FLAG=""
  if [ -n "$BLOB_URL" ]; then
    BLOB_FLAG="--sequencer.blobSinkUrl \$BLOB_SINK_URL"
  fi

  # 生成 docker-compose.yml 文件
  print_info "生成 $AZTEC_DIR/docker-compose.yml 文件..."
  cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-sequencer:
    container_name: aztec-sequencer
    network_mode: host
    image: aztecprotocol/aztec:0.87.2
    restart: unless-stopped
    environment:
      - ETHEREUM_HOSTS=\${ETHEREUM_HOSTS}
      - L1_CONSENSUS_HOST_URLS=\${L1_CONSENSUS_HOST_URLS}
      - P2P_IP=\${P2P_IP}
      - VALIDATOR_PRIVATE_KEY=\${VALIDATOR_PRIVATE_KEY}
      - COINBASE=\${COINBASE}
      - DATA_DIRECTORY=\${DATA_DIRECTORY}
      - LOG_LEVEL=\${LOG_LEVEL}
      - BLOB_SINK_URL=\${BLOB_SINK_URL:-}
    entrypoint: >
      sh -c "node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer \${BLOB_FLAG:-}"
    volumes:
      - /root/.aztec/alpha-testnet/data/:/data
EOF
  chmod 644 "$AZTEC_DIR/docker-compose.yml"

  # 创建数据目录
  print_info "创建数据目录 $DATA_DIR..."
  mkdir -p "$DATA_DIR"
  chmod -R 755 "$DATA_DIR"

  # 启动节点
  print_info "启动 Aztec 全节点 (尝试 docker compose up -d)..."
  cd "$AZTEC_DIR"
  if ! docker compose up -d; then
    print_info "docker compose 失败，尝试 docker-compose up -d..."
    if ! command -v docker-compose >/dev/null 2>&1; then
      echo "docker-compose 未安装。请安装 docker-compose 或确保 Docker Compose V2 可用。"
      exit 1
    fi
    if ! docker-compose up -d; then
      echo "启动 Aztec 节点失败，请检查 docker logs -f aztec-sequencer。"
      exit 1
    fi
  fi
  # 完成
  print_info "安装和启动完成！"
  print_info "  - 查看日志：docker logs -f aztec-sequencer"
  print_info "  - 配置目录：$AZTEC_DIR"
  print_info "  - 数据目录：$DATA_DIR"
}

# 获取区块高度和同步证明
get_block_and_proof() {
  if ! check_command jq; then
    print_info "未找到 jq，正在安装..."
    update_apt
    if ! install_package jq; then
      print_info "错误：无法安装 jq，请检查网络或 apt 源。"
      echo "按任意键返回主菜单..."
      read -n 1
      return
    fi
  fi

  if [ -f "$AZTEC_DIR/docker-compose.yml" ]; then
    # 检查容器是否运行
    if ! docker ps -q -f name=aztec-sequencer | grep -q .; then
      print_info "错误：容器 aztec-sequencer 未运行，请先启动节点。"
      echo "按任意键返回主菜单..."
      read -n 1
      return
    fi

    print_info "获取当前区块高度..."
    BLOCK_NUMBER=$(curl -s -X POST -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
      http://localhost:8080 | jq -r ".result.proven.number" || echo "")

    if [ -z "$BLOCK_NUMBER" ] || [ "$BLOCK_NUMBER" = "null" ]; then
      print_info "错误：无法获取区块高度（请等待半个小时后再查询），请确保节点正在运行并检查日志（docker logs -f aztec-sequencer）。"
      echo "按任意键返回主菜单..."
      read -n 1
      return
    fi

    print_info "当前区块高度：$BLOCK_NUMBER"
    print_info "获取同步证明..."
    PROOF=$(curl -s -X POST -H 'Content-Type: application/json' \
      -d "$(jq -n --arg bn "$BLOCK_NUMBER" '{"jsonrpc":"2.0","method":"node_getArchiveSiblingPath","params":[$bn,$bn],"id":67}')" \
      http://localhost:8080 | jq -r ".result" || echo "")

    if [ -z "$PROOF" ] || [ "$PROOF" = "null" ]; then
      print_info "错误：无法获取同步证明，请确保节点正在运行并检查日志（docker logs -f aztec-sequencer）。"
    else
      print_info "同步一次证明：$PROOF"
    fi
  else
    print_info "错误：未找到 $AZTEC_DIR/docker-compose.yml 文件，请先安装并启动节点。"
  fi

  echo "按任意键返回主菜单..."
  read -n 1
}

# 主菜单函数
main_menu() {
  while true; do
    clear
    echo "脚本由哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
    echo "如有问题，可联系推特，仅此只有一个号"
    echo "================================================================"
    echo "退出脚本，请按键盘 ctrl + C 退出即可"
    echo "请选择要执行的操作:"
    echo "1. 安装并启动 Aztec 节点"
    echo "2. 查看节点日志"
    echo "3. 获取区块高度和同步证明（请等待半个小时后再查询）"
    echo "4. 退出"
    read -p "请输入选项 (1-4): " choice

    case $choice in
      1)
        install_and_start_node
        echo "按任意键返回主菜单..."
        read -n 1
        ;;
      2)
        if [ -f "$AZTEC_DIR/docker-compose.yml" ]; then
          print_info "查看节点日志..."
          docker logs -f aztec-sequencer
        else
          print_info "错误：未找到 $AZTEC_DIR/docker-compose.yml 文件，请先安装并启动节点。"
        fi
        echo "按任意键返回主菜单..."
        read -n 1
        ;;
      3)
        get_block_and_proof
        ;;
      4)
        print_info "退出脚本..."
        exit 0
        ;;
      *)
        print_info "无效选项，请输入 1-4。"
        echo "按任意键返回主菜单..."
        read -n 1
        ;;
    esac
  done
}

# 执行主菜单
main_menu
