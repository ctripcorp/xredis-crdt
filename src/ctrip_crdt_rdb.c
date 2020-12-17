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
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_START %d %s %s", crdtServer.crdt_gid, sdsVectorClock, info->repl_id);

    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE");
    if (crdtRdbSaveRio(rdb, error, info) == C_ERR) goto werr;

    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_END");
    if (rioWrite(rdb, "*5\r\n", 4) == 0) goto werr;
    if (rioWriteBulkString(rdb, "CRDT.MERGE_END", 14) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, crdtServer.crdt_gid) == 0) goto werr;
    if (rioWriteBulkString(rdb, sdsVectorClock, sdslen(sdsVectorClock)) == 0) goto werr;
    if (rioWriteBulkString(rdb, info->repl_id, 41) == 0) goto werr;
    if (rioWriteBulkLongLong(rdb, info->repl_offset) == 0) goto werr;
    serverLog(LL_NOTICE, "[CRDT] [rdbSaveRioWithCrdtMerge] CRDT.MERGE_END %d %s %s %lld", crdtServer.crdt_gid,
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

CrdtObject** dataFilter(CrdtObject* data, int gid, long long logic_time, long long maxsize, int* length) {
    CrdtObjectMethod* method = getCrdtObjectMethod(data);
    if(method == NULL) {
        serverLog(LL_WARNING, "[CRDT][crdtRdbSaveRio][dataFilter] NOT FIND CRDT OBJECT FILTER METHOD");
        return NULL;
    }
    return method->filterAndSplit(data, gid, logic_time, maxsize, length);
}
void freeDataFilter(CrdtObject** data, int length) {
    if(length == 0) return;
    CrdtObjectMethod* method = getCrdtObjectMethod(data[0]);
    if(method == NULL) {
        serverLog(LL_WARNING, "[CRDT][crdtRdbSaveRio][freeDataFilter] NOT FIND CRDT OBJECT FILTER METHOD");
        return ;
    }
    method->freefilter(data, length);
}

CrdtObject** tombstoneFilter(CrdtObject* tombstone, int gid, long long logic_time, long long maxsize, int* length) {
    CrdtTombstoneMethod* method = getCrdtTombstoneMethod(tombstone);
    if(method == NULL) {
        serverLog(LL_WARNING, "[CRDT][crdtRdbSaveRio][tombstoneFilter] NOT FIND CRDT TOMBSTONE FILTER METHOD");
        return NULL;
    }
    return method->filterAndSplit(tombstone, gid, logic_time, maxsize, length);
}
void freeTombstoneFilter(CrdtObject** tombstone, int length) {
    CrdtTombstoneMethod* method = getCrdtTombstoneMethod(tombstone[0]);
    if(method == NULL) {
        serverLog(LL_WARNING, "[CRDT][crdtRdbSaveRio][freeTombstoneFilter] NOT FIND CRDT TOMBSTONE FILTER METHOD");
        return ;
    }
    method->freefilter(tombstone, length);
}

#define initStaticModuleObject(_var,_ptr) do { \
    _var.refcount = 1; \
    _var.type = OBJ_MODULE; \
    _var.encoding = OBJ_ENCODING_RAW; \
    _var.ptr = _ptr; \
} while(0)

