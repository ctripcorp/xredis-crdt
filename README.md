[![CRDT-Redis CI](https://github.com/ctripcorp/xredis-crdt/actions/workflows/crdt-redis.yml/badge.svg)](https://github.com/ctripcorp/xredis-crdt/actions/workflows/crdt-redis.yml)

<!-- MarkdownTOC -->

- [Introduction](#introduction)
- [Features](#features)
- [Details](#details)
- [Develop](#develop)


<!-- /MarkdownTOC -->


<a name="introduction"></a>
# Introduction
XRedis is [ctrip](http://www.ctrip.com/) redis branch. Ctrip is a leading provider of travel services including accommodation reservation, transportation ticketing, packaged tours and corporate travel management.

<a name="features"></a>
# Features
* Multi Master
* Peer Replication
* Partially Full-Sync

<a name="details"></a>

# Build

redis-server with swap feature depends on rocksdb (>=5.17).

1. ubuntu

```
apt install librocksdb-dev libsnappy-dev zlib1g-dev libgflags-dev libstdc++6
cd /path/to/xredis-crdt && make
```

2. centos

```
yum install snappy zlib gflags libstdc++
cd /path/to/rocksdb
make shared_lib
cd /path/to/xredis-crdt && CFLAGS=-I/path/to/rocksdb/include LDFLAGS=-L/path/to/rocksdb/lib make
```

# Details

<a name="develop"></a>
# Develop
[GITHUB] is the first-priority git repository




