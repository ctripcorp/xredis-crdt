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

void crdtReplicationResurrectCachedMaster(CRDT_Master_Instance *crdtMaster, int newfd);
void crdtReplicationDiscardCachedMaster(CRDT_Master_Instance *crdtMaster);



/**---------------------------CRDT Master Instance Related--------------------------------*/

CRDT_Master_Instance *createPeerMaster(client *c, int gid) {
    CRDT_Master_Instance *masterInstance = zmalloc(sizeof(CRDT_Master_Instance));
    masterInstance->gid = gid;
    masterInstance->master = c;
    masterInstance->repl_transfer_s = -1;
    masterInstance->cached_master = NULL;
    masterInstance->repl_down_since = 0;
    masterInstance->repl_state = REPL_STATE_NONE;
    masterInstance->master_initial_offset = -1;
    masterInstance->masterhost = NULL;
    masterInstance->masterport = -1;
    masterInstance->masterauth = NULL;
    masterInstance->vectorClock = newVectorClock(0);
    masterInstance->repl_transfer_lastio = mstime();
    return masterInstance;
}

void freePeerMaster(CRDT_Master_Instance *masterInstance) {
    if (!masterInstance) {
        return;
    }
    int gid = (int) masterInstance->gid;
    crdtServer.crdtMasters[gid] = NULL;
    if(masterInstance->masterhost) {
        sdsfree(masterInstance->masterhost);
        masterInstance->masterhost = NULL;
    }
    if(!isNullVectorClock(masterInstance->vectorClock)) {
        freeVectorClock(masterInstance->vectorClock);
        masterInstance->vectorClock = newVectorClock(0);
    }
    if (masterInstance->master) {
        masterInstance->master->flags &= ~CLIENT_CRDT_MASTER;
        masterInstance->master->peer_master = NULL;
        freeClient(masterInstance->master);
        masterInstance->master = NULL;
    }
    if (masterInstance->cached_master) {
        masterInstance->cached_master->flags &= ~CLIENT_CRDT_MASTER;
        masterInstance->cached_master->peer_master = NULL;
        freeClient(masterInstance->cached_master);
        masterInstance->cached_master = NULL;
    }
    zfree(masterInstance);

}

CRDT_Master_Instance *getPeerMaster(int gid) {
    return crdtServer.crdtMasters[gid];
}

void refreshVectorClock(client *c, sds vcStr) {
    VectorClock vclock = sdsToVectorClock(vcStr);
    if(!isNullVectorClock(c->vectorClock)) {
        freeVectorClock(c->vectorClock);
        c->vectorClock = newVectorClock(0);
    }
    c->vectorClock = vclock;
}

void crdtReplicationSendAck(CRDT_Master_Instance *masterInstance) {
    client *c = masterInstance->master;

    if (c != NULL) {
        c->flags |= CLIENT_MASTER_FORCE_REPLY;
        addReplyMultiBulkLen(c,3);
        addReplyBulkCString(c,"CRDT.REPLCONF");
        addReplyBulkCString(c,"ACK-VC");
        sds vclockSds = vectorClockToSds(crdtServer.vectorClock);
        addReplyBulkCBuffer(c, vclockSds, sdslen(vclockSds));
        sdsfree(vclockSds);

        addReplyMultiBulkLen(c,3);
        addReplyBulkCString(c,"CRDT.REPLCONF");
        addReplyBulkCString(c,"ACK");
        addReplyBulkLongLong(c,c->reploff);
        c->flags &= ~CLIENT_MASTER_FORCE_REPLY;
    }
}

// peerof <gid> <ip> <port>
//  0       1    2    3
void peerofCommand(client *c) {
    /* PEEROF is not allowed in cluster mode as replication is automatically
    * configured using the current address of the master node. */
    if (server.cluster_enabled) {
        addReplyError(c,"PEEROF not allowed in cluster mode.");
        return;
    }

    long port;
    long long gid;
    if ((getLongLongFromObjectOrReply(c, c->argv[1], &gid, NULL) != C_OK))
        return;
    if (gid == crdtServer.crdt_gid) {
        addReplyError(c,"invalid gid");
        return ;
    }
    if (!strcasecmp(c->argv[2]->ptr,"no") &&
        !strcasecmp(c->argv[3]->ptr,"one")) {

        if (getPeerMaster(gid)) {
            crdtReplicationUnsetMaster(gid);
            sds client = catClientInfoString(sdsempty(),c);
            serverLog(LL_NOTICE,"[CRDT] REMOVE MASTER %lld enabled (user request from '%s')",
                      gid, client);
            sdsfree(client);
        }

        server.dirty ++;
        addReply(c, shared.ok);
        return;
    }

    if ((getLongFromObjectOrReply(c, c->argv[3], &port, NULL) != C_OK))
        return;

    /* Check if we are already attached to the specified master */
    CRDT_Master_Instance *peerMaster = getPeerMaster(gid);
    if(peerMaster && !strcasecmp(peerMaster->masterhost, c->argv[2]->ptr)
       && peerMaster->masterport == port) {
        serverLog(LL_NOTICE,"[CRDT]PEER OF would result into synchronization with the master we are already connected with. No operation performed.");
        addReplySds(c,sdsnew("+OK Already connected to specified master\r\n"));
        return;
    }


    /* There was no previous master or the user specified a different one,
     * we can continue. */
    crdtReplicationSetMaster(gid, c->argv[2]->ptr, (int)port);
    peerMaster = getPeerMaster(gid);
    if (isMasterMySelf() == C_OK) {
        sds client = catClientInfoString(sdsempty(), c);
        serverLog(LL_NOTICE, "[CRDT]PEER OF %lld %s:%d enabled (user request from '%s')",
                  gid, peerMaster->masterhost, peerMaster->masterport, client);
        sdsfree(client);
    } 
    server.dirty ++;
    addReply(c,shared.ok);
}

void crdtReplicationSetMaster(int gid, char *ip, int port) {

    CRDT_Master_Instance *peerMaster = getPeerMaster(gid);
    if (!peerMaster) {
        peerMaster = createPeerMaster(NULL, gid);
        crdtServer.crdtMasters[gid] = peerMaster;
    }
    if (peerMaster->masterhost != NULL) {
        sdsfree(peerMaster->masterhost);
    }
    peerMaster->masterhost = sdsnew(ip);
    peerMaster->masterport = port;
    if (peerMaster->master) {
        freeClient(peerMaster->master);
    } 
    crdtCancelReplicationHandshake(gid);
    
    peerMaster->repl_state = REPL_STATE_CONNECT;
    peerMaster->repl_down_since = 0;
}

/* Cancel replication, setting the instance as a master itself. */
void crdtReplicationUnsetMaster(int gid) {
    CRDT_Master_Instance *peerMaster;
    if ((peerMaster = getPeerMaster(gid)) == NULL) return;
    if(peerMaster->masterhost) {
        sdsfree(peerMaster->masterhost);
        peerMaster->masterhost = NULL;
    }
    crdtReplicationDiscardCachedMaster(peerMaster);
    crdtCancelReplicationHandshake(gid);
    freePeerMaster(peerMaster);
}


/**---------------------------CRDT RDB Start/End Mark--------------------------------*/


//CRDT.START_MERGE <gid> <vector-clock> <repl_id> <repl_offset>
void
crdtMergeStartCommand(client *c) {
    serverLog(LL_NOTICE, "[CRDT][crdtMergeStartCommand][begin]");
    long long sourceGid;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;
    if(!check_gid(sourceGid)) { return; }
    CRDT_Master_Instance *peerMaster = getPeerMaster(sourceGid);
    //clear cache_master and master
    if(peerMaster->master) {
        peerMaster->master->flags &= ~CLIENT_CRDT_MASTER;
        peerMaster->master->peer_master = NULL;
        freeClient(peerMaster->master);
        peerMaster->master = NULL;
    }
    if(peerMaster->cached_master) {
        peerMaster->cached_master->flags &= ~CLIENT_CRDT_MASTER;
        peerMaster->cached_master->peer_master = NULL;
        freeClient(peerMaster->cached_master);
        peerMaster->cached_master = NULL;
    }
    peerMaster->repl_transfer_lastio = server.unixtime;
    VectorClock vclock = sdsToVectorClock(c->argv[2]->ptr);
    VectorClock curGcVclock = crdtServer.gcVectorClock;
    crdtServer.gcVectorClock = vectorClockMerge(crdtServer.gcVectorClock, vclock);
    if (isNullVectorClockUnit(getVectorClockUnit(crdtServer.vectorClock, sourceGid))) {
        crdtServer.vectorClock = addVectorClockUnit(crdtServer.vectorClock, sourceGid, 0);
    }
    freeVectorClock(vclock);;
    freeVectorClock(curGcVclock);
    server.dirty ++;
    serverLog(LL_NOTICE, "[CRDT][crdtMergeStartCommand][end] master gid: %lld", sourceGid);
}

