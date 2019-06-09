/*
 * Copyright (c) 2016, Salvatore Sanfilippo <antirez at gmail dot com>
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
#include <unistd.h>

/* Open a child-parent channel used in order to move information about the
 * RDB / AOF saving process from the child to the parent (for instance
 * the amount of copy on write memory used) */
void openChildInfoPipe(struct redisServer *srv) {
    if (pipe(srv->child_info_pipe) == -1) {
        /* On error our two file descriptors should be still set to -1,
         * but we call anyway cloesChildInfoPipe() since can't hurt. */
        closeChildInfoPipe(srv);
    } else if (anetNonBlock(NULL,srv->child_info_pipe[0]) != ANET_OK) {
        closeChildInfoPipe(srv);
    } else {
        memset(&srv->child_info_data,0,sizeof(srv->child_info_data));
    }
}

/* Close the pipes opened with openChildInfoPipe(). */
void closeChildInfoPipe(struct redisServer *srv) {
    if (srv->child_info_pipe[0] != -1 ||
        srv->child_info_pipe[1] != -1)
    {
        close(srv->child_info_pipe[0]);
        close(srv->child_info_pipe[1]);
        srv->child_info_pipe[0] = -1;
        srv->child_info_pipe[1] = -1;
    }
}

/* Send COW data to parent. The child should call this function after populating
 * the corresponding fields it want to sent (according to the process type). */
void sendChildInfo(int process_type, struct redisServer *srv) {
    if (srv->child_info_pipe[1] == -1) return;
    srv->child_info_data.magic = CHILD_INFO_MAGIC;
    srv->child_info_data.process_type = process_type;
    ssize_t wlen = sizeof(srv->child_info_data);
    if (write(srv->child_info_pipe[1],&srv->child_info_data,wlen) != wlen) {
        /* Nothing to do on error, this will be detected by the other side. */
    }
}

/* Receive COW data from parent. */
void receiveChildInfo(struct redisServer *srv) {
    if (srv->child_info_pipe[0] == -1) return;
    ssize_t wlen = sizeof(srv->child_info_data);
    if (read(srv->child_info_pipe[0],&srv->child_info_data,wlen) == wlen &&
        srv->child_info_data.magic == CHILD_INFO_MAGIC)
    {
        if (srv->child_info_data.process_type == CHILD_INFO_TYPE_RDB) {
            srv->stat_rdb_cow_bytes = srv->child_info_data.cow_size;
        } else if (srv->child_info_data.process_type == CHILD_INFO_TYPE_AOF) {
            srv->stat_aof_cow_bytes = srv->child_info_data.cow_size;
        }
    }
}
