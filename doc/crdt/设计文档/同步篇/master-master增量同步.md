Master-Master增量同步
对于Master-Slave架构与Master-Master架构增量同步的设计, 不同站点的Slave接收的内容完全一样, 都是源 master 站点在 effect 阶段广播的内容

这里, master 和 slave 之间同步的通讯协议并没有发生变化, 只是数据的内容发生了变化

原有的架构:

Master 收到客户端的 SET KEY VAL, 执行完毕, 并且把同样的命令发送给所有的 Slave

* 目前的变更:
    + 源Master收到客户端的 SET KEY VAL, 执行完毕, 进入 prepare 阶段, 将操作转译为 rupdate <gid> <key> <vector_clock> <timestamp> <val> 0
    + 源Master将相同的EFFECT发送给所有 slave 和 peer-master
    + peer-master 收到源 master 的EFFECT操作后, 同步给自己的slave, slave 执行同样的操作 