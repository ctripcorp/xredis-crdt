MODULE_PATH=../crdt-module
XREDIS_PATH=../xredis-crdt
echo "[COMPILE START]"
make
cd $MODULE_PATH
make
cd $XREDIS_PATH
cp -f $MODULE_PATH/crdt.so ./
echo "[COMPILE END]"

echo "[BOOT START]"
echo "[info] starting master on 6379"
./src/redis-server --crdt-gid default 1 --loadmodule ./crdt.so --port 6379 --logfile master1.log --daemonize yes 
./src/redis-server --crdt-gid default 1 --loadmodule ./crdt.so --port 7379 --logfile slave1.log --daemonize yes 
echo "[info] starting peer on 6579"
./src/redis-server --crdt-gid default 2 --loadmodule ./crdt.so --port 6579 --logfile master2.log --daemonize yes 
./src/redis-server --crdt-gid default 2 --loadmodule ./crdt.so --port 7579 --logfile slave2.log --daemonize yes 

echo "[info] 6379 - PEEROF 6579"
./src/redis-cli -p 6379 peerof 2 127.0.0.1 6579
echo "[info] 6579 - PEEROF 6379"
./src/redis-cli -p 6579 peerof 1 127.0.0.1 6379

echo "[info] 7379 - SLAVEOF 6379"
./src/redis-cli -p 7379 slaveof 127.0.0.1 6379
echo "[info] 7579 - SLAVEOF 6579"
./src/redis-cli -p 7579 slaveof 127.0.0.1 6579

echo "[info] 6379 - CONFIG.SET repl-diskless-sync-delay=1"
./src/redis-cli -p 6379 config crdt.set repl-diskless-sync-delay 1
echo "[info] 6579 - CONFIG.SET repl-diskless-sync-delay=1"
./src/redis-cli -p 6579 config crdt.set repl-diskless-sync-delay 1
sleep 3
echo "[BOOT END]"
