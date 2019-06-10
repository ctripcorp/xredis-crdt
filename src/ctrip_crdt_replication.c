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
void crdtReplicationCreateMasterClient(CRDT_Master_Instance *crdtMaster, int fd, int dbid);


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

CRDT_Master_Instance *getPeerMaster(long long gid) {
    listIter li;
    listNode *ln;
    CRDT_Master_Instance *peerMaster = NULL;

    listRewind(crdtServer.crdtMasters, &li);
    while((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;
        if (crdtMaster->gid == gid) {
            peerMaster = crdtMaster;
            break;
        }
    }
    return peerMaster;
}

// peerof <gid> <ip> <port>
//  0       1    2    3
void peerofCommand(client *c) {
    /* SLAVEOF is not allowed in cluster mode as replication is automatically
    * configured using the current address of the master node. */
    if (server.cluster_enabled) {
        addReplyError(c,"PEEROF not allowed in cluster mode.");
        return;
    }


    long port;
    long long gid;
    if ((getLongLongFromObjectOrReply(c, c->argv[1], &gid, NULL) != C_OK))
        return;

    if ((getLongFromObjectOrReply(c, c->argv[3], &port, NULL) != C_OK))
        return;

    /* Check if we are already attached to the specified master */
    CRDT_Master_Instance *peerMaster = getPeerMaster(gid);
    if(peerMaster && !strcasecmp(peerMaster->masterhost, c->argv[2]->ptr)
       && peerMaster->masterport == port) {
        serverLog(LL_NOTICE,"PEER OF would result into synchronization with the master we are already connected with. No operation performed.");
        addReplySds(c,sdsnew("+OK Already connected to specified master\r\n"));
        return;
    }


    /* There was no previous master or the user specified a different one,
     * we can continue. */
    crdtReplicationSetMaster(gid, c->argv[1]->ptr, port);
    peerMaster = getPeerMaster(gid);
    sds client = catClientInfoString(sdsempty(),c);
    serverLog(LL_NOTICE,"PEER OF %s:%d enabled (user request from '%s')",
              peerMaster->masterhost, peerMaster->masterport, client);
    sdsfree(client);

    addReply(c,shared.ok);
}

void crdtReplicationSetMaster(long long gid, char *ip, int port) {

    CRDT_Master_Instance *peerMaster = getPeerMaster(gid);
    if (!peerMaster) {
        peerMaster = createPeerMaster(NULL, gid);
    }

    sdsfree(peerMaster->masterhost);
    peerMaster->masterhost = sdsnew(ip);
    peerMaster->masterport = port;
    if (peerMaster->master) {
        freeClient(peerMaster->master);
    }

    peerMaster->repl_state = REPL_STATE_CONNECT;
    peerMaster->repl_down_since = 0;
}

/**---------------------------CRDT RDB Start/End Mark--------------------------------*/

int listMatchCrdtMaster(void *a, void *b) {
    CRDT_Master_Instance *ma = a, *mb = b;
    return ma->gid == mb->gid;
}


//CRDT.START_MERGE <gid> <vector-clock> <repl_id>
void
crdtMergeStartCommand(client *c) {
    long long sourceGid;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;

    CRDT_Master_Instance *peerMaster = getPeerMaster(sourceGid);
    if (!peerMaster) {
        peerMaster = createPeerMaster(c, sourceGid);
    }
    peerMaster->master = c;
    memcpy(peerMaster->master_replid, c->argv[3]->ptr, sizeof(peerMaster->master_replid));
}

//CRDT.END_MERGE <gid> <vector-clock> <repl_id> <offset>
// 0               1        2            3          4
void
crdtMergeEndCommand(client *c) {
    long long sourceGid, offset;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;

    CRDT_Master_Instance *peerMaster = getPeerMaster(sourceGid);
    if (!peerMaster) goto err;

    peerMaster->vectorClock = sdsToVectorClock(c->argv[2]->ptr);
    memcpy(peerMaster->master_replid, c->argv[3]->ptr, sizeof(peerMaster->master_replid));
    if (getLongLongFromObjectOrReply(c, c->argv[4], &offset, NULL) != C_OK) return;
    peerMaster->master_initial_offset = offset;
    addReply(c, shared.ok);
    return;

err:
    addReply(c, shared.crdtmergeerr);
    crdtCancelReplicationHandshake(sourceGid);
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

/* Returns 1 if the given replication state is a handshake state,
 * 0 otherwise. */
int crdtSlaveIsInHandshakeState(CRDT_Master_Instance *crdtMaster) {
    return crdtMaster->repl_state >= REPL_STATE_RECEIVE_PONG &&
           crdtMaster->repl_state <= REPL_STATE_RECEIVE_PSYNC;
}

#define SYNC_CMD_READ (1<<0)
#define SYNC_CMD_WRITE (1<<1)
#define SYNC_CMD_FULL (SYNC_CMD_READ|SYNC_CMD_WRITE)
char *crdtSendSynchronousCommand(int flags, int fd, ...) {

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
            return sdscatprintf(sdsempty(),"-Writing to master: %s",
                                strerror(errno));
        }
        sdsfree(cmd);
    }

    /* Read the reply from the server. */
    if (flags & SYNC_CMD_READ) {
        char buf[256];

        if (syncReadLine(fd,buf,sizeof(buf),server.repl_syncio_timeout*1000)
            == -1)
        {
            return sdscatprintf(sdsempty(),"-Reading from master: %s",
                                strerror(errno));
        }
        server.repl_transfer_lastio = server.unixtime;
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
            serverLog(LL_NOTICE,"Trying a partial resynchronization (request %s:%s).", psync_replid, psync_offset);
        } else {
            serverLog(LL_NOTICE,"Partial resynchronization not possible (no cached master)");
            psync_replid = "?";
            memcpy(psync_offset,"-1",3);
        }

        /* Issue the PSYNC command */
        reply = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "CRDT.PSYNC", psync_replid, psync_offset, NULL);
        if (reply != NULL) {
            serverLog(LL_WARNING,"Unable to send PSYNC to master: %s",reply);
            sdsfree(reply);
            aeDeleteFileEvent(server.el,fd,AE_READABLE);
            return PSYNC_WRITE_ERROR;
        }
        return PSYNC_WAIT_REPLY;
    }

    /* Reading half */
    reply = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
    if (sdslen(reply) == 0) {
        /* The master may send empty newlines after it receives PSYNC
         * and before to reply, just to keep the connection alive. */
        sdsfree(reply);
        return PSYNC_WAIT_REPLY;
    }

    aeDeleteFileEvent(server.el,fd,AE_READABLE);

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
                      "Master replied with wrong +FULLRESYNC syntax.");
            /* This is an unexpected condition, actually the +FULLRESYNC
             * reply means that the master supports PSYNC, but the reply
             * format seems wrong. To stay safe we blank the master
             * replid to make sure next PSYNCs will fail. */
            memset(masterInstance->master_replid,0,CONFIG_RUN_ID_SIZE+1);
        } else {
            memcpy(masterInstance->master_replid, replid, offset-replid-1);
            masterInstance->master_replid[CONFIG_RUN_ID_SIZE] = '\0';
            masterInstance->master_initial_offset = strtoll(offset,NULL,10);
            serverLog(LL_NOTICE,"Crdt Full resync from master: %s:%lld",
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
                  "Successful partial resynchronization with master.");

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

            memcpy(masterInstance->master_replid, new, CONFIG_RUN_ID_SIZE);
            masterInstance->master_replid[CONFIG_RUN_ID_SIZE] = '\0';
        }

        /* Setup the replication to continue. */
        sdsfree(reply);

        crdtReplicationResurrectCachedMaster(masterInstance, fd);

        /* If this instance was restarted and we read the metadata to
         * PSYNC from the persistence file, our replication backlog could
         * be still not initialized. Create it. */
        if (crdtServer.repl_backlog == NULL) createReplicationBacklog(&crdtServer);
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
                  "Master is currently unable to PSYNC "
                  "but should be in the future: %s", reply);
        sdsfree(reply);
        return PSYNC_TRY_LATER;
    }

    if (strncmp(reply,"-ERR",4)) {
        /* If it's not an error, log the unexpected event. */
        serverLog(LL_WARNING,
                  "Unexpected reply to PSYNC from master: %s", reply);
    } else {
        serverLog(LL_NOTICE,
                  "Master does not support PSYNC or is in "
                  "error state (reply: %s)", reply);
    }
    sdsfree(reply);
    return PSYNC_NOT_SUPPORTED;
}

