## Vector Clock 

### 简介

由于每种数据结构对应`CRDT`中的数据结构都不一样, 针对每种数据结果需要的内容也不同, 所以需要针对每个数据结构进行说明

每种数据结构中, 我们需要引入一个叫做 `vector clock`的概念, 用于GC操作和一些协议上的需求

#### 对于VectorClock的定义

操作:

对于数据的修改 例子: 我们对于数据k的添删改等行为 叫做操作



clock的定义

逻辑时钟用来标记本地操作

1. 例子: A当前的clock是1,当设置key值为value时,clock会增加到2



可见操作: 与操作相关所有信息都完整

1. 例子: 节点A在时间戳为1000时对k1进行了修改操作值为v1,操作的时钟是<A:1> 我们认为这次操作是的可见操作



进程的vectorClock:

单个节点只保存执行可见操作的节点对应的最大时钟的集合

1. 节点A <A:10> 接收到B <B:10,C:10>, A最后的进程vc为<A:10,B:10>, B先收到了C的操作,再发送给A 不代表A收到了C的操作
2. 节点B <B:10,C:10> 接收到A<A:11,C:11> 最后B节点的进程vc为<A:11,B:10,C:10>



Key的VectorClock

key的 vector clock, 根据 CRDT 的数据类型, 有不同的定义

`OR-SET 类型`

定义: 单个节点上保存所有节点对于同一个key的可见操作的最大时钟
1. 假设当前A节点上key为k1的vectorClock<A:2,B:2,C:2>,
   1. 如果收到的vectorClock是<A:2,B:3,C:3>,最后A节点上k1的vectorClock是<A:2,B:3,C:3>(偏序)
   2. 如果收到的vectorClock是<B:3,C:3>,最后A节点上k1的vectorClock是<A:2,B:3,C:3>(冲突)
   3. 如果收到的vectorClock是是<A:1,B:1,C:1> 那么A节点依然是<A:2,B:2,C:2> (过期偏序)

`LWW 类型`

定义: 单个节点上保存,  key 最后一次有效操作, 相对于全局所有操作的时钟

原因: LWW 只会保留一个元素, 如果只剩下 tombstone 的情况下, 一个节点 tombstone GC 掉, 其他节点没有

那么, 这个节点, 对于相同 key 的重新插入, 就会缺少有 tombstone 这么一个信息

只记录 key 的操作历史, 会导致该信息丢失, 但是记录这个节点上, 本次操作相对于全局操作的时钟, 就可以携带有 tombstone 这一历史信息, 保证数据一致

1. 假设 A 节点上, 进程vector clock 为 <A:1,B:2,C:3>
2. 一个全新的 key 写入, set key val
3. 此时, key 对应的 vector clock 为 <A:2,B:2,C:3>
4. 进程的 vector clock 也变为 <A:2,B:2,C:3>





gc的vectorClock:

所有节点进程的vectorClock的最小时钟集合

1. 节点A <A:11,B:1,C:1>,节点B<A:2,B:12,C:2>,节点C<A:3,B:3,C:13> 最终gc <A:2,B:1,C:1>



如果在丢失数据的情况下使用clock,会存在clock重复,为了避免这种场景的发生 我们需要跳过一段不可能重复的clock

1. 当slave切换成master的时候存在数据丢失
2. redis宕机重启的情况下存在数据丢失



具体 vector-clock 的内容以及相关概念, 可以参考:
* [VectorClock WiKi](https://en.wikipedia.org/wiki/Vector_clock)
* [CRDT启蒙篇](http://jtfmumm.com/blog/2015/11/17/crdt-primer-1-defanging-order-theory/)



```
typedef struct VectorClockUnit {
    long long gid;
    long long logic_time;
}VectorClockUnit;
 
typedef struct VectorClock {
    VectorClockUnit *clocks;
    int length;
}VectorClock;
```

 单个 vector clock单元 由两部分组成:

1. gid:  Redis 具有站点的信息属性, 用来区分不同站点之间的 Redis
2. logic time: 每一次操作, logic time 都会自增 1

多个 vector clock unit 组成了一个站点的 vector clock

#### Vector Clock 的大小

两个 vector clock 之间的大小比较的逻辑如下:

1. 如果某一 gid 在 vector clock 中不存在, 则认为对应的logic_time为 0
2. 两个 vector clock, vclock1, vclock2
   1. vclock1 > vclock2, if for any gid,  vclock1[gid].logic_time >= vclock2[gid].logic_time

#### 关于偏序(Partial Order)

> 偏序是指, 两个操作是否存在单调递增的逻辑关系 (即, 一个操作 happens before 另一个操作)

假设有两个操作, 他们的 vector clock 分别是 vclock-A, vclock-B, 那么 vclock-A <= vclock-B, 则我们认为这两个操作满足偏序的关系.

#### Vector Clock 的使用

CRDT 数据结构中, vector clock 主要使用在两个方面:

1. 每个 Redis 有两个全局的 vector clock:
   1. 用来记录这个 Redis 总共执行过的操作. 比如 1:100;2:100 表示的是在这个 redis 上, 执行了 gid 为 1 的站点的 100 个操作, 和 gid 为 2 的站点的 100 个操作
   2. 用来记录可以 GC 的数据结构的 vector clock. 每个站点会定时想其他站点发送 CRDT.OVC 命令, 诠释自己站点的 OVC(observed vector clock), 将这些 OVC 和 自身的 vector clock 进行一次 merge 操作(取所有 logic time 的最小值), 得到的 vector clock 即为可以被 GC 掉的数据的 vclock
2. 每次操作会储存对应的 vector clock 信息
   1. 当没有value和tombstone的时候我们使用的是进程vectorClock.主要原因是使用对key可见操作的vectorClock,gc无法强一致的话会导致vectorClock冲突从而引发数据不一致.