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
// Created by zhuchen on 2019-08-05.
//

#include "ctrip_crdt_gc.h"
#include "server.h"
#include "dict.h"

/*-----------------------------------------------------------------------------
 * Database API
 *----------------------------------------------------------------------------*/

// 1 for deleted, 0 for not deleted
void markDeleted(dictEntry *de, long long gid, long long timestamp, VectorClock *vclock) {
    CrdtCommon *crdtCommon = retrieveCrdtCommon(de->v.val);
    crdtCommon->deleted = 1;
    crdtCommon->gid = gid;
    crdtCommon->timestamp = timestamp;
    VectorClock *prevVectorClock = crdtCommon->vectorClock;
    crdtCommon->vectorClock = dupVectorClock(vclock);
    freeVectorClock(prevVectorClock);
}

/* Set an del to the specified key. */
int setDel(redisDb *db, robj *key, long long gid, long long timestamp, VectorClock *vclock) {
    dictEntry *kde, *de, *objde;

    /* Reuse the sds from the main dict in the expire dict */
    kde = dictFind(db->dict,key->ptr);
    // CRDT Logic: you can never delete an object, that is never exists
    if (kde != NULL) {
        return 0;
    }
    // You can never delete a key, that is never exist
    objde = dictFind(db->dict, key);
    if (objde == NULL) {
        return 0;
    }
    de = dictAddOrFind(db->deleted_keys,dictGetKey(kde));
    dictSetVal(db->deleted_keys, de, dictGetVal(objde));
    incrRefCount(objde->v.val);
//    markDeleted(objde, 1, gid, timestamp, vclock);
    return 1;
}

/* Delete a key, value, and associated expiration entry if any, from the DB */
int crdtSyncDelete(redisDb *db, robj *key, long long gid, long long timestamp, VectorClock *vclock) {
    /* Deleting an entry from the expires dict will not free the sds of
     * the key, because it is shared with the main dictionary. */
    if (dictSize(db->expires) > 0) dictDelete(db->expires, key->ptr);
    return setDel(db, key, gid, timestamp, vclock);
}



/*-----------------------------------------------------------------------------
 * Del API
 *----------------------------------------------------------------------------*/

int removeDel(redisDb *db, robj *key, int gid, long long timestamp, VectorClock *vclock) {
    /* An expire may only be removed if there is a corresponding entry in the
     * main dict. Otherwise, the key will never be freed. */
    dictEntry *de;
    serverAssertWithInfo(NULL,key, (de = dictFind(db->dict,key->ptr)) != NULL);
    CrdtCommon *crdtCommon = retrieveCrdtCommon(de->v.val);
    crdtCommon->deleted = 0;
    return dictDelete(db->deleted_keys,key->ptr) == DICT_OK;
}

void replaceDelCommandForReplication(client *c, long long gid, long long timestamp, VectorClock *vclock) {
    sds vcStr = vectorClockToSds(vclock);
    robj **argv = zmalloc(sizeof(robj*) * (c->argc+3));
    memcpy(argv, &c->argv[4], (c->argc-1)* sizeof(robj*));
    argv[0] = shared.crdtdel;
    argv[1] = createStringObjectFromLongLong(gid);
    argv[2] = createStringObjectFromLongLong(timestamp);
    argv[3] = createEmbeddedStringObject(vcStr, sdslen(vcStr));
    replaceClientCommandVector(c, c->argc + 3, argv);
    sdsfree(vcStr);
}

