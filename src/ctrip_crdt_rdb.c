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


/**---------------------------CRDT RDB Send Functions--------------------------------*/
/* Spawn an RDB child that writes the RDB to the sockets of the slaves
 * that are currently in SLAVE_STATE_WAIT_BGSAVE_START state. */


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

    sds sdsVectorClock = vectorClockToSds(crdtServer.vectorClock);
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

    sdsfree(sdsVectorClock);
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] C_OK");
    return C_OK;

werr: /* Write error. */
    /* Set 'error' only if not already set by rdbSaveRio() call. */
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] error");
    if (error && *error == 0) *error = errno;
    return C_ERR;
}

int crdtSendMergeRequest(rio *rdb, crdtRdbSaveInfo *rsi, dictIterator *di, const char *cmdname) {
    dictEntry *de;
    rio payload;

    /* Iterate this DB writing every entry */
    while((de = dictNext(di)) != NULL) {
        sds keystr = dictGetKey(de);
        robj key, *o = dictGetVal(de);
        if(o->type != OBJ_MODULE || isModuleCrdt(o) != C_OK) {
            serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] NOT CRDT MODULE, SKIP");
            continue;
        }

        /* Check if the crdt module's vector clock on local gid is avaiable for crdt merge */
        
        CrdtObject *object = retrieveCrdtObject(o);
        CrdtObject *filter = object->method->filter((void*)object, crdtServer.crdt_gid, rsi->logic_time);
        if(filter == NULL) {
            continue;
        }

        moduleValue *mv = o->ptr;
        // void *moduleValue = mv->value;
        robj *result = createModuleObject(mv->type, filter);
        //CRDT.Merge <src-gid> <key>  <ttl> <value>
        initStaticStringObject(key,keystr);

        serverAssertWithInfo(NULL, &key, sdsEncodedObject((&key)));
        if(!rioWriteBulkCount(rdb, '*', 4)) return C_ERR;
        // if(!rioWriteBulkString(rdb,"CRDT.Merge",10)) return C_ERR;
        if(!rioWriteBulkString(rdb, cmdname, strlen(cmdname))) return C_ERR;
        if(!rioWriteBulkLongLong(rdb, crdtServer.crdt_gid)) return C_ERR;
        if(!rioWriteBulkString(rdb, (&key)->ptr,sdslen((&key)->ptr))) return C_ERR;

        /* Emit the payload argument, that is the serialized object using
         * * the DUMP format. */
        createDumpPayload(&payload, result);
        if (!rioWriteBulkString(rdb, payload.io.buffer.ptr, sdslen(payload.io.buffer.ptr))) {
            sdsfree(payload.io.buffer.ptr);
            return C_ERR;
        }
        sdsfree(payload.io.buffer.ptr);

    }
    return C_OK;
}

// CRDT.Merge_Del <gid> <key> <val>
int crdtSendMergeDelRequest(rio *rdb, crdtRdbSaveInfo *rsi, dictIterator *di, const char* cmdname) {
    dictEntry *de;
    rio payload;

    /* Iterate this DB tombstone writing every entry that is locally changed, but not gc'ed*/
    while((de = dictNext(di)) != NULL) {
        sds keystr = dictGetKey(de);
        robj key, *o = dictGetVal(de);
        if(o->type != OBJ_MODULE || isModuleCrdt(o) != C_OK) {
            serverLog(LL_NOTICE, "[CRDT] [crdtSendMergeDelRequest] NOT CRDT MODULE, SKIP");
            continue;
        }

        /* Check if the crdt module's vector clock on local gid is avaiable for crdt merge */
         // moduleValue *mv = o->ptr;
        // void *moduleValue = mv->value;
        CrdtTombstone *tombstone = retrieveCrdtTombstone(o);
        CrdtTombstone *result = tombstone->method->filter(tombstone, crdtServer.crdt_gid, rsi->logic_time);
        if(result == NULL) {
            continue;
        }
       
        //CRDT.Merge_Del <gid> <key> <val>
        initStaticStringObject(key,keystr);

        serverAssertWithInfo(NULL, &key, sdsEncodedObject((&key)));
        if(!rioWriteBulkCount(rdb, '*', 4)) return C_ERR;
        if(!rioWriteBulkString(rdb,cmdname,strlen(cmdname)))    return C_ERR;
        if(!rioWriteBulkLongLong(rdb, crdtServer.crdt_gid)) return C_ERR;
        if(!rioWriteBulkString(rdb, (&key)->ptr,sdslen((&key)->ptr)))   return C_ERR;
        
        /* Emit the payload argument, that is the serialized object using
         * * the DUMP format. */
        createDumpPayload(&payload, o);
        if(!rioWriteBulkString(rdb, payload.io.buffer.ptr,
                                                sdslen(payload.io.buffer.ptr))) {
            sdsfree(payload.io.buffer.ptr);
            return C_ERR;
        }
        sdsfree(payload.io.buffer.ptr);
    }
    return C_OK;
}

