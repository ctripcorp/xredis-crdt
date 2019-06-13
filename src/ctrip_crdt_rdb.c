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

//CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <expire> <value>
int
crdtRdbSaveRio(rio *rdb, int *error, crdtRdbSaveInfo *rsi) {
    dictIterator *di = NULL;
    dictEntry *de;
    char llstr[LONG_STR_SIZE];
    int j;
    long long now = mstime();

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
            serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] retrieve [CrdtCommon]");
            CrdtCommon *common = (CrdtCommon *) moduleValue;
            serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] retrieve [CrdtCommon.vc]");
            VectorClock *vc = sdsToVectorClock(common->vectorClock);
            serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] compare [CrdtCommon.vc]");
            int result = vectorClockCmp(vc, rsi->vc, crdtServer.crdt_gid);
            serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] vector clock compare: %d", result);
            freeVectorClock(vc);
            if (result < 0) {
                continue;
            }

            //CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <expire> <value>
            initStaticStringObject(key,keystr);
            expire = getExpire(db,&key);
            // not send if expired already
            if (expire != -1 && expire < now) {
                continue;
            }

            if (rioWrite(rdb, "*7\r\n", 4) == 0) goto werr;
            if (rioWriteBulkString(rdb, "CRDT.Merge", 10) == 0) goto werr;
            if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
            if (crdtRdbSaveKeyValuePair(rdb, &key, o, expire) == -1) goto werr;

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
//<key> <vc> <timestamp/-1> <expire> <value>
int
crdtRdbSaveKeyValuePair(rio *rdb, robj *key, robj *val, long long expireTime) {

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveKeyValuePair] write key");
    // write $N/r/nkey/r/n
    if (rioWriteBulkObject(rdb, key) == 0) return -1;

    moduleValue *mv = val->ptr;
    void *moduleValue = mv->value;
    CrdtCommon *common = (CrdtCommon *) moduleValue;
    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveKeyValuePair] write vc");
    // write $N/r/n/vc/r/n
    if (rioWriteBulkString(rdb, common->vectorClock, sdslen(common->vectorClock)) == 0) return -1;

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveKeyValuePair] write timestamp");
    // write $N/r/ntimestamp/r/n
    if (rioWriteBulkLongLong(rdb, common->timestamp) == 0) return -1;

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveKeyValuePair] write expire time");
    // write $N/r/n/expireTime/r/n
    if (rioWriteBulkLongLong(rdb, expireTime) == 0) return -1;

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveKeyValuePair] write value");
    // write $N/r/n/compressed val/r/n
    if (crdtRdbSaveObject(rdb, val) == -1) return -1;

    return 1;
}

int
crdtRdbSaveObject(rio *rdb, robj *val) {
    if(val->type != OBJ_MODULE) {
        return 0;
    }
    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject] init buffer");
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

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject] compressed val: %lu", sdslen(buf));
    if(rioWriteBulkString(rdb, buf, sdslen(buf)) == 0) {
        serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject][ERROR] write compressed val ");
        sdsfree(buf);
        return -1;
    }
    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject] write val success");
    sdsfree(buf);

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject] free buf");
    if (io.ctx) {
        moduleFreeContext(io.ctx);
        zfree(io.ctx);
    }
    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveObject] ok");
    return io.error ? -1 : (ssize_t)io.bytes;
}

/**---------------------------CRDT Merge Command--------------------------------*/
//CRDT.Merge <gid> <key> <vc> <timestamp/-1> <expire> <value>
// 0           1    2     3      4             5        6
void
crdtMergeCommand(client *c) {
    long long sourceGid, timestamp, expire;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) goto error;
    robj *key = c->argv[2];

    if (getLongLongFromObjectOrReply(c, c->argv[4], &timestamp, NULL) != C_OK) goto error;
    if (getLongLongFromObjectOrReply(c, c->argv[5], &expire, NULL) != C_OK) goto error;

    sds rdbVal = sdsdup(c->argv[6]->ptr);
    rio *buf = NULL;
    rioInitWithBuffer(buf, rdbVal);
    /* Read value */
    robj *val;
    if ((val = rdbLoadObject(RDB_TYPE_MODULE_2, buf)) == NULL) goto error;

    /* Merge the new object in the hash table */
    moduleValue *mv = val->ptr;
    moduleType *mt = mv->type;
    void *moduleDataType = mv->value;
    CrdtCommon *common = (CrdtCommon *) moduleDataType;

    robj *currentVal = lookupKeyWrite(c->db, key);
    void *mergedVal;
    if (currentVal) {
        moduleValue *cmv = currentVal->ptr;
        // call merge function, and store the merged val
        mergedVal = common->merge(cmv->value, mv->value);
        decrRefCount(currentVal);
    } else {
        mergedVal = common->merge(NULL, mv->value);
    }
    setKey(c->db, key, createModuleObject(mt, mergedVal));
    decrRefCount(val);


    /* Set the expire time if needed */
    if (expire != -1 && getExpire(c->db, key) <= expire) {
        setExpire(NULL, c->db, key, expire);
    }
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