/* This handler fires when the non blocking connect was able to
 * establish a connection with the master. */
void crdtSyncWithMaster(aeEventLoop *el, int fd, void *privdata, int mask) {
    char tmpfile[256], *err = NULL;
    int maxtries = 5;
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
        serverLog(LL_WARNING,"Error condition on socket for SYNC: %s",
                  strerror(sockerr));
        goto error;
    }

    /* Send a PING to check the master is able to reply without errors. */
    if (crdtMaster->repl_state == REPL_STATE_CONNECTING) {
        serverLog(LL_NOTICE,"Non blocking connect for SYNC fired the event.");
        /* Delete the writable event so that the readable event remains
         * registered and we can wait for the PONG reply. */
        aeDeleteFileEvent(crdtServer.el,fd,AE_WRITABLE);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_PONG;
        /* Send the PING, don't check for errors at all, we have the timeout
         * that will take care about this. */
        err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "PING", NULL);
        if (err) goto write_error;
        return;
    }

    /* Receive the PONG command. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_PONG) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);

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
                      "Master replied to PING, replication can continue...");
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_AUTH;
    }

    /* AUTH with the master if required. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_AUTH) {
        if (crdtMaster->masterauth) {
            err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "AUTH", crdtMaster->masterauth, NULL);
            if (err) goto write_error;
            crdtMaster->repl_state = REPL_STATE_RECEIVE_AUTH;
            return;
        } else {
            crdtMaster->repl_state = REPL_STATE_SEND_PORT;
        }
    }

    /* Receive AUTH reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_AUTH) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
        if (err[0] == '-') {
            serverLog(LL_WARNING,"Unable to AUTH to MASTER: %s",err);
            sdsfree(err);
            goto error;
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_PORT;
    }

    /* Set the slave port, so that Master's INFO command can list the
     * slave listening port correctly. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_PORT) {
        sds port = sdsfromlonglong(crdtServer.slave_announce_port ?
                                   crdtServer.slave_announce_port : server.port);
        err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "REPLCONF",
                                         "listening-port", port, NULL);
        sdsfree(port);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_PORT;
        return;
    }

    /* Receive REPLCONF listening-port reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_PORT) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF listening-port. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"(Non critical) Master does not understand "
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
        err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "REPLCONF",
                                         "ip-address", server.slave_announce_ip, NULL);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_IP;
        return;
    }

    /* Receive REPLCONF ip-address reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_IP) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF listening-port. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"(Non critical) Master does not understand "
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
        err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "REPLCONF",
                                         "capa", "eof", "capa", "psync2", NULL);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_CAPA;
        return;
    }

    /* Receive CAPA reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_CAPA) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF capa. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"(Non critical) Master does not understand "
                                "REPLCONF capa: %s", err);
        }
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_SEND_VC;
    }

    /* Inform the master of our (slave) min-vector-clock
     *
     * The master will ignore capabilities it does not understand. */
    if (crdtMaster->repl_state == REPL_STATE_SEND_VC) {
        sds vc = vectorClockToSds(crdtServer.vectorClock);
        err = crdtSendSynchronousCommand(SYNC_CMD_WRITE, fd, "REPLCONF",
                                         "min-vc", vc, NULL);
        sdsfree(vc);
        if (err) goto write_error;
        sdsfree(err);
        crdtMaster->repl_state = REPL_STATE_RECEIVE_VC;
        return;
    }

    /* Receive Vector Clock reply. */
    if (crdtMaster->repl_state == REPL_STATE_RECEIVE_VC) {
        err = crdtSendSynchronousCommand(SYNC_CMD_READ, fd, NULL);
        /* Ignore the error if any, not all the Redis versions support
         * REPLCONF capa. */
        if (err[0] == '-') {
            serverLog(LL_NOTICE,"(Non critical) Master does not understand "
                                "REPLCONF capa: %s", err);
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
        serverLog(LL_WARNING,"syncWithMaster(): state machine error, "
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
        serverLog(LL_NOTICE, "MASTER <-> SLAVE sync: Master accepted a Partial Resynchronization.");
        return;
    }

    if (psync_result == PSYNC_FULLRESYNC) {
        crdtReplicationCreateMasterClient(crdtMaster, fd, -1);
    }

    /* Fall back to SYNC if needed. Otherwise psync_result == PSYNC_FULLRESYNC
     * and the crdtMaster->master_replid and master_initial_offset are
     * already populated. */
    if (psync_result == PSYNC_NOT_SUPPORTED) {
        goto error;

    }

    crdtMaster->repl_state = REPL_STATE_TRANSFER;
    crdtMaster->repl_transfer_size = -1;
    crdtMaster->repl_transfer_read = 0;
    crdtMaster->repl_transfer_last_fsync_off = 0;
    crdtMaster->repl_transfer_lastio = server.unixtime;
    return;

error:
    aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE|AE_WRITABLE);
    close(fd);
    crdtMaster->repl_transfer_s = -1;
    crdtMaster->repl_state = REPL_STATE_CONNECT;
    return;

write_error: /* Handle sendSynchronousCommand(SYNC_CMD_WRITE) errors. */
    serverLog(LL_WARNING,"Sending command to master in replication handshake: %s", err);
    sdsfree(err);
    goto error;
}