//CRDT.END_MERGE <gid> <vector-clock> <repl_id> <offset>
// 0               1        2            3          4
void
crdtMergeEndCommand(client *c) {
    long long sourceGid, offset;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;
    if(!check_gid(sourceGid)) goto err;
    CRDT_Master_Instance *peerMaster = getPeerMaster(sourceGid);
    peerMaster->repl_transfer_lastio = server.unixtime;
    if (!peerMaster) goto err;
    serverLog(LL_NOTICE, "[CRDT][crdtMergeEndCommand][begin] master gid: %lld", sourceGid);

    if (!isNullVectorClock(peerMaster->vectorClock)) {
        freeVectorClock(peerMaster->vectorClock);
    }
    peerMaster->vectorClock = sdsToVectorClock(c->argv[2]->ptr);
    mergeLogicClock(&crdtServer.vectorClock, &peerMaster->vectorClock, sourceGid);
    refreshGcVectorClock(peerMaster->vectorClock);
    if (getLongLongFromObjectOrReply(c, c->argv[4], &offset, NULL) != C_OK) return;
    if(isMasterMySelf() == C_OK) {
        crdtReplicationCreateMasterClient(peerMaster, c, -1);
        crdtReplicationSendAck(c->peer_master);
        peerMaster->repl_state = REPL_STATE_CONNECTED;
    } else {
        memcpy(peerMaster->master_replid, c->argv[3]->ptr, sdslen(c->argv[3]->ptr));
        peerMaster->master_initial_offset = offset;
        crdtReplicationCreateMasterClient(peerMaster, createClient(-1), -1);
    }
    server.dirty ++;
    serverLog(LL_NOTICE, "[CRDT][crdtMergeEndCommand][end] master gid: %lld", sourceGid);
    return;

err:
    serverLog(LL_NOTICE, "[CRDT][crdtMergeEndCommand][crdtCancelReplicationHandshake] master gid: %lld", sourceGid);
    if (isMasterMySelf() == C_OK) {
        crdtCancelReplicationHandshake(sourceGid);
    }
    return;
}

/** ================================== CRDT Repl MASTER ================================== */

long long getMyGidLogicTime(VectorClock vc) {
    if (isNullVectorClock(vc)) {
        return 0;
    }
    VectorClockUnit vcu = getVectorClockUnit(vc, crdtServer.crdt_gid);
    if (isNullVectorClockUnit(vcu)) {
        return 0;
    }
    return get_logic_clock(vcu);
}

long long getMyLogicTime() {
    return getMyGidLogicTime(crdtServer.vectorClock);
}


///*  =================================================================== CRDT Repl Slave ======================================================================  */
crdtRdbSaveInfo*
crdtRdbPopulateSaveInfo(crdtRdbSaveInfo *rsi, long long min_logic_time) {
    crdtRdbSaveInfo rsi_init = CRDT_RDB_SAVE_INFO_INIT;
    *rsi = rsi_init;

    if(crdtServer.repl_backlog) {
        /* Note that when server.slaveseldb is -1, it means that this master
         * didn't apply any write commands after a full synchronization.
         * So we can let repl_stream_db be 0, this allows a restarted slave
         * to reload replication ID/offset, it's safe because the next write
         * command must generate a SELECT statement. */
        rsi->repl_stream_db = crdtServer.slaveseldb == -1 ? 0 : crdtServer.slaveseldb;
        rsi->repl_offset = getPsyncInitialOffset(&crdtServer);
        memcpy(rsi->repl_id, crdtServer.replid, CONFIG_RUN_ID_SIZE);
        rsi->repl_id[CONFIG_RUN_ID_SIZE] = '\0';
        rsi->logic_time = min_logic_time;
        return rsi;
    }
    return NULL;
}

/* Returns 1 if the given replication state is a handshake state,
 * 0 otherwise. */
int crdtSlaveIsInHandshakeState(CRDT_Master_Instance *crdtMaster) {
    return crdtMaster->repl_state >= REPL_STATE_RECEIVE_PONG &&
           crdtMaster->repl_state <= REPL_STATE_RECEIVE_PSYNC;
}

#define SYNC_CMD_READ (1<<0)
#define SYNC_CMD_WRITE (1<<1)
#define SYNC_CMD_FULL (SYNC_CMD_READ|SYNC_CMD_WRITE)
char *crdtSendSynchronousCommand(CRDT_Master_Instance *crdtMaster, int flags, int fd, ...) {

    /* Create the command to send to the master, we use simple inline
     * protocol for simplicity as currently we only send simple strings. */
    if (flags & SYNC_CMD_WRITE) {
        char *arg;
        va_list ap;
        sds cmd = sdsempty();
        va_start(ap,fd);

        while(1) {
            arg = va_arg(ap, char*);
            if (arg == NULL) break;
            if (sdslen(cmd) != 0) cmd = sdscatlen(cmd," ",1);
            cmd = sdscat(cmd,arg);
        }
        cmd = sdscatlen(cmd,"\r\n",2);
        va_end(ap);

        /* Transfer command to the server. */
        if (syncWrite(fd,cmd,sdslen(cmd),crdtServer.repl_syncio_timeout*1000)
            == -1)
        {
            sdsfree(cmd);
            return sdscatprintf(sdsempty(),"-Writing to ip: %s port: %d error: %s",
                                crdtMaster->masterhost, crdtMaster->masterport, strerror(errno));
        }
        sdsfree(cmd);
    }

    /* Read the reply from the server. */
    if (flags & SYNC_CMD_READ) {
        char buf[256];

        if (syncReadLine(fd,buf,sizeof(buf),crdtServer.repl_syncio_timeout*1000)
            == -1)
        {
            return sdscatprintf(sdsempty(),"-Reading from ip: %s port: %d, error: %s",
                                crdtMaster->masterhost, crdtMaster->masterport, strerror(errno));
        }
        crdtMaster->repl_transfer_lastio = server.unixtime;
        return sdsnew(buf);
    }
    return NULL;
}

/* Try a partial resynchronization with the master if we are about to reconnect.
 * If there is no cached master structure, at least try to issue a
 * "PSYNC ? -1" command in order to trigger a full resync using the PSYNC
 * command in order to obtain the master run id and the master replication
 * global offset.
 *
 * This function is designed to be called from syncWithMaster(), so the
 * following assumptions are made:
 *
 * 1) We pass the function an already connected socket "fd".
 * 2) This function does not close the file descriptor "fd". However in case
 *    of successful partial resynchronization, the function will reuse
 *    'fd' as file descriptor of the server.master client structure.
 *
 * The function is split in two halves: if read_reply is 0, the function
 * writes the PSYNC command on the socket, and a new function call is
 * needed, with read_reply set to 1, in order to read the reply of the
 * command. This is useful in order to support non blocking operations, so
 * that we write, return into the event loop, and read when there are data.
 *
 * When read_reply is 0 the function returns PSYNC_WRITE_ERR if there
 * was a write error, or PSYNC_WAIT_REPLY to signal we need another call
 * with read_reply set to 1. However even when read_reply is set to 1
 * the function may return PSYNC_WAIT_REPLY again to signal there were
 * insufficient data to read to complete its work. We should re-enter
 * into the event loop and wait in such a case.
 *
 * The function returns:
 *
 * PSYNC_CONTINUE: If the PSYNC command succeded and we can continue.
 * PSYNC_FULLRESYNC: If PSYNC is supported but a full resync is needed.
 *                   In this case the master run_id and global replication
 *                   offset is saved.
 * PSYNC_NOT_SUPPORTED: If the server does not understand PSYNC at all and
 *                      the caller should fall back to SYNC.
 * PSYNC_WRITE_ERROR: There was an error writing the command to the socket.
 * PSYNC_WAIT_REPLY: Call again the function with read_reply set to 1.
 * PSYNC_TRY_LATER: Master is currently in a transient error condition.
 *
 * Notable side effects:
 *
 * 1) As a side effect of the function call the function removes the readable
 *    event handler from "fd", unless the return value is PSYNC_WAIT_REPLY.
 * 2) server.master_initial_offset is set to the right value according
 *    to the master reply. This will be used to populate the 'server.master'
 *    structure replication offset.
 */

