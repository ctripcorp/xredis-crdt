redis内部有2套Sub/Pub机制,一套是和原声redis一样的Sub/Pub只作用与master和slave之间.另外一套是支持crdt环境内多个master之间.

原因是:为了保证哨兵机制正常进行,sub/pub消息不被其他master的消息干扰且不需要引入新的处理逻辑

crdt环境下的Sub/Pub

| TimeStamp | Master-1 | Master-2 |
|  ----  | ----  | ---- |  
|   t1	 | `crdtpublish <channel> <message>` | |
|   t2   | | `crdt.publish <channel> <message> <gid>` |
|   t..  | | ……………… |