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
#include "ctrip_vector_clock.h"
#include "ctrip_crdt_gc.h"
#include "server.h"
#include "dict.h"

/*-----------------------------------------------------------------------------
 * Database API
 *----------------------------------------------------------------------------*/

/* Add the key to the DB tombstone. It's up to the caller to increment the reference
* counter of the value if needed.
*
* The program is aborted if the key already exists. */
void tombstoneAdd(redisDb *db, robj *key, robj *val) {
    sds copy = sdsdup(key->ptr);
    int retval = dictAdd(db->deleted_keys, copy, val);

    serverAssertWithInfo(NULL,key,retval == DICT_OK);
}

/* Overwrite an existing key with a new value in tombstone. Incrementing the reference
 * count of the new value is up to the caller.
 * This function does not modify the delete time of the existing key.
 *
 * The program is aborted if the key was not already present. */
void tombstoneOverwrite(redisDb *db, robj *key, robj *val) {
    dictReplace(db->deleted_keys, key->ptr, val);
}

robj *lookupTombstone(dict *d, robj *key) {
    dictEntry *de;

    /* No deleted? return ASAP */
    if (dictSize(d) == 0 ||
        (de = dictFind(d,key->ptr)) == NULL) return NULL;

    return dictGetVal(de);
}
/* High level Set operation. This function can be used in order to set
 * a key to tombstone, whatever it was existing or not, to a new object.
 *
 * 1) The ref count of the value object is incremented.
 * 2) clients WATCHing for the destination key notified.
 * 3) The delete time of the key is reset (the key is made persistent).
 *
 * All the new keys in the database should be created via this interface. */
void setKeyToTombstone(redisDb *db, robj *key, robj *val) {
    robj *existing;
    if ((existing = lookupTombstone(db->deleted_keys,key)) == NULL) {
        tombstoneAdd(db,key,val);
    } else {
        // CrdtCommon *existingCrdtCommon = retrieveCrdtCommon(existing);
        // CrdtCommon *incomeCrdtCommon = retrieveCrdtCommon(val);
        // if (!isVectorClockMonoIncr(existingCrdtCommon->vectorClock, incomeCrdtCommon->vectorClock)) {
        //     VectorClock *toFree = incomeCrdtCommon->vectorClock;
        //     incomeCrdtCommon->vectorClock = vectorClockMerge(existingCrdtCommon->vectorClock, incomeCrdtCommon->vectorClock);
        //     freeVectorClock(toFree);
        // }
        tombstoneOverwrite(db, key, val);
    }
    incrRefCount(val);
    signalModifiedKey(db,key);
}

/* Lookup a key for write operations
 *
 * Returns the linked value object if the key exists or NULL if the key
 * does not exist in the specified DB. */
robj *lookupTombstoneKey(redisDb *db, robj *key) {
    gcIfNeeded(db->deleted_keys,key);
    return lookupTombstone(db->deleted_keys,key);
}


int gcIfNeeded(dict *d, robj *key) {
    robj *val = lookupTombstone(d,key);
    if(val == NULL) {
        return 0;
    }
    CrdtObject *tombstone = retrieveCrdtObject(val);

    /* Don't del anything while loading. It will be done later. */
    if (server.loading) return 0;

    /* It's ready to be deleted, when and only when other peers already know what happend.
     * 1. Gc Vector Clock is collected from each peer's vector clock, and do a minimium of them
     * 2. if the vector clock of gcVectorClock is mono-increase, comparing to the deleted keys, the delete event will be triggered
     * */
    //todo: update gc vector clock, each time when set operation
    updateGcVectorClock();
    CrdtTombstoneMethod* method = getCrdtTombstoneMethod(tombstone);
    if(method == NULL) return 0;
    if(!method->gc(tombstone, crdtServer.gcVectorClock)){
        return 0;
    }
    if (dictDelete(d,key->ptr) == DICT_OK) {
        return 1;
    } else {
        return 0;
    }

}
/*-----------------------------------------------------------------------------
 * Del API
 *----------------------------------------------------------------------------*/

int removeDel(redisDb *db, robj *key) {
    /* An expire may only be removed if there is a corresponding entry in the
     * main dict. Otherwise, the key will never be freed. */
    dictEntry *de;
    if ((de = dictFind(db->deleted_keys,key->ptr)) == NULL) {
        return 1;
    }
    if (dictDelete(db->deleted_keys,key->ptr) == DICT_OK) {
        return 1;
    } else {
        return 0;
    }
}

void tombstoneSizeCommand(client *c) {
    addReplyLongLong(c,dictSize(c->db->deleted_keys));
}
void expireSizeCommand(client *c) {
    addReplyLongLong(c,dictSize(c->db->expires));
}


