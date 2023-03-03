#include "server.h"

/*============================ CRDT functions ============================ */

void
incrLocalVcUnit(long long delta) {
    // VectorClockUnit *localVcu = getVectorClockUnit(crdtServer.vectorClock, crdtServer.crdt_gid);
    incrLogicClock(&crdtServer.vectorClock, crdtServer.crdt_gid, delta);
    if (!isNullVectorClock(crdtServer.vectorClockCache)) { incrLogicClock(&crdtServer.vectorClockCache, crdtServer.crdt_gid, delta); }
}

void refullsyncCommand(client *c) {

    sds client = catClientInfoString(sdsempty(),c);
    serverLog(LL_NOTICE,"refullsync called (user request from '%s')", client);
    sdsfree(client);

    disconnectSlaves(); /* Force our slaves to resync with us as well. */
    freeReplicationBacklog(&server); /* Don't allow our chained slaves to PSYNC. */

    addReply(c,shared.ok);
}

void xslaveofCommand(client *c) {
    /* SLAVEOF is not allowed in cluster mode as replication is automatically
     * configured using the current address of the master node. */
    if (server.cluster_enabled) {
        addReplyError(c,"SLAVEOF not allowed in cluster mode.");
        return;
    }

    /* The special host/port combination "NO" "ONE" turns the instance
     * into a master. Otherwise the new master address is set. */
    if (!strcasecmp(c->argv[1]->ptr,"no") &&
        !strcasecmp(c->argv[2]->ptr,"one")) {
        if (server.masterhost) {
            replicationUnsetMaster();
            sds client = catClientInfoString(sdsempty(),c);
            serverLog(LL_NOTICE,"(XSLAVEOF)MASTER MODE enabled (user request from '%s')",
                client);
            sdsfree(client);
        }
    } else {
        long port;

        if ((getLongFromObjectOrReply(c, c->argv[2], &port, NULL) != C_OK))
            return;

        /* Check if we are already attached to the specified slave */
        if (server.masterhost && !strcasecmp(server.masterhost,c->argv[1]->ptr)
            && server.masterport == port) {
            serverLog(LL_NOTICE,"XSLAVE OF would result into synchronization with the master we are already connected with. No operation performed.");
            addReplySds(c,sdsnew("+OK Already connected to specified master\r\n"));
            return;
        }
        /* There was no previous master or the user specified a different one,
         * we can continue. */
        replicationSetMaster(c->argv[1]->ptr, port);
        sds client = catClientInfoString(sdsempty(),c);
        serverLog(LL_NOTICE,"XSLAVE OF %s:%d enabled (user request from '%s')",
            server.masterhost, server.masterport, client);
        sdsfree(client);

        /* reconnect to master immdediately */
        serverLog(LL_NOTICE,"XSLAVE OF %s:%d, connect to master immediately", server.masterhost, server.masterport);
        replicationCron();
    }
    addReply(c,shared.ok);
}

void initVectorClockCache() {
    VectorClock vectorClockCache = newVectorClock(0);
    int vlen = get_len(crdtServer.vectorClock);
    for(int i = 0; i < vlen; i++) {
        clk* current_clk = get_clock_unit_by_index(&crdtServer.vectorClock, i);
        int gid = get_gid(*current_clk);
        if (!(crdtServer.offline_peer_set & (1 << gid))) {
            vectorClockCache = addVectorClockUnit(vectorClockCache, gid, get_logic_clock(*current_clk));
        }
    }
    if (!isNullVectorClock(crdtServer.vectorClockCache)) {
        freeVectorClock(crdtServer.vectorClockCache);
    }
    crdtServer.vectorClockCache = vectorClockCache;
}

void setOfflinePeerSet(int gids) {
    if (crdtServer.offline_peer_set == gids) return;
    crdtServer.offline_peer_set = gids;
    if (gids == 0) {
        if (!isNullVectorClock(crdtServer.vectorClockCache )) {
            freeVectorClock(crdtServer.vectorClockCache);
            crdtServer.vectorClockCache = newVectorClock(0);
        }
    } else {
        initVectorClockCache();
    }
}

void setOfflineGidCommand(client *c) {
    int gids = 0;
    for(int i = 1; i < c->argc; i++) {
        long gid = 0;
        if ((getLongFromObjectOrReply(c, c->argv[i], &gid, NULL) != C_OK))
            return;
        if (gid > (1 << GIDSIZE)) {
            addReplyError(c, "peer gid invalid");
            return;
        }
        gids |= 1 << gid;
    }
    setOfflinePeerSet(gids);
    server.dirty++;
    if (server.configfile != NULL && rewriteConfig(server.configfile) == -1) {
        addReplyBulkCString(c,"OK,but save config fail");
        return;
    } 
    serverLog(LL_WARNING, "setOfflineGid  (%d)", crdtServer.offline_peer_set);
    addReply(c,shared.ok);
}

void getOfflineGidCommand(client *c) {
    sds gids = sdsempty();
    for(int i = 0; i < (1 << GIDSIZE); i++) {
        if(crdtServer.offline_peer_set & (1 << i)) {
            gids = sdscatprintf(gids, "%d ", i);
        }
    }
    addReplyBulkSds(c, sdstrim(gids, " "));
}