#define PSYNC_WRITE_ERROR 0
#define PSYNC_WAIT_REPLY 1
#define PSYNC_CONTINUE 2
#define PSYNC_FULLRESYNC 3
#define PSYNC_NOT_SUPPORTED 4
#define PSYNC_TRY_LATER 5

int crdtSlaveTryPartialResynchronization(CRDT_Master_Instance *masterInstance, int fd, int read_reply) {
    char *psync_replid;
    char psync_offset[32];
    sds reply;

    /* Writing half */
    if (!read_reply) {
        /* Initially set master_initial_offset to -1 to mark the current
         * master run_id and offset as not valid. Later if we'll be able to do
         * a FULL resync using the PSYNC command we'll set the offset at the
         * right value, so that this information will be propagated to the
         * client structure representing the master into server.master. */
        masterInstance->master_initial_offset = -1;

        if (masterInstance->cached_master) {
            psync_replid = masterInstance->cached_master->replid;
            snprintf(psync_offset,sizeof(psync_offset),"%lld", masterInstance->cached_master->reploff+1);
            serverLog(LL_NOTICE,"[CRDT]Trying a partial resynchronization (request %s:%s).", psync_replid, psync_offset);
        } else {
            serverLog(LL_NOTICE,"[CRDT]Partial resynchronization not possible (no cached master)");
            psync_replid = "?";
            memcpy(psync_offset,"-1",3);
        }

        /* Issue the PSYNC command */
        reply = crdtSendSynchronousCommand(masterInstance, SYNC_CMD_WRITE, fd, "CRDT.PSYNC", psync_replid, psync_offset, NULL);
        if (reply != NULL) {
            serverLog(LL_WARNING,"[CRDT]Unable to send PSYNC to master: %s",reply);
            sdsfree(reply);
            aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE);
            return PSYNC_WRITE_ERROR;
        }
        return PSYNC_WAIT_REPLY;
    }

    /* Reading half */
    reply = crdtSendSynchronousCommand(masterInstance, SYNC_CMD_READ, fd, NULL);
    if (sdslen(reply) == 0) {
        /* The master may send empty newlines after it receives PSYNC
         * and before to reply, just to keep the connection alive. */
        sdsfree(reply);
        return PSYNC_WAIT_REPLY;
    }

    aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE);

    if (!strncmp(reply,"+FULLRESYNC",11)) {
        char *replid = NULL, *offset = NULL;

        /* FULL RESYNC, parse the reply in order to extract the run id
         * and the replication offset. */
        replid = strchr(reply,' ');
        if (replid) {
            replid++;
            offset = strchr(replid,' ');
            if (offset) offset++;
        }
        if (!replid || !offset || (offset-replid-1) != CONFIG_RUN_ID_SIZE) {
            serverLog(LL_WARNING,
                      "[CRDT]Master replied with wrong +FULLRESYNC syntax.");
            /* This is an unexpected condition, actually the +FULLRESYNC
             * reply means that the master supports PSYNC, but the reply
             * format seems wrong. To stay safe we blank the master
             * replid to make sure next PSYNCs will fail. */
            memset(masterInstance->master_replid,0,CONFIG_RUN_ID_SIZE+1);
        } else {
            memcpy(masterInstance->master_replid, replid, offset-replid-1);
            masterInstance->master_replid[CONFIG_RUN_ID_SIZE] = '\0';
            masterInstance->master_initial_offset = strtoll(offset,NULL,10);
            serverLog(LL_NOTICE,"[CRDT] Full resync from master: %s:%lld",
                      masterInstance->master_replid,
                      masterInstance->master_initial_offset);
        }

        /* We are going to full resync, discard the cached master structure. */
        crdtReplicationDiscardCachedMaster(masterInstance);
        sdsfree(reply);
        return PSYNC_FULLRESYNC;
    }

    if (!strncmp(reply,"+CONTINUE",9)) {
        /* Partial resync was accepted. */
        serverLog(LL_NOTICE,
                  "[CRDT] Successful partial resynchronization with master.");

        /* Check the new replication ID advertised by the master. If it
         * changed, we need to set the new ID as primary ID, and set or
         * secondary ID as the old master ID up to the current offset, so
         * that our sub-slaves will be able to PSYNC with us after a
         * disconnection. */
        char *start = reply+10;
        char *end = reply+9;
        while(end[0] != '\r' && end[0] != '\n' && end[0] != '\0') end++;
        if (end-start == CONFIG_RUN_ID_SIZE) {
            char new[CONFIG_RUN_ID_SIZE+1];
            memcpy(new,start,CONFIG_RUN_ID_SIZE);
            new[CONFIG_RUN_ID_SIZE] = '\0';

            serverLog(LL_WARNING,"Master replication ID changed to %s",new);

            memcpy(masterInstance->master_replid, new, CONFIG_RUN_ID_SIZE);
            masterInstance->master_replid[CONFIG_RUN_ID_SIZE] = '\0';
        }

        /* Setup the replication to continue. */
        sdsfree(reply);

        crdtReplicationResurrectCachedMaster(masterInstance, fd);

        /* If this instance was restarted and we read the metadata to
         * PSYNC from the persistence file, our replication backlog could
         * be still not initialized. Create it. */
        if (crdtServer.repl_backlog == NULL) createReplicationBacklog();
        return PSYNC_CONTINUE;
    }

    /* If we reach this point we received either an error (since the master does
     * not understand PSYNC or because it is in a special state and cannot
     * serve our request), or an unexpected reply from the master.
     *
     * Return PSYNC_NOT_SUPPORTED on errors we don't understand, otherwise
     * return PSYNC_TRY_LATER if we believe this is a transient error. */

    if (!strncmp(reply,"-NOMASTERLINK",13) ||
        !strncmp(reply,"-LOADING",8))
    {
        serverLog(LL_NOTICE,
                  "[CRDT] Master is currently unable to PSYNC "
                  "but should be in the future: %s", reply);
        sdsfree(reply);
        return PSYNC_TRY_LATER;
    }

    if (strncmp(reply,"-ERR",4)) {
        /* If it's not an error, log the unexpected event. */
        serverLog(LL_WARNING,
                  "[CRDT] Unexpected reply to CRDT.PSYNC from master: %s", reply);
    } else {
        serverLog(LL_NOTICE,
                  "[CRDT] Master does not support CRDT.PSYNC or is in "
                  "error state (reply: %s)", reply);
    }
    sdsfree(reply);
    crdtReplicationDiscardCachedMaster(masterInstance);
    return PSYNC_NOT_SUPPORTED;
}

/* This handler fires when the non blocking connect was able to
 * establish a connection with the master. */