//CRDT.Merge <src-gid> <key> <vc> <timestamp/-1> <ttl> <value>
int
crdtRdbSaveRio(rio *rdb, int *error, crdtRdbSaveInfo *rsi) {
    dictIterator *di = NULL;
    char llstr[LONG_STR_SIZE];
    int j;

    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] start");
    for (j = 0; j < server.dbnum; j++) {
        redisDb *db = server.db+j;
        dict *d = db->dict;
        if (
            dictSize(d) == 0 && 
            dictSize(db->deleted_keys) == 0 &&
            dictSize(db->expires) == 0 &&
            dictSize(db->deleted_expires) == 0
        ) continue;
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;

        /*Send select command first before we send merge command*/
        robj *selectcmd;
        int needDelete = C_ERR;
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
            needDelete = C_OK;
        }
        if(rioWriteBulkObject(rdb, selectcmd) == 0) goto werr;
        if (needDelete == C_OK) {
            decrRefCount(selectcmd);
        }
        if (dictSize(d) != 0 && crdtSendMergeRequest(rdb, rsi, di, "CRDT.Merge") == C_ERR) {
            goto werr;
        }
        dictReleaseIterator(di);

        d = db->deleted_keys;
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;
        if (dictSize(d) != 0 && crdtSendMergeDelRequest(rdb, rsi, di, "CRDT.Merge_Del") == C_ERR) {
            goto werr;
        }
        dictReleaseIterator(di);

        d = db->expires;
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;
        if (dictSize(d) != 0 && crdtSendMergeRequest(rdb, rsi, di, "CRDT.merge_expire") == C_ERR) {
            goto werr;
        }
        dictReleaseIterator(di);

        d = db->deleted_expires;
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;
        if (dictSize(d) != 0 && crdtSendMergeDelRequest(rdb, rsi, di, "CRDT.merge_del_expire") == C_ERR) {
            goto werr;
        }
        dictReleaseIterator(di);
        
    }
    serverLog(LL_NOTICE, "[CRDT] [crdtRdbSaveRio] end");
    return C_OK;

    werr:
    if (error) *error = errno;
    if (di) dictReleaseIterator(di);
    return C_ERR;
}

