#include "server.h"
#include "xpipe_proxy.h"

int getProxyType(sds type) {
    if(strcasecmp(type, "xpipe-proxy") == 0) {
        return XPIPE_PROXY;
    } else {
        return NONE_PROXY;
    }
}

void* parseProxyByRobjArray(int proxy_type, robj** argv, int argc) {
    if(proxy_type == XPIPE_PROXY) {
        return parseXpipeProxyByRobjArray(argv, argc);
    } else {
        return NULL;
    }
}

void* parseProxyBySdsArray(int proxy_type, sds* argv, int argc) {
    if(proxy_type == XPIPE_PROXY) {
        return parseXpipeProxyBySdsArray(argv, argc);
    } else {
        return NULL;
    }
}

sds getProxyInfo(int peer_index, int proxy_type, void* proxy) {
    if(proxy_type == XPIPE_PROXY) {
        return getXpipeProxyInfo(peer_index, proxy);
    } else {
        return NULL;
    }
}

void freeProxy(int proxy_type, void* proxy) {
    if(proxy_type == XPIPE_PROXY) {
        freeXpipeProxy(proxy);
        return;
    } else {
        return;
    }
}

sds getProxyConfigInfo(int proxy_type, void* proxy) {
    if(proxy_type == XPIPE_PROXY) {
        return getXpipeProxyConfigInfo(proxy);
    } else {
        return NULL;
    }
}

int eqProxy(int proxy_type, void* p1, void* p2) {
    if(proxy_type == XPIPE_PROXY) {
        return eqXpipeProxy(p1, p2);
    } else if(proxy_type == NONE_PROXY && p1 == NULL && p2 == NULL) {
        return 1;
    } else {
        return 0;
    }
}

int proxyConnect(int proxy_type, void* proxy, char* host, int port) {
    if(proxy_type == XPIPE_PROXY) {
        return xpipeProxyConnect(proxy, host, port);
    }
    return -1;
}

int initProxy(int fd, int proxy_type, void* p, char* src_host, int src_port, char* dst_host, int dst_port) {
    if(proxy_type == XPIPE_PROXY) {
        return initXpipeProxy(fd, p, src_host, src_port, dst_host, dst_port);
    }
    return 0;
}

void* str2proxy(int proxy_type, sds str) {
    if(proxy_type == XPIPE_PROXY) {
        return str2XpipeProxy(str);
    }
    return 0;
}

sds proxy2str(int proxy_type, void* proxy) {
    if(proxy_type == XPIPE_PROXY) {
        return xpipeProxy2str(proxy);
    }
    return 0;
}

void* proxyHiRedis(int proxy_type, void* proxy, char* src_host, int src_port, char* dst_host, int dst_port) {
    if(proxy_type == XPIPE_PROXY) {
        return xpipeProxyHiRedis(proxy, src_host, src_port, dst_host, dst_port);
    }
    return NULL;
}

int proxyIsKeepConnected(int proxy_type, void* current, void* proxy) {
    if(proxy_type == XPIPE_PROXY) {
        return xpipeProxyIsKeepConnected(current, proxy);
    }
    return 0;
}