void crdtSyncWithMaster(aeEventLoop *el, int fd, void *privdata, int mask) {
    char *err = NULL;
    int sockerr = 0, psync_result;
    socklen_t errlen = sizeof(sockerr);
    UNUSED(el);
    UNUSED(mask);

    CRDT_Master_Instance *crdtMaster = (CRDT_Master_Instance *) privdata;

    /* If this event fired after the user turned the instance into a master
     * with SLAVEOF NO ONE we must just return ASAP. */
    if (crdtMaster->repl_state == REPL_STATE_NONE) {
        close(fd);
        return;
    }

    /* Check for errors in the socket: after a non blocking connect() we
     * may find that the socket is in error state. */
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &sockerr, &errlen) == -1)
        sockerr = errno;
    if (sockerr) {
        serverLog(LL_WARNING,"[CRDT] Error condition on socket for SYNC: %s",
                  strerror(sockerr));
        goto error;
    }

    /* Send a PING to check the master is able to reply without errors. */
    if (crdtMaster->repl_state == REPL_STATE_CONNECTING) {
        serverLog(LL_NOTICE,"[CRDT] Non blocking connect for SYNC fired the event.");
        /* Delete the writable event so that the readable event remains
         * registered and we can wait for the PONG reply. */
        aeDeleteFileEvent(crdtServer.el,fd,AE_WRITABLE);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_PONG;
        /* Send the PING, don't check for errors at all, we have the timeout
         * that will take care about this. */
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "PING", NULL);
        if (err) goto write_error;
        return;
    }

    /* Receive the PONG command. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_PONG) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);

        /* We accept only two replies as valid, a positive +PONG reply
         * (we just check for "+") or an authentication error.
         * Note that older versions of Redis replied with "operation not
         * permitted" instead of using a proper error code, so we test
         * both. */
        if (err[0] != '+' &&
            strncmp(err,"-NOAUTH",7) != 0 &&
            strncmp(err,"-ERR operation not permitted",28) != 0)
        {
            serverLog(LL_WARNING,"Error reply to PING from master: '%s'",err);
            sdsfree(err);
            goto error;
        } else {
            serverLog(LL_NOTICE,
                      "[CRDT]Crdt Master replied to PING, replication can continue...");
        }
        sdsfree(err);
        // crdtMaster->repl_state = REPL_STATE_SEND_AUTH;
        crdtMaster->repl_state = REPL_STATE_SEND_CRDT_AUTH;
    }
    if(crdtMaster->repl_state == REPL_STATE_SEND_CRDT_AUTH) {
        sds gid = sdsfromlonglong(crdtMaster->gid);
        sds namespace = sdsnew(crdtServer.crdt_namespace);
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "CRDT.AUTH", namespace, gid, NULL);
        sdsfree(gid);
        sdsfree(namespace);
        if (err) {
            sdsfree(err);
            goto write_error;
        }
        crdtMaster->repl_state = REPL_STATE_RECEIVE_CRDT_AUTH;
        return;
    } 

    if(crdtMaster->repl_state == REPL_STATE_RECEIVE_CRDT_AUTH) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"[CRDT] Unable to Namespace and GID to MASTER namespace :%s, gid: %lld , error: '%s'", 
                    crdtServer.crdt_namespace,crdtMaster->gid, err);
            sdsfree(err);
            goto error;
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_AUTH;
    }

    /* AUTH with the master if required. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_AUTH) {
        if (crdtMaster->masterauth) {
            err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "AUTH", crdtMaster->masterauth, NULL);
            if (err) goto write_error;
            crdtMaster->repl_state = REPL_STATE_RECEIVE_AUTH;
            return;
        } else {
            crdtMaster->repl_state = REPL_STATE_SEND_PORT;
        }
    }

    /* Receive AUTH reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_AUTH) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        if (err[0] == '-') {
            serverLog(LL_WARNING,"[CRDT]Unable to AUTH to MASTER: %s",err);
            sdsfree(err);
            goto error;
        } else {
            serverLog(LL_WARNING,"[CRDT]AUTH to MASTER Succeed");
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_PORT;
    }

    /* Set the slave port, so that Master's INFO command can list the
     * slave listening port correctly. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_PORT) {
        sds port = sdsfromlonglong(crdtServer.slave_announce_port ?
                                   crdtServer.slave_announce_port : server.port);
        serverLog(LL_NOTICE,
                  "[CRDT]send listening-port: %s to master", port);
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "CRDT.REPLCONF",
                                         "listening-port", port, NULL);
        sdsfree(port);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_PORT;
        return;
    }

    /* Receive REPLCONF listening-port reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_PORT) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF listening-port. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"[CRDT] (Non critical) Master does not understand "
                                "REPLCONF listening-port: %s", err);
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_IP;
    }

    /* Skip REPLCONF ip-address if there is no slave-announce-ip option set. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_IP &&
        server.slave_announce_ip == NULL)
    {
        crdtMaster->repl_state = REPL_STATE_SEND_CAPA;
    }

    /* Set the slave ip, so that Master's INFO command can list the
     * slave IP address port correctly in case of port forwarding or NAT. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_IP) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "CRDT.REPLCONF",
                                         "ip-address", server.slave_announce_ip, NULL);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_IP;
        return;
    }

    /* Receive REPLCONF ip-address reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_IP) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF listening-port. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"[CRDT] (Non critical) Master does not understand "
                                "REPLCONF ip-address: %s", err);
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_CAPA;
    }

    /* Inform the master of our (slave) capabilities.
     *
     * EOF: supports EOF-style RDB transfer for diskless replication.
     * PSYNC2: supports PSYNC v2, so understands +CONTINUE <new repl ID>.
     *
     * The master will ignore capabilities it does not understand. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_CAPA) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "CRDT.REPLCONF",
                                         "capa", "eof", "capa", "psync2", NULL);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_CAPA;
        return;
    }

    /* Receive CAPA reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_CAPA) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF capa. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"[CRDT] (Non critical) Master does not understand "
                                "REPLCONF capa: %s", err);
        } else {
            serverLog(LL_NOTICE,
                      "[CRDT] Master: %s:%d, accept capa eof/psync2", crdtMaster->masterhost, crdtMaster->masterport);
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_VC;
    }

    /* Inform the master of our (slave) min-vector-clock
     *
     * The master will ignore capabilities it does not understand. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_VC) {
        sds vc = vectorClockToSds(crdtServer.vectorClock);
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_WRITE, fd, "CRDT.REPLCONF",
                                         "min-vc", vc, NULL);

        serverLog(LL_NOTICE,
                "[CRDT] Master: %s:%d, send master my min-vc: %s", crdtMaster->masterhost, crdtMaster->masterport, vc);
        sdsfree(vc);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_VC;
        return;
    }

    /* Receive Vector Clock reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_VC) {
        err = crdtSendSynchronousCommand(crdtMaster, SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF capa. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"(Non critical) Master does not understand "
                                "REPLCONF capa: %s", err);
        } else {
            serverLog(LL_NOTICE,
                      "[CRDT] Master: %s:%d, accept min-vc", crdtMaster->masterhost, crdtMaster->masterport);
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_PSYNC;
    }

    /* Try a partial resynchonization. If we don't have a cached master
     * slaveTryPartialResynchronization() will at least try to use PSYNC
     * to start a full resynchronization so that we get the master run id
     * and the global offset, to try a partial resync at the next
     * reconnection attempt. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_PSYNC) {
        if (crdtSlaveTryPartialResynchronization(crdtMaster, fd,0) == PSYNC_WRITE_ERROR) {
            err = sdsnew("Write error sending the PSYNC command.");
            goto write_error;
        }
        crdtMaster->repl_state = REPL_STATE_RECEIVE_PSYNC;
        return;
    }

    /* If reached this point, we should be in REPL_STATE_RECEIVE_PSYNC. */
    if (crdtMaster->repl_state != REPL_STATE_RECEIVE_PSYNC) {
        serverLog(LL_WARNING,"[CRDT] crdtSyncWithMaster(): state machine error, "
                             "state should be RECEIVE_PSYNC but is %d",
                  crdtMaster->repl_state);
        goto error;
    }

    psync_result = crdtSlaveTryPartialResynchronization(crdtMaster,fd,1);
    if (psync_result == PSYNC_WAIT_REPLY) return; /* Try again later... */

    /* If the master is in an transient error, we should try to PSYNC
     * from scratch later, so go to the error path. This happens when
     * the server is loading the dataset or is not connected with its
     * master and so forth. */
    if (psync_result == PSYNC_TRY_LATER) goto error;

    /* Note: if PSYNC does not return WAIT_REPLY, it will take care of
     * uninstalling the read handler from the file descriptor. */

    if (psync_result == PSYNC_CONTINUE) {
        serverLog(LL_NOTICE, "[CRDT] MASTER <-> SLAVE sync: Crdt Master accepted a Partial Resynchronization.");
        return;
    }

    if (psync_result == PSYNC_FULLRESYNC) {
        serverLog(LL_NOTICE, "[CRDT] MASTER <-> SLAVE sync: Crdt Master accepted a Full Resynchronization.");
        // crdtReplicationCreateMasterClient(crdtMaster, fd, -1);
        createClient(fd);
        crdtMaster->repl_transfer_s = -1;
    }

    /* Fall back to SYNC if needed. Otherwise psync_result == PSYNC_FULLRESYNC
     * and the crdtMaster->master_replid and master_initial_offset are
     * already populated. */
    if (psync_result == PSYNC_NOT_SUPPORTED) {
        serverLog(LL_NOTICE, "[CRDT] MASTER <-> SLAVE sync: PSYNC_NOT_SUPPORTED.");
        goto error;

    }
    serverLog(LL_NOTICE, "[CRDT] Replication: Master Client create successfully: %lld", crdtMaster->master->peer_master->gid);
    crdtMaster->repl_state = REPL_STATE_TRANSFER;
    crdtMaster->repl_transfer_lastio = server.unixtime;
    return;

error:
    aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE|AE_WRITABLE);
    close(fd);
    crdtMaster->repl_transfer_s = -1;
    crdtMaster->repl_state = REPL_STATE_CONNECT;
    return;

write_error: /* Handle sendSynchronousCommand(SYNC_CMD_WRITE) errors. */
    serverLog(LL_WARNING,"[CRDT]Sending command to master in replication handshake: %s", err);
    sdsfree(err);
    goto error;
}


