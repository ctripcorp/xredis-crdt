
#include "xpipe_proxy.h"
#include "hiredis.h"

struct Point* parsePoint(sds str) {
    struct Point* point = zmalloc(sizeof(struct Point));
    int len = 0;
    sds *vcUnits = sdssplitlen(str, sdslen(str), ":", 1, &len);
    if(len == 2) {
        point->host = sdsdup(vcUnits[0]);
        long port = 0;
        if(string2l(vcUnits[1], sdslen(vcUnits[1]), &port)) {
            point->port = port;
        } else {
            sdsfree(point->host);
            zfree(point);
            point = NULL;
        }   
    } else {
        zfree(point);
        point = NULL;
    }
    sdsfreesplitres(vcUnits, len);
    return point;
}

void freePoint(struct Point* point) {
    sdsfree(point->host);
    zfree(point);
}

struct Point** parseServers(sds vcStr, int* len) {
    sds *vcUnits = sdssplitlen(vcStr, sdslen(vcStr), ",", 1, len);
    struct Point** points = zmalloc(sizeof(struct Point*) * (*len));
    for(int i = 0; i < *len; i++) {
        struct Point* point = parsePoint(vcUnits[i]);
        if(point == NULL) {
            for(int index = 0; index < i - 1; index++) {
                freePoint(points[index]);
            }
            zfree(points);
            sdsfreesplitres(vcUnits, *len);
            return NULL;
        } 
        points[i] = point;
    }
    sdsfreesplitres(vcUnits, *len);
    return points;
}

void* createXpipeProxy() {
    struct XpipeProxy* proxy = zmalloc(sizeof(XpipeProxy));
    proxy->servers_len = 0;
    proxy->servers_index = 0;
    proxy->servers = NULL;
    proxy->params = NULL;
    return proxy;
}

sds getPointInfo(struct Point* point) {
    return sdscatprintf(sdsempty(), "%s:%ld", point->host, point->port);
}

sds getProxyServersInfo(struct XpipeProxy* proxy) {
    sds result = getPointInfo(proxy->servers[0]);
    for(int i = 1; i < proxy->servers_len; i++) {
        sds info = getPointInfo(proxy->servers[i]);
        result = sdscatprintf(result, ",%s",  info);
        sdsfree(info);
    }
    return result;
}

sds getXpipeProxyInfo(int peer_index, void* p) {
    if(p == NULL) return NULL;
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    sds servers_str = getProxyServersInfo(proxy);
    sds server_info = getPointInfo(proxy->servers[proxy->servers_index]);
    sds result = sdscatprintf(sdsempty(), 
        "peer%d_proxy_type:%s\r\n"
        "peer%d_proxy_servers:%s\r\n"
        "peer%d_proxy_server:%s\r\n"
        "peer%d_proxy_params:%s\r\n", 
        peer_index, "xpipe_proxy",
        peer_index, servers_str,
        peer_index, server_info,
        peer_index, proxy->params
    );
    sdsfree(server_info);
    sdsfree(servers_str);
    return result;
}
typedef char* getSdsByIter(void* value);
void* parseXpipeProxyByArray(void** argv, int argc, getSdsByIter get) {
    struct XpipeProxy* proxy = createXpipeProxy();
    for(int i = 4; i < argc; i++) {
        serverLog(LL_WARNING, "%s", get(argv[i]));
        if(strcasecmp(get(argv[i]), "proxy-server") == 0) {
            int len = 0;
            struct Point** server = parseServers(get(argv[++i]), &len);
            serverLog(LL_WARNING, "%s len: %d", get(argv[i]), len);
            if( server != NULL) {
                serverLog(LL_WARNING, "w");
                proxy->servers = server;
                proxy->servers_len = len;
                proxy->servers_index = 0;
            } 
        } else if(strcasecmp(get(argv[i]), "proxy-params") == 0) {
            sds options = sdsnew(get(argv[++i]));
            proxy->params = options;
        }
    }
    if(proxy->servers_len == 0) {
        freeXpipeProxy(proxy);
        return NULL;
    }
    return proxy;
}

