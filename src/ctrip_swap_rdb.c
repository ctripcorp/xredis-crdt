/* Copyright (c) 2021, ctrip.com
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

#include "server.h"

typedef struct {
    rio *rdb;               /* rdb stream */
    robj *key;              /* key object */
    robj *dup;              /* val object */
    long long expire;       /* expire time */
    long long now;          /* now */
    int totalswap;          /* # of needed swaps */
    int numswapped;         /* # of finished swaps */
    complementObjectFunc comp;  /* function to complent val with rocksdb swap result */
    void *pd;               /* comp function private data  */
} keyValuePairCtx;

keyValuePairCtx *keyValuePairCtxNew(rio *rdb, robj *key, robj *dup,
        int totalswap, long long expire, long long now,
        complementObjectFunc comp, void *pd) {
    keyValuePairCtx *ctx = zmalloc(sizeof(keyValuePairCtx));
    ctx->rdb = rdb;
    ctx->key = key;
    ctx->dup = dup;
    ctx->expire = expire;
    ctx->now = now;
    ctx->totalswap = totalswap;
    ctx->numswapped = 0;
    ctx->comp = comp;
    ctx->pd = pd;
    return ctx;
}

void keyValuePairCtxFree(keyValuePairCtx *kvp) {
    decrRefCount(kvp->key);
    decrRefCount(kvp->dup);
    zfree(kvp);
}

int rdbSaveSwapFinished(sds rawkey, sds rawval, void *_kvp) {
    keyValuePairCtx *kvp = _kvp;

    if (complementObject(kvp->dup, rawkey, rawval, kvp->comp, kvp->pd)) {
        serverLog(LL_WARNING, "[rdbSaveEvicted] comp object failed:%.*s %.*s",
                (int)sdslen(rawkey), rawkey, (int)sdslen(rawval), rawval);
        goto err;
    }

    kvp->numswapped++;
    if (kvp->numswapped == kvp->totalswap) {
        if (rdbSaveKeyValuePair(kvp->rdb, kvp->key, kvp->dup,
                    kvp->expire, kvp->now) == -1) {
            keyValuePairCtxFree(kvp);
            goto err;
        }
        keyValuePairCtxFree(kvp);
    }

    sdsfree(rawkey);
    sdsfree(rawval);
    return C_OK;

err:
    sdsfree(rawkey);
    sdsfree(rawval);
    return C_ERR;
}

int rdbSaveEvictDb(rio *rdb, int *error, redisDb *db) {
    dictIterator *di = NULL;
    dictEntry *de;
    dict *d = db->evict;
    long long now = mstime(), num = 0;

    parallelSwap *ps = parallelSwapNew(16);

    di = dictGetSafeIterator(d);
    while((de = dictNext(di)) != NULL) {
        int i;
        long long expire;
        keyValuePairCtx *kvp;
        sds keystr = dictGetKey(de);
        robj *key, *dup, *val = dictGetVal(de);
        complementObjectFunc comp;
        void *pd;
        getSwapsResult result = GETSWAPS_RESULT_INIT;

        /* skip if it's just a swapping key(not evicted), already saved it. */
        if (!val->evicted) continue;

        num++;

        key = createStringObject(keystr, sdslen(keystr));
        expire = getExpire(db,key);

        /* swap result will be merged into duplicated object, to avoid messing
         * up keyspace and causing drastic COW. */
        dup = getComplementSwaps(db, key, &result, &comp, &pd);

        /* no need to swap, normally it should not happend, we'are just being
         * protective here. */
        if (result.numswaps == 0) {
            decrRefCount(key);
            if (dup) decrRefCount(dup);
            rdbSaveKeyValuePair(rdb, key, val, expire, now);
            continue;
        }

        kvp = keyValuePairCtxNew(rdb, key, dup, result.numswaps, expire, now,
                comp, pd);

        for (i = 0; i < result.numswaps; i++) {
            swap *s = &result.swaps[i];
            if (parallelSwapSubmit(ps, (sds)s->key, rdbSaveSwapFinished, kvp)) {
                goto werr;
            }
        }
    }
    dictReleaseIterator(di);

    if (parallelSwapDrain(ps)) goto werr;
    parallelSwapFree(ps);

    if (num) serverLog(LL_WARNING, "[RKS] DB-%d saved %lld evicted key to rdb.",
            db->id, num);

    return C_OK;

werr:
    if (error) *error = errno;
    if (di) dictReleaseIterator(di);
    parallelSwapFree(ps);
    return C_ERR;
}

