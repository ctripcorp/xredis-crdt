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


typedef struct CRDT_Client_Replication {

    int authenticated;      /* When requirepass is non-NULL. for further use*/
    int replstate;          /* Replication state if this is a slave. */
    int repl_put_online_on_ack; /* Install slave write handler on ACK. */
    int repldbfd;           /* Replication DB file descriptor. */
    off_t repldboff;        /* Replication DB file offset. */
    off_t repldbsize;       /* Replication DB file size. */
    sds replpreamble;       /* Replication DB preamble. */

    /**========================= CRDT Replication Client (master) ==============================*/
    long long read_reploff; /* Read offset represents the offset we current read from master's socket, some are not implied yet */
    long long reploff;      /* Applied replication offset */

    /**========================= CRDT Replication Client (slave) ==============================*/
    long long repl_ack_off; /* Replication ack offset, if this is a slave. */
    long long repl_ack_time;/* Replication ack time, if this is a slave. */
    long long psync_initial_offset; /* CRDT FULLRESYNC reply offset other slaves
                                       copying this slave output buffer
                                       should use. */
    char replid[CONFIG_RUN_ID_SIZE+1]; /* Master replication ID (if master). */
    int slave_listening_port; /* As configured with: SLAVECONF listening-port */
    char slave_ip[NET_IP_STR_LEN]; /* Optionally given by REPLCONF ip-address */

}CRDT_Client_Replication;

void crdtPSyncCommand(client *c);

void crdtReplconfCommand(client *c);

void initClientCrdtIfNeeded(client *c);


void crdtCancelReplicationHandshake(client *peer);


#endif //REDIS_CRDT_REPLICATION_H
