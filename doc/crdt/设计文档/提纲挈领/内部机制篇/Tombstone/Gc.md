## GC 机制

> GC 机制的引入是因为我们引入了 Tombstone 机制, 如果我们有一个无限大的内存, 当然可以做到储存所有的删除操作, 但是, 现实中明显是不可能的, 所以就需要一个 GC 的机制, 定期或是不定期地处理 Tombstone 中已经没有用的数据

#### GC 的设计原理

> Definition 4.1 (Stability). Update f is stable at replica xi (noted Φi (f )) if al l updates concurrent to f according to delivery order <d are already delivered at xi. Formally, Φi(f) ⇔ ∀j : f ∈ C(xj) ∧ ̸ ∃g ∈ C(xj) \ C(xi) : f ∥d g.
>
> Liveness of Φ requires that the set of replicas be known and that they not crash per- manently (undetectably). Under these assumptions, the stability algorithm of Wuu and Bernstein [44] can be adapted. The algorithm assumes causal delivery. An update g has an associated vector clock v(g). Replica xi maintains the last vector clock value received from every other replica x , noted V min(j), which identifies all updates that x knows to have been jii delivered by x . Replica must periodically propagate its vector clock to update V min values, ji possibly by sending empty messages. With this information, (∀j : V min(j) ≥ v(f)) ⇒ Φ (f). ii Importantly, the information required is typically already used by a reliable delivery mech- anism, and GC can be performed in the background.
>
> For instance, our Add-Remove Partial Order data type from Section 3.4.2 could use Φ to remove tombstones left by remove once all concurrent addBetween updates have been delivered. In the state-based emulation of Section 2.4.2, stable messages could be discarded (this is Wuu’s original motivation). RGA also uses this approach (Section 3.5.1), as do Treedoc and Logoot [32, 35, 43].

如果当前站点可以确认所有的站点, 逻辑上可以达到的最小一致性, 那么, 在 tombstone 中, 小于或等于这个最小一致性的操作, 都可以被删除.

实际上, 论文中的理论也引入了 vector clock 这一机制, 来计算不同站点之间的最小的偏序(Partial Order), 来定位可以删除的 tombstone

#### GC的机制原理 – 基于 `vector clock`的GC

CRDT关于GC的理论机制, 主要是基于`vector clock`的GC, 原理如下:

**如果每个站点的vector_clock均大于DEL操作时的vector_clock, 且元素被标记为删除状态, 那么该元素就可以被GC**

#### GC 的实现机制

实现上, 通过 Redis Master 之间互相发送 自身的 vector clock, 来达到 redis 之间可以互相确定最小偏序的 vector clock 的目的

Redis 的 GC 机制完全参考了 Expire 机制的实现, 在处理上分为两种:

1. 被动 GC
2. 主动 GC

#### 被动 GC

Redis 定时轮询 tombstone 中的key, 随机抽出一个 key, 判断是否可以删除 (key 的 value 中 vector clock 小于/等于 最小偏序), 如果删除成功, 继续下一个, 直到达到当次的最大检查次数(默认 20)

此时, 如果 GC 掉的个数, 是总轮询数目的 1/4, 就继续下一轮, 反之, 换一个 DB 的 tombstone

如果在过程中, 超出了单次被动 GC 的总时间, 也会推出



#### 主动 GC

每一次查询 Tombstone 的操作, 都会触发 GC 机制, 检查是否可以 GC 掉 key

master-slave 分开GC的原因

a.分开来gc不会导致数据不一致

b.如果统一由master进行gc通知slave的话,会导致增加命令以及offset没有必要