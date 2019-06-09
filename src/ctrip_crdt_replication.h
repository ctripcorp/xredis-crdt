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
// Created by zhuchen on 2019-05-05.
//

#ifndef REDIS_CRDT_REPLICATION_H
#define REDIS_CRDT_REPLICATION_H

/* Slave replication state. Used in server.repl_state for slaves to remember
 * what to do next. */
#define CRDT_REPL_STATE_NONE 0 /* No active replication */
#define CRDT_REPL_STATE_CONNECT 1 /* Must connect to master */
#define CRDT_REPL_STATE_CONNECTING 2 /* Connecting to master */
/* --- Handshake states, must be ordered --- */
#define CRDT_REPL_STATE_RECEIVE_PONG 3 /* Wait for PING reply */
#define CRDT_REPL_STATE_SEND_AUTH 4 /* Send AUTH to master */
#define CRDT_REPL_STATE_RECEIVE_AUTH 5 /* Wait for AUTH reply */
#define CRDT_REPL_STATE_SEND_PORT 6 /* Send REPLCONF listening-port */
#define CRDT_REPL_STATE_RECEIVE_PORT 7 /* Wait for REPLCONF reply */
#define CRDT_REPL_STATE_SEND_IP 8 /* Send REPLCONF ip-address */
#define CRDT_REPL_STATE_RECEIVE_IP 9 /* Wait for REPLCONF reply */
#define CRDT_REPL_STATE_SEND_CAPA 10 /* Send REPLCONF capa */
#define CRDT_REPL_STATE_RECEIVE_CAPA 11 /* Wait for REPLCONF reply */
#define CRDT_REPL_STATE_SEND_VECTOR_CLOCK 12 /* Send PSYNC */
#define CRDT_REPL_STATE_RECEIVE_VECTOR_CLOCK 13 /* Wait for PSYNC reply */
#define CRDT_REPL_STATE_SEND_PSYNC 14 /* Send PSYNC */
#define CRDT_REPL_STATE_RECEIVE_PSYNC 15 /* Wait for PSYNC reply */
/* --- End of handshake states --- */
#define CRDT_REPL_STATE_TRANSFER 16 /* Receiving .rdb from master */
#define CRDT_REPL_STATE_CONNECTED 17 /* Connected to master */

/* State of slaves from the POV of the master. Used in client->replstate.
 * In SEND_BULK and ONLINE state the slave receives new updates
 * in its output queue. In the WAIT_BGSAVE states instead the server is waiting
 * to start the next background saving in order to send updates to it. */
#define CRDT_SLAVE_STATE_WAIT_BGSAVE_START 6 /* We need to produce a new RDB file. */
#define CRDT_SLAVE_STATE_WAIT_BGSAVE_END 7 /* Waiting RDB file creation to finish. */
#define CRDT_SLAVE_STATE_SEND_BULK 8 /* Sending RDB file to slave. */
#define CRDT_SLAVE_STATE_ONLINE 9 /* RDB file transmitted, sending just updates. */

#include "server.h"


void crdtCancelReplicationHandshake(long long gid);


#endif //REDIS_CRDT_REPLICATION_H
