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
// Created by zhuchen on 2019-06-07.
//

#ifndef REDIS_CTRIP_CRDT_COMMON_H
#define REDIS_CTRIP_CRDT_COMMON_H

#define CRDT_MODULE_OBJECT_PREFIX "crdt"

#include "sds.h"
#include "ctrip_vector_clock.h"
typedef void *(*crdtMergeFunc)(void *curVal, void *value);
// RM_CrdtMultiWrappedReplicate should be called during this
typedef int (*crdtPropagateDelFunc)(int db_id, void *keyRobj, void *key, void *crdtObj);
typedef void* (*crdtFilterFunc)(void* obj,int gid, long long logic_time);
typedef int (*crdtGCFunc)(void *crdtObj, VectorClock* clock);
typedef int (*crdtPurageFunc)(void* tombstone, void* value);
typedef struct CrdtMeta {
    int gid;
    VectorClock *vectorClock;
    long long timestamp;
} CrdtMeta;
typedef struct CrdtObjectMethod {
    crdtMergeFunc merge;
    crdtFilterFunc filter;
} CrdtObjectMethod;

typedef struct CrdtObject {
    unsigned char type;
    // CrdtObjectMethod* method;
} CrdtObject;
typedef VectorClock* (*crdtGetLastVCFunc)(void* value);
typedef void* (*crdtUpdateLastVCFunc)(void* value,VectorClock* data);
typedef struct CrdtDataMethod {
    crdtGetLastVCFunc getLastVC;
    crdtUpdateLastVCFunc updateLastVC;
    crdtPropagateDelFunc propagateDel;
} CrdtDataMethod;
typedef struct CrdtExpireObj {
    CrdtMeta* meta;
    long long expireTime;
} CrdtExpireObj; 
typedef int (*crdtExpireAddFunc)(void* expire, CrdtExpireObj *obj);
typedef CrdtExpireObj* (*crdtExpireGetFunc)(void* expire);
typedef void (*crdtExpireFreeFunc)(void* value);
typedef void* (*crdtExpireDupFunc)( void* value);
typedef void (*crdtPersistFunc)(void* value, void* moduleKey, int dbId, void* key);
typedef long long (*crdtExpireGetLastExpireTimeFunc)(struct CrdtExpire* expire);
typedef int (*crdtExpireGetLastGid)(struct CrdtExpire* expire);
typedef struct CrdtExpireMethod {
    crdtExpireAddFunc add;
    crdtExpireGetLastExpireTimeFunc getLastExpireTime;
    crdtExpireGetLastGid getLastGid;
    crdtExpireFreeFunc free;
    crdtExpireDupFunc dup;
    crdtPersistFunc persist;
} CrdtExpireMethod;
typedef struct CrdtTombstoneMethod {
    crdtMergeFunc merge;
    crdtFilterFunc filter;
    crdtGCFunc gc;
    crdtPurageFunc purage;
} CrdtTombstoneMethod;
typedef int (*crdtIsExpireFunc)(void* target, CrdtMeta* meta);
typedef int (*crdtExpireTombstoneAddFunc)(void* target, CrdtMeta* meta);
typedef struct CrdtExpireTombstoneMethod {
    crdtIsExpireFunc isExpire;
    crdtExpireTombstoneAddFunc add;
} CrdtExpireTombstoneMethod;
CrdtExpireMethod* getCrdtExpireMethod(CrdtObject* expire);
CrdtDataMethod* getCrdtDataMethod(CrdtObject* expire);
CrdtObjectMethod* getCrdtObjectMethod(CrdtObject* expire);
CrdtTombstoneMethod* getCrdtTombstoneMethod(CrdtObject* tombstone);
int getDataType(int type);
int isData(int type);
int isTombstone(int type);
int isExpireTombstone(int type);
int isTombstone(int type);
#endif //REDIS_CTRIP_CRDT_COMMON_H
