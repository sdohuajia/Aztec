#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ 本脚本必须以 root 权限运行。"
  exit 1
fi

# 检查 Docker 是否安装及版本
MIN_DOCKER_VERSION="20.10"
if command -v docker &> /dev/null; then
  DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
  if [ "$(printf '%s\n' "$DOCKER_VERSION" "$MIN_DOCKER_VERSION" | sort -V | head -n1)" = "$MIN_DOCKER_VERSION" ]; then
    echo "🐋 Docker 已安装，版本 $DOCKER_VERSION，满足要求。"
  else
    echo "🐋 Docker 版本 $DOCKER_VERSION 过低（要求 >= $MIN_DOCKER_VERSION），将重新安装..."
    DOCKER_INSTALL=true
  fi
else
  echo "🐋 未找到 Docker，正在安装..."
  DOCKER_INSTALL=true
fi

# 如果需要安装 Docker
if [ "${DOCKER_INSTALL:-false}" = true ]; then
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# 检查 Docker Compose 是否安装及版本
MIN_COMPOSE_VERSION="1.29.2"
if command -v docker-compose &> /dev/null; then
  COMPOSE_VERSION=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
  if [ "$(printf '%s\n' "$COMPOSE_VERSION" "$MIN_COMPOSE_VERSION" | sort -V | head -n1)" = "$MIN_COMPOSE_VERSION" ]; then
    echo "🐋 Docker Compose 已安装，版本 $COMPOSE_VERSION，满足要求。"
  else
    echo "🐋 Docker Compose 版本 $COMPOSE_VERSION 过低（要求 >= $MIN_COMPOSE_VERSION），将重新安装..."
    COMPOSE_INSTALL=true
  fi
else
  echo "🐋 未找到 Docker Compose，正在安装..."
  COMPOSE_INSTALL=true
fi

# 如果需要安装 Docker Compose
if [ "${COMPOSE_INSTALL:-false}" = true ]; then
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

if ! command -v node &> /dev/null; then
  echo "🟢 未找到 Node.js，正在安装最新版本..."
  curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
  apt-get install -y nodejs
else
  echo "🟢 Node.js 已安装。"
fi

echo "⚙️ 安装 Aztec CLI 并准备 alpha 测试网..."
curl -sL https://install.aztec.network | bash

export PATH="$HOME/.aztec/bin:$PATH"

if ! command -v aztec-up &> /dev/null; then
  echo "❌ Aztec CLI 安装失败。"
  exit 1
fi

aztec-up alpha-testnet

echo -e "\n📋 获取 RPC URL 的说明："
echo "  - L1 执行客户端（EL）RPC URL："
echo "    1. 在 https://dashboard.alchemy.com/ 注册或登录"
echo "    2. 为 Sepolia 测试网创建一个新应用"
echo "    3. 复制 HTTPS URL（例如：https://eth-sepolia.g.alchemy.com/v2/<你的密钥>）"
echo ""
echo "  - L1 共识（CL）RPC URL："
echo "    1. 在 https://drpc.org/ 注册或登录"
echo "    2. 为 Sepolia 测试网创建一个 API 密钥"
echo "    3. 复制 HTTPS URL（例如：https://lb.drpc.org/ogrpc?network=sepolia&dkey=<你的密钥>）"
echo ""

read -p "▶️ L1 执行客户端（EL）RPC URL： " ETH_RPC
read -p "▶️ L1 共识（CL）RPC URL： " CONS_RPC
read -p "▶️ Blob Sink URL（无则按 Enter）： " BLOB_URL
read -p "▶️ 验证者私钥： " VALIDATOR_PRIVATE_KEY

echo "🌐 获取公共 IP..."
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
echo "    → $PUBLIC_IP"

cat > .env <<EOF
ETHEREUM_HOSTS="$ETH_RPC"
L1_CONSENSUS_HOST_URLS="$CONS_RPC"
P2P_IP="$PUBLIC_IP"
VALIDATOR_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
DATA_DIRECTORY="/data"
LOG_LEVEL="debug"
EOF

if [ -n "$BLOB_URL" ]; then
  echo "BLOB_SINK_URL=\"$BLOB_URL\"" >> .env
fi

BLOB_FLAG=""
if [ -n "$BLOB_URL" ]; then
  BLOB_FLAG="--sequencer.blobSinkUrl \$BLOB_SINK_URL"
fi

cat > docker-compose.yml <<EOF
version: "3.8"
services:
  node:
    image: aztecprotocol/aztec:0.85.0-alpha-testnet.5
    network_mode: host
    environment:
      - ETHEREUM_HOSTS=\${ETHEREUM_HOSTS}
      - L1_CONSENSUS_HOST_URLS=\${L1_CONSENSUS_HOST_URLS}
      - P2P_IP=\${P2P_IP}
      - VALIDATOR_PRIVATE_KEY=\${VALIDATOR_PRIVATE_KEY}
      - DATA_DIRECTORY=\${DATA_DIRECTORY}
      - LOG_LEVEL=\${LOG_LEVEL}
      - BLOB_SINK_URL=\${BLOB_SINK_URL:-}
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer $BLOB_FLAG'
    volumes:
      - $(pwd)/data:/data
EOF

mkdir -p data

echo "🚀 启动 Aztec 全节点 (docker-compose up -d)..."
docker-compose up -d

echo -e "\n✅ 安装和启动完成！"
echo "   - 查看日志：docker-compose logs -f"
echo "   - 数据目录：$(pwd)/data"
