### CRDT Info 信息

| 简述         | 参数             | 返回值及说明                                                 |
| :----------- | :--------------- | :----------------------------------------------------------- |
| CRDT.role    | NULL             |                                                              |
| CRDT.info    | replicationstats |                                                              |
| tomstoneSize | NULL             | 获取 tombstone 字典的大小                                    |
| config       | crdt.set         | 设置 CRDT 的相关属性, 参数同原生 redis作用范围: 在作用域 crdtServer 对象 |
| expireSize   | NULL             | 获取过期字典的大小                                           |

