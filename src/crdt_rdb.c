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
// Created by zhuchen on 2019-05-24.
//

#include "vector_clock.h"
#include "crdt_rdb.h"
#include "rdb.h"
#include "rio.h"


/**---------------------------CRDT RDB Send Functions--------------------------------*/
/* Spawn an RDB child that writes the RDB to the sockets of the slaves
 * that are currently in SLAVE_STATE_WAIT_BGSAVE_START state. */
int
rdbSaveToCrdtSlavesSockets(crdtRdbSaveInfo *rsi) {
    int *fds;
    uint64_t *clientids;
    int numfds;
    listNode *ln;
    listIter li;
    pid_t childpid;
    long long start;
    int pipefds[2];

    if (crdtServer.aof_child_pid != -1 || crdtServer.rdb_child_pid != -1) return C_ERR;

    /* Before to fork, create a pipe that will be used in order to
     * send back to the parent the IDs of the slaves that successfully
     * received all the writes. */
    if (pipe(pipefds) == -1) return C_ERR;
    crdtServer.rdb_pipe_read_result_from_child = pipefds[0];
    crdtServer.rdb_pipe_write_result_to_parent = pipefds[1];

    /* Collect the file descriptors of the slaves we want to transfer
     * the RDB to, which are i WAIT_BGSAVE_START state. */
    fds = zmalloc(sizeof(int)*listLength(crdtServer.slaves));
    /* We also allocate an array of corresponding client IDs. This will
     * be useful for the child process in order to build the report
     * (sent via unix pipe) that will be sent to the parent. */
    clientids = zmalloc(sizeof(uint64_t)*listLength(crdtServer.slaves));
    numfds = 0;

    listRewind(crdtServer.slaves, &li);
    while((ln = listNext(&li))) {
        client *slave = ln->value;

        if (slave->replstate == SLAVE_STATE_WAIT_BGSAVE_START) {
            clientids[numfds] = slave->id;
            fds[numfds++] = slave->fd;
            replicationSetupSlaveForFullResync(slave, getPsyncInitialOffset(crdtServer));
            /* Put the socket in blocking mode to simplify RDB transfer.
             * We'll restore it when the children returns (since duped socket
             * will share the O_NONBLOCK attribute with the parent). */
            anetBlock(NULL,slave->fd);
            anetSendTimeout(NULL, slave->fd, crdtServer.repl_timeout*1000);
        }
    }

    /* Create the child process. */
    openChildInfoPipe(crdtServer);
    start = ustime();
    if ((childpid = fork()) == 0) {
        /* Child */
        int retval;
        rio slave_sockets;

        rioInitWithFdset(&slave_sockets,fds,numfds);
        zfree(fds);

        closeListeningSockets(0);
        redisSetProcTitle("crdt-rdb-to-slaves");

        retval = rdbSaveRioWithCrdtMerge(&slave_sockets,NULL,rsi);
        if (retval == C_OK && rioFlush(&slave_sockets) == 0)
            retval = C_ERR;

        if (retval == C_OK) {
            size_t private_dirty = zmalloc_get_private_dirty(-1);

            if (private_dirty) {
                serverLog(LL_NOTICE,
                          "RDB: %zu MB of memory used by copy-on-write",
                          private_dirty/(1024*1024));
            }

            crdtServer.child_info_data.cow_size = private_dirty;
            sendChildInfo(CHILD_INFO_TYPE_RDB, crdtServer);

            /* If we are returning OK, at least one slave was served
             * with the RDB file as expected, so we need to send a report
             * to the parent via the pipe. The format of the message is:
             *
             * <len> <slave[0].id> <slave[0].error> ...
             *
             * len, slave IDs, and slave errors, are all uint64_t integers,
             * so basically the reply is composed of 64 bits for the len field
             * plus 2 additional 64 bit integers for each entry, for a total
             * of 'len' entries.
             *
             * The 'id' represents the slave's client ID, so that the master
             * can match the report with a specific slave, and 'error' is
             * set to 0 if the replication process terminated with a success
             * or the error code if an error occurred. */
            void *msg = zmalloc(sizeof(uint64_t)*(1+2*numfds));
            uint64_t *len = msg;
            uint64_t *ids = len+1;
            int j, msglen;

            *len = numfds;
            for (j = 0; j < numfds; j++) {
                *ids++ = clientids[j];
                *ids++ = slave_sockets.io.fdset.state[j];
            }

            /* Write the message to the parent. If we have no good slaves or
             * we are unable to transfer the message to the parent, we exit
             * with an error so that the parent will abort the replication
             * process with all the childre that were waiting. */
            msglen = sizeof(uint64_t)*(1+2*numfds);
            if (*len == 0 ||
                write(crdtServer.rdb_pipe_write_result_to_parent,msg,msglen)
                != msglen)
            {
                retval = C_ERR;
            }
            zfree(msg);
        }
        zfree(clientids);
        rioFreeFdset(&slave_sockets);
        exitFromChild((retval == C_OK) ? 0 : 1);
    } else {
        /* Parent */
        if (childpid == -1) {
            serverLog(LL_WARNING,"Can't save in background: fork: %s",
                      strerror(errno));

            /* Undo the state change. The caller will perform cleanup on
             * all the slaves in BGSAVE_START state, but an early call to
             * replicationSetupSlaveForFullResync() turned it into BGSAVE_END */
            listRewind(crdtServer.slaves,&li);
            while((ln = listNext(&li))) {
                client *slave = ln->value;
                int j;

                for (j = 0; j < numfds; j++) {
                    if (slave->id == clientids[j]) {
                        slave->replstate = SLAVE_STATE_WAIT_BGSAVE_START;
                        break;
                    }
                }
            }
            close(pipefds[0]);
            close(pipefds[1]);
            closeChildInfoPipe(crdtServer);
        } else {
            crdtServer.stat_fork_time = ustime()-start;
            crdtServer.stat_fork_rate = (double) zmalloc_used_memory() * 1000000 / server.stat_fork_time / (1024*1024*1024); /* GB per second. */
            latencyAddSampleIfNeeded("fork",server.stat_fork_time/1000);

            serverLog(LL_NOTICE,"Background RDB transfer started by pid %d",
                      childpid);
            crdtServer.rdb_save_time_start = time(NULL);
            crdtServer.rdb_child_pid = childpid;
            crdtServer.rdb_child_type = RDB_CHILD_TYPE_SOCKET;
            updateDictResizePolicy();
        }
        zfree(clientids);
        zfree(fds);
        return (childpid == -1) ? C_ERR : C_OK;
    }
    return C_OK; /* Unreached. */
}


