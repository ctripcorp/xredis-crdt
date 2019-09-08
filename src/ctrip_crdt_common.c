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
#include "sds.h"
#include "server.h"

#include <stdlib.h>

CrdtCommon *retrieveCrdtCommon(robj *obj) {
    if (obj == NULL || isModuleCrdt(obj) == C_ERR) return NULL;
    moduleValue *mv = obj->ptr;
    void *moduleDataType = mv->value;
    CrdtCommon *common = (CrdtCommon *) moduleDataType;
    return common;
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



