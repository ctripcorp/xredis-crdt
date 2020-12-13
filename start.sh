

#only mac 
cp ./tests/assets/mac/crdt.so ./
./src/redis-server --crdt-gid default 1 --loadmodule ./crdt.so --port 6379 --logfile master.log --daemonize yes 
./src/redis-server --crdt-gid default 2 --loadmodule ./crdt.so --port 6579 --logfile peer.log --daemonize yes 
./src/redis-cli -p 6379 peerof 2 127.0.0.1 6579
./src/redis-cli -p 6579 peerof 1 127.0.0.1 6379
./src/redis-cli -p 6379 config crdt.set repl-diskless-sync-delay 1
./src/redis-cli -p 6579 config crdt.set repl-diskless-sync-delay 1
sleep 3
./src/redis-cli -p 6379 set k 100
sleep 1
./src/redis-cli -p 6579 get k 