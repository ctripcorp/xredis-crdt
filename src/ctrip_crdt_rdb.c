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

#include "ctrip_vector_clock.h"
#include "ctrip_crdt_rdb.h"
#include "rdb.h"
#include "rio.h"
#include "server.h"
#include "ctrip_crdt_replication.h"


/**---------------------------CRDT RDB Send Functions--------------------------------*/
/* Spawn an RDB child that writes the RDB to the sockets of the slaves
 * that are currently in SLAVE_STATE_WAIT_BGSAVE_START state. */

// replace to `int rdbSaveToSlavesSockets(rdbSaveInfo *rsi)`



//CRDT.MERGE_START <local-gid> <vector-clock> <repl_id>
//CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <expire> <value>
//CRDT.MERGE_END <local-gid> <vector-clock> <repl_id> <offset>
int
rdbSaveRioWithCrdtMerge(rio *rdb, int *error, void *rsi) {

    crdtRdbSaveInfo *info = (crdtRdbSaveInfo*) rsi;
    if (error) *error = 0;
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_START");
    if (rioWrite(rdb, "*4\r\n", 4) == 0) goto werr;
    if (rioWriteBulkString(rdb, "CRDT.MERGE_START", 16) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
    sds sdsVectorClock = vectorClockToSds(info->vc);
    if (rioWriteBulkString(rdb, sdsVectorClock, sdslen(sdsVectorClock)) == 0) goto werr;
    if (rioWriteBulkString(rdb, info->repl_id, 41) == 0) goto werr;
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_START %lld %s %s", crdtServer.crdt_gid, sdsVectorClock, info->repl_id);

    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE");
    if (crdtRdbSaveRio(rdb, error, info) == C_ERR) goto werr;

    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_END");
    if (rioWrite(rdb, "*5\r\n", 4) == 0) goto werr;
    if (rioWriteBulkString(rdb, "CRDT.MERGE_END", 14) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
    if (rioWriteBulkString(rdb, sdsVectorClock, sdslen(sdsVectorClock)) == 0) goto werr;
    if (rioWriteBulkString(rdb, info->repl_id, 41) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, info->repl_offset) == 0) goto werr;
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_END %lld %s %s %lld", crdtServer.crdt_gid,
            sdsVectorClock, info->repl_id, info->repl_offset);

    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] C_OK");
    return C_OK;

werr: /* Write error. */
    /* Set 'error' only if not already set by rdbSaveRio() call. */
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] error");
    if (error && *error == 0) *error = errno;
    return C_ERR;
}

//CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <ttl> <value>
int
crdtRdbSaveRio(rio *rdb, int *error, crdtRdbSaveInfo *rsi) {
    dictIterator *di = NULL;
    dictEntry *de;
    char llstr[LONG_STR_SIZE];
    int j;
    long long now = mstime();
    rio payload;

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] start");
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
            if(o->type != OBJ_MODULE || isModuleCrdt(o)) {
                serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] NOT CRDT MODULE, SKIP");
                continue;
            }

            /* Check if the crdt module's vector clock on local gid is avaiable for crdt merge */
            moduleValue *mv = o->ptr;
            void *moduleValue = mv->value;
            CrdtCommon *common = (CrdtCommon *) moduleValue;
            VectorClock *vc = sdsToVectorClock(common->vectorClock);
            int result = vectorClockCmp(vc, rsi->vc, crdtServer.crdt_gid);
            freeVectorClock(vc);

            if (result < 0) {
                continue;
            }

            //CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <ttl> <value>
            initStaticStringObject(key,keystr);
            expire = getExpire(db,&key);
            // not send if expired already
            if (expire != -1 && expire < now) {
                continue;
            }

            long long ttl = 0;
            if (expire != -1) {
                ttl = expire-mstime();
                if (ttl < 1) ttl = 1;
            }
            serverAssertWithInfo(NULL, &key, sdsEncodedObject((&key)));
            serverAssertWithInfo(NULL, &key, rioWriteBulkCount(rdb, '*', 7));

            serverAssertWithInfo(NULL, &key, rioWriteBulkString(rdb,"CRDT.Merge",10));
            serverAssertWithInfo(NULL, &key, rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0);
            serverAssertWithInfo(NULL, &key, rioWriteBulkString(rdb, (&key)->ptr,sdslen((&key)->ptr)));
            serverAssertWithInfo(NULL, &key, rioWriteBulkString(rdb, common->vectorClock, sdslen(common->vectorClock)));
            serverAssertWithInfo(NULL, &key, rioWriteBulkLongLong(rdb, common->timestamp));
            serverAssertWithInfo(NULL, &key, rioWriteBulkLongLong(rdb, ttl));

            /* Emit the payload argument, that is the serialized object using
             * * the DUMP format. */
            createDumpPayload(&payload, o);
            serverAssertWithInfo(NULL, &key,
                                 rioWriteBulkString(rdb, payload.io.buffer.ptr,
                                                    sdslen(payload.io.buffer.ptr)));
            sdsfree(payload.io.buffer.ptr);

        }
        dictReleaseIterator(di);
    }
    return C_OK;

    werr:
    if (error) *error = errno;
    if (di) dictReleaseIterator(di);
    return C_ERR;
}

/**---------------------------CRDT Merge Command--------------------------------*/
//CRDT.Merge <gid> <key> <vc> <timestamp/-1> <expire> <value>
// 0           1    2     3      4             5        6
void
crdtMergeCommand(client *c) {
    rio payload;
    robj *obj;
    int type;
    long long sourceGid, timestamp, expire, ttl;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) goto error;
    robj *key = c->argv[2];

    if (getLongLongFromObjectOrReply(c, c->argv[4], &timestamp, NULL) != C_OK) goto error;
    if (getLongLongFromObjectOrReply(c, c->argv[5], &ttl, NULL) != C_OK) goto error;

    if (verifyDumpPayload(c->argv[6]->ptr,sdslen(c->argv[6]->ptr)) == C_ERR) {
        goto error;
    }

    rioInitWithBuffer(&payload,c->argv[6]->ptr);
    if (((type = rdbLoadObjectType(&payload)) == -1) ||
        ((obj = rdbLoadObject(type,&payload)) == NULL))
    {
        goto error;
    }

    /* Merge the new object in the hash table */
    moduleValue *mv = obj->ptr;
    moduleType *mt = mv->type;
    void *moduleDataType = mv->value;
    CrdtCommon *common = (CrdtCommon *) moduleDataType;

    robj *currentVal = lookupKeyRead(c->db, key);
    void *mergedVal;
    if (currentVal) {
        moduleValue *cmv = currentVal->ptr;
        // call merge function, and store the merged val
        mergedVal = common->merge(cmv->value, mv->value);
        dbDelete(c->db, key);
    } else {
        mergedVal = common->merge(NULL, mv->value);
    }

    /* Create the key and set the TTL if any */
    dbAdd(c->db, key, createModuleObject(mt, mergedVal));

    /* Set the expire time if needed */
    if (ttl) {
        expire = mstime() + ttl;
        if (getExpire(c->db, key) <= expire) {
            setExpire(NULL, c->db, key, expire);
        }
    }
    signalModifiedKey(c->db,c->argv[1]);
    server.dirty++;
    return;

error:
    crdtCancelReplicationHandshake(sourceGid);
    return;

}


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