int crdtConnectWithMaster(CRDT_Master_Instance *masterInstance) {
    int fd;

    fd = anetTcpNonBlockBestEffortBindConnect(NULL,
                                              masterInstance->masterhost,masterInstance->masterport,NET_FIRST_BIND_ADDR);
    if (fd == -1) {
        serverLog(LL_WARNING,"Unable to connect to MASTER: %s",
                  strerror(errno));
        return C_ERR;
    }

    if (aeCreateFileEvent(server.el,fd,AE_READABLE|AE_WRITABLE,crdtSyncWithMaster,masterInstance) ==
        AE_ERR)
    {
        close(fd);
        serverLog(LL_WARNING,"Can't create readable event for SYNC");
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
    int fd = server.repl_transfer_s;

    aeDeleteFileEvent(crdtServer.el,fd,AE_READABLE|AE_WRITABLE);
    close(fd);
    masterInstance->repl_transfer_s = -1;
}

/* Abort the async download of the bulk dataset while SYNC-ing with master.
 * Never call this function directly, use cancelReplicationHandshake() instead.
 */
void crdtReplicationAbortSyncTransfer(CRDT_Master_Instance *masterInstance) {
    serverAssert(server.repl_state == REPL_STATE_TRANSFER);
    crdtUndoConnectWithMaster(masterInstance);
}

/* This function aborts a non blocking replication attempt if there is one
 * in progress, by canceling the non-blocking connect attempt or
 * the initial bulk transfer.
 *
 * If there was a replication handshake in progress 1 is returned and
 * the replication state (server.repl_state) set to REPL_STATE_CONNECT.
 *
 * Otherwise zero is returned and no operation is perforemd at all. */
void crdtCancelReplicationHandshake(long long gid) {
    CRDT_Master_Instance *masterInstance = getPeerMaster(gid);
    if(masterInstance == NULL) {
        return;
    }
    if (server.repl_state == REPL_STATE_TRANSFER) {
        crdtReplicationAbortSyncTransfer(masterInstance);
        server.repl_state = REPL_STATE_CONNECT;
    } else if (server.repl_state == REPL_STATE_CONNECTING || crdtSlaveIsInHandshakeState(masterInstance))
    {
        crdtUndoConnectWithMaster(masterInstance);
        server.repl_state = REPL_STATE_CONNECT;
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
        serverLog(LL_WARNING,"Error resurrecting the cached master, impossible to add the readable handler: %s", strerror(errno));
        freeClientAsync(crdtMaster->master); /* Close ASAP. */
    }

    /* We may also need to install the write handler as well if there is
     * pending data in the write buffers. */
    if (clientHasPendingReplies(crdtMaster->master)) {
        if (aeCreateFileEvent(server.el, newfd, AE_WRITABLE,
                              sendReplyToClient, crdtMaster->master)) {
            serverLog(LL_WARNING,"Error resurrecting the cached master, impossible to add the writable handler: %s", strerror(errno));
            freeClientAsync(crdtMaster->master); /* Close ASAP. */
        }
    }
}

/* Free a cached master, called when there are no longer the conditions for
 * a partial resync on reconnection. */
void crdtReplicationDiscardCachedMaster(CRDT_Master_Instance *crdtMaster) {
    if (crdtMaster->cached_master == NULL) return;

    serverLog(LL_NOTICE,"Discarding previously cached master state.");
    crdtMaster->cached_master->flags &= ~CLIENT_CRDT_MASTER;
    freeClient(crdtMaster->cached_master);
    crdtMaster->cached_master = NULL;
}

/* Once we have a link with the master and the synchroniziation was
 * performed, this function materializes the master client we store
 * at server.master, starting from the specified file descriptor. */
void crdtReplicationCreateMasterClient(CRDT_Master_Instance *crdtMaster, int fd, int dbid) {
    crdtMaster->master = createClient(fd);
    crdtMaster->master->flags |= CLIENT_CRDT_MASTER;
    crdtMaster->master->authenticated = 1;
    crdtMaster->master->reploff = crdtMaster->master_initial_offset;
    crdtMaster->master->read_reploff = crdtMaster->master->reploff;
    memcpy(crdtMaster->master->replid, crdtMaster->master_replid,
           sizeof(crdtMaster->master_replid));
    if (dbid != -1) selectDb(crdtMaster->master,dbid);
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

void crdtReplicationSendAck(CRDT_Master_Instance *masterInstance) {
    client *c = masterInstance->master;

    if (c != NULL) {
        c->flags |= CLIENT_MASTER_FORCE_REPLY;
        addReplyMultiBulkLen(c,3);
        addReplyBulkCString(c,"CRDT.REPLCONF");
        addReplyBulkCString(c,"ACK");
        addReplyBulkLongLong(c,c->reploff);
        addReplyMultiBulkLen(c,3);
        addReplyBulkCString(c,"CRDT.REPLCONF");
        addReplyBulkCString(c,"ack-vc");
        addReplyBulkCString(c,vectorClockToSds(c->vectorClock));
        c->flags &= ~CLIENT_MASTER_FORCE_REPLY;
    }
}

void crdtReplicationCacheMaster(client *c) {
    if (!(c->flags & CLIENT_CRDT_MASTER)) {
        return;
    }
    CRDT_Master_Instance *crdtMaster = getPeerMaster(c->gid);
    if (crdtMaster == NULL) {
        crdtMaster = createPeerMaster(c, c->gid);
    }
    serverLog(LL_NOTICE,"Caching the disconnected master state.");

    /* Unlink the client from the server structures. */
    unlinkClient(c);

    /* Reset the master client so that's ready to accept new commands:
     * we want to discard te non processed query buffers and non processed
     * offsets, including pending transactions, already populated arguments,
     * pending outputs to the master. */
    sdsclear(crdtMaster->master->querybuf);
    sdsclear(crdtMaster->master->pending_querybuf);
    crdtMaster->master->read_reploff = crdtMaster->master->reploff;
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
    CRDT_Master_Instance *masterInstance = getPeerMaster(c->gid);
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

/* Replication cron function, called 1 time per second. */
void crdtReplicationCron(void) {
    static long long replication_cron_loops = 0;
    listIter li;
    listNode *ln;
    /* Non blocking connection timeout? */

    listRewind(crdtServer.crdtMasters, &li);
    while((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;


        if (crdtMaster->masterhost &&
            (crdtMaster->repl_state == REPL_STATE_CONNECTING || crdtSlaveIsInHandshakeState(crdtMaster)) &&
            (time(NULL) - crdtMaster->repl_transfer_lastio) > crdtServer.repl_timeout) {
            serverLog(LL_WARNING, "Timeout connecting to the MASTER...");
            crdtCancelReplicationHandshake(crdtMaster->gid);
        }

        /* Bulk transfer I/O timeout? */
        if (crdtMaster->masterhost && crdtMaster->repl_state == REPL_STATE_TRANSFER &&
            (time(NULL) - crdtMaster->repl_transfer_lastio) > crdtServer.repl_timeout) {
            serverLog(LL_WARNING,
                      "Timeout receiving bulk data from MASTER... If the problem persists try to set the 'repl-timeout' parameter in redis.conf to a larger value.");
            crdtCancelReplicationHandshake(crdtMaster->gid);
        }

        /* Timed out master when we are an already connected slave? */
        if (crdtMaster->masterhost && crdtMaster->repl_state == REPL_STATE_CONNECTED &&
            (time(NULL) - crdtMaster->master->lastinteraction) > crdtServer.repl_timeout) {
            serverLog(LL_WARNING, "MASTER timeout: no data nor PING received...");
            freeClient(crdtMaster->master);
        }

        /* Check if we should connect to a MASTER */
        if (crdtMaster->repl_state == REPL_STATE_CONNECT) {
            serverLog(LL_NOTICE, "Crdt Connecting to MASTER %s:%d",
                      crdtMaster->masterhost, crdtMaster->masterport);
            if (crdtConnectWithMaster(crdtMaster) == C_OK) {
                serverLog(LL_NOTICE, "MASTER <-> SLAVE sync started");
            }
        }

        /* Send ACK to master from time to time.
         * Note that we do not send periodic acks to masters that don't
         * support PSYNC and replication offsets. */
        if (crdtMaster->masterhost && crdtMaster->master &&
                (crdtMaster->repl_state == REPL_STATE_CONNECTED)) {
            crdtReplicationSendAck(crdtMaster);
        }
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
                      "Crdt Replication backlog freed after %d seconds "
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
        listNode *ln = NULL;
        listIter li;

        listRewind(crdtServer.slaves,&li);
        while((ln = listNext(&li))) {
            client *slave = ln->value;
            if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) {
                idle = crdtServer.unixtime - slave->lastinteraction;
                if (idle > max_idle) max_idle = idle;
                slaves_waiting++;
            }
        }

        if (slaves_waiting > 0 && max_idle > crdtServer.repl_diskless_sync_delay) {
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
