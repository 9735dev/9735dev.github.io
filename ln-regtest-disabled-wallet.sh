#!/bin/bash
# note: you need to stop all bitcoin and lightning node processes from previous runs of this script before running this script again

# variables that need to be changed based on your installation, BN=bitcoin node, LN=lightning node
# executables
BITCOIN_QT="$HOME/Desktop/bitcoin/src/qt/bitcoin-qt"
BITCOIN_CLI="$HOME/Desktop/bitcoin/src/bitcoin-cli"
LIGHTNINGD="$HOME/Desktop/lightning/lightningd/lightningd"
LIGHTNING_CLI="$HOME/Desktop/lightning/cli/lightning-cli"
# node directories
BN1="/tmp/bn1"
BN_MINER="/tmp/bn_miner"
LN1="/tmp/ln1"
LN2="/tmp/ln2"
LN3="/tmp/ln3"

# wipe and create the node directories
rm -rf $BN1 $BN_MINER $LN1 $LN2 $LN3
mkdir -p $BN1 $BN_MINER $LN1 $LN2 $LN3

# start the bitcoin nodes
$BITCOIN_QT -regtest -datadir=$BN_MINER -txindex -listen -server -rpcallowip=127.0.0.1 -rpcbind=127.0.0.1:18445 &
$BITCOIN_QT -regtest -datadir=$BN1 -txindex -server -connect=127.0.0.1 -disablewallet &
# generate enough blocks so that the mining node has some mature coins to use
$BITCOIN_CLI -regtest -datadir=$BN_MINER -rpcwait -rpcport=18445 generate 101 > /dev/null 2>&1

# start the lightning nodes
$LIGHTNINGD --network=regtest --daemon --port=9735 --lightning-dir=$LN1 --bitcoin-datadir=$BN1 --log-file=log.txt --log-level=debug --bitcoin-cli=$BITCOIN_CLI --bitcoind-poll=1s
$LIGHTNINGD --network=regtest --daemon --port=9736 --lightning-dir=$LN2 --bitcoin-datadir=$BN1 --log-file=log.txt --log-level=debug --bitcoin-cli=$BITCOIN_CLI --bitcoind-poll=1s
$LIGHTNINGD --network=regtest --daemon --port=9737 --lightning-dir=$LN3 --bitcoin-datadir=$BN1 --log-file=log.txt --log-level=debug --bitcoin-cli=$BITCOIN_CLI --bitcoind-poll=1s

# give the lightning nodes some coins
LN1_DEPOSIT_ADDR=$($LIGHTNING_CLI --lightning-dir=$LN1 newaddr | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["address"]);');
LN2_DEPOSIT_ADDR=$($LIGHTNING_CLI --lightning-dir=$LN2 newaddr | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["address"]);');
LN3_DEPOSIT_ADDR=$($LIGHTNING_CLI --lightning-dir=$LN3 newaddr | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["address"]);');
$BITCOIN_CLI -regtest -datadir=$BN_MINER -rpcport=18445 sendmany '' "{\"$LN1_DEPOSIT_ADDR\":1, \"$LN2_DEPOSIT_ADDR\":1, \"$LN3_DEPOSIT_ADDR\":1}" > /dev/null 2>&1
$BITCOIN_CLI -regtest -datadir=$BN_MINER -rpcport=18445 generate 6 > /dev/null 2>&1
while [ $($BITCOIN_CLI -regtest -datadir=$BN1 getblockcount) != "107" ]; do sleep 1; done # pause to wait for the non-mining bitcoin node to process the new blocks
sleep 3 # pause to let the lightning nodes catch up

# show some info that is useful for running ad-hoc commands
LN1_NODE_ID=$($LIGHTNING_CLI --lightning-dir=$LN1 getinfo | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["id"]);')
LN2_NODE_ID=$($LIGHTNING_CLI --lightning-dir=$LN2 getinfo | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["id"]);')
LN3_NODE_ID=$($LIGHTNING_CLI --lightning-dir=$LN3 getinfo | /usr/bin/env python3 -c 'import json, sys; data=json.load(sys.stdin); print(data["id"]);')

$LIGHTNING_CLI --lightning-dir=$LN1 getinfo
$LIGHTNING_CLI --lightning-dir=$LN2 getinfo
$LIGHTNING_CLI --lightning-dir=$LN3 getinfo

# form a small network between the lightning nodes
$LIGHTNING_CLI --lightning-dir=$LN1 connect $LN2_NODE_ID 127.0.0.1 9736 > /dev/null 2>&1
$LIGHTNING_CLI --lightning-dir=$LN1 fundchannel $LN2_NODE_ID 16777215 > /dev/null 2>&1

$LIGHTNING_CLI --lightning-dir=$LN1 connect $LN3_NODE_ID 127.0.0.1 9737 > /dev/null 2>&1
$LIGHTNING_CLI --lightning-dir=$LN1 fundchannel $LN3_NODE_ID 1000000 > /dev/null 2>&1

# get the new channels to normal state
sleep 3 # pause to let the transaction propagate to the mining node
$BITCOIN_CLI -regtest -datadir=$BN_MINER -rpcport=18445 generate 6 > /dev/null 2>&1
while [ $($BITCOIN_CLI -regtest -datadir=$BN1 getblockcount) != "113" ]; do sleep 1; done # pause to wait for the non-mining bitcoin node to process the new blocks
sleep 3 # pause to let the lightning nodes catch up

$LIGHTNING_CLI --lightning-dir=$LN1 listpeers
$LIGHTNING_CLI --lightning-dir=$LN2 listpeers
$LIGHTNING_CLI --lightning-dir=$LN3 listpeers

echo "Sample commands:"
echo "$LIGHTNING_CLI --lightning-dir=$LN1 getinfo"
echo "$BITCOIN_CLI -regtest -datadir=$BN_MINER -rpcport=18445 generate 6"

