# 函数：从私钥推导以太坊地址（简单实现）
derive_address_from_private_key() {
  local private_key=$1
  if ! check_command aztec-cli; then
    echo "错误：未找到 aztec-cli，无法推导地址。请确保 Aztec CLI 已安装。"
    exit 1
  fi
  # 使用 aztec-cli 获取地址（假设 aztec-cli 有相关命令）
  local address
  address=$(aztec-cli get-account --private-key "$private_key" 2>/dev/null | grep -oP '0x[a-fA-F0-9]{40}' || echo "")
  if [ -z "$address" ]; then
    echo "错误：无法从私钥推导地址。请检查私钥格式或 aztec-cli 功能。"
    exit 1
  fi
  echo "$address"
}

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
if [ -z "$VALIDATOR_PRIVATE_KEY" ] || [[ ! "$VALIDATOR_PRIVATE_KEY" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
  echo "错误：验证者私钥格式无效，必须是 0x 开头的 64 位十六进制字符串。"
  exit 1
fi

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
  --p2p.p2pIp \"$PUBLIC_IP\""

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
