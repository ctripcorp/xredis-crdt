

#only mac 
cp ./tests/assets/mac/crdt.so ./
./src/redis-server --crdt-gid default 1 --loadmodule ./crdt.so --port 7379 --logfile master.log --daemonize yes 
./src/redis-server --crdt-gid default 2 --loadmodule ./crdt.so --port 7579 --logfile peer.log --daemonize yes 
./src/redis-cli -p 7379 peerof 2 127.0.0.1 7579
./src/redis-cli -p 7579 peerof 1 127.0.0.1 7379
./src/redis-cli -p 7379 config crdt.set repl-diskless-sync-delay 1
./src/redis-cli -p 7579 config crdt.set repl-diskless-sync-delay 1
sleep 3
./src/redis-cli -p 7379 set k 100
sleep 1
./src/redis-cli -p 7579 get k 