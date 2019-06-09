/*
 * Copyright (c) 2009-2012, CTRIP CORP <RDkjdata at ctrip dot com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */
//
// Created by zhuchen on 2019-05-05.
//

//#include "server.h"
#include "ctrip_crdt_replication.h"
#include "ctrip_crdt_rdb.h"

#include <sys/time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>




/**---------------------------CRDT Master Instance Related--------------------------------*/
CRDT_Master_Instance *createPeerMaster(client *c, long long gid) {
    CRDT_Master_Instance *masterInstance = zmalloc(sizeof(CRDT_Master_Instance));
    masterInstance->gid = gid;
    masterInstance->master = c;
    return masterInstance;
}

void freePeerMaster(CRDT_Master_Instance *masterInstance) {
    zfree(masterInstance->vectorClock);
    if (masterInstance->cached_master) {
        zfree(masterInstance->cached_master);
    }
    zfree(masterInstance);
}



/**---------------------------CRDT RDB Start/End Mark--------------------------------*/

/* This function aborts a non blocking replication attempt if there is one
 * in progress, by canceling the non-blocking connect attempt or
 * the initial bulk transfer.
 *
 * If there was a replication handshake in progress 1 is returned and
 * the replication state (server.repl_state) set to REPL_STATE_CONNECT.
 *
 * Otherwise zero is returned and no operation is perforemd at all. */
void crdtCancelReplicationHandshake(client *peer) {
    if (server.repl_state == REPL_STATE_TRANSFER) {
//        replicationAbortSyncTransfer();
        server.repl_state = REPL_STATE_CONNECT;
    } else if (server.repl_state == REPL_STATE_CONNECTING )
//               slaveIsInHandshakeState())
    {
//        undoConnectWithMaster();
        server.repl_state = REPL_STATE_CONNECT;
    }
//    else {
//        return 0;
//    }
//    return 1;
}

int listMatchCrdtMaster(void *a, void *b) {
    CRDT_Master_Instance *ma = a, *mb = b;
    return ma->gid == mb->gid;
}


//CRDT.START_MERGE <gid> <vector-clock> <repl_id>
void
crdtMergeStartCommand(client *c) {
    listIter li;
    listNode *ln;
    CRDT_Master_Instance *peerMaster = NULL;
    long long sourceGid;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;
    listRewind(crdtServer.crdtMasters, &li);
    while((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;
        if (crdtMaster->gid == sourceGid) {
            peerMaster = crdtMaster;
            break;
        }
    }
    if (!peerMaster) {
        peerMaster = createPeerMaster(c, sourceGid);
    }
    memcpy(peerMaster->master_replid, c->argv[3]->ptr, sizeof(peerMaster->master_replid));
}

//CRDT.END_MERGE <gid> <vector-clock> <repl_id> <offset>
// 0               1        2            3          4
void
crdtMergeEndCommand(client *c) {
    listIter li;
    listNode *ln;
    CRDT_Master_Instance *peerMaster = NULL;

    long long sourceGid, offset;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;

    listRewind(crdtServer.crdtMasters, &li);
    while((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;
        if (crdtMaster->gid == sourceGid) {
            peerMaster = crdtMaster;
            break;
        }
    }
    if (!peerMaster) goto err;

    peerMaster->vectorClock = sdsToVectorClock(c->argv[2]->ptr);
    memcpy(peerMaster->master_replid, c->argv[3]->ptr, sizeof(peerMaster->master_replid));
    if (getLongLongFromObjectOrReply(c, c->argv[4], &offset, NULL) != C_OK) return;
    peerMaster->master_initial_offset = offset;
    addReply(c, shared.ok);
    return;

err:
    addReply(c, shared.crdtmergeerr);
    crdtCancelReplicationHandshake(c);
    return;
}

/** ================================== CRDT Repl MASTER ================================== */




///*  =================================================================== CRDT Repl Slave ======================================================================  */
crdtRdbSaveInfo*
crdtRdbPopulateSaveInfo(crdtRdbSaveInfo *rsi) {
    crdtRdbSaveInfo rsi_init = CRDT_RDB_SAVE_INFO_INIT;
    *rsi = rsi_init;

    if(crdtServer.repl_backlog) {
        /* Note that when server.slaveseldb is -1, it means that this master
         * didn't apply any write commands after a full synchronization.
         * So we can let repl_stream_db be 0, this allows a restarted slave
         * to reload replication ID/offset, it's safe because the next write
         * command must generate a SELECT statement. */
        rsi->repl_stream_db = crdtServer.slaveseldb == -1 ? 0 : crdtServer.slaveseldb;
    }

    return NULL;
}
/* --------------------------- REPLICATION CRON  ---------------------------- */

int startCrdtBgsaveForReplication() {
    int retval;
    listIter li;
    listNode *ln;

    serverLog(LL_NOTICE,"Starting BGSAVE for SYNC with target: Crdt Merge");

    crdtRdbSaveInfo rsi, *rsiptr;
    rsiptr = crdtRdbPopulateSaveInfo(&rsi);
    /* Only do rdbSave* when rsiptr is not NULL,
     * otherwise slave will miss repl-stream-db. */
    if (rsiptr) {
        retval = rdbSaveToSlavesSockets(rsiptr, &crdtServer);
    } else {
        serverLog(LL_WARNING,"BGSAVE for replication: replication information not available, can't generate the RDB file right now. Try later.");
        retval = C_ERR;
    }

    /* If we failed to BGSAVE, remove the slaves waiting for a full
     * resynchorinization from the list of salves, inform them with
     * an error about what happened, close the connection ASAP. */
    if (retval == C_ERR) {
        serverLog(LL_WARNING,"BGSAVE for replication failed");
        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;

            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) {
                slave->flags &= ~CLIENT_CRDT_SLAVE;
                listDelNode(crdtServer.slaves,ln);
                addReplyError(slave,
                              "BGSAVE failed, replication can't continue");
                slave->flags |= CLIENT_CLOSE_AFTER_REPLY;
            }
        }
    }

    return retval;

}

