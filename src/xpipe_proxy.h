#ifndef __XPIPE_PROXY_H
#define __XPIPE_PROXY_H
#include "server.h"

typedef struct XpipeProxy
{
    struct Point** servers;
    int servers_len;
    int servers_index;
    sds params;
} XpipeProxy;

void* parseXpipeProxyByRobjArray(robj** argv, int argc);
void* parseXpipeProxyBySdsArray(sds* argv, int argc);
sds getXpipeProxyInfo(int peer_index, void* p);
void freeXpipeProxy(void* proxy);
sds getXpipeProxyConfigInfo(void* proxy);
int eqXpipeProxy(void* p1, void* p2);
int xpipeProxyConnect(void* proxy, char* host, int port);
int xpipeProxyConnectFail(void* proxy);
int xipieProxyConnectedAfter(int fd, void* p, char* src_host, int src_port, char* dst_host, int dst_port);
void* str2XpipeProxy(sds str);
sds xpipeProxy2str(void* p);
void* xpipeProxyHiRedis(void* p, char* src_host, int src_port, char* dst_host, int dst_port);
int xpipeProxyIsKeepConnected(void* c, void* p);
#endif /* _ZIPLIST_H */