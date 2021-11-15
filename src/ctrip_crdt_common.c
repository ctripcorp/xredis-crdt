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

#include "ctrip_crdt_common.h"
#include "server.h"

#include <stdlib.h>

/* Macro to initialize an IO context. Note that the 'ver' field is populated
 * inside rdb.c according to the version of the value to load. */
int isModuleCrdt(robj *obj) {
    if(obj->type != OBJ_MODULE) {
        return C_ERR;
    }
    moduleValue *mv = obj->ptr;
    if(strncmp(CRDT_MODULE_OBJECT_PREFIX, mv->type->name, 4) == 0) {
        return C_OK;
    }
    return C_ERR;
}

int check_gid(int gid) {
    if(gid > 0 && gid < (1 << GIDSIZE)) {
        return 1; 
    }
    return 0;
}
void* getMethod(void* obj, const char* name) {
    void* (*getmethod)(void*);
    getmethod = (void* (*)(void*))(unsigned long)getModuleFunction(CRDT_MODULE, (char*)name);
    if(getmethod == NULL) {
        return NULL;
    }
    return getmethod(obj);
}
CrdtDataMethod* getCrdtDataMethod(CrdtObject* expire) {
    return getMethod(expire, "getCrdtDataMethod");
}
CrdtObjectMethod* getCrdtObjectMethod(CrdtObject* obj) {
    return getMethod(obj, "getCrdtObjectMethod");
}
CrdtTombstoneMethod* getCrdtTombstoneMethod(CrdtObject* tombstone) {
    return getMethod(tombstone, "getCrdtTombstoneMethod");
}
int getDataType(CrdtObject* data) {
    return (int)(long)getMethod(data, "getDataType");
}
int isData(CrdtObject* data) {
    return (int)(long)getMethod(data, "isData");
}
int isTombstone(CrdtObject* data) {
    return (int)(long)getMethod(data, "isTombstone");
}
void* getObjValue(robj *obj) {
    if (obj == NULL || isModuleCrdt(obj) == C_ERR) return NULL;
    moduleValue *mv = obj->ptr;
    return mv->value;
}

CrdtObject *retrieveCrdtObject(robj *obj) {
    return (CrdtObject*)getObjValue(obj);
}

moduleType* getModuleType(robj *obj) {
    moduleValue *mv = obj->ptr;
    moduleType *mt = mv->type;
    return mt;
}
#if defined(CRDT_COMMON_TEST_MAIN)
#include <stdio.h>
#include "testhelp.h"
#include "limits.h"

#define UNUSED(x) (void)(x)
typedef struct nickObject {
    CrdtCommon common;
    sds content;
}nickObject;

void*
mergeFunc (void *curVal, void *value) {
    if(value == NULL || curVal == NULL) {
        return NULL;
    }
    void *dup = zmalloc(1);
    return dup;
}

nickObject
*createNickObject() {
    nickObject *obj = zmalloc(sizeof(nickObject));
    printf("[nickObject]%lu\r\n", sizeof(nickObject));
    obj->content = sdsnew("hello");

    obj->common.vectorClock = sdsnew("1:200");
    obj->common.merge = mergeFunc;
    return obj;
}

int crdtCommonTest(void) {
    nickObject *obj = createNickObject();
    CrdtCommon *common = (CrdtCommon *) obj;
    test_cond("[crdtCommonTest]", sdscmp(sdsnew("1:200"), common->vectorClock) == 0);
    test_cond("[crdtCommonTest]", sdscmp(sdsnew("hello"), obj->content) == 0);
    test_report();
    return 0;
}
#endif

#ifdef CRDT_COMMON_TEST_MAIN
int main(void) {
    return crdtCommonTest();
}
#endif