/* Replication cron function, called 1 time per second. */
void crdtReplicationCron(void) {
    static long long replication_cron_loops = 0;
    listIter li;
    listNode *ln;
    /* Non blocking connection timeout? */

    listRewind(crdtServer.crdtMasters, &li);
    while((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;

//
//        if (crdtServer.masterhost &&
//            (crdtServer.repl_state == REPL_STATE_CONNECTING ||
//             slaveIsInHandshakeState()) &&
//            (time(NULL) - crdtServer.repl_transfer_lastio) > crdtServer.repl_timeout) {
//            serverLog(LL_WARNING, "Timeout connecting to the MASTER...");
//            crdtCancelReplicationHandshake();
//        }
//
//        /* Bulk transfer I/O timeout? */
//        if (crdtServer.masterhost && crdtServer.repl_state == REPL_STATE_TRANSFER &&
//            (time(NULL) - crdtServer.repl_transfer_lastio) > crdtServer.repl_timeout) {
//            serverLog(LL_WARNING,
//                      "Timeout receiving bulk data from MASTER... If the problem persists try to set the 'repl-timeout' parameter in redis.conf to a larger value.");
//            cancelReplicationHandshake();
//        }
//
//        /* Timed out master when we are an already connected slave? */
//        if (crdtServer.masterhost && crdtServer.repl_state == REPL_STATE_CONNECTED &&
//            (time(NULL) - crdtServer.master->lastinteraction) > crdtServer.repl_timeout) {
//            serverLog(LL_WARNING, "MASTER timeout: no data nor PING received...");
//            freeClient(crdtServer.master);
//        }
//
//        /* Check if we should connect to a MASTER */
//        if (crdtServer.repl_state == REPL_STATE_CONNECT) {
//            serverLog(LL_NOTICE, "Connecting to MASTER %s:%d",
//                      crdtServer.masterhost, crdtServer.masterport);
//            if (connectWithMaster() == C_OK) {
//                serverLog(LL_NOTICE, "MASTER <-> SLAVE sync started");
//            }
//        }
//
//        /* Send ACK to master from time to time.
//         * Note that we do not send periodic acks to masters that don't
//         * support PSYNC and replication offsets. */
//        if (crdtServer.masterhost && crdtServer.master &&
//            !(crdtServer.master->flags & CLIENT_PRE_PSYNC))
//            replicationSendAck();
    }
    /* If we have attached slaves, PING them from time to time.
     * So slaves can implement an explicit timeout to masters, and will
     * be able to detect a link disconnection even if the TCP connection
     * will not actually go down. */
    robj *ping_argv[1];

    /* First, send PING according to ping_slave_period. */
    if ((replication_cron_loops % crdtServer.repl_ping_slave_period) == 0 &&
        listLength(crdtServer.slaves))
    {
        ping_argv[0] = createStringObject("PING",4);
        replicationFeedSlaves(&crdtServer, crdtServer.slaves, crdtServer.slaveseldb,
                              ping_argv, 1);
        decrRefCount(ping_argv[0]);
    }

    /* Second, send a newline to all the slaves in pre-synchronization
     * stage, that is, slaves waiting for the master to create the RDB file.
     *
     * Also send the a newline to all the chained slaves we have, if we lost
     * connection from our master, to keep the slaves aware that their
     * master is online. This is needed since sub-slaves only receive proxied
     * data from top-level masters, so there is no explicit pinging in order
     * to avoid altering the replication offsets. This special out of band
     * pings (newlines) can be sent, they will have no effect in the offset.
     *
     * The newline will be ignored by the slave but will refresh the
     * last interaction timer preventing a timeout. In this case we ignore the
     * ping period and refresh the connection once per second since certain
     * timeouts are set at a few seconds (example: PSYNC response). */
    listRewind(crdtServer.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;

        int is_presync =
                (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START ||
                 (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_END &&
                  crdtServer.rdb_child_type != RDB_CHILD_TYPE_SOCKET));

        if (is_presync) {
            if (write(slave->fd, "\n", 1) == -1) {
                /* Don't worry about socket errors, it's just a ping. */
            }
        }
    }

    /* Disconnect timedout slaves. */
    if (listLength(crdtServer.slaves)) {
        listIter li;
        listNode *ln;

        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;

            if (slave->replstate != SLAVE_STATE_ONLINE) continue;
            if (slave->flags & CLIENT_PRE_PSYNC) continue;
            if ((crdtServer.unixtime - slave->repl_ack_time) > crdtServer.repl_timeout)
            {
                serverLog(LL_WARNING, "Disconnecting timedout slave: %s",
                          replicationGetSlaveName(slave));
                freeClient(slave);
            }
        }
    }

    /* If this is a master without attached slaves and there is a replication
     * backlog active, in order to reclaim memory we can free it after some
     * (configured) time. Note that this cannot be done for slaves: slaves
     * without sub-slaves attached should still accumulate data into the
     * backlog, in order to reply to PSYNC queries if they are turned into
     * masters after a failover. */
    if (listLength(crdtServer.slaves) == 0 && crdtServer.repl_backlog_time_limit &&
        crdtServer.repl_backlog)
    {
        time_t idle = crdtServer.unixtime - crdtServer.repl_no_slaves_since;

        if (idle > crdtServer.repl_backlog_time_limit) {
            /* When we free the backlog, we always use a new
             * replication ID and clear the ID2. This is needed
             * because when there is no backlog, the master_repl_offset
             * is not updated, but we would still retain our replication
             * ID, leading to the following problem:
             *
             * 1. We are a master instance.
             * 2. Our slave is promoted to master. It's repl-id-2 will
             *    be the same as our repl-id.
             * 3. We, yet as master, receive some updates, that will not
             *    increment the master_repl_offset.
             * 4. Later we are turned into a slave, connecto to the new
             *    master that will accept our PSYNC request by second
             *    replication ID, but there will be data inconsistency
             *    because we received writes. */
            changeReplicationId(&crdtServer);
            clearReplicationId2(&crdtServer);
            freeReplicationBacklog(&crdtServer);
            serverLog(LL_NOTICE,
                      "Replication backlog freed after %d seconds "
                      "without connected slaves.",
                      (int) crdtServer.repl_backlog_time_limit);
        }
    }

    /* Start a BGSAVE good for replication if we have slaves in
     * WAIT_BGSAVE_START state.
     *
     * In case of diskless replication, we make sure to wait the specified
     * number of seconds (according to configuration) so that other slaves
     * have the time to arrive before we start streaming. */
    if (crdtServer.rdb_child_pid == -1 && crdtServer.aof_child_pid == -1) {
        time_t idle, max_idle = 0;
        int slaves_waiting = 0;
        int mincapa = -1;
        listNode *ln;
        listIter li;

        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) {
                idle = crdtServer.unixtime - slave->lastinteraction;
                if (idle > max_idle) max_idle = idle;
                slaves_waiting++;
                mincapa = (mincapa == -1) ? slave->slave_capa :
                          (mincapa & slave->slave_capa);
            }
        }

        if (slaves_waiting &&
            (!crdtServer.repl_diskless_sync ||
             max_idle > crdtServer.repl_diskless_sync_delay))
        {
            /* Start the BGSAVE. The called function may start a
             * BGSAVE with socket target or disk target depending on the
             * configuration and slaves capabilities. */
            startCrdtBgsaveForReplication();
        }
    }

    /* Refresh the number of slaves with lag <= min-slaves-max-lag. */
    refreshGoodSlavesCount(&crdtServer);
    replication_cron_loops++; /* Incremented with frequency 1 HZ. */
}