//CRDT.MERGE_START <local-gid> <vector-clock> <repl_id>
//CRDT.MERGE_END <local-gid> <vector-clock> <repl_id> <offset>
int
rdbSaveRioWithCrdtMerge(rio *rdb, int *error, crdtRdbSaveInfo *rsi) {

    if (error) *error = 0;
    if (rioWrite(rdb, "*4\r\n", 3) == 0) goto werr;
    if (rioWriteBulkString(rdb, "CRDT.MERGE_START", 16) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
    sds sdsVectorClock = convertVectorClockToSds(rsi->vc);
    if (rioWriteBulkString(rdb, sdsVectorClock, sdslen(sdsVectorClock)) == 0) goto werr;
    if (rioWriteBulkString(rdb, rsi->repl_id, 41) == 0) goto werr;

    if (crdtRdbSaveRio(rdb, error, rsi) == C_ERR) goto werr;

    if (rioWrite(rdb, "*5\r\n", 3) == 0) goto werr;
    if (rioWriteBulkString(rdb, "CRDT.MERGE_END", 14) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
    if (rioWriteBulkString(rdb, sdsVectorClock, sdslen(sdsVectorClock)) == 0) goto werr;
    if (rioWriteBulkString(rdb, rsi->repl_id, 41) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, rsi->repl_offset) == 0) goto werr;

    return C_OK;

    werr: /* Write error. */
    /* Set 'error' only if not already set by rdbSaveRio() call. */
    if (error && *error == 0) *error = errno;
    return C_ERR;
}

//CRDT.Merge <gid> <RDB-key> <expire-if-possible> <RDB-value>
int
crdtRdbSaveRio(rio *rdb, int *error, crdtRdbSaveInfo *rsi) {
    dictIterator *di = NULL;
    dictEntry *de;
    char llstr[LONG_STR_SIZE];
    int j;
    long long now = mstime();

    if (crdtServer.rdb_checksum)
        rdb->update_cksum = rioGenericUpdateChecksum;

    for (j = 0; j < server.dbnum; j++) {
        redisDb *db = server.db+j;
        dict *d = db->dict;
        if (dictSize(d) == 0) continue;
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;

        /*Send select command first before we send merge command*/
        robj *selectcmd;
        int dictid = j;
        /* Write the SELECT DB opcode */
        if (dictid >= 0 && dictid < PROTO_SHARED_SELECT_CMDS) {
            selectcmd = shared.select[dictid];
        } else {
            int dictid_len;

            dictid_len = ll2string(llstr,sizeof(llstr),dictid);
            selectcmd = createObject(OBJ_STRING,
                                     sdscatprintf(sdsempty(),
                                                  "*2\r\n$6\r\nSELECT\r\n$%d\r\n%s\r\n",
                                                  dictid_len, llstr));
        }
        if(rioWriteBulkObject(rdb, selectcmd) == 0) goto werr;


        /* Iterate this DB writing every entry */
        while((de = dictNext(di)) != NULL) {
            sds keystr = dictGetKey(de);
            robj key, *o = dictGetVal(de);
            long long expire;
            if(o->type != OBJ_MODULE) {
                continue;
            }

            /* Check if the crdt module is avaiable for merge */
            moduleValue *mv = o->ptr;
            moduleType *mt = mv->type;
            if(mt->is_mergable(convertVectorClockToSds(rsi->vc), mv->value) != C_OK) {
                continue;
            }

            //CRDT.Merge <gid> <RDB-key> <expire-if-possible> <RDB-value>
            initStaticStringObject(key,keystr);
            expire = getExpire(db,&key);
            // not send if expired already
            if (expire != -1 && expire < now) {
                continue;
            }

            if (rioWriteBulkString(rdb, "CRDT.Merge", 10) == 0) goto werr;
            if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
            if (crdtRdbSaveKeyValuePair(rdb,&key,o,expire) == -1) goto werr;

        }
        dictReleaseIterator(di);
    }
    return C_OK;

    werr:
    if (error) *error = errno;
    if (di) dictReleaseIterator(di);
    return C_ERR;
}

/* Save a key-value pair, with expire time, type, key, value.
 * On error -1 is returned.
 * On success if the key was actually saved 1 is returned, otherwise 0
 * is returned (the key was already expired). */
int
crdtRdbSaveKeyValuePair(rio *rdb, robj *key, robj *val, long long expiretime) {

    /* Save key, value */
    rio *buffer = NULL;
    sds rdbKeyStr = sdsempty();
    rioInitWithBuffer(buffer, rdbKeyStr);
    if (rdbSaveStringObject(buffer,key) == -1) {
        sdsfree(rdbKeyStr);
        return -1;
    }
    if (rioWriteBulkString(rdb, rdbKeyStr, sdslen(rdbKeyStr)) == 0) {
        sdsfree(rdbKeyStr);
        return -1;
    }
    sdsfree(rdbKeyStr);

    /* Save the expire time */

    if (rioWriteBulkLongLong(rdb,expiretime) == 0) return -1;

    if (crdtRdbSaveObject(rdb,val) == -1) return -1;
    return 1;
}

int
crdtRdbSaveObject(rio *rdb, robj *val) {
    if(val->type != OBJ_MODULE) {
        return 0;
    }

    rio *buffer = NULL;
    sds buf = sdsempty();
    rioInitWithBuffer(buffer, buf);

    /* Save a module-specific value. */
    RedisModuleIO io;
    moduleValue *mv = val->ptr;
    moduleType *mt = mv->type;
    moduleInitIOContext(io,mt,buffer);

    /* Write the "module" identifier as prefix, so that we'll be able
     * to call the right module during loading. */
    int retval = rdbSaveLen(buffer,mt->id);
    if (retval == -1) return -1;
    io.bytes += retval;

    /* Then write the module-specific representation + EOF marker. */
    mt->rdb_save(&io,mv->value);
    retval = rdbSaveLen(buffer, RDB_MODULE_OPCODE_EOF);
    if (retval == -1) return -1;
    io.bytes += retval;

    if(rioWriteBulkString(rdb, buf, sdslen(buf)) == 0) {
        sdsfree(buf);
        return -1;
    }
    sdsfree(buf);

    if (io.ctx) {
        moduleFreeContext(io.ctx);
        zfree(io.ctx);
    }
    return io.error ? -1 : (ssize_t)io.bytes;
}

/**---------------------------CRDT Merge Command--------------------------------*/
//CRDT.Merge <gid> <key> <RDB-value>
//void
//crdtMergeCommand(client *c) {
//    long long sourceGid;
//    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) return;
//    robj *keyObj = c->argv[2];
//}


/**------------------------RIO Related Utility Functions--------------------*/

//int rioWriteBulkString(rio *rdb, const char *str, long long len) {
//
//}

#if defined(CRDT_RDB_TEST_MAIN)
#include <stdio.h>
#include <stdlib.h>
#include "testhelp.h"
#include "limits.h"

int testCrdtRdbSaveObject(void) {
    printf("========[testCrdtRdbSaveObject]==========\r\n");

    rio *buffer = NULL;
    sds buf = sdsempty();
    rioInitWithBuffer(buffer, buf);

    sds example = sdsnew("Hello, World!");
    rioWriteBulkString(buffer, example, sdslen(example));
    test_cond("buffer test", sdscmp(example, sdsnew("Hello, World!")) == 0)

    return 0;
}

int crdtRdbTest(void) {
    int result = 0;
    {
        result |= testCrdtRdbSaveObject();
    }
    test_report();
    return result;
}
#endif

#ifdef CRDT_RDB_TEST_MAIN
int main(void) {
    return crdtRdbTest();
}
#endif
