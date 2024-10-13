#!/bin/bash
set -e

NETWORK="${NETWORK:-allora-testnet-1}"                 #! Replace with your network name
GENESIS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/genesis.json"
SEEDS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/seeds.txt"
PEERS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/peers.txt"
HEADS_URL="https://raw.githubusercontent.com/allora-network/networks/main/${NETWORK}/heads.txt"

export APP_HOME="${APP_HOME:-./data}"
INIT_FLAG="${APP_HOME}/.initialized"
MONIKER="${MONIKER:-$(hostname)}"
KEYRING_BACKEND=test                              #! Use test for simplicity, you should decide which backend to use !!!
GENESIS_FILE="${APP_HOME}/config/genesis.json"
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
    wget -O ${APP_HOME}/addrbook.json  https://server-3.itrocket.net/testnet/allora/addrbook.json
    # Update Mempool Configuration (16GB)
    sed -i 's|max_txs_bytes = .*|max_txs_bytes = 8589934592|' $CONFIG_FILE
    sed -i 's|size = .*|size = 100000|' $CONFIG_FILE
    sed -i 's|cache_size = .*|cache_size = 100000|' $CONFIG_FILE
    # Update RPC Configuration
    sed -i 's|max_open_connections = .*|max_open_connections = 5000|' $CONFIG_FILE
    sed -i 's|max_body_bytes = .*|max_body_bytes = 10000000|' $CONFIG_FILE
    sed -i 's|max_header_bytes = .*|max_header_bytes = 4194304|' $CONFIG_FILE
    sed -i 's|timeout_broadcast_tx_commit = .*|timeout_broadcast_tx_commit = "7s"|' $CONFIG_FILE
    
    sed -i 's|timeout_propose = .*|timeout_propose = "1s"|' $CONFIG_FILE
    sed -i 's|timeout_prevote = .*|timeout_prevote = "700ms"|' $CONFIG_FILE
    sed -i 's|timeout_precommit = .*|timeout_precommit = "700ms"|' $CONFIG_FILE

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
    sed -i 's|minimum-gas-prices = .*|minimum-gas-prices = "0.025ualo"|' $APP_FILE

    touch $INIT_FLAG
fi
echo "Node is initialized"

SEEDS=$(curl -Ls ${SEEDS_URL})
PEERS=$(curl -Ls ${PEERS_URL})
PEERS=$(curl -Ls ${PEERS_URL})

NEW_PEER="a8cde2de31410d896668e53446495a4a68c4c24f@allora-testnet-peer.itrocket.net:27656,5965f27e7d59d788aced79d099713c3fea1ceca1@157.90.209.40:26656,7d548f78f0c67d391279c36fa9e127c52ce8b14c@65.108.225.207:55656,18fbf5f16f73e216f93304d94e8b79bf5acd7578@15.204.101.152:26656,2eb9f5f80d721be2d37ab72c10a7be6aaf7897a4@15.204.101.92:26656,0f6b64fcd38872d18a78d89e090a5e6928883d52@8.209.116.116:26656,3a7eb1cdefc0dcbb79eb143837a17260ab88eb87@212.126.35.133:26664,c8f7c18f98ada342100c7bade62a28a244188951@204.29.146.8:26656,d3c79122924ff477e941ec0ca1ed775cfb01ca20@66.35.84.140:26656,9cca620ee99e7d733baee084fd7b54273d9d6bdb@35.228.18.126:26656,c416589304a02cd55509fcd5584f2ef2653144e2@116.202.116.35:29656"

PEERS="${PEERS},${NEW_PEER}"

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
        --minimum-gas-prices=0.025${DENOM} \
        --rpc.laddr=tcp://0.0.0.0:26657 \
        --p2p.seeds=$SEEDS \
        --p2p.persistent_peers=$PEERS
else
    echo "Starting validator node without cosmovisor"
    allorad \
        --home=${APP_HOME} \
        start \
        --moniker=${MONIKER} \
        --minimum-gas-prices=0.025${DENOM} \
        --rpc.laddr=tcp://0.0.0.0:26657 \
        --p2p.seeds=$SEEDS \
        --p2p.persistent_peers=$PEERS
fi