/*-----------------------------------------------------------------------------
 * Incremental collection of deleted keys.
 *
 * When keys are accessed they are deleted on-access. However we need a
 * mechanism in order to ensure keys are eventually removed when deleted even
 * if no access is performed on them.
 *----------------------------------------------------------------------------*/
VectorClock getGcVectorClock() {
    listIter li;
    listNode *ln;
    VectorClock gcVectorClock = dupVectorClock(crdtServer.vectorClock);
    if (crdtServer.crdtMasters == NULL || listLength(crdtServer.crdtMasters) == 0) {
        return gcVectorClock;
    }
    listRewind(crdtServer.crdtMasters, &li);
    while ((ln = listNext(&li)) != NULL) {
        CRDT_Master_Instance *crdtMaster = ln->value;
        if (crdtMaster == NULL) {
            continue;
        }
        VectorClock other = crdtMaster->vectorClock;
        VectorClock old = gcVectorClock;
        gcVectorClock = mergeMinVectorClock(old, other);
        
        freeVectorClock(old);
        // for (int i = 0; i < gcVectorClock->length; i++) {
        //     VectorClockUnit *gcVectorClockUnit = &(gcVectorClock->clocks[i]);
        //     VectorClockUnit *otherVectorClockUnit = getVectorClockUnit(other, gcVectorClock->clocks[i].gid);
        //     if(otherVectorClockUnit != NULL) {
        //         gcVectorClockUnit->logic_time = min(gcVectorClockUnit->logic_time, otherVectorClockUnit->logic_time);
        //     } else {
        //         gcVectorClockUnit->logic_time = 0;
        //     }
        // }
    }
    return gcVectorClock;
}
void updateGcVectorClock() {
    
    if (!isNullVectorClock(crdtServer.gcVectorClock)) {
        freeVectorClock(crdtServer.gcVectorClock);
        crdtServer.gcVectorClock = newVectorClock(0);
    }
    crdtServer.gcVectorClock = getGcVectorClock();
}

/* Helper function for the activeExpireCycle() function.
 * This function will try to expire the key that is stored in the hash table
 * entry 'de' of the 'expires' hash table of a Redis database.
 *
 * If the key is found to be expired, it is removed from the database and
 * 1 is returned. Otherwise no operation is performed and 0 is returned.
 *
 * When a key is expired, server.stat_expiredkeys is incremented.
 *
 * The parameter 'now' is the current time in milliseconds as is passed
 * to the function to avoid too many gettimeofday() syscalls. */
int activeGcCycleTryGc(dict *d, dictEntry *de) {
    robj *val = dictGetVal(de);
    CrdtObject *tombstone = retrieveCrdtObject(val);
    if (tombstone == NULL) {
        return 0;
    }
    /* It's ready to be deleted, when and only when other peers already know what happend.
     * 1. Gc Vector Clock is collected from each peer's vector clock, and do a minimium of them
     * 2. if the vector clock of gcVectorClock is mono-increase, comparing to the deleted keys, the delete event will be triggered
     * */
    CrdtTombstoneMethod* method = getCrdtTombstoneMethod(tombstone);
    if(method == NULL) {
        serverLog(LL_WARNING, "no gc method");
        return 0;
    }
    sds gc = vectorClockToSds(crdtServer.gcVectorClock);
    sdsfree(gc);
    if(!method->gc(tombstone, crdtServer.gcVectorClock)) {
        return 0;
    }
    sds key = dictGetKey(de);
    if (dictDelete(d,key) == DICT_OK) {
        return 1;
    } else {
        return 0;
    }
}

/* Try to expire a few timed out keys. The algorithm used is adaptive and
 * will use few CPU cycles if there are few expiring keys, otherwise
 * it will get more aggressive to avoid that too much memory is used by
 * keys that can be removed from the keyspace.
 *
 * No more than CRON_DBS_PER_CALL databases are tested at every
 * iteration.
 *
 * This kind of call is used when Redis detects that timelimit_exit is
 * true, so there is more work to do, and we do it more incrementally from
 * the beforeSleep() function of the event loop.
 *
 * Expire cycle type:
 *
 * If type is ACTIVE_EXPIRE_CYCLE_FAST the function will try to run a
 * "fast" expire cycle that takes no longer than EXPIRE_FAST_CYCLE_DURATION
 * microseconds, and is not repeated again before the same amount of time.
 *
 * If type is ACTIVE_EXPIRE_CYCLE_SLOW, that normal expire cycle is
 * executed, where the time limit is a percentage of the REDIS_HZ period
 * as specified by the ACTIVE_EXPIRE_CYCLE_SLOW_TIME_PERC define. */