int crdtConnectWithMaster(CRDT_Master_Instance *masterInstance) {
    int fd;

    fd = anetTcpNonBlockBestEffortBindConnect(NULL,
                                              masterInstance->masterhost,masterInstance->masterport,NET_FIRST_BIND_ADDR);
    if (fd == -1) {
        serverLog(LL_NOTICE, "[CRDT]Unable to connect to MASTER: %s",
                  strerror(errno));
        return C_ERR;
    }

    if (aeCreateFileEvent(server.el,fd,AE_READABLE|AE_WRITABLE,crdtSyncWithMaster,masterInstance) ==
        AE_ERR)
    {
        close(fd);
        serverLog(LL_WARNING,"[CRDT]Can't create readable event for SYNC");
        return C_ERR;
    }

    masterInstance->repl_transfer_lastio = server.unixtime;
    masterInstance->repl_transfer_s = fd;
    masterInstance->repl_state = REPL_STATE_CONNECTING;
    return C_OK;
}

/* This function can be called when a non blocking connection is currently
 * in progress to undo it.
 * Never call this function directly, use cancelReplicationHandshake() instead.
 */
void crdtUndoConnectWithMaster(CRDT_Master_Instance *masterInstance) {
    if(masterInstance->repl_transfer_s == -1) {
        return;
    }
    int fd = masterInstance->repl_transfer_s;

    aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE|AE_WRITABLE);
    close(fd);
    masterInstance->repl_transfer_s = -1;
}

/* Abort the async download of the bulk dataset while SYNC-ing with master.
 * Never call this function directly, use cancelReplicationHandshake() instead.
 */
void crdtReplicationAbortSyncTransfer(CRDT_Master_Instance *masterInstance) {
    serverAssert(masterInstance->repl_state == REPL_STATE_TRANSFER);
    crdtUndoConnectWithMaster(masterInstance);
    if(masterInstance->master != NULL) { 
        freeClient(masterInstance->master); 
        masterInstance->master = NULL;
    }
}

/* This function aborts a non blocking replication attempt if there is one
 * in progress, by canceling the non-blocking connect attempt or
 * the initial bulk transfer.
 *
 * If there was a replication handshake in progress 1 is returned and
 * the replication state (server.repl_state) set to REPL_STATE_CONNECT.
 *
 * Otherwise zero is returned and no operation is perforemd at all. */
void crdtCancelReplicationHandshake(int gid) {
    CRDT_Master_Instance *masterInstance = getPeerMaster(gid);
    if(masterInstance == NULL) {
        return;
    }
    if (masterInstance->repl_state == REPL_STATE_TRANSFER) {
        crdtReplicationAbortSyncTransfer(masterInstance);
        masterInstance->repl_state = REPL_STATE_CONNECT;
    } else if (masterInstance->repl_state == REPL_STATE_CONNECTING || crdtSlaveIsInHandshakeState(masterInstance))
    {
        crdtUndoConnectWithMaster(masterInstance);
        masterInstance->repl_state = REPL_STATE_CONNECT;
    }

}

/* Turn the cached master into the current master, using the file descriptor
 * passed as argument as the socket for the new master.
 *
 * This function is called when successfully setup a partial resynchronization
 * so the stream of data that we'll receive will start from were this
 * master left. */
void crdtReplicationResurrectCachedMaster(CRDT_Master_Instance *crdtMaster, int newfd) {
    crdtMaster->master = crdtMaster->cached_master;
    crdtMaster->cached_master = NULL;
    crdtMaster->master->fd = newfd;
    crdtMaster->master->flags &= ~(CLIENT_CLOSE_AFTER_REPLY|CLIENT_CLOSE_ASAP);
    crdtMaster->master->authenticated = 1;
    crdtMaster->master->lastinteraction = server.unixtime;
    crdtMaster->repl_state = REPL_STATE_CONNECTED;

    /* Re-add to the list of clients. */
    listAddNodeTail(server.clients,crdtMaster->master);
    if (aeCreateFileEvent(server.el, newfd, AE_READABLE,
                          readQueryFromClient, crdtMaster->master)) {
        serverLog(LL_WARNING,"[CRDT]Error resurrecting the cached master, impossible to add the readable handler: %s", strerror(errno));
        freeClientAsync(crdtMaster->master); /* Close ASAP. */
    }

    /* We may also need to install the write handler as well if there is
     * pending data in the write buffers. */
    if (clientHasPendingReplies(crdtMaster->master)) {
        if (aeCreateFileEvent(server.el, newfd, AE_WRITABLE,
                              sendReplyToClient, crdtMaster->master)) {
            serverLog(LL_WARNING,"[CRDT]Error resurrecting the cached master, impossible to add the writable handler: %s", strerror(errno));
            freeClientAsync(crdtMaster->master); /* Close ASAP. */
        }
    }
}

/* Free a cached master, called when there are no longer the conditions for
 * a partial resync on reconnection. */
void crdtReplicationDiscardCachedMaster(CRDT_Master_Instance *crdtMaster) {
    if (crdtMaster->cached_master == NULL) return;

    serverLog(LL_NOTICE,"[CRDT]Discarding previously cached master state.");
    crdtMaster->cached_master->flags &= ~CLIENT_CRDT_MASTER;
    freeClient(crdtMaster->cached_master);
    crdtMaster->cached_master = NULL;
}
void crdtReplicationAllPeersStateReset() {

}
/* Once we have a link with the master and the synchroniziation was
 * performed, this function materializes the master client we store
 * at server.master, starting from the specified file descriptor. */
void crdtReplicationCreateMasterClient(CRDT_Master_Instance *crdtMaster, client* c, int dbid) {
    c->peer_master = crdtMaster;
    c->flags |= CLIENT_CRDT_MASTER;
    c->authenticated = 1;
    c->reploff = crdtMaster->master_initial_offset;
    c->read_reploff = c->reploff;
    memcpy(c->replid, crdtMaster->master_replid,
           sizeof(crdtMaster->master_replid));
    if (dbid != -1) selectDb(c,dbid);
    crdtMaster->master = c;
}


/* --------------------------- REPLICATION CRON  ---------------------------- */

