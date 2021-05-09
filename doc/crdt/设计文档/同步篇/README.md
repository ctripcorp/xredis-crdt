State-based replication 的特性(commutative/idempotent/associate), 在网络不稳定需要全量同步时, 给我们带来了理论支持和方法论证的同时, 也带来了其他问题, 那就是Master与Master之间的数据传输是否可以只发送增量的状态变更, 从而达到节省网络流量加速同步时间的目的

### 实现原理
    + 上文已经出现的数据结构中, 均引入了vector clock的概念
    + 通讯协议 -- 公共协议篇也介绍了具体发送的协议, 数据发送方的 master 会收到 peer-master 的min-repl-vc
那么剩下的问题是, 如何将增量的数据从源 redis 导出:

    + redis fork出一个子进程, 基于 Linux 系统COW的特性, 子进行拥有父进程相同的内存空间
    + 在子进程中遍历 redis 的字典, 遇到 <vector_clock>比min-repl-vc大的节点, 就将 val 按照不同的类型压缩为RDB的格式
    + 子进程通过 CRDT.MERGE的命令, 将每一条增量RDB发送至 peer master 的 fd
    + 子进程通过 CRDT.MERGE_DEL 命令, 将每一条 Tombstone 压缩发送给 peer master
    + 最终, 子进程将对应这些结果的offset发送给 peer-master