typedef dict* (*getDictFunc)(redisDb *db);
void Gc(int type, unsigned int *current_db,int *timelimit_exit, long long *last_fast_cycle,getDictFunc getDict, const char* name) {
    int j, iteration = 0;
    int dbs_per_call = CRON_DBS_PER_CALL;
    long long start = ustime(), timelimit, elapsed;

    /* When clients are paused the dataset should be static not just from the
     * POV of clients not being able to write, but also from the POV of
     * expires and evictions of keys not being performed. */
    if (clientsArePaused()) return;

    updateGcVectorClock();

    if (type == ACTIVE_GC_CYCLE_FAST) {
        /* Don't start a fast cycle if the previous cycle did not exited
         * for time limt. Also don't repeat a fast cycle for the same period
         * as the fast cycle total duration itself. */
        if (!*timelimit_exit) return;
        if (start < *last_fast_cycle + ACTIVE_EXPIRE_CYCLE_FAST_DURATION*2) return;
        *last_fast_cycle = start;
    }
    /* We usually should test CRON_DBS_PER_CALL per iteration, with
     * two exceptions:
     *
     * 1) Don't test more DBs than we have.
     * 2) If last time we hit the time limit, we want to scan all DBs
     * in this iteration, as there is work to do in some DB and we don't want
     * expired keys to use memory for too much time. */
    if (dbs_per_call > server.dbnum || *timelimit_exit)
        dbs_per_call = server.dbnum;

    /* We can use at max ACTIVE_EXPIRE_CYCLE_SLOW_TIME_PERC percentage of CPU time
     * per iteration. Since this function gets called with a frequency of
     * server.hz times per second, the following is the max amount of
     * microseconds we can spend in this function. */
    timelimit = 1000000*ACTIVE_EXPIRE_CYCLE_SLOW_TIME_PERC/server.hz/100;
    *timelimit_exit = 0;
    if (timelimit <= 0) timelimit = 1;

    if (type == ACTIVE_GC_CYCLE_FAST)
        timelimit = ACTIVE_EXPIRE_CYCLE_FAST_DURATION; /* in microseconds. */

    for (j = 0; j < dbs_per_call && *timelimit_exit == 0; j++) {
        int deleted;
        redisDb *db = server.db+(*current_db % server.dbnum);
        dict* d = getDict(db);
        /* Increment the DB now so we are sure if we run out of time
         * in the current DB we'll restart from the next. This allows to
         * distribute the time evenly across DBs. */
        *current_db = *current_db+1;

        /* Continue to delete if at the end of the cycle more than 25%
         * of the keys were deleted. */
        do {
            unsigned long num, slots;
            iteration++;

            /* If there is nothing to delete try next DB ASAP. */
            if ((num = dictSize(d)) == 0) {
                break;
            }
            slots = dictSlots(d);

            /* When there are less than 1% filled slots getting random
             * keys is expensive, so stop here waiting for better times...
             * The dictionary will be resized asap. */
            if (num && slots > DICT_HT_INITIAL_SIZE &&
                (num*100/slots < 1)) break;

            /* The main collection cycle. Sample random keys among keys
             * with an delete set, checking for deleted ones. */
            deleted = 0;

            if (num > ACTIVE_EXPIRE_CYCLE_LOOKUPS_PER_LOOP)
                num = ACTIVE_EXPIRE_CYCLE_LOOKUPS_PER_LOOP;

            while (num--) {
                dictEntry *de;

                if ((de = dictGetRandomKey(d)) == NULL) break;

                if (activeGcCycleTryGc(d,de)) deleted++;

            }

            /* We can't block forever here even if there are many keys to
             * delete. So after a given amount of milliseconds return to the
             * caller waiting for the other active delete cycle. */
            if ((iteration & 0xf) == 0) { /* check once every 16 iterations. */
                elapsed = ustime()-start;
                if (elapsed > timelimit) {
                    *timelimit_exit = 1;
                    break;
                }
            }
            /* We don't repeat the cycle if there are less than 25% of keys
             * found deleted in the current DB. */
        } while (deleted > ACTIVE_EXPIRE_CYCLE_LOOKUPS_PER_LOOP/4);
    }
    elapsed = ustime()-start;
    latencyAddSampleIfNeeded(name,elapsed/1000);
}
dict* getDeletedKeys(redisDb* db) {
    return db->deleted_keys;
}
void activeGcCycle(int type) {
    /* This function has some global state in order to continue the work
     * incrementally across calls. */
    static unsigned int current_db = 0; /* Last DB tested. */
    static int timelimit_exit = 0;      /* Time limit hit in previous call? */
    static long long last_fast_cycle = 0; /* When last fast cycle ran. */
    Gc(type, &current_db, &timelimit_exit, &last_fast_cycle, getDeletedKeys, "gc-cycle");
}