/**---------------------------CRDT Merge Command--------------------------------*/
static int updateReplTransferLastio(long long gid) {
    CRDT_Master_Instance *peerMasterServer = getPeerMaster(gid);
    if(peerMasterServer == NULL) {
        return C_ERR;
    }
    peerMasterServer->repl_transfer_lastio = server.unixtime;
    return C_OK;
}
typedef robj* (*DictFindFunc)(redisDb* db, robj* key);
typedef int (*DictDeleteFunc)(redisDb* db, robj* key);
typedef void (*DictAddFunc)(redisDb* db, robj* key, robj* value);
typedef int (*CheckTypeFunc)(void* current, void* merge, robj* key);
int crdtMergeTomstoneCommand(client* c, DictFindFunc findtombstone, DictAddFunc addtombstone, DictFindFunc findval, DictDeleteFunc deleteval, CheckTypeFunc checktype) {
    rio payload;
    robj *obj;
    int type;
    long long sourceGid;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) goto error;
    if (updateReplTransferLastio(sourceGid) != C_OK) goto error;
    robj *key = c->argv[2];

    if (verifyDumpPayload(c->argv[3]->ptr,sdslen(c->argv[3]->ptr)) == C_ERR) {
        goto error;
    }
    
    rioInitWithBuffer(&payload,c->argv[3]->ptr);
    if (((type = rdbLoadObjectType(&payload)) == -1) ||
        ((obj = rdbLoadObject(type,&payload)) == NULL))
    {
        goto error;
    }
    
    /**
     * For tombstone object, if it has been deleted, we need to delete our object first
     * **/
    CrdtTombstone *tombstoneCrdtCommon = NULL;
    robj* tombstone = findtombstone(c->db,key);
    if (tombstone != NULL) {
        // moduleValue *mv = obj->ptr;
        // void *moduleDataType = mv->value;
        CrdtTombstone *common = retrieveCrdtTombstone(obj);
        
        // void *oldModuleDataType = old_mv->value;
        CrdtTombstone *oldCommon = retrieveCrdtTombstone(tombstone);
        if(checktype(common, oldCommon, key) != C_OK) {
            decrRefCount(obj);
            return C_ERR;
        }
        
       
        void *mergedVal = common->method->merge(common, oldCommon);
        moduleValue *old_mv = tombstone->ptr;
        old_mv->type->free(old_mv->value);
        old_mv->value = mergedVal;
        tombstoneCrdtCommon = mergedVal;
        decrRefCount(obj);
    }else{
        tombstoneCrdtCommon = retrieveCrdtTombstone(obj);
        addtombstone(c->db, key, obj);
    }
    robj *currentVal = findval(c->db, key);
    if(currentVal != NULL) {
        CrdtObject *currentCrdtCommon = retrieveCrdtObject(currentVal);
        if(tombstoneCrdtCommon->method->purage(tombstoneCrdtCommon, currentCrdtCommon)) {
            // dbDelete(c->db, key);
            deleteval(c->db, key);
        }
    }
    
    server.dirty++;
    return C_OK;

error:
    crdtCancelReplicationHandshake(sourceGid);
    return C_ERR;
}
robj* findRobj(dict* d, void* key) {
    dictEntry *de = dictFind(d, key);
    if(de == NULL) return NULL;
    return dictGetVal(de);
}
robj* findExpireTombstone(redisDb *db, robj *key) {
    return findRobj(db->deleted_expires, key->ptr);
}
int deleteExpire(redisDb *db, robj *key) {
    return dictDelete(db->expires, key->ptr);
}
robj* findExpire(redisDb  *db, robj* key) {
    return findRobj(db->expires, key->ptr);
}
void addExpireTombstone(redisDb *db, robj *key, robj *value) {
    dictAdd(db->deleted_expires, sdsdup(key->ptr), value);
}
int checkExpireTombstoneType(void* current, void* other, robj* key) {
    CrdtExpireTombstone* c = (CrdtExpireTombstone*)current;
    CrdtExpireTombstone* o = (CrdtExpireTombstone*)other;
    if(c->parent.type != o->parent.type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE EXPIRE TOMBSTONE] key: %s, expire tombstone type: %d, merge type %d",
                key->ptr, c->parent.type, o->parent.type);
        return C_ERR;
    }
    if (c->dataType != o->dataType) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE EXPIRE TOMBSTONE DATATYPE] key: %s, expire tombstone type: %d",
                key->ptr, c->dataType);
        return C_ERR;  
    }
    return C_OK;
}
void crdtMergeDelExpireCommand(client *c) {
    crdtMergeTomstoneCommand(c, 
        findExpireTombstone,
        addExpireTombstone,
        findExpire,
        deleteExpire,
        checkExpireTombstoneType
    );
}
robj* findTombstone(redisDb *db, robj *key) {
    return findRobj(db->deleted_keys, key->ptr);
}
void addTombstone(redisDb *db, robj *key, robj *value) {
    dictAdd(db->deleted_keys, sdsdup(key->ptr), value);
}
int checkTombstoneType(void* current, void* other, robj* key) {
    CrdtTombstone* c = (CrdtTombstone*)current;
    CrdtTombstone* o = (CrdtTombstone*)other;
    if(c->type != o->type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE TOMBSTONE] key: %s, tombstone type: %d, merge type %d",
                key->ptr, c->type, o->type);
        return C_ERR;
    }
    if(c->type != CRDT_DATA) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE TOMBSTONE TYPE] key: %s, tombstone type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    return C_OK;
}
void
crdtMergeDelCommand(client *c) {
    crdtMergeTomstoneCommand(c, 
        findTombstone, 
        addTombstone,
        lookupKeyRead,
        dbDelete,
        checkTombstoneType
    );
}

