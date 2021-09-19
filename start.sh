echo "[COMPILE START]"
make
cd crdt-module
make
cd ..
cp -f crdt-module/crdt.so ./
echo "[COMPILE END]"

echo "[BOOT START]"
echo "[info] starting master on 6379"
./src/redis-server --crdt-gid default 1 --loadmodule ./crdt.so --port 6379 --logfile master.log --daemonize yes 
echo "[info] starting peer on 6579"
./src/redis-server --crdt-gid default 2 --loadmodule ./crdt.so --port 6579 --logfile peer.log --daemonize yes 

echo "[info] 6379 - PEEROF 6579"
./src/redis-cli -p 6379 peerof 2 127.0.0.1 6579
echo "[info] 6579 - PEEROF 6379"
./src/redis-cli -p 6579 peerof 1 127.0.0.1 6379

echo "[info] 6379 - CONFIG.SET repl-diskless-sync-delay=1"
./src/redis-cli -p 6379 config crdt.set repl-diskless-sync-delay 1
echo "[info] 6579 - CONFIG.SET repl-diskless-sync-delay=1"
./src/redis-cli -p 6579 config crdt.set repl-diskless-sync-delay 1
sleep 3
echo "[BOOT END]"