int startCrdtBgsaveForReplication(long long min_logic_time) {
    int retval;
    listIter li;
    listNode *ln;

    serverLog(LL_NOTICE,"[CRDT]Starting BGSAVE for SYNC with target: [CRDT] Merge");

    crdtRdbSaveInfo rsi, *rsiptr;
    rsiptr = crdtRdbPopulateSaveInfo(&rsi, min_logic_time);
    /* Only do rdbSave* when rsiptr is not NULL,
     * otherwise slave will miss repl-stream-db. */
    if (rsiptr) {
        retval = rdbSaveToSlavesSockets(rsiptr, &crdtServer);
    } else {
        serverLog(LL_WARNING,"[CRDT]BGSAVE for replication: replication information not available, can't generate the RDB file right now. Try later.");
        retval = C_ERR;
    }

    /* If we failed to BGSAVE, remove the slaves waiting for a full
     * resynchorinization from the list of salves, inform them with
     * an error about what happened, close the connection ASAP. */
    if (retval == C_ERR) {
        serverLog(LL_WARNING,"[CRDT] BGSAVE for replication failed");
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
void crdtReplicationCacheAllMaster() {
    for (int gid = 0; gid < (MAX_PEERS + 1); gid++) {
        CRDT_Master_Instance *crdtMaster = crdtServer.crdtMasters[gid];
        if(crdtMaster == NULL) continue;
        if(crdtMaster->master) {
            crdtReplicationDiscardCachedMaster(crdtMaster);
            crdtReplicationCacheMaster(crdtMaster->master);
        }
        crdtMaster->repl_state = REPL_STATE_NONE;
    }
}
void crdtReplicationCacheMaster(client *c) {
    if (!(c->flags & CLIENT_CRDT_MASTER)) {
        return;
    }
    CRDT_Master_Instance *crdtMaster = c->peer_master;
    serverLog(LL_NOTICE,"[CRDT]Caching the disconnected master state.(%s: %lld)", crdtMaster->master ? crdtMaster->master->replid : "null", crdtMaster->master ? crdtMaster->master->reploff : -1);
    /* Unlink the client from the server structures. */
    unlinkClient(c);

    /* Reset the master client so that's ready to accept new commands:
     * we want to discard te non processed query buffers and non processed
     * offsets, including pending transactions, already populated arguments,
     * pending outputs to the master. */
    if (crdtMaster->master) {
        sdsclear(crdtMaster->master->querybuf);
        sdsclear(crdtMaster->master->pending_querybuf);
        crdtMaster->master->read_reploff = crdtMaster->master->reploff;
    }
    if (c->flags & CLIENT_MULTI) discardTransaction(c);
    listEmpty(c->reply);
    c->bufpos = 0;
    resetClient(c);

    /* Save the master. crdtMaster->master will be set to null later by
     * replicationHandleMasterDisconnection(). */
    crdtMaster->cached_master = crdtMaster->master;

    /* Invalidate the Peer ID cache. */
    if (c->peerid) {
        sdsfree(c->peerid);
        c->peerid = NULL;
    }

    /* Caching the master happens instead of the actual freeClient() call,
     * so make sure to adjust the replication state. This function will
     * also set crdtMaster->master to NULL. */
    crdtReplicationHandleMasterDisconnection(c);
}

/* This function is called when the slave lose the connection with the
 * master into an unexpected way. */
void crdtReplicationHandleMasterDisconnection(client *c) {
    CRDT_Master_Instance *masterInstance = c->peer_master;
    if (masterInstance == NULL) {
        return;
    }
    masterInstance->master = NULL;
    masterInstance->repl_state = REPL_STATE_CONNECT;
    masterInstance->repl_down_since = server.unixtime;
    /* We lost connection with our master, don't disconnect slaves yet,
     * maybe we'll be able to PSYNC with our master later. We'll disconnect
     * the slaves only if we'll have to do a full resync with our master. */
}

// CRDT.OVC <gid> <vclock>
void sendObservedVectorClock() {
    robj *crdt_ovc_argv[3];
    crdt_ovc_argv[0] = createStringObject("CRDT.OVC",8);
    crdt_ovc_argv[1] = createStringObjectFromLongLong(crdtServer.crdt_gid);
    sds vclockStr = vectorClockToSds(crdtServer.vectorClock);
    crdt_ovc_argv[2] = createStringObject(vclockStr, sdslen(vclockStr));

    replicationFeedAllSlaves(server.slaveseldb, crdt_ovc_argv, 3);

    sdsfree(vclockStr);
    decrRefCount(crdt_ovc_argv[0]);
    decrRefCount(crdt_ovc_argv[1]);
    decrRefCount(crdt_ovc_argv[2]);
}

void crdtOvcCommand(client *c) {
    if (c->argc != 3) {
        addReply(c, shared.syntaxerr);
        return;
    }
    long long gid;
    if (getLongLongFromObject(c->argv[1], &gid) != C_OK) {
        addReply(c, shared.syntaxerr);
    }
    int flags = PROPAGATE_REPL;
    if (gid != crdtServer.crdt_gid) {
        sds vclockStr = (sds) c->argv[2]->ptr;
        VectorClock vclock = sdsToVectorClock(vclockStr);

        CRDT_Master_Instance *peerMaster = getPeerMaster(gid);
        VectorClock newVectorClock = vectorClockMerge(peerMaster->vectorClock, vclock);
        if (!isNullVectorClock(peerMaster->vectorClock)) {
            freeVectorClock(peerMaster->vectorClock);
        }
        freeVectorClock(vclock);
        // about peerMaster reploff
        c->peer_master = peerMaster;
        peerMaster->vectorClock = newVectorClock;
    } else {
        feedCrdtBacklog(c->argv, c->argc);
    }
    addReply(c, shared.ok);
    forceCommandPropagation(c, flags);
}

void crdtAuthGidCommand(client *c) {
    if (c->argc != 2) {
        addReply(c, shared.syntaxerr);
        return;
    }
    long long gid;
    if (getLongLongFromObject(c->argv[1], &gid) != C_OK) {
        addReply(c, shared.syntaxerr);
        return;
    }
    if (gid != crdtServer.crdt_gid) {
        addReplyError(c,"invalid gid");
        return;
    }
    c->slave_capa |= SLAVE_CAPA_CRDT;
    addReply(c, shared.ok);
}
void crdtAuthCommand(client *c) {
    if (c->argc != 3) {
        addReply(c, shared.syntaxerr);
        return;
    }
    if (!!strcasecmp(crdtServer.crdt_namespace, c->argv[1]->ptr)) {
        addReplyError(c,"invalid namespace");
        return;
    }
    long long gid;
    if (getLongLongFromObject(c->argv[2], &gid) != C_OK) {
        addReply(c, shared.syntaxerr);
        return;
    }
    if (gid != crdtServer.crdt_gid) {
        addReplyError(c,"invalid gid");
        return;
    }
    addReply(c, shared.ok);
}

void feedCrdtBacklog(robj **argv, int argc) {
    int j, len;

    /* Write the command to the replication backlog if any. */
    if (!crdtServer.repl_backlog) {
        createReplicationBacklog();
    }
    char aux[LONG_STR_SIZE+3];
    /* Add the multi bulk reply length. */
    aux[0] = '*';
    len = ll2string(aux+1,sizeof(aux)-1,argc);
    aux[len+1] = '\r';
    aux[len+2] = '\n';
    feedReplicationBacklog(&crdtServer, aux,len+3);

    for (j = 0; j < argc; j++) {
        long objlen = stringObjectLen(argv[j]);

        /* We need to feed the buffer with the object as a bulk reply
         * not just as a plain string, so create the $..CRLF payload len
         * and add the final CRLF */
        aux[0] = '$';
        len = ll2string(aux+1,sizeof(aux)-1,objlen);
        aux[len+1] = '\r';
        aux[len+2] = '\n';
        feedReplicationBacklog(&crdtServer, aux,len+3);
        feedReplicationBacklogWithObject(&crdtServer, argv[j]);
        feedReplicationBacklog(&crdtServer, aux+len+1,2);
    }


}
void replicationFeedRobj(robj* cmd) {
    listNode *ln;
    listIter li;

    /* Add the SELECT command into the both backlogs. */
    if (server.repl_backlog) {
        feedReplicationBacklogWithObject(&server, cmd);
    }

    if (crdtServer.repl_backlog) {
        feedReplicationBacklogWithObject(&crdtServer, cmd);
    }

    /* Send it to slaves. */
    listRewind(server.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
        addReply(slave,cmd);
    }

    /* Send it to crdt slaves. */
    listRewind(crdtServer.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
        addReply(slave,cmd);
    }
}
void replicationFeedString(void *ptr, size_t ptrlen) {
    listNode *ln;
    listIter li;

    /* Add the SELECT command into the both backlogs. */
    if (server.repl_backlog) {
        // feedReplicationBacklogWithObject(&server, cmd);
        feedReplicationBacklog(&server, ptr, ptrlen);
    }

    if (crdtServer.repl_backlog) {
        feedReplicationBacklog(&crdtServer, ptr, ptrlen);
    }

    /* Send it to slaves. */
    listRewind(server.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
        // addReply(slave,cmd);
        addReplyString(slave, ptr, ptrlen);
    }

    /* Send it to crdt slaves. */
    listRewind(crdtServer.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
        // addReply(slave,cmd);
        addReplyString(slave, ptr, ptrlen);
    }
}
void replicationFeedRobjToAllSlaves(int dictid, robj* cmd) {
    // int j, len;
    char llstr[LONG_STR_SIZE];
    char gidstr[LONG_STR_SIZE];
    if (server.masterhost != NULL && !server.repl_slave_repl_all && isSameTypeWithMaster() == C_OK ) return;
    if (server.slaveseldb != dictid || crdtServer.slaveseldb != dictid) {
        robj *selectcmd;

        int dictid_len, gid_len;

        dictid_len = ll2string(llstr,sizeof(llstr),dictid);
        gid_len = ll2string(gidstr,sizeof(gidstr),crdtServer.crdt_gid);

        selectcmd = createObject(OBJ_STRING,
                                 sdscatprintf(sdsempty(),
                                              "*3\r\n$11\r\nCRDT.SELECT\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n",
                                              gid_len, gidstr, dictid_len, llstr));
        replicationFeedRobj(selectcmd);
        decrRefCount(selectcmd);
    }
    server.slaveseldb = dictid;
    crdtServer.slaveseldb = dictid;
    replicationFeedRobj(cmd);
}
void replicationFeedStringToAllSlaves(int dictid, void* cmdbuf, size_t cmdlen) {
    // int j, len;
    char llstr[LONG_STR_SIZE];
    char gidstr[LONG_STR_SIZE];
    if (server.masterhost != NULL && !server.repl_slave_repl_all && isSameTypeWithMaster() == C_OK ) return;
    if (server.slaveseldb != dictid || crdtServer.slaveseldb != dictid) {
        //robj *selectcmd;

        int dictid_len, gid_len;

        dictid_len = ll2string(llstr,sizeof(llstr),dictid);
        gid_len = ll2string(gidstr,sizeof(gidstr),crdtServer.crdt_gid);

        // selectcmd = createObject(OBJ_STRING,
        //                          sdscatprintf(sdsempty(),
        //                                       "*3\r\n$11\r\nCRDT.SELECT\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n",
        //                                       gid_len, gidstr, dictid_len, llstr));
        char selectcmdbuf[87];//4+ (4 + 13) + (10 + 23) + (10 + 23) 
        size_t selectcmdlen = sprintf(selectcmdbuf,  "*3\r\n$11\r\nCRDT.SELECT\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n",
                                            gid_len, gidstr, dictid_len, llstr);
        replicationFeedString(selectcmdbuf, selectcmdlen);
        // decrRefCount(selectcmd);
    }
    server.slaveseldb = dictid;
    crdtServer.slaveseldb = dictid;
    replicationFeedString(cmdbuf, cmdlen);
}
/* Propagate write commands to slaves, and populate the replication backlog
 * as well. This function is used if the instance is a master: we use
 * the commands received by our clients in order to create the replication
 * stream. Instead if the instance is a slave and has sub-slaves attached,
 * we use replicationFeedSlavesFromMaster() && feedCrdtBacklog*/
void replicationFeedAllSlaves(int dictid, robj **argv, int argc) {
    listNode *ln;
    listIter li;
    int j, len;
    char llstr[LONG_STR_SIZE];
    char gidstr[LONG_STR_SIZE];

    /* If the instance is not a top level master, return ASAP: we'll just proxy
     * the stream of data we receive from our master instead, in order to
     * propagate *identical* replication stream. In this way this slave can
     * advertise the same replication ID as the master (since it shares the
     * master replication history and has the same backlog and offsets). */
    if (server.masterhost != NULL && !server.repl_slave_repl_all && isSameTypeWithMaster() == C_OK ) return;
    /* If there aren't slaves, and there is no backlog buffer to populate,
     * we can return ASAP. */
//    if (server.repl_backlog == NULL && listLength(server.slaves) == 0
//        && crdtServer.repl_backlog == NULL && listLength(crdtServer.slaves) == 0)
//        return;

        /* Send SELECT command to every slave if needed. */
    if (server.slaveseldb != dictid || crdtServer.slaveseldb != dictid) {
        robj *selectcmd;

        int dictid_len, gid_len;

        dictid_len = ll2string(llstr,sizeof(llstr),dictid);
        gid_len = ll2string(gidstr,sizeof(gidstr),crdtServer.crdt_gid);

        selectcmd = createObject(OBJ_STRING,
                                 sdscatprintf(sdsempty(),
                                              "*3\r\n$11\r\nCRDT.SELECT\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n",
                                              gid_len, gidstr, dictid_len, llstr));


        /* Add the SELECT command into the both backlogs. */
        if (server.repl_backlog) {
            feedReplicationBacklogWithObject(&server, selectcmd);
        }

        if (crdtServer.repl_backlog) {
            feedReplicationBacklogWithObject(&crdtServer, selectcmd);
        }

        /* Send it to slaves. */
        listRewind(server.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
            addReply(slave,selectcmd);
        }

        /* Send it to crdt slaves. */
        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;
            addReply(slave,selectcmd);
        }

        decrRefCount(selectcmd);
    }
    server.slaveseldb = dictid;
    crdtServer.slaveseldb = dictid;

    /* Write the command to the replication backlog if any. */
    if (server.repl_backlog || crdtServer.repl_backlog) {
        char aux[LONG_STR_SIZE+3];

        /* Add the multi bulk reply length. */
        aux[0] = '*';
        len = ll2string(aux+1,sizeof(aux)-1,argc);
        aux[len+1] = '\r';
        aux[len+2] = '\n';

        if (server.repl_backlog) {
            feedReplicationBacklog(&server, aux,len+3);
        }

        if (crdtServer.repl_backlog) {
            feedReplicationBacklog(&crdtServer, aux,len+3);
        }

        for (j = 0; j < argc; j++) {
            long objlen = stringObjectLen(argv[j]);

            /* We need to feed the buffer with the object as a bulk reply
             * not just as a plain string, so create the $..CRLF payload len
             * and add the final CRLF */
            aux[0] = '$';
            len = ll2string(aux+1,sizeof(aux)-1,objlen);
            aux[len+1] = '\r';
            aux[len+2] = '\n';

            if (server.repl_backlog) {
                feedReplicationBacklog(&server, aux, len + 3);
                feedReplicationBacklogWithObject(&server, argv[j]);
                feedReplicationBacklog(&server, aux + len + 1, 2);
            }
            if (crdtServer.repl_backlog) {
                feedReplicationBacklog(&crdtServer, aux, len + 3);
                feedReplicationBacklogWithObject(&crdtServer, argv[j]);
                feedReplicationBacklog(&crdtServer, aux + len + 1, 2);
            }
        }
    }

    /* Write the command to every slave. */
    listRewind(server.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;

        /* Don't feed slaves that are still waiting for BGSAVE to start */
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;

        /* Feed slaves that are waiting for the initial SYNC (so these commands
         * are queued in the output buffer until the initial SYNC completes),
         * or are already in sync with the master. */

        /* Add the multi bulk length. */
        addReplyMultiBulkLen(slave,argc);

        /* Finally any additional argument that was not stored inside the
         * static buffer if any (from j to argc). */
        for (j = 0; j < argc; j++)
            addReplyBulk(slave,argv[j]);
    }

    /* Write the command to every slave. */
    listRewind(crdtServer.slaves,&li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;

        /* Don't feed slaves that are still waiting for BGSAVE to start */
        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) continue;

        /* Feed slaves that are waiting for the initial SYNC (so these commands
         * are queued in the output buffer until the initial SYNC completes),
         * or are already in sync with the master. */

        /* Add the multi bulk length. */
        addReplyMultiBulkLen(slave,argc);

        /* Finally any additional argument that was not stored inside the
         * static buffer if any (from j to argc). */
        for (j = 0; j < argc; j++)
            addReplyBulk(slave,argv[j]);
    }
}