int mergeCrdtObjectCommand(client *c, DictFindFunc find, DictAddFunc add, DictDeleteFunc delete, DictFindFunc findtombstone, CheckTypeFunc checktype) {
    rio payload;
    robj *obj;
    int type;
    long long sourceGid;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK) goto error;
    if (updateReplTransferLastio(sourceGid) != C_OK) goto error;
    robj *key = c->argv[2];


    if (verifyDumpPayload(c->argv[3]->ptr,sdslen(c->argv[3]->ptr)) == C_ERR) {
        goto error;
    }

    rioInitWithBuffer(&payload,c->argv[3]->ptr);
    if (((type = rdbLoadObjectType(&payload)) == -1) ||
        ((obj = rdbLoadObject(type,&payload)) == NULL))
    {
        goto error;
    }

    /* Merge the new object in the hash table */
    moduleType *mt = getModuleType(obj);

    CrdtObject *common = retrieveCrdtObject(obj);
    
    // robj *currentVal = lookupKeyRead(c->db, key);
    robj *currentVal = find(c->db, key);
    CrdtObject *mergedVal;
    if (currentVal) {
        CrdtObject *ccm = retrieveCrdtObject(currentVal);
        if(checktype(ccm, common, key) != C_OK) {
            decrRefCount(obj);
            return C_ERR;
        }
        mergedVal = common->method->merge(ccm, common);
        delete(c->db, key);
    } else {
        mergedVal = common->method->merge(NULL, common);
    }
    decrRefCount(obj);
    robj* tombstone = findtombstone(c->db,key);
    if(tombstone != NULL) {
        CrdtTombstone* tom = retrieveCrdtTombstone(tombstone);
        if(tom->method->purage(tom, mergedVal)) {
            mt->free(mergedVal);
            mergedVal = NULL;
        }
    }
    /* Create the key and set the TTL if any */
    if(mergedVal) add(c->db, key, createModuleObject(mt, mergedVal));

    signalModifiedKey(c->db,c->argv[1]);
    server.dirty++;
    return C_OK;

error:
    crdtCancelReplicationHandshake(sourceGid);
    return C_ERR;
}


void addExpire(redisDb *db, robj *key, robj *value) {
    dictAdd(db->expires, sdsdup(key->ptr), value);
}

int checkExpireType(void* current, void* other, robj* key) {
    CrdtObject* c = (CrdtObject*)current;
    CrdtObject* o = (CrdtObject*)other;
    if (c->type != o->type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE EXPIRE] key: %s, local type: %d, merge type %d",
                key->ptr, c->type, o->type);
        return C_ERR;
    }
    if(c->type != CRDT_EXPIRE) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE EXPIRE TYPE ERROR] key: %s, local type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    return C_OK;
}


//CRDT.Merge_Expire <gid> <key>  <value>
// 0           1    2       3   
void crdtMergeExpireCommand(client *c) {
    mergeCrdtObjectCommand(c, 
        findExpire,
        addExpire,
        deleteExpire,
        findExpireTombstone,
        checkExpireType
    );
}


int checkDataType(void* current, void* other, robj* key) {
    CrdtData* c = (CrdtData*)current;
    CrdtData* o = (CrdtData*)other;
    if (c->parent.type != o->parent.type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE] key: %s, local type: %d, merge type %d",
                key->ptr, c->parent.type, o->parent.type);
        return C_ERR;
    }
    if(c->parent.type != CRDT_DATA) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE DATA TYPE ERROR] key: %s, local type: %d",
                key->ptr, c->parent.type);
        return C_ERR;
    }
    
    if (c->dataType != o->dataType) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE DATA] key: %s, local type: %d, merge type %d",
                key->ptr, c->dataType, o->dataType);
        return C_ERR;
    }
    
    return C_OK;
}
// CRDT.Merge <gid> <key>  <value>
// 0           1    2       3  
void crdtMergeCommand(client *c) {
    mergeCrdtObjectCommand(c, 
        lookupKeyRead,
        dbAdd,
        dbDelete,
        findTombstone,
        checkDataType
    );
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
