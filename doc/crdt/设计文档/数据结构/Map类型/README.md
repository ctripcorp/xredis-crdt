## MAP 类型

#### 支持 API

| Redis API | 目前进度 |
| :-------- | :------- |
| hmset     | **DONE** |
| hmset     | **DONE** |
| hget      | **DONE** |
| hmget     | **DONE** |
| hkeys     | **DONE** |
| hvals     | **DONE** |
| hgetall   | **DONE** |
| hdel      | **DONE** |

#### CRDT

> 先来讲一下, CRDT理论中, 如何处理Redis MAP类型的同步问题

Redis的MAP类型对应于CRDT里面的`Map`数据结构, 对应的具体实现有两种比较符合我们的应用场景:

- `Observed Remove Map (OR Map)` - this map shares the same semantics as ORset, i.e. where the elements can be added and removed any number of times and the adds always win. In the case of concurrent update, the 2 new values are merged.
- `Grow-only map (GMap)` - as for the case of other grow-only structures, also in this one we can’t undo the state. That said, once the key-value pair is added, it can’t be removed. Similarly to OR Map, when the keys are with different values in several datasets, the values are merged into a single one.
- `Last-write wins Map (LWW Map)` - it’s a OR Map with the values of Last-write Wins Register (LWW Regiter) type. Thus in the case of conflicting writes, the most recent write is always kept.

#### CRDT API

| CRDT API      | 目前进度 | 使用场景                       |
| :------------ | :------- | :----------------------------- |
| CRDT.HSET     | **DONE** | 插入 MAP 的值                  |
| CRDT.DEL_HASH | **DONE** | 删除整个 MAP, 对标 DEL         |
| CRDT.REM_HASH | **DONE** | 删除 MAP 中的部分值, 对标 HDEL |

#### MAP 的实现

MAP 的实现由普通的 HashMap 上文中的 CRDT_STRING 组成

```
typedef` `struct` `CRDT_Hash {``    ``dict *map;``    ``int` `gid;``    ``long` `long` `timestamp;``    ``VectorClock *vclock;` `    ``unsigned ``char` `remvAll;``    ``VectorClock *maxdvc;``} CRDT_Hash;
```



#### HSET操作 – Op-Based Replication

1. prepare 阶段
   将 `HSET <key> <field> <val>`的形式, 转化为 CRDT.`HSET <key> <gid> <timestamp> <vector-clock> <length> <field> <val> <field> <val> ...`
   举个栗子

   `HMSET key field val` ==>
   `CRDT.HSET key 1 1553148256336368208 1,24;2,32 2 field val`

2. effect 阶段
   Master 将prepare 阶段的操作, broadcast 到所有 slave 以及 peer-master

#### EFFECT 操作

> 其他站点或 slave 如何响应 master 发出的 EFFECT操作

具体通讯内容详情参照`通讯协议`篇
slave 及其他 master 会收到源 master 传播的 `CRDT.HMSET <key> <src-gid> <timestamp> <vector-clock> <length> <field> <val> <field> <val> ...`, 收到之后如何处理如下文:

CRDT.HSET 写入操作



1. 首先从数据库中, 尝试拿出 key 对应的对象

   1. 如果存在, 且类型不是 CrdtHash, 则报错返回
   2. 反之, 进入下一步

2. 取出 tombstone 中, 有关 key 的值

   1. 如果不存在, 进入下一步
   2. 如果存在, 且类型是 CRDT.HASH, 并且 max-deleted-vector-clock 比目前 set 的 vector clock 大, 则什么都不做, 返回
   3. 如果存在, 且类型不是 CRDT.HASH, 接收的 vector clock 小于 tombstone 中的 vector clock, 则什么都不做, 反之, 进入下一步

3. 如果本站点没有`key`, 那么直接执行`ADD`操作, 针对每一个field 进行插入

4. 如果本站点有 

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



MAP 类型 的DEL 操作, 使用 **CRDT.DEL_HASH** 进行传播, 执行逻辑如下:

```
CRDT.DEL_HASH <key> gid timestamp <del-op-vclock> <max-deleted-vclock>
```

CRDT.DEL_REG 操作



1. 从 Tombstone 中取出 DEL 的 key 对应的对象, 如果对象不为 NULL 且不是 CrdtHash 类型, 则报错返回 
2. 如果 Tombstone 中已经有值, 并且 vector clock 对比当前 DEL 操作单调递增, 则直接返回
3. 如果 Tombstone 中值为 NULL 
   1. 创建 CRDT.CrdtHash, 并写入 Tombstone
   2. 更新 Tombstone 中, 对应值的 timestamp 和 vector clock
   3. 将 remvAll 参数设置为 true
   4. 更新 maxdvc (max-deleted-vector-clock)
4. 取出数据库中对应的 key 的对象
   1. 如果对象为空, 则返回
   2. 如果对象不为空, 轮询 map
      1. 如果 vector clock 小于等于 max-deleted-vector-clock, 则删除; 反之, 不做任何操作
      2. 如果发现 map 为空, 则删除 key

#### HDEL 操作



MAP 类型 的DEL 操作, 使用 **CRDT.DEL_HASH** 进行传播, 执行逻辑如下:

```
CRDT.REM_HASH <key> gid timestamp <del-op-vclock> <field1> <field2> ....
```

CRDT.DEL_REG 操作





1. 如果 Tombstone 中值为 NULL 或者 不是 CrdtHash 类型
   1. 创建 CRDT.CrdtHash, 并写入 Tombstone
   2. 更新 Tombstone 中, 对应值的 timestamp 和 vector clock
   3. 将 remvAll 参数设置为 false
   4. 并不会更新 maxdvc (max-deleted-vector-clock)
2. 取出数据库中对应的 key 的对象
   1. 如果对象为空, 则返回
   2. 如果对象不为空, 轮询 map
      1. 如果 vector clock 小于等于 max-deleted-vector-clock, 则删除; 反之, 不做任何操作
      2. 同时, 将删除的 field, 写入 tombstone 中的 map
      3. 如果发现 map 为空, 则删除 key