void crdtReplicationCloseAllMasters() {
    serverLog(LL_NOTICE, "[CRDT][begin]disconnect all crdt masters");
    for (int gid = 0; gid < (MAX_PEERS + 1); gid++) {
        CRDT_Master_Instance *crdtMaster = crdtServer.crdtMasters[gid];
        if(crdtMaster == NULL) {
            continue;
        }
        crdtReplicationDiscardCachedMaster(crdtMaster);
        if(crdtMaster->repl_state == REPL_STATE_CONNECTED) {
            if(crdtMaster->master) {freeClient(crdtMaster->master);}
        } else {
            crdtCancelReplicationHandshake(gid);
        }
        crdtMaster->repl_state = REPL_STATE_NONE;
    }
    serverLog(LL_NOTICE, "[CRDT][end]disconnect all crdt masters");
}

/* Replication cron function, called 1 time per second. */
void crdtReplicationCron(void) {
    static long long replication_cron_loops = 0;
    listIter li;
    listNode *ln;
    /* Non blocking connection timeout? */
    /**!!!!Important!!!!!
     * Connect crdt master if and only if I'm NOT a SLAVE here
     * SLAVE SHOULD RECEIVE DATA from their masters*/
    if (isMasterMySelf() == C_OK) {
        for (int gid = 0; gid < (MAX_PEERS + 1); gid++) {
            CRDT_Master_Instance *crdtMaster = crdtServer.crdtMasters[gid];
            if (crdtMaster == NULL) {
                continue;
            }
            if (crdtMaster->masterhost &&
                (crdtMaster->repl_state == REPL_STATE_CONNECTING || crdtSlaveIsInHandshakeState(crdtMaster)) &&
                (time(NULL) - crdtMaster->repl_transfer_lastio) > crdtServer.repl_timeout) {
                serverLog(LL_NOTICE, "[CRDT]Timeout connecting to the MASTER...");
                crdtCancelReplicationHandshake(gid);
            }

            /* Bulk transfer I/O timeout? */
            if (crdtMaster->masterhost && crdtMaster->repl_state == REPL_STATE_TRANSFER &&
                (time(NULL) - crdtMaster->repl_transfer_lastio) > crdtServer.repl_timeout) {
                serverLog(LL_NOTICE,
                          "[CRDT]Timeout receiving bulk data from MASTER... If the problem persists try to set the 'repl-timeout' parameter in redis.conf to a larger value.");
                crdtCancelReplicationHandshake(gid);
            }

            /* Timed out master when we are an already connected slave? */
            if (crdtMaster->masterhost && crdtMaster->repl_state == REPL_STATE_CONNECTED &&
                (time(NULL) - crdtMaster->master->lastinteraction) > crdtServer.repl_timeout) {
                serverLog(LL_NOTICE, "[CRDT]MASTER timeout: no data nor PING received in %d second...", crdtServer.repl_timeout);
                freeClient(crdtMaster->master);
            }

            /* Check if we should connect to a MASTER */
            if (crdtMaster->repl_state == REPL_STATE_CONNECT) {
                serverLog(LL_NOTICE, "[CRDT] Connecting to MASTER %s:%d",
                          crdtMaster->masterhost, crdtMaster->masterport);
                if (crdtConnectWithMaster(crdtMaster) == C_OK) {
                    serverLog(LL_NOTICE, "[CRDT]MASTER <-> SLAVE sync started, master(%s:%d)",
                              crdtMaster->masterhost, crdtMaster->masterport);
                }
            }

            /* Check if we should connect to a MASTER */
            if (crdtMaster->repl_state == REPL_STATE_NONE) {
                serverLog(LL_NOTICE, "[CRDT] Prepare CONNECT to MASTER [gid %lld] %s:%d", crdtMaster->gid,
                          crdtMaster->masterhost, crdtMaster->masterport);
                crdtMaster->repl_state = REPL_STATE_CONNECT;
            }

            /* Send ACK to master from time to time.
             * Note that we do not send periodic acks to masters that don't
             * support PSYNC and replication offsets. */
            if (crdtMaster->masterhost && crdtMaster->master &&
                (crdtMaster->repl_state == REPL_STATE_CONNECTED)) {
                crdtReplicationSendAck(crdtMaster);
            }
        }
    }
    /* If we have attached slaves, PING them from time to time.
     * So slaves can implement an explicit timeout to masters, and will
     * be able to detect a link disconnection even if the TCP connection
     * will not actually go down. */

    /* First, send PING according to ping_slave_period. */
    if ((replication_cron_loops % crdtServer.repl_ping_slave_period) == 0 &&
        listLength(crdtServer.slaves) && crdtServer.active_crdt_ovc)
    {
        int num = 0;
        listRewind(crdtServer.slaves, &li);
        while ((ln = listNext(&li)) != NULL) {
            client *slave = ln->value;
            if (slave->replstate != SLAVE_STATE_WAIT_BGSAVE_START)
                num ++;
        }
        if (num) {
            sendObservedVectorClock();
        }
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

    /* Disconnect timedout slaves. */
    if (listLength(crdtServer.slaves)) {
        listIter li;
        listNode *ln;

        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;

            if (slave->replstate != SLAVE_STATE_ONLINE) continue;
            if (slave->flags & CLIENT_PRE_PSYNC) continue;
            if ((server.unixtime - slave->repl_ack_time) > crdtServer.repl_timeout)
            {
                serverLog(LL_WARNING, "[CRDT] Disconnecting timedout slave: %s",
                          replicationGetSlaveName(slave));
                if (!isNullVectorClock(slave->vectorClock)) {
                    freeVectorClock(slave->vectorClock);
                    slave->vectorClock = newVectorClock(0);
                }
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
    if (isMasterMySelf() == C_OK && listLength(crdtServer.slaves) == 0 && crdtServer.repl_backlog_time_limit &&
        crdtServer.repl_backlog && listLength(server.slaves) == 0 && server.repl_backlog_time_limit && server.repl_backlog)
    {
        time_t crdt_idle = server.unixtime - crdtServer.repl_no_slaves_since;
        time_t idle = server.unixtime - server.repl_no_slaves_since;
        if (crdt_idle > crdtServer.repl_backlog_time_limit && idle > server.repl_backlog_time_limit) {
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
            changeReplicationId(&server);
            changeReplicationId(&crdtServer);
            clearReplicationId2(&server);
            clearReplicationId2(&crdtServer);
            freeReplicationBacklog(&server);
            freeReplicationBacklog(&crdtServer);
            serverLog(LL_NOTICE,
                      "[CRDT] Replication backlog freed after %d seconds "
                      "without connected slaves.",
                      (int) crdtServer.repl_backlog_time_limit);
            serverLog(LL_NOTICE, 
                        "[CRDT] changeReplicationId when Replication backlog freed");
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
        listNode *ln = NULL;
        listIter li;
        long long min_logic_time = getMyLogicTime();
        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) {
                idle = server.unixtime - slave->lastinteraction;
                if (idle > max_idle) max_idle = idle;
                slaves_waiting++;
                min_logic_time = min(min_logic_time, getMyGidLogicTime(slave->vectorClock));
            }
        }

        if (slaves_waiting > 0 && max_idle > crdtServer.repl_diskless_sync_delay) {
            /* Start the BGSAVE. The called function may start a
             * BGSAVE with socket target or disk target depending on the
             * configuration and slaves capabilities. */
            serverLog(LL_NOTICE,
                      "[CRDT] crdt replication cron call startCrdtBgsaveForReplication().");
            startCrdtBgsaveForReplication(min_logic_time);
        }
    }

    /* Refresh the number of slaves with lag <= min-slaves-max-lag. */
    refreshGoodSlavesCount(&crdtServer);
    replication_cron_loops++; /* Incremented with frequency 1 HZ. */
}

/*------------------------CRDT Info Commands-------------*/
void debugCancelCrdt(client *c) {
    if (c->argc != 3) {
        addReply(c, shared.syntaxerr);
        return;
    }

    if (strcasecmp(c->argv[2]->ptr,"chenzhu") != 0) {
        addReply(c, shared.syntaxerr);
        return;
    }
    long long gid;
    if ((getLongLongFromObjectOrReply(c, c->argv[1], &gid, NULL) != C_OK)) {
        addReply(c, shared.syntaxerr);
        return;
    }
    CRDT_Master_Instance *masterInstance;
    if((masterInstance = getPeerMaster(gid)) == NULL) {
        addReply(c, shared.syntaxerr);
        return;
    }

    freeClient(masterInstance->master);
    addReply(c, shared.ok);
}

void crdtRoleCommand(client *c) {

    long long gid;
    if ((getLongLongFromObjectOrReply(c, c->argv[2], &gid, NULL) != C_OK))
        return;

    if (!strcasecmp(c->argv[1]->ptr,"master")) {
        listIter li;
        listNode *ln;
        void *mbcount;
        int slaves = 0;

        addReplyMultiBulkLen(c,3);
        addReplyBulkCBuffer(c,"master",6);
        addReplyLongLong(c,crdtServer.master_repl_offset);
        mbcount = addDeferredMultiBulkLength(c);
        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            char ip[NET_IP_STR_LEN], *slaveip = slave->slave_ip;

            if (slaveip[0] == '\0') {
                if (anetPeerToString(slave->fd,ip,sizeof(ip),NULL) == -1)
                    continue;
                slaveip = ip;
            }
            if (slave->replstate != SLAVE_STATE_ONLINE) continue;
            addReplyMultiBulkLen(c,3);
            addReplyBulkCString(c,slaveip);
            addReplyBulkLongLong(c,slave->slave_listening_port);
            addReplyBulkLongLong(c,slave->repl_ack_off);
            slaves++;
        }
        setDeferredMultiBulkLength(c,mbcount,slaves);
    }
    else if (!strcasecmp(c->argv[1]->ptr,"slave")) {
        CRDT_Master_Instance *masterInstance = getPeerMaster(gid);
        char *slavestate = NULL;

        addReplyMultiBulkLen(c,5);
        addReplyBulkCBuffer(c,"slave",5);
        addReplyBulkCString(c,masterInstance->masterhost);
        addReplyLongLong(c,masterInstance->masterport);
        if (crdtSlaveIsInHandshakeState(masterInstance)) {
            slavestate = "handshake";
        } else {
            switch(masterInstance->repl_state) {
                case REPL_STATE_NONE: slavestate = "none"; break;
                case REPL_STATE_CONNECT: slavestate = "connect"; break;
                case REPL_STATE_CONNECTING: slavestate = "connecting"; break;
                case REPL_STATE_TRANSFER: slavestate = "sync"; break;
                case REPL_STATE_CONNECTED: slavestate = "connected"; break;
                default: slavestate = "unknown"; break;
            }
        }
        addReplyBulkCString(c,slavestate);
        addReplyLongLong(c,masterInstance->master ? masterInstance->master->reploff : -1);
    }
}

