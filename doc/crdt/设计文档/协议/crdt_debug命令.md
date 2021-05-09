### CRDT debug 命令

| 简述            | 参数               | 场景                                                         | 用法说明                                                     |
| :-------------- | :----------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| debugCancelCrdt | <gid> chenzhu      | 仅限 debug/测试使用可以断开指定 <gid>的 master 链接一次      | 结尾的 chenzhu 是为了防止被人滥用例如: 关闭 peer 的 gid 为 2发送 `debugCancelCrdt 2 chenzhu` |
| debug           | set-crdt-ovc <0/1> | 单测中, 为了测试 offset 是否完全对齐可以关闭 peer 之间的定时命令让 peer 之间流达到一个相对静止的状态 | 关闭定时 crdt.ovc 命令debug set-crdt-ovc 0开启定时 crdt.ovc 命令debug set-crdt-ovc 1 |