char* getSdsMyself(void* value) {
    return (char*)value;
}

void* parseXpipeProxyBySdsArray(sds* argv, int argc) {
    return parseXpipeProxyByArray((void**)argv, argc, getSdsMyself);
}

char* getStrByRobj(void* robj_value) {
    return ((robj*)robj_value)->ptr;
}

void* parseXpipeProxyByRobjArray(robj** argv, int argc) {
    return parseXpipeProxyByArray((void**)argv, argc, getStrByRobj);
}

void freeXpipeProxy(void* p) {
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    if (proxy->servers_len != 0) {
        for(int i = 0; i < proxy->servers_len; i++) {
            // sdsfree(proxy->servers[i]);
            freePoint(proxy->servers[i]);
        }
    }
    if (proxy->params != NULL) {
        sdsfree(proxy->params);
    }
    zfree(proxy->servers);
    zfree(proxy);
}

sds getXpipeProxyConfigInfo(void* p) {
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    sds servers = getProxyServersInfo(proxy);
    sds result = sdscatprintf(sdsempty(), "proxy-type XPIPE-PROXY proxy-server %s", servers);
    if(proxy->params != NULL) {
        result = sdscatprintf(result, " proxy-params '%s'", proxy->params);
    } 
    sdsfree(servers);
    return result;
}

int eqPoint(struct Point* p1, struct Point* p2) {
    if (sdscmp(p1->host, p2->host) != 0) {
        return 0;
    }
    if (p1->port != p2->port) {
        return 0;
    }
    return 1;
}

int eqXpipeProxy(void* p1, void* p2) {
    struct XpipeProxy* proxy1 = (struct XpipeProxy*)p1;
    struct XpipeProxy* proxy2 = (struct XpipeProxy*)p2;
    if(proxy1->params == NULL && proxy2->params != NULL) {
        return 0;
    }
    if(proxy1->params != NULL && proxy2->params == NULL) {
        return 0;
    }
    if(proxy1->params != NULL && proxy2->params != NULL) {
        if(sdscmp(proxy1->params, proxy2->params) != 0) {
            return 0;
        }
    }
    if(proxy1->servers_len != proxy2->servers_len) {
        return 0;
    }
    for(int i = 0; i < proxy1->servers_len; i++) {
        struct Point* proxy1_server = proxy1->servers[i];
        int eq = 0;
        for(int j = 0; j < proxy2->servers_len; j++) {
            struct Point* proxy2_server = proxy2->servers[j];    
            if(eqPoint(proxy1_server, proxy2_server)) {
                eq = 1;
                break;
            }
        }
        if(eq == 0) {
            return 0;
        }
    }
    return 1;
}





int xpipeProxyConnect(void* p, char* host, int port) {
    UNUSED(host);
    UNUSED(port);
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    struct Point* point = proxy->servers[proxy->servers_index];
    assert(point != NULL);
    int fd = anetTcpNonBlockBestEffortBindConnect(NULL,
                                              point->host,
                                              point->port, NULL);
    // sdsfree(point.host);
    if(fd == -1) {
        sds point_info = getPointInfo(point) ;
        serverLog(LL_WARNING, "[XPIPE-PROXY] connect %s fail", point_info);
        sdsfree(point_info);
        proxy->servers_index = (proxy->servers_index + 1) % proxy->servers_len;
        return fd;
    }
    return fd;
}

int ramdonIndex(int start, int end){
    int dis = end - start;
    return rand() % dis + start;
}

int xpipeProxyConnect2(void* p, char* host, int port) {
    UNUSED(host);
    UNUSED(port);
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    int index = ramdonIndex(0, proxy->servers_len);
    struct Point* point = proxy->servers[index];
    assert(point != NULL);
    int fd = anetTcpNonBlockBestEffortBindConnect(NULL,
                                              point->host,
                                              point->port, NULL);
    sds point_info = getPointInfo(point) ;
    if(fd == -1) {
        serverLog(LL_WARNING, "[XPIPE-PROXY] connect %s fail", point_info);
    } else {
        serverLog(LL_WARNING, "[XPIPE-PROXY] connect %s", point_info);
        proxy->servers_index = index;
    }
    sdsfree(point_info);
    return fd;
}