// CRDT.Merge_Del <gid> <key> <val>
// CRDT.Merge <gid> <key> <val>
int crdtSendMergeRequest(rio *rdb, crdtRdbSaveInfo *rsi, dictIterator *di, const char* cmdname, crdtFilterSplitFunc filterFun, crdtFreeFilterResultFunc freeFilterFunc, redisDb *db) {
    dictEntry *de;
    rio payload;
    robj *result = NULL;
    int num = 0;
    /* Iterate this DB tombstone writing every entry that is locally changed, but not gc'ed*/
    while((de = dictNext(di)) != NULL) {
        sds keystr = dictGetKey(de);
        robj key, *o = dictGetVal(de);
        if(o->type != OBJ_MODULE || isModuleCrdt(o) != C_OK) {
            serverLog(LL_NOTICE, "[CRDT][%s] key: %s,NOT CRDT MODULE OBJECT, SKIP", cmdname, keystr);
            continue;
        }
        initStaticStringObject(key,keystr);
        serverAssertWithInfo(NULL, &key, sdsEncodedObject((&key)));
        long long expire = -1;
        if(db != NULL) {
            expire = getExpire(db,&key);    
        }
        /* Check if the crdt module's vector clock on local gid is avaiable for crdt merge */
        CrdtObject *object = retrieveCrdtObject(o);
        int length = 0;
        CrdtObject **filter = filterFun(object, crdtServer.crdt_gid, rsi->logic_time, server.proto_max_bulk_len, &length);
        if(length == -1) {
            serverLog(LL_WARNING, "[CRDT][FILTER] key:{%s} ,value is too big", keystr);
            goto error;
        }
        if(filter == NULL) {
            continue;
        }
        if(length >= 2) {
            serverLog(LL_WARNING, "[CRDT][SENDMERGE] key:{%s} %d splitted", keystr, length);
        }
        robj result;
        moduleValue *mv = o->ptr;
        moduleValue v = {
            .type = mv->type
        };
        initStaticModuleObject(result, &v);
        for(int i = 0; i < length; i++) {
            v.value = filter[i];
            //CRDT.Merge_Del <gid> <key> <val>
            if(!rioWriteBulkCount(rdb, '*', 5)) goto error;
            if(!rioWriteBulkString(rdb,cmdname,strlen(cmdname))) goto error;
            if(!rioWriteBulkLongLong(rdb, crdtServer.crdt_gid)) goto error;
            if(!rioWriteBulkString(rdb, (&key)->ptr,sdslen((&key)->ptr))) goto error;
            
            /* Emit the payload argument, that is the serialized object using
            * * the DUMP format. */
            createDumpPayload(&payload, &result);
            if(!rioWriteBulkString(rdb, payload.io.buffer.ptr,
                                                    sdslen(payload.io.buffer.ptr))) {
                sdsfree(payload.io.buffer.ptr);
                goto error;
            }
            sdsfree(payload.io.buffer.ptr);
            if(!rioWriteBulkLongLong(rdb, expire)) return C_ERR;
        }
        freeFilterFunc(filter, length);
        
        num++;
    }
    return num;
error:
    if(result != NULL) {decrRefCount(result);}
    return C_ERR;
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
            dictSize(db->deleted_keys) == 0 
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
        if(rioWrite(rdb, selectcmd->ptr, sdslen(selectcmd->ptr)) == 0) goto werr;
        if (needDelete == C_OK) {
            decrRefCount(selectcmd);
        }
        if (dictSize(d) != 0) {
            int num = crdtSendMergeRequest(rdb, rsi, di, "CRDT.Merge", dataFilter, freeDataFilter,db);
            if(num == C_ERR) {
                goto werr;
            }
            serverLog(LL_WARNING, "db :%d ,send crdt data num: %d", j, num);
        }
        dictReleaseIterator(di);

        d = db->deleted_keys;
       
        di = dictGetSafeIterator(d);
        if (!di) return C_ERR;
        if (dictSize(d) != 0) {
            int num = crdtSendMergeRequest(rdb, rsi, di, "CRDT.Merge_Del", tombstoneFilter, freeTombstoneFilter ,NULL);
            if(num == C_ERR) {
                goto werr;
            }
            serverLog(LL_WARNING, "db :%d ,send crdt tombstone num: %d", j, num);
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
static int updateReplTransferLastio(int gid) {
    CRDT_Master_Instance *peerMasterServer = getPeerMaster(gid);
    if(peerMasterServer == NULL) {
        return C_ERR;
    }
    if(iAmMaster() == C_OK) {
        peerMasterServer->repl_transfer_lastio = server.unixtime;
    }
    return C_OK;
}
typedef robj* (*DictFindFunc)(redisDb* db, robj* key);
typedef int (*DictDeleteFunc)(redisDb* db, robj* key);
typedef void (*DictAddFunc)(redisDb* db, robj* key, robj* value);
typedef int (*CheckTypeFunc)(void* current, void* merge, robj* key);
typedef int (*CheckTombstoneDataFunc)(void* tombstone, void* data, robj* key);
int crdtMergeTomstoneCommand(client* c, DictFindFunc findtombstone, DictAddFunc addtombstone, DictFindFunc findval, DictDeleteFunc deleteval, DictDeleteFunc deletetombstone, CheckTypeFunc checktype, CheckTombstoneDataFunc checktdtype) {
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
    CrdtObject *tombstoneCrdtCommon = NULL;
    robj* tombstone = findtombstone(c->db,key);
    if (tombstone != NULL) {
        // moduleValue *mv = obj->ptr;
        // void *moduleDataType = mv->value;
        CrdtObject *common = retrieveCrdtObject(obj);
        
        // void *oldModuleDataType = old_mv->value;
        CrdtObject *oldCommon = retrieveCrdtObject(tombstone);
        if(checktype(common, oldCommon, key) != C_OK) {
            decrRefCount(obj);
            return C_ERR;
        }
        
       CrdtTombstoneMethod* method = getCrdtTombstoneMethod(common);
        if(method == NULL) {
            serverLog(LL_WARNING, "no tombstone merge method, type: %hhu", common->type);
            decrRefCount(obj);
            return C_ERR;
        }
        void *mergedVal = method->merge(common, oldCommon);
        moduleValue *old_mv = tombstone->ptr;
        old_mv->type->free(old_mv->value);
        old_mv->value = mergedVal;
        tombstoneCrdtCommon = mergedVal;
        decrRefCount(obj);
    }else{
        tombstoneCrdtCommon = retrieveCrdtObject(obj);
        addtombstone(c->db, key, obj);
    }
    robj *currentVal = findval(c->db, key);
    if(currentVal != NULL) {
        CrdtObject *currentCrdtCommon = retrieveCrdtObject(currentVal);
        if(checktdtype(tombstoneCrdtCommon, currentCrdtCommon, key) == C_OK) {
            CrdtTombstoneMethod* method = getCrdtTombstoneMethod(tombstoneCrdtCommon);
            if(method == NULL) {
                serverLog(LL_WARNING, "no purge method type:%d", tombstoneCrdtCommon->type);
                return C_ERR;
            }
            int purge = method->purge(tombstoneCrdtCommon, currentCrdtCommon);
            if(purge == PURGE_VAL) {
                // dbDelete(c->db, key);
                deleteval(c->db, key);
            }  else if (purge == PURGE_TOMBSTONE) {
                 deletetombstone(c->db, key);
            }
        } else {
            serverLog(LL_WARNING, "[crdtMergeTomstoneCommand] key:%s ,tombstone and value  purge error", (sds)key->ptr);
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


robj* findTombstone(redisDb *db, robj *key) {
    return findRobj(db->deleted_keys, key->ptr);
}
void addTombstone(redisDb *db, robj *key, robj *value) {
    dictAdd(db->deleted_keys, sdsdup(key->ptr), value);
}
int checkTombstoneType(void* current, void* other, robj* key) {
    CrdtObject* c = (CrdtObject*)current;
    CrdtObject* o = (CrdtObject*)other;
    if(!isTombstone(c)) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE TOMBSTONE TYPE] key: %s, tombstone type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    if(c->type != o->type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE TOMBSTONE] key: %s, tombstone type: %d, merge type %d",
                key->ptr, c->type, o->type);
        incrCrdtConflict(MERGECONFLICT | TYPECONFLICT);
        return C_ERR;
    }
    return C_OK;
}

int checkTombstoneDataType(void* current, void* other, robj* key) {
    CrdtObject* c = (CrdtObject*)current;
    CrdtObject* o = (CrdtObject*)other;
    if(!isTombstone(c)) {
        serverLog(LL_WARNING, "[INCONSIS][TOMBSTONE DATA] TOMBSTONE TYPE key: %s, tombstone type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    if(!isData(other)) {
        serverLog(LL_WARNING, "[INCONSIS][TOMBSTONE DATA] DATA TYPE key: %s, data type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    if(getDataType(c)!= getDataType(o)) {
        serverLog(LL_WARNING, "[INCONSIS][TOMBSTONE DATA] key: %s, tombstone type: %d, data type %d",
                key->ptr, c->type, o->type);
        incrCrdtConflict(MERGECONFLICT | TYPECONFLICT);
        return C_ERR;
    }
    return C_OK;
}
int dbTombstone(redisDb *db, robj* key) {
    return dictDelete(db->deleted_keys, key->ptr);
}
void
crdtMergeDelCommand(client *c) {
    crdtMergeTomstoneCommand(c, 
        findTombstone, 
        addTombstone,
        lookupKeyWrite,
        dbDelete,
        dbTombstone,
        checkTombstoneType,
        checkTombstoneDataType
    );
}

int mergeCrdtObjectCommand(client *c, DictFindFunc find, DictAddFunc add, DictDeleteFunc delete, DictDeleteFunc deletetombstone, DictFindFunc findtombstone, CheckTypeFunc checktype, CheckTombstoneDataFunc checktdtype) {
    rio payload;
    robj *obj;
    int type;
    long long sourceGid;
    long long expireTime = -1;
    if (getLongLongFromObjectOrReply(c, c->argv[1], &sourceGid, NULL) != C_OK)  goto error;
    if(!check_gid(sourceGid)) goto error;
    if (updateReplTransferLastio(sourceGid) != C_OK) goto error;
    robj *key = c->argv[2];

    if (getLongLongFromObjectOrReply(c, c->argv[4], &expireTime, NULL) != C_OK) goto error;
    if (verifyDumpPayload(c->argv[3]->ptr,sdslen(c->argv[3]->ptr)) == C_ERR) {
        goto error;
    }

    rioInitWithBuffer(&payload,c->argv[3]->ptr);
    if (((type = rdbLoadObjectType(&payload)) == -1) ||
        ((obj = rdbLoadObject(type,&payload)) == NULL))
    {
        goto error;
    }
    
    
    
    long long et = getExpire(c->db, key);
    if(et != -1) {
        expireTime = max(et, expireTime);
    }
    /* Merge the new object in the hash table */
    moduleType *mt = getModuleType(obj);

    CrdtObject *common = retrieveCrdtObject(obj);
    
    // robj *currentVal = lookupKeyRead(c->db, key);
    robj *currentVal = find(c->db, key);
    CrdtObject *mergedVal;
    CrdtObjectMethod* method = getCrdtObjectMethod(common);
    if(method == NULL) {
        decrRefCount(obj);
        return C_ERR;
    }
    if (currentVal) {
        CrdtObject *ccm = retrieveCrdtObject(currentVal);
        if(checktype(ccm, common, key) != C_OK) {

            decrRefCount(obj);
            return C_ERR;
        }
        mergedVal = method->merge(ccm, common);
        delete(c->db, key);
    } else {
        mergedVal = method->merge(NULL, common);
    }
    decrRefCount(obj);
    robj* tombstone = findtombstone(c->db,key);
    if(tombstone != NULL) {
        CrdtObject* tom = retrieveCrdtObject(tombstone);
        if(checktdtype(tom, mergedVal, key) == C_OK) {
            CrdtTombstoneMethod* tombstone_method = getCrdtTombstoneMethod(tom);
            if(tombstone_method == NULL) return C_ERR;
            int result = tombstone_method->purge(tom, mergedVal);
            if(result == PURGE_VAL) {
                mt->free(mergedVal);
                mergedVal = NULL;
            } else if(result == PURGE_TOMBSTONE) {
                deletetombstone(c->db, key);
            }
        } else {
            serverLog(LL_WARNING, "[mergeCrdtObjectCommand] key: %s, tombstone and value purge error", (sds)key->ptr);
        }
    }
    /* Create the key and set the TTL if any */
    if(mergedVal) {
        add(c->db, key, createModuleObject(mt, mergedVal));
        if (expireTime != -1) {
            setExpire(c, c->db, key, expireTime);
        }
    }
    
    signalModifiedKey(c->db,c->argv[1]);
    server.dirty++;
    return C_OK;

error:
    serverLog(LL_NOTICE, "[CRDT][mergeCrdtObjectCommand][freeClient] gid: %lld", sourceGid);
    if(iAmMaster() == C_OK) {
        crdtCancelReplicationHandshake(sourceGid);
    } else {
        freeClient(c);
    }
    return C_ERR;
}


void addExpire(redisDb *db, robj *key, robj *value) {
    dictAdd(db->expires, sdsdup(key->ptr), value);
}



int checkDataType(void* current, void* other, robj* key) {
    CrdtObject* c = (CrdtObject*)current;
    CrdtObject* o = (CrdtObject*)other;
    if(!(isData(c))) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE DATA TYPE ERROR] key: %s, local type: %d",
                key->ptr, c->type);
        return C_ERR;
    }
    if (c->type != o->type) {
        serverLog(LL_WARNING, "[INCONSIS][MERGE DATA] key: %s, local type: %d, merge type %d, type: %d != %d",
                key->ptr, getDataType(c), getDataType(o), c->type, o->type);
        incrCrdtConflict(MERGECONFLICT | TYPECONFLICT);
        return C_ERR;
    }
    
    return C_OK;
}
// CRDT.Merge <gid> <key>  <value> <expire>
// 0           1    2       3       4
void crdtMergeCommand(client *c) {
    mergeCrdtObjectCommand(c, 
        lookupKeyWrite,
        dbAdd,
        dbDelete,
        dbTombstone,
        findTombstone,
        checkDataType,
        checkTombstoneDataType
    );
}
//crdt save rdb
void addKeys(dict* d, dict* keys) {
    dictIterator* di = dictGetIterator(d);
    dictEntry* de = NULL;
    while((de = dictNext(di)) != NULL) {
        sds keystr = dictGetKey(de);
        dictEntry *de = dictAddRaw(keys,keystr,NULL);
        if (de) {
            dictSetKey(keys,de,sdsdup(keystr));
            dictSetVal(keys,de,NULL);
        }
    }
    dictReleaseIterator(di);
}

int rdbLoadCrdtData(rio* rdb, redisDb* db, long long current_expire_time, LoadCrdtDataFunc load) {
    robj* key = NULL;
    void* moduleKey = NULL;
    int result = C_ERR;
    if ((key = rdbLoadStringObject(rdb)) == NULL) goto eoferr;
    // assert(dictFind(db->dict,key->ptr) == NULL);
    moduleKey = createModuleKey(db, key, REDISMODULE_WRITE | REDISMODULE_TOMBSTONE | REDISMODULE_NO_TOUCH_KEY, NULL, NULL);
    if(load(db, key, rdb, moduleKey) == C_ERR) goto eoferr;
    //use dictFind function for compatibility(version1.0.3) when rdb has expire but no data
    if(dictFind(db->dict,key->ptr) != NULL && current_expire_time != -1) {
        setExpire(NULL, db, key, current_expire_time);
    }
    result = C_OK;
eoferr:
    if(key != NULL) decrRefCount(key);
    if(moduleKey != NULL) closeModuleKey(moduleKey);
    return result;
}

int rdbSaveCrdtDbSize(rio* rdb, redisDb* db) {
    uint32_t tombstone_size;
    tombstone_size = (dictSize(db->deleted_keys) <= UINT32_MAX) ?
                dictSize(db->deleted_keys) :
                UINT32_MAX;
    if (rdbSaveLen(rdb,tombstone_size) == -1) return C_ERR;
    return C_OK;
}
int rdbLoadCrdtDbSize(rio* rdb, redisDb* db) {
    uint64_t tombstone_size;
    if ((tombstone_size = rdbLoadLen(rdb,NULL)) == RDB_LENERR)
        return C_ERR;
    dictExpand(db->deleted_keys,tombstone_size);
    return C_OK;  
}
int rdbSaveAuxFieldCrdt(rio *rdb) {
    for (int gid = 0; gid < (MAX_PEERS + 1); gid++) {
        CRDT_Master_Instance *masterInstance = crdtServer.crdtMasters[gid];
        if(masterInstance == NULL) continue;
        if (rdbSaveAuxFieldStrInt(rdb, "peer-master-gid", masterInstance->gid)
            == -1)  return C_ERR;
        if (rdbSaveAuxFieldStrStr(rdb, "peer-master-host", masterInstance->masterhost)
            == -1)  return C_ERR;
        if (rdbSaveAuxFieldStrInt(rdb, "peer-master-port", masterInstance->masterport)
            == -1)  return C_ERR;
        char* replid = NULL;
        long long replid_offset  = -1;
        if(masterInstance->master) {
            replid = masterInstance->master->replid;
            replid_offset = masterInstance->master->reploff;
            serverLog(LL_WARNING, "master reploff %lld, replid %lld", replid_offset, masterInstance->master_initial_offset);
        } else if(masterInstance->cached_master) {
            replid = masterInstance->cached_master->replid;
            replid_offset = masterInstance->cached_master->reploff;
        } else {
            replid = masterInstance->master_replid;
            replid_offset = masterInstance->master_initial_offset;
        }
        if (rdbSaveAuxFieldStrStr(rdb, "peer-master-repl-id", replid)
            == -1)  return C_ERR;
        if (rdbSaveAuxFieldStrInt(rdb, "peer-master-repl-offset", replid_offset)
            == -1)  return C_ERR;

    }
    return C_OK;
}
int rdbSaveCrdtInfoAuxFields(rio* rdb) {
    sds vclockSds = vectorClockToSds(crdtServer.vectorClock);
    if (rdbSaveAuxFieldStrStr(rdb,"vclock",vclockSds)
        == -1) {
        sdsfree(vclockSds);
        return -1;
    }
    sdsfree(vclockSds);
    if (rdbSaveAuxFieldStrStr(rdb,"crdt-repl-id",crdtServer.replid)
        == -1) return -1;
    if (rdbSaveAuxFieldStrInt(rdb,"crdt-repl-offset",crdtServer.master_repl_offset)
        == -1) return -1;
    if(rdbSaveAuxFieldCrdt(rdb) == -1) return -1;
    return 1;
}
int initedCrdtServer() {
    if(get_len(crdtServer.vectorClock) != 1) {
        return 1;
    }
    VectorClockUnit unit = getVectorClockUnit(crdtServer.vectorClock, crdtServer.crdt_gid);
    if(isNullVectorClockUnit(unit)) return 0;
    long long vcu = get_logic_clock(unit);
    if(vcu == 0) {
        return 0;
    }
    return 1;
}
int iAmMaster() {
    if(crdt_enabled && !server.master_is_crdt && server.masterhost ) {
        return C_OK;
    }
    if(!server.masterhost) {
        return C_OK;
    }
    return C_ERR;
}
int isSameTypeWithMaster() {
    if(crdt_enabled && server.master_is_crdt) {
        return C_OK;
    }
    if(!crdt_enabled && !server.master_is_crdt) {
        return C_OK;
    }
    return C_ERR;
}
int verifyRdbType(int isCrdtRdb) {
    if(crdt_enabled && isCrdtRdb) {
        return C_OK;
    }
    if(!crdt_enabled && !isCrdtRdb) {
        return C_OK;
    }
    return C_ERR;
}
robj* createStrRobjFromLongLong(long long val) {
    char buf[LONG_STR_SIZE];
    size_t len = ll2string(buf,sizeof(buf),val);
    return createStringObject(buf, len);
}
robj* reverseHashToArgv(hashTypeIterator* hi, int type) {
    if (hi->encoding == OBJ_ENCODING_ZIPLIST) {
        unsigned char *vstr = NULL;
        unsigned int vlen = UINT_MAX;
        long long vll = LLONG_MAX;
        hashTypeCurrentFromZiplist(hi, type, &vstr, &vlen, &vll);
        if (vstr) {
            return createStringObject((const char *)vstr, vlen);
        }else{
            return createStrRobjFromLongLong(vll);
        }
    }else if(hi->encoding == OBJ_ENCODING_HT) {
        sds value = hashTypeCurrentFromHashTable(hi, type);
        return createObject(OBJ_STRING, sdsdup(value));
    }else{
        serverLog(LL_WARNING, "hash encoding error");
        return NULL;
    }
}

int processInputRdb(client* fakeClient) {
    struct redisCommand* cmd = lookupCommand(fakeClient->argv[0]->ptr);
    if (!cmd) {
        serverLog(LL_WARNING,"Unknown command '%s' reading the append only file", fakeClient->argv[0]->ptr);
        freeClientArgv(fakeClient);
        fakeClient->cmd = NULL;
        return C_ERR;
    } 
    fakeClient->cmd = fakeClient->lastcmd = cmd;
    call(fakeClient, CMD_CALL_PROPAGATE);
    freeClientArgv(fakeClient);
    fakeClient->cmd = NULL;
    return C_OK;
}
int crdtSelectDb(client* fakeClient, int dbid) {
    fakeClient->argc = 2;
    // fakeClient->argv = zmalloc(sizeof(robj*)*2);
    fakeClient->argv[0] = createStringObject("select", 6);
    fakeClient->argv[1] = createStrRobjFromLongLong(dbid);
    return processInputRdb(fakeClient);
}
int data2CrdtData(client* fakeClient,robj* key, robj* val) {
    long long len;
    switch(val->type) {
        case OBJ_STRING: 
            fakeClient->argc = 3;
            // fakeClient->argv = zmalloc(sizeof(robj*)*3);
            fakeClient->argv[0] = shared.set;
            incrRefCount(shared.set);
            fakeClient->argv[1] = key;
            incrRefCount(key);
            long long result;
            if(getLongLongFromObject(val, &result) == C_OK) {
                fakeClient->argv[2] = createObject(OBJ_STRING, sdsfromlonglong(result));
            } else {
                fakeClient->argv[2] = val;
                incrRefCount(val);
            }
            processInputRdb(fakeClient);
        break;
        // case OBJ_LIST: freeListObject(o); break;
        // case OBJ_SET: freeSetObject(o); break;
        // case OBJ_ZSET: freeZsetObject(o); break;
        case OBJ_HASH: {
            len = hashTypeLength(val);
            int i = 0;
            hashTypeIterator* hi = hashTypeInitIterator(val);
            hashTypeNext(hi);
            while(len > 0) {
                fakeClient->argv[0] = shared.hset;
                incrRefCount(shared.hset);
                fakeClient->argv[1] = key;
                incrRefCount(key);
                i = 2;
                do {
                    fakeClient->argv[i++] = reverseHashToArgv(hi, OBJ_HASH_KEY);
                    fakeClient->argv[i++] = reverseHashToArgv(hi, OBJ_HASH_VALUE);
                    len--;
                } while (hashTypeNext(hi) != C_ERR && i < MAX_FAKECLIENT_ARGV);
                fakeClient->argc = i;
                processInputRdb(fakeClient);
            } 
            hashTypeReleaseIterator(hi);    
        }      
        break;
        case OBJ_SET: {
            len = setTypeSize(val);
            int i = 0;
            setTypeIterator* si = setTypeInitIterator(val);
            sds field = setTypeNextObject(si);
            while(len > 0) {
                fakeClient->argv[0] = shared.sadd;
                incrRefCount(shared.sadd);
                fakeClient->argv[1] = key;
                incrRefCount(key);
                i = 2;
                do {
                    fakeClient->argv[i++] = createRawStringObject(field, sdslen(field));
                    sdsfree(field);
                    len--;
                } while ((field = setTypeNextObject(si)) != NULL && i < MAX_FAKECLIENT_ARGV);
                fakeClient->argc = i;
                processInputRdb(fakeClient);
            } 
            setTypeReleaseIterator(si);
        }
        break;
        case OBJ_ZSET: {
            int len = zsetLength(val);
            if (val->encoding == OBJ_ENCODING_ZIPLIST) {
                unsigned char *zl = val->ptr;
                unsigned char *eptr, *sptr;
                unsigned char *vstr;
                unsigned int vlen;
                long long vlong;
                eptr = ziplistIndex(zl,0);
                sptr = ziplistNext(zl,eptr);
                while (len > 0) {
                    fakeClient->argv[0] = shared.zadd;
                    incrRefCount(shared.zadd);
                    fakeClient->argv[1] = key;
                    incrRefCount(key);
                    int i = 2;
                    do {
                        ziplistGet(eptr,&vstr,&vlen,&vlong);
                        assert(vstr != NULL);                   
                        double score = zzlGetScore(sptr);
                        fakeClient->argv[i++] = createStringObjectFromLongDouble((long double)score, 1);
                        zzlNext(zl,&eptr,&sptr);
                        fakeClient->argv[i++] = createRawStringObject(vstr, vlen);
                        len--;
                    } while (eptr != NULL && i < MAX_FAKECLIENT_ARGV);
                    fakeClient->argc = i;
                    processInputRdb(fakeClient);
                }

            } else if (val->encoding == OBJ_ENCODING_SKIPLIST) {
                zset *zs = val->ptr;
                zskiplist *zsl = zs->zsl;
                zskiplistNode *ln;
                sds ele;
                /* Check if starting point is trivial, before doing log(N) lookup. */  
                ln = zsl->header->level[0].forward;
                while(len > 0) {
                    fakeClient->argv[0] = shared.zadd;
                    incrRefCount(shared.zadd);
                    fakeClient->argv[1] = key;
                    incrRefCount(key);
                    int i = 2;
                    do {
                        ele = ln->ele;
                        // addReplyBulkCBuffer(c,ele,sdslen(ele));
                        long double score = (long double)ln->score;
                        fakeClient->argv[i++] =  createStringObjectFromLongDouble(score, 1);
                        fakeClient->argv[i++] = createRawStringObject(ele, sdslen(ele));
                        
                        ln = ln->level[0].forward;
                        len--;
                    } while(ln != NULL && i < MAX_FAKECLIENT_ARGV);
                    fakeClient->argc = i;
                    processInputRdb(fakeClient);
                }
            } else {
                serverPanic("Unknown sorted set encoding");
            }
            
        }
        break;
        // case OBJ_MODULE: freeModuleObject(o); break;
        default:  {
            serverLog(LL_WARNING, "load data fail key: %s, type: %d", (sds)key->ptr, val->type);
            goto error;
        }
    }
    decrRefCount(val);  
    return C_OK;
error:
    if(val != NULL) {
        decrRefCount(val);
    } 
    return C_ERR;
}

int expire2CrdtExpire(client* fakeClient, robj* key, long long expiretime) {
    fakeClient->argc = 3;
    // fakeClient->argv = zmalloc(sizeof(robj*)*3);
    fakeClient->argv[0] = shared.pexpireat;
    incrRefCount(shared.pexpireat); 
    fakeClient->argv[1] = key;
    incrRefCount(key);
    fakeClient->argv[2] = createStrRobjFromLongLong(expiretime);
    return processInputRdb(fakeClient);
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
