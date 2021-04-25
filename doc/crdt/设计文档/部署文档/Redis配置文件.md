

## Redis Conf 文档

非常重要



CRDT Redis 增加了关于 global id 的重要概念, 需要在文档中指定说明

同时, CRDT Redis 的全量同步必须基于 socket 传输(而不是 RDB 传输), 配置需要特殊指定

```
port 6379
 
.....
 
crdt-gid 2
 
loadmodule /{absolute-path}/crdt.so
 
repl-diskless-sync yes
  
......
```

## gid和namespace

### 定义:redis中的配置和数据

- 配置是通过外部设置或者读取配置文件来获得，每个服务器的配置是独立的 
- 数据是会存储到rdb或者aof文件以及maste和slave需要保持一致的

### 结论:gid和namespace看做是配置的优点

- gid和namespace保存到配置文件上行为合理
- master服务器功能更明确,只需校验slave的gid是否和master的gid一致

### 用户设置:

gid只能配置里修改

- 配置文件（

  gid只能在启动 redis 前, 修改配置文件

  ）

  - crdt-gid  namespace  gid

- 命令设置namespace 

  -  config set crdt-gid namespace

### 作用:

#### gid的作用

gid 目的是为了区分双向同步中, 数据源端是谁的问题, 原则上, 

1. 不同站点同一分片的 gid 必须不一样
2. 同一站点同一分片必须一样
3. 同一站点不同分片不作要求

错误的 GID 分配 可能会导致同步失败, 或引起 redis 数据错乱

#### namespace的作用

目的是为了区分双向同步中,数据源所在的组,原则上,

1. 不同的站点,group相同 namespace必须一样,
2. 同一站点group不同,namespace必须不一样

错误的namespace分配 可能会导致同步错误,引发数据混乱



## 建立连接

假设目前有 4 个 redis 已经在运行, 我们需要双向同步

master1

host: 127.0.0.1

port: 6379

gid:  1

slave1

host: 127.0.0.1

port: 6479

gid:  1

master2

host: 127.0.0.1

port: 6579

gid:  2

slave2

host: 127.0.0.1

port: 6679

gid:  2

#### 首先搭建 Master-Slave 同步

```
slaveof <target-host> <target-port>
 
redis-cli -h 127.0.0.1 -p 6479 slaveof 127.0.0.1 6379
redis-cli -h 127.0.0.1 -p 6679 slaveof 127.0.0.1 6579
```

#### 然后搭建 Master-Master 之间同步

为了避免 Master-Master 和 Master-Slave 之间同时全量同步, 请尽量在 Master-Slave 搭建成功后, 再搭建 Master-Master 的同步通道

```
peerof <target-gid> <target-host> <target-port>
 
redis-cli -h 127.0.0.1 -p 6379 peerof 2 127.0.0.1 6579
redis-cli -h 127.0.0.1 -p 6579 peerof 1 127.0.0.1 6379
```