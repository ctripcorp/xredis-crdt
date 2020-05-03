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

#ifndef REDIS_CRDT_RDB_H
#define REDIS_CRDT_RDB_H

#include "server.h"
typedef struct crdtRdbSaveInfo {
    int repl_stream_db;  /* DB to select in server.master client. */
    int repl_id_is_set;  /* True if repl_id field is set. */
    char repl_id[CONFIG_RUN_ID_SIZE+1];     /* Replication ID. */
    long long repl_offset;                  /* Replication offset. */
    /* CRDT Specialized param */
    long long logic_time;
} crdtRdbSaveInfo;
#define CRDT_RDB_SAVE_INFO_INIT {-1,0,"000000000000000000000000000000",-1,0}
//crdt module

#define SAVE_CRDT_VALUE  "RdbSaveCrdtValue"
#define LOAD_CRDT_VALUE "RdbLoadCrdtValue"
crdtRdbSaveInfo*
crdtRdbPopulateSaveInfo(crdtRdbSaveInfo *rsi, long long min_logic_time);

int
crdtRdbSaveRio(rio *rdb, int *error, crdtRdbSaveInfo *rsi);

int
rdbSaveRioWithCrdtMerge(rio *rdb, int *error, void *rsi);
int initedCrdtServer();


#endif //REDIS_CRDT_RDB_H
