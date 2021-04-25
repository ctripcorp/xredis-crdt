## Tombstone 的设计

1. Tombstone 在 GC 前, 新的 Tombstone 过来, 如何处理
2. Tombstone 在 GC 前, 新的 Tombstone 有不同数据结构过来, 如何处理
3. Map 这种数据结构, 有两种 Tombstone, 一个是部分删除的 HDEL, 一个是全部删除的 DEL, 如何处理