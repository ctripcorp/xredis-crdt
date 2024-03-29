## 全量同步 打包/加载 RDB 速度优化

| 版本  | 优化内容                                                     | 优化后                                                       | master → slave（crdt)                                        | master→master(2个peer)                                       | 普通master->crdt(rdb加载成命令执行）                         |
| :---- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| 1.0.5 | 优化普通rdb转换命令执行 优化命令 减少命令执行次数（hash的hset等) | 测试环境: 内存10g  5400万个key优化后普通redis导到crdt服务器耗时优化到433s->307秒 |                                                              |                                                              | 测试环境:优化前  92s（rdb打包) + 342s（加载)优化后  97s (rdb打包)+ 210s (加载)优化30% |
| 1.0.6 | 优化加载crdt的rdb,加载rdb的setmodule时减少一次查询,修改收集key到字典里后再遍历字典(减少申请字典内存和1次遍历字典) | 测试环境:xredis keys=19118133和expires=19011255,rdb大小优化后 crdt的master-slave全量同步 总耗时 255s->205s | 优化前 90s（rdb打包) + 165s(加载)优化后 90s（rdb打包) + 115s（加载)优化20% |                                                              |                                                              |
| 1.0.7 | 优化RDB 中, vector clock 存储方式从 string 优化为 long long  | 测试环境: xredis 占用13.6G 6000万个key优化后 peer之间同步总耗时 303s->224s优化后 crdt的master-slave全量同步同步总耗时 330s->280s | 优化前 总耗时 330秒优化后 总耗时 280秒优化16%                | 测试环境: 13.6G 6000万个key优化前 总耗时 303秒优化前 总耗时 224秒优化 35% |                                                              |



环境6000个key, 普通redis 10.89G key 23 字节 value  105字节

物理机硬件  现在是用32核192G（原来测用的是64核 256G,）

|                               | 发送rdb | 加载    | 总时间 | 内存   |
| :---------------------------- | :------ | :------ | :----- | :----- |
| 普通redis同步（master->slave) | 2分07秒 | 1分23秒 | 210秒  | 10.89G |
| 1.0.8 （master->slave）       | 3分19秒 | 2分30秒 | 349秒  | 13.25G |

### uat环境测试(20G)

普通redis redis4.0.12  （4C22G）

docker  xredis1.0.10    （4C30G）



key长度最大 Key+数字  数字长度（0-9)  个

value长度Value + 数字  数字长度  (0-9）个



|                                                     | 打包发送            | 加载                     | 总耗时   |
| :-------------------------------------------------- | :------------------ | :----------------------- | :------- |
| 普通redis-crdt的redis20.6G246942894个key            | 5分05秒（7.05G）    | 24分12秒加载完成后28.02G | 29分16秒 |
| crdt_master→ crdt_slave28.02G246942894个key 左右    | 15分20秒 （17.18G） | 16分15秒                 | 31分40秒 |
| crdt_master->crdt_peer28.02G246928522个key 左右     | 27分55秒            | 28分05秒                 |          |
| 普通redis_master→普通redis_slave246928522个key 左右 | 5分49秒             | 5分31秒                  | 11分24秒 |

### 1.0.7 优化 CRDT RDB

LWW_TYPE 可以增加关于版本的特性, 放在高16 位, 既可以允许有 **65535** 个版本

根据版本不同, 对 vector clock 的 RDB 反序列化可以使用不同的逻辑



CRDT_RDB_VERSION 设计



/**
*

- | version | opt | crdt type |
- |--16 bits--| 40 bits | 8 bits |
  *
- LWW_TYEP 1
- ORSET_TYPE 2
- FUTURE 3
- OTHERS 4
- */