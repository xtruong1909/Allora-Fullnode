#!/bin/bash
set -e

NETWORK="${NETWORK:-allora-testnet-1}"                 #! Replace with your network name
GENESIS_URL="https://raw.githubusercontent.com/allora-network/networks/main/allora-testnet-1/genesis.json"
SEEDS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/seeds.txt"
PEERS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/peers.txt"
HEADS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/heads.txt"
ADDRESS_URL="https://snapshots.polkachu.com/testnet-addrbook/allora/addrbook.json"

export APP_HOME="${APP_HOME:-./data}"
INIT_FLAG="${APP_HOME}/.initialized"
MONIKER="${MONIKER:-$(hostname)}"
KEYRING_BACKEND=test                              #! Use test for simplicity, you should decide which backend to use !!!
GENESIS_FILE="${APP_HOME}/config/genesis.json"
ADDRESS_FILE="${APP_HOME}/config/addrbook.json"

DENOM="uallo"
RPC_PORT="${RPC_PORT:-26657}"

if [ "$RESTORE_S3_SNAPSHOT" == "true" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "${SCRIPT_DIR}/restore_snapshot.sh"
fi

BINARY=""
if [ "$UPGRADE" == "true" ]; then
    echo "You have set upgrade to true, please make sure you are running the correct docker image (vx.x.x-upgrader)"
    BINARY=/cosmovisor/genesis/bin/allorad
else
    BINARY=allorad
fi

echo "To re-initiate the node, remove the file: ${INIT_FLAG}"
if [ ! -f $INIT_FLAG ]; then
    #* Remove if existing config
    rm -rf ${APP_HOME}/config

    #* Create symlink for allorad config - workaround
    ln -sf ${APP_HOME} ${HOME}/.allorad

    #* Init node
    $BINARY --home=${APP_HOME} init ${MONIKER} --chain-id=${NETWORK} --default-denom $DENOM
    #* Download genesis
    rm -f $GENESIS_FILE
    rm -f $ADDRESS_FILE
    curl -Lo $ADDRESS_FILE $ADDRESS_URL
    curl -Lo $GENESIS_FILE $GENESIS_URL
    #* Import allora account, priv_validator_key.json and node_key.json from the vault here
    #* Here create a new allorad account
    $BINARY --home $APP_HOME keys add ${MONIKER} --keyring-backend $KEYRING_BACKEND > $APP_HOME/${MONIKER}.account_info 2>&1

    #* Adjust configs
    #* Enable prometheus metrics
    #dasel put -t bool -v true 'instrumentation.prometheus' -f ${APP_HOME}/config/config.toml

    #* Setup allorad client
    $BINARY  --home=${APP_HOME} config set client chain-id ${NETWORK}
    $BINARY  --home=${APP_HOME} config set client keyring-backend $KEYRING_BACKEND

    export APP_HOME="${APP_HOME:-./data}"
    CONFIG_FILE="${APP_HOME}/config/config.toml"
    APP_FILE="${APP_HOME}/config/app.toml"
    # Update Mempool Configuration (16GB)
    sed -i 's|chunk_fetchers = .*|chunk_fetchers = "10"|' $CONFIG_FILE
    sed -i 's|max_txs_bytes = .*|max_txs_bytes = 8589934592|' $CONFIG_FILE
    sed -i 's|size = .*|size = 500000|' $CONFIG_FILE
    sed -i 's|cache_size = .*|cache_size = 500000|' $CONFIG_FILE
    
    # Update RPC Configuration
    sed -i 's|max_open_connections = .*|max_open_connections = 0|' $CONFIG_FILE
    sed -i 's|max_request_batch_size = .*|max_request_batch_size = 50000|' $CONFIG_FILE
    sed -i 's|max_subscription_clients = .*|max_subscription_clients = 20000|' $CONFIG_FILE
    sed -i 's|max_subscriptions_per_client = .*|max_subscriptions_per_client = 1000|' $CONFIG_FILE

    sed -i 's|max_body_bytes = .*|max_body_bytes = 20000000|' $CONFIG_FILE
    sed -i 's|max_header_bytes = .*|max_header_bytes = 8388608|' $CONFIG_FILE
    sed -i 's|timeout_broadcast_tx_commit = .*|timeout_broadcast_tx_commit = "15s"|' $CONFIG_FILE
    
    sed -i 's|timeout_propose = .*|timeout_propose = "2s"|' $CONFIG_FILE
    sed -i 's|timeout_prevote = .*|timeout_prevote = "800ms"|' $CONFIG_FILE
    sed -i 's|timeout_precommit = .*|timeout_precommit = "800ms"|' $CONFIG_FILE

    # Update Pruning Configuration
    sed -i 's|pruning = .*|pruning = "custom"|' $APP_FILE
    sed -i 's|pruning-keep-recent = .*|pruning-keep-recent = "1000"|' $APP_FILE
    sed -i 's|pruning-keep-every = .*|pruning-keep-every = "0"|' $APP_FILE
    sed -i 's|pruning-interval = .*|pruning-interval = "10"|' $APP_FILE
    
    # Increase the P2P Settings for Better Network Performance
    sed -i 's|max_num_inbound_peers = .*|max_num_inbound_peers = 200|' $CONFIG_FILE
    sed -i 's|max_num_outbound_peers = .*|max_num_outbound_peers = 80|' $CONFIG_FILE
    sed -i 's|recv_rate = .*|recv_rate = 5120000|' $CONFIG_FILE
    sed -i 's|send_rate = .*|send_rate = 5120000|' $CONFIG_FILE
    sed -i 's|flush_throttle_timeout = .*|flush_throttle_timeout = "50ms"|' $CONFIG_FILE
    
    # Adjust the State Sync and Fast Sync Settings
    sed -i 's|fast_sync = .*|fast_sync = true|' $CONFIG_FILE
    sed -i 's|snapshot_interval = .*|snapshot_interval = 1000|' $CONFIG_FILE
    sed -i 's|snapshot_keep_recent = .*|snapshot_keep_recent = 5|' $CONFIG_FILE
    
    # Update app.toml Configuration
    sed -i 's|max-txs = .*|max-txs = 0|' $APP_FILE
    sed -i 's|telemetry.enabled = .*|telemetry.enabled = true|' $APP_FILE


    touch $INIT_FLAG
fi
echo "Node is initialized"

SEEDS="2eb9f5f80d721be2d37ab72c10a7be6aaf7897a4@seed-1.testnet.allora.network:26656,18fbf5f16f73e216f93304d94e8b79bf5acd7578@seed-2.testnet.allora.network:26656"
PEERS="2bd135ae4cc0362ac2b62891947f4edf1be45edb@peer-1.testnet.allora.network:26656,b91e41cf5340d418969f25702de42ba31b381710@peer-2.testnet.allora.network:26656,eef95b887114cda87fc6c7cbb6dfaa0937259878@peer-3.testnet.allora.network:26656"

NEW_PEER="23f24d0a6e80e07ecd9c89aba5896ddea5307bec@213.136.72.4:26656,a8cde2de31410d896668e53446495a4a68c4c24f@allora-testnet-peer.itrocket.net:27656,a8cde2de31410d896668e53446495a4a68c4c24f@allora-testnet-peer.itrocket.net:27656,18fbf5f16f73e216f93304d94e8b79bf5acd7578@15.204.101.152:26656,be2f87102b8bd5bdfed8b8e1fff5bde5b481de62@65.108.130.39:47656,7d548f78f0c67d391279c36fa9e127c52ce8b14c@65.108.225.207:55656,08da0acdc31a11bd1be662a68afd8f2fa35e9c31@157.90.181.126:10656,2fe343c9ff90b609990d5b5869a7f73ab7372b30@211.219.19.69:26656,3eb7d079c74d22e6ac8402cb77a55f7cb90a8815@15.204.46.178:26656,d3c79122924ff477e941ec0ca1ed775cfb01ca20@66.35.84.140:26656,9cca620ee99e7d733baee084fd7b54273d9d6bdb@35.228.18.126:26656,2eb9f5f80d721be2d37ab72c10a7be6aaf7897a4@15.204.101.92:26656"
NEW_SEEDS="720d83b52611c64d119adfc4d08d2e85885d8c74@allora-testnet-seed.itrocket.net:27656,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@testnet-seeds.polkachu.com:26756,ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@testnet-seeds.polkachu.com:26756"

PEERS="${PEERS},${NEW_PEER}"
SEEDS="${SEEDS},${NEW_SEEDS}"

if [ "x${STATE_SYNC_RPC1}" != "x" ]; then
    echo "Enable state sync"
    TRUST_HEIGHT=$(($(curl -s $STATE_SYNC_RPC1/block | jq -r '.result.block.header.height')))

    #* Snapshots are taken every 1000 blocks so we need to round down to the nearest 1000
    TRUST_HEIGHT=$(($TRUST_HEIGHT - ($TRUST_HEIGHT % 1000)))

    curl -s "$STATE_SYNC_RPC1/block?height=$TRUST_HEIGHT"

    TRUST_HEIGHT_HASH=$(curl -s $STATE_SYNC_RPC1/block?height=$TRUST_HEIGHT | jq -r '.result.block_id.hash')

    echo "Trust height: $TRUST_HEIGHT $TRUST_HEIGHT_HASH"

    dasel put statesync.enable -t bool -v true -f ${APP_HOME}/config/config.toml
    dasel put statesync.rpc_servers -t string -v "$STATE_SYNC_RPC1,$STATE_SYNC_RPC2" -f ${APP_HOME}/config/config.toml
    dasel put statesync.trust_height -t string -v $TRUST_HEIGHT -f ${APP_HOME}/config/config.toml
    dasel put statesync.trust_hash -t string -v $TRUST_HEIGHT_HASH -f ${APP_HOME}/config/config.toml
fi

if [ "$UPGRADE" == "true" ]; then
    if [ ! -d "/data/cosmovisor" ]; then
        echo "initialize cosmovisor"
        cp -R /cosmovisor /data/
        cosmovisor init /data/cosmovisor/genesis/bin/allorad
    fi

    echo "Starting validator node with cosmovisor"
    cosmovisor \
        run \
        --home=${APP_HOME} \
        start \
        --moniker=${MONIKER} \
        --minimum-gas-prices=0${DENOM} \
        --rpc.laddr=tcp://0.0.0.0:26657 \
        --p2p.seeds=$SEEDS \
        --p2p.persistent_peers=$PEERS
else
    echo "Starting validator node without cosmovisor"
    allorad \
        --home=${APP_HOME} \
        start \
        --moniker=${MONIKER} \
        --minimum-gas-prices=0${DENOM} \
        --rpc.laddr=tcp://0.0.0.0:26657 \
        --p2p.seeds=$SEEDS \
        --p2p.persistent_peers=$PEERS
fi
