[![CRDT-Redis CI](https://github.com/ctripcorp/xredis-crdt/actions/workflows/crdt-redis.yml/badge.svg)](https://github.com/ctripcorp/xredis-crdt/actions/workflows/crdt-redis.yml)

<!-- MarkdownTOC -->

- [Introduction](#introduction)
- [Features](#features)
  - [# Build](#-build)
- [Test](#test)
- [Run](#run)


<!-- /MarkdownTOC -->


<a name="introduction"></a>
# Introduction
XRedis is [ctrip](http://www.ctrip.com/) redis branch. Ctrip is a leading provider of travel services including accommodation reservation, transportation ticketing, packaged tours and corporate travel management.

<a name="features"></a>
# Features
* Multi Master
* Peer Replication
* Partially Full-Sync



# Build
--------------

Redis can be compiled and used on Linux, OSX, OpenBSD, NetBSD, FreeBSD.
We support big endian and little endian architectures, and both 32 bit
and 64 bit systems.

It may compile on Solaris derived systems (for instance SmartOS) but our
support for this platform is *best effort* and Redis is not guaranteed to
work as well as in Linux, OSX, and \*BSD.

It is as simple as:

    % make


# Test
After building Redis, it is a good idea to test it using:

    % make crdt-test

# Run 
redis-server with crdt feature depends [crdt-module](https://github.com/ctripcorp/crdt-module)

```
% cd /path/to/crdt-module && make     
% redis-server --crdt-gid {namespace} {gid} --loadmodule /path/to/crdt-module/
    crdt.so
```





