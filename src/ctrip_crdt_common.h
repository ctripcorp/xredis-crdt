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
typedef struct CrdtObject {
    unsigned char type;
} CrdtObject;
int check_gid(int gid);
typedef void *(*crdtMergeFunc)(void *curVal, void *value);
// RM_CrdtMultiWrappedReplicate should be called during this
typedef int (*crdtPropagateDelFunc)(int db_id, void *keyRobj, void *key, void *crdtObj);
typedef CrdtObject** (*crdtFilterSplitFunc)(CrdtObject* obj,int gid, long long logic_time, long long maxsize, int* length);
typedef CrdtObject** (*crdtFilterSplitFunc2)(CrdtObject* obj,int gid, VectorClock min_vc, long long maxsize, int* length);
typedef void (*crdtFreeFilterResultFunc)(CrdtObject** obj, int length);
typedef int (*crdtGCFunc)(void *crdtObj, VectorClock clock);
typedef int (*crdtPurgeFunc)(void* tombstone, void* value);

typedef struct CrdtObjectMethod {
    crdtMergeFunc merge;
    crdtFilterSplitFunc filterAndSplit;
    crdtFilterSplitFunc2 filterAndSplit2;
    crdtFreeFilterResultFunc freefilter;
} CrdtObjectMethod;


typedef VectorClock (*crdtGetLastVCFunc)(void* value);
typedef void* (*crdtUpdateLastVCFunc)(void* value,VectorClock data);
typedef sds (*crdtInfoFunc)(void* value);
typedef int (*crdtGetLastGidFunc)(void* value);
typedef struct CrdtDataMethod {
    crdtGetLastVCFunc getLastVC;
    crdtUpdateLastVCFunc updateLastVC;
    crdtPropagateDelFunc propagateDel;
    crdtInfoFunc info;
    crdtGetLastGidFunc getLastGid;
} CrdtDataMethod;
#define PURGE_VAL 1
#define PURGE_TOMBSTONE -1
typedef VectorClock (*crdtGetVcFunc)(void* value);
typedef struct CrdtTombstoneMethod {
    crdtMergeFunc merge;
    crdtFilterSplitFunc filterAndSplit;
    crdtFilterSplitFunc2 filterAndSplit2;
    crdtFreeFilterResultFunc freefilter;
    crdtGCFunc gc;
    crdtPurgeFunc purge;
    crdtInfoFunc info;
    crdtGetVcFunc getVc;
} CrdtTombstoneMethod;

CrdtDataMethod* getCrdtDataMethod(CrdtObject* expire);
CrdtObjectMethod* getCrdtObjectMethod(CrdtObject* expire);
CrdtTombstoneMethod* getCrdtTombstoneMethod(CrdtObject* tombstone);
int getDataType(CrdtObject* data);
int isData(CrdtObject* data);
int isTombstone(CrdtObject* data);
// long long tombstoneGetIdle(VectorClock vc, VectorClock currentVc);

#endif //REDIS_CTRIP_CRDT_COMMON_H