/* This command implements DEL and crdt. */
// crdt.del <gid> <timestamp> <vc> key1 key2 key3 ....
//   0         1      2        3     4
void crdtDelGenericCommand(client *c, int isCrdt) {
    int numdel = 0, j;
    long long gid, timestamp;
    VectorClock *vclock;
    if (isCrdt == 1) {
        serverAssertWithInfo(c, NULL, getLongLongFromObject(c->argv[1], &gid) == C_OK);
        serverAssertWithInfo(c, NULL, getLongLongFromObject(c->argv[2], &timestamp) == C_OK);
        serverAssertWithInfo(c, NULL, (vclock = sdsToVectorClock(c->argv[3]->ptr)) != NULL);
    }  else {
        gid = crdtServer.crdt_gid;
        timestamp = mstime();
        incrLocalVcUnit(1);
        vclock = dupVectorClock(crdtServer.vectorClock);
        replaceDelCommandForReplication(c, gid, timestamp, vclock);
    }
    for (j = 4; j < c->argc; j++) {
        int deleted = crdtSyncDelete(c->db, c->argv[j], gid, timestamp, vclock);
        if (deleted) {
            signalModifiedKey(c->db,c->argv[j]);
            notifyKeyspaceEvent(NOTIFY_GENERIC,
                                "del",c->argv[j],c->db->id);
            server.dirty++;
            numdel++;
        }
    }
    freeVectorClock(vclock);
    addReplyLongLong(c,numdel);
}

///* Propagate expires into slaves and the AOF file.
// * When a key expires in the master, a DEL operation for this key is sent
// * to all the slaves and the AOF file if enabled.
// *
// * This way the key expiry is centralized in one place, and since both
// * AOF and the master->slave link guarantee operation ordering, everything
// * will be consistent even if we allow write operations against expiring
// * keys. */
//void propagateExpire(redisDb *db, robj *key, int lazy) {
//    robj *argv[2];
//
//    argv[0] = lazy ? shared.unlink : shared.del;
//    argv[1] = key;
//    incrRefCount(argv[0]);
//    incrRefCount(argv[1]);
//
//    if (server.aof_state != AOF_OFF)
//        feedAppendOnlyFile(server.delCommand,db->id,argv,2);
//    replicationFeedSlaves(&server, server.slaves,db->id,argv,2);
//
//    decrRefCount(argv[0]);
//    decrRefCount(argv[1]);
//}
//
//int expireIfNeeded(redisDb *db, robj *key) {
//    mstime_t when = getExpire(db,key);
//    mstime_t now;
//
//    if (when < 0) return 0; /* No expire for this key */
//
//    /* Don't expire anything while loading. It will be done later. */
//    if (server.loading) return 0;
//
//    /* If we are in the context of a Lua script, we claim that time is
//     * blocked to when the Lua script started. This way a key can expire
//     * only the first time it is accessed and not in the middle of the
//     * script execution, making propagation to slaves / AOF consistent.
//     * See issue #1525 on Github for more information. */
//    now = server.lua_caller ? server.lua_time_start : mstime();
//
//    /* If we are running in the context of a slave, return ASAP:
//     * the slave key expiration is controlled by the master that will
//     * send us synthesized DEL operations for expired keys.
//     *
//     * Still we try to return the right information to the caller,
//     * that is, 0 if we think the key should be still valid, 1 if
//     * we think the key is expired at this time. */
//    if (server.masterhost != NULL) return now > when;
//
//    /* Return when this key has not expired */
//    if (now <= when) return 0;
//
//    /* Delete the key */
//    server.stat_expiredkeys++;
//    propagateExpire(db,key,server.lazyfree_lazy_expire);
//    notifyKeyspaceEvent(NOTIFY_EXPIRED,
//                        "expired",key,db->id);
//    return server.lazyfree_lazy_expire ? dbAsyncDelete(db,key) :
//           dbSyncDelete(db,key);
//}


/*-----------------------------------------------------------------------------
 * Generic Del API Command
 *----------------------------------------------------------------------------*/

void crdtDelCommand(client *c) {
    crdtDelGenericCommand(c, 1);
}

// crdt.del <gid> <timestamp> <vc> key1 key2 key3 ....
//   0         1      2        3     4
void delCommand(client *c) {
    crdtDelGenericCommand(c, 0);
}
