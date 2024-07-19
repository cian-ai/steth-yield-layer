#!/bin/bash

source .env

RPC_FILE="scripts/data/addresses/"$CHAIN_ID"/rpc.json"
echo $RPC_FILE

FORK_RPC=$(jq -r '.FORK_RPC' $RPC_FILE)
# FORK_RPC="https://eth.llamarpc.com"
FORK_RPC="http://192.168.1.104:10005"
# echo $FORK_RPC

LOCAL_RPC_PORT=$(jq -r '.LOCAL_RPC_PORT' $RPC_FILE)
echo $LOCAL_RPC_PORT

RPC_URL=$FORK_RPC
DELAY_BLOCK_NUM=5

response=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id":0}' $RPC_URL)
hex_value=$(echo $response | awk -F'"' '{for (i=1; i<=NF; i++) if ($i == "result") {print $(i+2); exit}}')
current_block=$(( $hex_value ))
fork_block_num=$(( $current_block - $DELAY_BLOCK_NUM ))
echo -e "\033[33mCurrent block number is: $current_block\033[0m"
echo -e "\033[33mFork    block number is: $fork_block_num\033[0m"

npx hardhat node --fork $RPC_URL --hostname 0.0.0.0 --port $LOCAL_RPC_PORT --fork-block-number $fork_block_num  --network hardhat
# npx hardhat node --fork $RPC_URL --hostname 0.0.0.0 --port $LOCAL_RPC_PORT --fork-block-number 20070796  --network hardhat
# anvil --fork-url $RPC_URL   --host 0.0.0.0 --port $LOCAL_RPC_PORT --fork-block-number $fork_block_num 