
## STRING 类型

#### 支持 API

| Redis API | 目前进度    |
| :-------- | :---------- |
| set       | **DONE**    |
| get       | **DONE**    |
| getSet    | **PENDING** |
| setex     | **DONE**    |
| mset      | **DONE**    |
| mget      | **DONE**E   |

#### CRDT

> 先来讲一下, CRDT理论中, 如何处理Redis String 类型的同步问题

Redis的String类型对应于CRDT里面的`Register`数据结构, 对应的具体实现有两种比较符合我们的应用场景:

`MV(Multi-Value) Register`: 数据保留多份副本, 客户端执行`GET`操作时, 根据一定的规则返回值, 这种类型比较适合 `INCRBY` 的整型数操作

`LWW(Last-Write-Wins) Register`: 数据只保留一份副本, 以时间戳最大的那组数据为准, `SET`操作中, 我们使用这种类型.



#### CRDT API

| CRDT API     | 目前进度 | API 使用场景                                               |
| :----------- | :------- | :--------------------------------------------------------- |
| CRDT.SET     | **DONE** | 发送 K/V 相关的写入操作                                    |
| CRDT.GET     | **DONE** | debug 使用, 可以获得一个 key 的 vclock 和 timestamp 等细节 |
| CRDT.DEL_REG | **DONE** | 发送 K/V 类型的 delete 操作                                |

#### STRING 的数据结构

以下是理论上的数据结构, 并不是 redis 中真正的结构体, 仅仅作为说明使用



```
struct` `CRDT.Register {``    ``string key;``    ``string val;``    ``int` `gid;``    ``int` `timestamp;``    ``CRDT_VectorClock vector_clock;``}
```

1. key 既是SET操作中的 key
2. val 用来存储相应的 value
3. timestamp 用于LWW(Last Write Wins)机制, 来解决并发冲突
4. vector_clock 的用于记录这个操作产生时, 对应的 vector clock

#### SET操作 – Op-Based Replication

1. prepare 阶段
   将 `SET <key> <val>`的形式, 转化为 `CRDT.SET <key> <val> <gid> <timestamp> <vector-clock> <expire-timestamp>`
   举个栗子

   `SET key val` ==>
   `CRDT.SET key 1,23;2,32 1553148256336368208 val 0`

2. effect 阶段
   Master 将prepare 阶段的操作, broadcast 到所有 slave 以及 peer-master

#### EFFECT 操作

> 其他站点Redis Master 或 slave 如何响应 master 发出的 EFFECT操作

具体通讯内容详情参照`通讯协议`篇
slave 及其他 master 会收到源 master 传播的 `CRDT.SET <src-gid> <key> <vector-clock> <timestamp> <val> <expire-timestamp>`, 收到之后如何处理如下文:

CRDT.SET 写入逻辑



1. 首先取出 tombstone 中, 有关 key 的值

   1. 如果不存在, 进入下一步
   2. 如果存在, 且接收的 vector clock 小于 tombstone 中的 vector clock, 则什么都不做, 反之, 进入下一步

2. 如果本站点没有`key`, 那么直接执行`ADD`操作, 同时将 `<vector-clock>`, `<timestamp>` 记入

3. 如果本站点有 

   ```
   key
   ```

    存在

   1. 接收的 vector clock 和本身已存在的 值对应 vector clock比较, 如果是单调递增的, 则直接进行覆盖操作
   2. 如果是单调递减的, 则什么都不做
   3. 如果发生了冲突, 则进入下面步骤
      1. 取 timestamp 值较大的为最终值, 如果 timestamp 相同, 取 gid 较小的为最终值
      2. 记录冲突的发生和最终结果



#### DEL 操作

STRING 类型(Register) 的DEL 操作, 使用 **CRDT.DEL_REG** 进行传播, 执行逻辑如下:

CRDT.DEL_REG 操作



1. 从 Tombstone 中取出 DEL 的 key 对应的对象, 如果对象为

    

   NULL

    

   或是

    

   非 CRDT.Register 类型

   1. 创建 CRDT.Register, 并写入 Tombstone
   2. 更新 Tombstone 中, 对应值的 timestamp 和 vector clock

2. 取出数据库中对应的 key 的对象

   1. 如果对象为空, 则返回
   2. 如果对象不为空, **且 DEL 操作相对于对象的 vector clock 单调递增, 则删除 key**

### 内存对比

单个机房时string类型 

|                         | 数据结构占用 | 具体                                                         |
| :---------------------- | :----------- | :----------------------------------------------------------- |
| 普通redis               | 16           | robj(16)                                                     |
| 双向同步（lww) 单个机房 | 56           | robj(16) + moduleValue(16) + 最终数据结构24( type(0.5) + gid (0.5)+ time(7)+vc(8) + value*(8)) |
| 双向同步（lww) 多机房   | 56 + n*8     | vcu(8) * n                                                   |