int initXpipeProxy(int fd, void* p, char* src_host, int src_port, char* dst_host, int dst_port) {
    UNUSED(src_host);
    UNUSED(src_port);
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    sds cmd = sdscatfmt(sdsempty(), "+PROXY ROUTE TCP://%s:%i ", dst_host, dst_port);
    if(proxy->params != NULL) {
        cmd = sdscatfmt(cmd, " %s", proxy->params);
    }
    //add src info
    cmd = sdscat(cmd, "\r\n");
    if (syncWrite(fd,cmd,sdslen(cmd),crdtServer.repl_syncio_timeout*1000)
            == -1)
    {
        serverLog(LL_WARNING, "[xpipe-proxy]connect proxy fail:%s", cmd);
        sdsfree(cmd);
        return 0;
    }
    serverLog(LL_WARNING, "[xpipe-proxy]connect proxy success:%s", cmd);
    sdsfree(cmd);
    return 1;
}

void* str2XpipeProxy(sds str) {
    struct XpipeProxy* proxy = createXpipeProxy();
    int len = 0;
    sds* splits = sdssplitlen(str, sdslen(str), "|", 1, &len);
    sds length_str = splits[0];
    long length = 0;
    if(!string2l(length_str, sdslen(length_str), &length)) {
        goto error;
    }
    int servers_len = 0;
    sds proxy_servers_str = splits[1];
    struct Point** servers = parseServers(proxy_servers_str, &servers_len);
    if(servers == NULL) {
        goto error;
    }
    proxy->servers_len = servers_len;
    proxy->servers = servers;
    proxy->servers_index = 0;
    if(len == 3) {
        proxy->params = sdsdup(splits[2]);
    }
    sdsfreesplitres(splits, len);
    return proxy;
error:
    zfree(proxy);
    sdsfreesplitres(splits, len);
    return NULL;

}

sds xpipeProxy2str(void* p) {
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    long long params = 1;
    if (proxy->params != NULL) {
        params++;
    }
    sds result = sdsfromlonglong(params);
    sds servers_info = getProxyServersInfo(proxy);
    result = sdscatprintf(result, "|%s", servers_info);
    sdsfree(servers_info);
    if (proxy->params != NULL) {
        result = sdscatprintf(result, "|%s", proxy->params);
    }
    return result;
}

void* xpipeProxyHiRedis(void* p, char* src_host, int src_port, char* dst_host, int dst_port) {
    struct XpipeProxy* proxy = (struct XpipeProxy*)p;
    redisContext *c = NULL;
    for(int i = 0; i < proxy->servers_len; i++) {
        struct Point* point = proxy->servers[i];

        c = redisConnect(point->host,point->port);
        if (initXpipeProxy(c->fd, p, src_host, src_port, dst_host, dst_port)) {
            return c;
        }
        redisFree(c);
        c = NULL;
    }
    return c;
}

int xpipeProxyIsKeepConnected(void* c, void* p) {
    struct XpipeProxy* current = (struct XpipeProxy*)c;
    struct XpipeProxy* peer = (struct XpipeProxy*)p;
    struct Point* point = current->servers[current->servers_index];
    if(peer->params != NULL &&  current->params != NULL ) {
        if(sdscmp(peer->params, current->params) != 0) {
            return 0;
        }
    } else if(peer->params != current->params) {
        return 0;
    }
    for(int i = 0; i < peer->servers_len; i++) {
        if(eqPoint(point, peer->servers[i])) {
            peer->servers_index = i;
            return 1;
        }
    }

    return 0;
}

#if defined(XPIPE_PROXY_TEST_MAIN)
#include <stdio.h>
#include "testhelp.h"
#include "limits.h"

#define UNUSED(x) (void)(x)
int main() {
    sds str = sdsnew("127.0.0.1:6379;127.0.0.1:6479");
    int len = 0;
    sds* value = parseServers(str, &len);
     test_cond("parse servers",
            value != NULL && len == 2);
    return 1;
}
#endif  
