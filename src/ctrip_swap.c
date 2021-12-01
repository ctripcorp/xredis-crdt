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

#define S2R(s)     (s)
#define R2S(r)     (r)

/* -------------------------- swapping clients ---------------------------- */
swapClient *swapClientCreate(client *c, swap *s) {
    swapClient *sc = zmalloc(sizeof(swapClient));
    sc->c = c;
    if (s->key) incrRefCount(s->key);
    sc->s.key = s->key;
    if (s->subkey) incrRefCount(s->subkey);
    sc->s.subkey = s->subkey;
    if (s->val) incrRefCount(s->val);
    sc->s.val = s->val;
    return sc;
}

void swapClientRelease(swapClient *sc) {
    if (sc->s.key) decrRefCount(sc->s.key);
    if (sc->s.subkey) decrRefCount(sc->s.subkey);
    if (sc->s.val) decrRefCount(sc->s.val);
    zfree(sc);
}

swappingClients *swappingClientsCreate(redisDb *db, robj *key, robj *subkey, swappingClients *parent) {
    swappingClients *scs = zmalloc(sizeof(struct swappingClients));
    scs->db = db;
    if (key) incrRefCount(key);
    scs->key = key;
    if (subkey) incrRefCount(subkey);
    scs->subkey = subkey;
    scs->swapclients = listCreate();
    scs->nchild = 0;
    scs->parent = parent;
    if (parent) parent->nchild++;
    return scs;
}

sds swappingClientsDump(swappingClients *scs) {
    listIter li;
    listNode *ln;
    sds result = sdsempty();
    char *actions[] = {"NOP", "GET", "PUT", "DEL"};

    result = sdscat(result, "[");
    listRewind(scs->swapclients,&li);
    while ((ln = listNext(&li))) {
        swapClient *sc = listNodeValue(ln);
        if (ln != listFirst(scs->swapclients)) result = sdscat(result,",");
        result = sdscat(result,"("); 
        result = sdscat(result,actions[sc->c->cmd->swap_action]); 
        result = sdscat(result,":"); 
        result = sdscatsds(result,sc->s.key->ptr); 
        result = sdscat(result,":"); 
        result = sdscat(result,sc->c->cmd->name); 
        result = sdscat(result,")"); 
    }
    result = sdscat(result, "]");
    return result;
}

/* create like mkdir -p */
swappingClients *swappingClientsCreateP(client *c, robj *key, robj *subkey) {
    swappingClients *scs = server.scs;

    serverAssert(key == NULL || sdsEncodedObject(key));
    serverAssert(subkey == NULL || sdsEncodedObject(subkey));

    /* create scs from root down, starting from global level. */
    if (scs == NULL) {
        swappingClientsCreate(c->db, NULL, NULL, NULL);
        server.scs = scs;
    }
    if (key == NULL) return scs;

    /* then key level */
    if (!lookupEvictSCS(c->db, key)) {
        scs = swappingClientsCreate(c->db, key, NULL, scs);
        setupSwappingClients(c, key, NULL, scs);
    }
    if (subkey == NULL) return scs;

    /* TODO support subkey level */
    return scs;
}

void swappingClientsRelease(swappingClients *scs) {
    if (!scs) return;
    serverAssert(!listLength(scs->swapclients));
    listRelease(scs->swapclients);
    if (scs->parent) scs->parent->nchild--;
    if (scs->key) decrRefCount(scs->key);
    if (scs->subkey) decrRefCount(scs->subkey);
    zfree(scs);
}

void swappingClientsPush(swappingClients *scs, swapClient *sc) {
    serverAssert(scs);
    serverAssert(scs->db == NULL || scs->db == sc->c->db);
    listAddNodeTail(scs->swapclients, sc);
}

swapClient *swappingClientsPop(swappingClients *scs) {
    serverAssert(scs);
    if (!listLength(scs->swapclients)) return NULL;
    listNode *ln = listFirst(scs->swapclients);
    swapClient *sc = listNodeValue(ln);
    listDelNode(scs->swapclients, ln);
    return sc;
}

swapClient *swappingClientsPeek(swappingClients *scs) {
    serverAssert(scs);
    if (!listLength(scs->swapclients)) return NULL;
    listNode *ln = listFirst(scs->swapclients);
    swapClient *sc = listNodeValue(ln);
    return sc;
}

/* return true if current client should directly block on scs (without trying
 * to proceed). */
int swappingClientsBlocking(swappingClients *scs) {
    /* if scs has pending swapclients or child scs, client should directly
     * block untill all pending clints child scs swap finish. */
    if (scs && (listLength(scs->swapclients) || scs->nchild > 0)) {
        return 1;
    } else {
        return 0;
    }
}

/* ----------------------------- swaps result ----------------------------- */

/* Prepare the getSwapsResult struct to hold numswaps, either by using the
 * pre-allocated swaps or by allocating a new array on the heap.
 *
 * This function must be called at least once before starting to populate
 * the result, and can be called repeatedly to enlarge the result array.
 */
void getSwapsPrepareResult(getSwapsResult *result, int numswaps) {
	/* GETKEYS_RESULT_INIT initializes keys to NULL, point it to the pre-allocated stack
	 * buffer here. */
	if (!result->swaps) {
		serverAssert(!result->numswaps);
		result->swaps = result->swapsbuf;
	}

	/* Resize if necessary */
	if (numswaps > result->size) {
		if (result->swaps != result->swapsbuf) {
			/* We're not using a static buffer, just (re)alloc */
			result->swaps = zrealloc(result->swaps, numswaps * sizeof(swap));
		} else {
			/* We are using a static buffer, copy its contents */
			result->swaps = zmalloc(numswaps * sizeof(swap));
			if (result->numswaps)
				memcpy(result->swaps, result->swapsbuf, result->numswaps * sizeof(swap));
		}
		result->size = numswaps;
	}
}

void getSwapsAppendResult(getSwapsResult *result, robj *key, robj *subkey, robj *val) {
    /* Check overflow */    
    if (result->numswaps == result->size) {
        int newsize = result->size + (result->size > 8192 ? 8192 : result->size);
        getSwapsPrepareResult(result, newsize);
    }

    swap *s = &result->swaps[result->numswaps++];
    s->key = key;
    s->subkey = subkey;
    s->val = val;
}

void releaseSwaps(getSwapsResult *result) {
    int i;
    for (i = 0; i < result->numswaps; i++) {
        robj *key = result->swaps[i].key, *subkey = result->swaps[i].subkey;
        if (key) decrRefCount(key);
        if (subkey) decrRefCount(subkey);
    }
}

void getSwapsFreeResult(getSwapsResult *result) {
    if (result && result->swaps != result->swapsbuf) {
        zfree(result->swaps);
    }
}

/* ----------------------------- client swap ------------------------------ */
typedef void (*clientSwapFinishedCallback)(client *c, robj *key, void *pd);

typedef struct {
    client *c;
    robj *key;
    robj *subkey;
    moduleSwapFinishedCallback module_cb;
    void *module_pd;
    swappingClients *scs;
    size_t memory_inflight;
} rocksPrivData;

void clientHoldKey(client *c, robj *key) {
    dictEntry *de;
    robj *val;

    /* No need to hold key if it has already been holded */
    if (dictFind(c->hold_keys, key)) return;
    /* Can't hold not existing key. */
    if ((de = dictFind(c->db->dict, key->ptr)) == NULL) return;
    val = dictGetVal(de);
    /* Increase refcount to reserve key/val in c->hold_keys dict */
    incrRefCount(key);
    incrRefCount(val);
    serverAssert(dictAdd(c->hold_keys, key, val) == DICT_OK);
}

void clientUnholdKeys(client *c) {
    dictEmpty(c->hold_keys, NULL);
}

void continueProcessCommand(client *c) {
    /* size_t prev_offset = c->reploff; */

	c->flags &= ~CLIENT_SWAPPING;
    server.current_client = c;
	call(c,CMD_CALL_FULL);
    /* post call */
    c->woff = server.master_repl_offset;
    if (listLength(server.ready_keys))
        handleClientsBlockedOnLists();
    /* post command */
    commandProcessed(c);
    /* pipelined command might already read into querybuf, if process not
     * restarted, pending commands would not be processed again. */
    processInputBuffer(c);
}

int clientSwapProceed(client *c, swap *s, swappingClients **scs);
void rocksSwapFinished(int action, sds rawkey, sds rawval, void *privdata) {
    rocksPrivData *rocks_pd = privdata;
    client *c = rocks_pd->c;
    swapClient *sc, *nsc;
    swappingClients *scs = rocks_pd->scs, *nscs;
    robj *key = rocks_pd->key, *subkey = rocks_pd->subkey;
    clientSwapFinishedCallback client_cb = (clientSwapFinishedCallback)c->client_swap_finished_cb;
    void *client_pd = c->client_swap_finished_pd;

    server.swap_memory_inflight -= rocks_pd->memory_inflight;
    updateStatsSwapFinish(R2S(action), rawkey, rawval);

    /* Current swapping client should be the head of swapping_clents. */
    sc = swappingClientsPeek(scs);
    serverAssert(sc->c == rocks_pd->c);

    /* Call module cb to swap in/out keyspace before client cb. */
    if (rocks_pd->module_cb) {
        moduleSwapFinished(c, action, rawkey, rawval, rocks_pd->module_cb,
                rocks_pd->module_pd);
    }

    /* Note that client_cb might spawned new swap(typically by expire), those
     * swaps can be appended to scs because PUT will not happend unless scs
     * is empty. */
    if (client_cb)  client_cb(c, key, client_pd);

    swappingClientsPop(scs);
    swapClientRelease(sc);

    /* Re-evaluate and start swap action(if needed) for subsequent clients in
     * current scs. if all clients in current level scs are processed, then
     * we try to process upper level scs. */ 
    while (scs) {
        /* Note that we can't Pop client here, because we need to keep client
         * in front if clientSwapProceed with swap. */
        while ((nsc = swappingClientsPeek(scs))) {
            if (clientSwapProceed(nsc->c, &nsc->s, &scs)) {
                break;
            } else {
                client *nc = nsc->c;
                client_cb = (clientSwapFinishedCallback)nc->client_swap_finished_cb;
                client_pd = nc->client_swap_finished_pd;
                if (client_cb) client_cb(nc, nsc->s.key, client_pd);
                swappingClientsPop(scs);
                swapClientRelease(nsc);
            }
        }

        if (scs->key == NULL) {
            /* Never released or reset global scs (scs->key == NULL). */
            break;
        } else if (!swappingClientsBlocking(scs)) {
            nscs = scs->parent;
            setupSwappingClients(c, scs->key, scs->subkey, NULL);
            swappingClientsRelease(scs);
            if (nscs->nchild > 0)  {
                /* Can't process parent scs if sibiling scs exists. */
                break;
            } else {
                scs = nscs;
            }
        } else {
            setupSwappingClients(c, scs->key, scs->subkey, scs);
            break;
        }
    }

    sdsfree(rawkey);
    sdsfree(rawval);

    if (key) decrRefCount(key);
    if (subkey) decrRefCount(subkey);
    zfree(rocks_pd);
}

/* Estimate memory used for one swap action, server will slow down event
 * processing if swap consumed too much memory(i.e. server is generating
 * io requests faster than rocksdb can handle). */
#define SWAP_MEM_ESTMIATED_ZMALLOC_OVERHEAD   512
#define SWAP_MEM_INFLIGHT_BASE (                                    \
        /* db.evict store scs */                                    \
        sizeof(moduleValue) + sizeof(robj) + sizeof(dictEntry) +    \
        sizeof(swapClient) + sizeof(swappingClients) +              \
        sizeof(rocksPrivData) +                                     \
        sizeof(RIO) +                                               \
        /* link in scs, pending_rios, processing_rios */            \
        (sizeof(list) + sizeof(listNode))*3 )
static inline size_t estimateSwapMemoryInflight(sds rawkey, sds rawval, rocksPrivData *pd) {
    size_t result = 0;
    if (rawkey) result += sdsalloc(rawkey);
    if (rawval) result += sdsalloc(rawval);
    if (pd->key) {
        result += sizeof(robj);
        result += sdsalloc(pd->key->ptr);
        result += keyComputeSize(pd->c->db, pd->key);
    }
    if (pd->subkey) {
        result += sizeof(robj);
        result += sdsalloc(pd->subkey->ptr);
    }
    return SWAP_MEM_INFLIGHT_BASE + SWAP_MEM_ESTMIATED_ZMALLOC_OVERHEAD + result;
}

/* Called when there are no preceding swapping clients: swap action will be
 * re-evaluated according to keyspace status to decide whether & which swap
 * action should be triggered. */
int clientSwapProceed(client *c, swap *s, swappingClients **pscs) {
    int action;
    sds rawkey, rawval = NULL;
    moduleSwapFinishedCallback module_cb;
    void *module_pd;

    if (swapAna(c, s->key, s->subkey, &action, &rawkey, &rawval, &module_cb,
                &module_pd) || action == SWAP_NOP) {
        /* TODO: Something went wrong in swap ana, flag client to abort
         * process current command and reply with SWAP_FAILED_xx:
         * c->swap_result = SWAP_FAILED_xx. */ 
        return 0;
    }

    /* Async swap is necessary if we reached here. 
     * scs NULL means that current swap is not blocked and should be blocked
     * on deepest level of scs */
    if (*pscs == NULL)  *pscs = swappingClientsCreateP(c, s->key, s->subkey);

    rocksPrivData *rocks_pd = zmalloc(sizeof(rocksPrivData));
    rocks_pd->c = c;
    if (s->key) incrRefCount(s->key);
    rocks_pd->key = s->key;
    if (s->subkey) incrRefCount(s->subkey);
    rocks_pd->subkey = s->subkey;
    rocks_pd->module_cb = module_cb;
    rocks_pd->module_pd = module_pd;
    rocks_pd->scs = *pscs;

    rocks_pd->memory_inflight = estimateSwapMemoryInflight(rawkey, rawval, rocks_pd);
    server.swap_memory_inflight += rocks_pd->memory_inflight;
    updateStatsSwapStart(action, rawkey, rawval);
    rocksIOSubmitAsync(crc16(rawkey, sdslen(rawkey)), S2R(action), rawkey,
           rawval, rocksSwapFinished, rocks_pd);
    return 1;
}

/* NOTE: swaps is swap intentions analyzed according to command (without query
 * keyspace). whether to start swap action is determined later in swapAna. */
int clientSwapSwaps(client *c, getSwapsResult *result, clientSwapFinishedCallback cb, void *pd) {
    int nswaps = 0, i;

    c->client_swap_finished_cb = (voidfuncptr)cb;
    c->client_swap_finished_pd = pd;

    for (i = 0; i < result->numswaps; i++) {
        swappingClients *scs;
        swap *s = &result->swaps[i];

        scs = lookupSwappingClients(c, s->key, s->subkey);

        /* defer command processsing if there are preceeding swap clients. */
        if (swappingClientsBlocking(scs)) {
            swappingClientsPush(scs, swapClientCreate(c,s));
            nswaps++;
        } else if (clientSwapProceed(c, s, &scs)) {
            serverAssert(scs); /* Proceed would create scs if swap needed. */
            swappingClientsPush(scs, swapClientCreate(c, s));
            nswaps++; 
        } else {
            /* no need to swap, but still we need to hold keys because client
             * might swap other keys. */
            if (s->key) clientHoldKey(c, s->key);
        }
    }

    if (!nswaps) clientUnholdKeys(c);
    c->swapping_count = nswaps;

    return nswaps;
}

void clientSwapFinished(client *c, robj *key, void *pd) {
    UNUSED(pd);
    if (key) clientHoldKey(c, key);
    c->swapping_count--;
    if (c->swapping_count == 0) {
        if (!c->CLIENT_DEFERED_CLOSING) continueProcessCommand(c);
        clientUnholdKeys(c);
    }
}

/* Start swapping or schedule a swapping task for client:
 * - if client requires swapping key (some other client is doing rocksdb IO for
 *   this key), we defer and re-evaluate untill all preceding swap finished.
 * - if client requires cold(evicted) key, and there is no preceeding swap
 *   action, we start a new swapping task.
 * - if client requires hot or not-existing key, no swap is needed.
 *
 * this funcion returns num swapping needed for this client, we should pause
 * processCommand if swapping needed. */
int clientSwap(client *c) {
    int swap_count;
    getSwapsResult result = GETSWAPS_RESULT_INIT;
    getSwaps(c, &result);
    swap_count = clientSwapSwaps(c, &result, clientSwapFinished, NULL);
    releaseSwaps(&result);
    getSwapsFreeResult(&result);
    return swap_count;
}

/* ----------------------------- repl swap ------------------------------ */
static void replDispatch(client *wc, client *c) {
    /* Move command from repl client to repl worker client. */
    if (wc->argv) zfree(wc->argv);
    wc->argc = c->argc, c->argc = 0;
    wc->argv = c->argv, c->argv = NULL;
    wc->cmd = c->cmd;
    wc->lastcmd = c->lastcmd;
    wc->flags = c->flags;
    wc->cmd_reploff = c->read_reploff - sdslen(c->querybuf);
    wc->repl_client = c;

    /* Also reset repl client args so it will not be freed by resetClient. */

    /* In order to dispatch transaction to the same worker client, process
     * multi command whether preceeding commands processed or not. */
    if (c->cmd->proc == multiCommand) {
        wc->CLIENT_REPL_DISPATCHING = 1;
        resetClient(wc);
    } else if (wc->CLIENT_REPL_DISPATCHING) {
        if (c->cmd->proc == execCommand || c->cmd->proc == crdtExecCommand) {
            wc->CLIENT_REPL_DISPATCHING = 0;
        } else {
            queueMultiCommand(wc);
            resetClient(wc);
        }
    } else {
        /* Switch to another repl worker client. */
    }
}

static void processRepl() {
    listNode *ln;
    client *wc, *c;

    while ((ln = listFirst(server.repl_worker_clients_used))) {
        wc = listNodeValue(ln);
        if (wc->CLIENT_REPL_SWAPPING) break;
        c = wc->repl_client;

        serverAssert((c->flags&CLIENT_MASTER) || (c->flags&CLIENT_CRDT_MASTER));

        wc->flags &= ~CLIENT_SWAPPING;
        listDelNode(server.repl_worker_clients_used, ln);
        listAddNodeTail(server.repl_worker_clients_free, wc);

        clientUnholdKeys(wc);

        server.current_client = c;

        call(wc, CMD_CALL_FULL);

        /* post call */
        c->woff = server.master_repl_offset;
        if (listLength(server.ready_keys))
            handleClientsBlockedOnLists();

        c->db = wc->db;
        c->gid = wc->gid;

        commandProcessed(wc);

        /* update peer backlog or offset. */
        if ((c->flags & CLIENT_MASTER) && iAmMaster() != C_OK) {
            if(c->gid == crdtServer.crdt_gid) {
                /* Recover peer-backlog from repl-stream so that when this slave
                   promoted as new master, other peers could PSYNC, Note that
                   we only recover peer-stream created by current gid.  */
                feedReplicationBacklog(&crdtServer, c->pending_querybuf,
                        wc->cmd_reploff - c->reploff);
            } else if(c->gid != -1) {
                CRDT_Master_Instance* peer = getPeerMaster(c->gid);
                if(peer) { 
                    if(peer->master != NULL) {
                        peer->master->reploff += wc->cmd_reploff - c->reploff;
                    } else {
                        serverLog(LL_WARNING, "peer client is null, gid:%d", c->gid);
                    }
                }
            }
        }

        long long prev_offset = c->reploff;
        /* update reploff */
        if (((c->flags & CLIENT_MASTER)
                    || ((c->flags & CLIENT_CRDT_MASTER) &&
                        getPeerMaster(c->gid)->repl_state == REPL_STATE_CONNECTED))
                && !(c->flags & CLIENT_MULTI)) {
            /* Update the applied replication offset of our master. */
            c->reploff = wc->cmd_reploff;
        }

        /* proxy repl stream to subslaves.
         * Note that crdt redis might replicate from vanilla redis when
         * migrating, in which case repl stream is not proxied (crdt redis
         * will propagate it's own crdt style repl stream). */

        /* Sep/07/2019 marked by nick, we should also propagate the stream if client is
         * a crdt(peer) master, as we wish our slaves to keeper align with peer master's
         * repl offset, so that, when a failover happend locally, the globally repl_offset
         * will not be any different */
        if (((c->flags & CLIENT_MASTER) && iAmMaster() != C_OK) ||
                ((c->flags & CLIENT_CRDT_MASTER) && 
                 getPeerMaster(c->gid)->repl_state == REPL_STATE_CONNECTED)) {
            long long applied = c->reploff - prev_offset;
            if (applied) {
                if(server.slaveseldb != c->db->id) {
                    sendSelectCommandToSlave(c->db->id);
                }
                replicationFeedSlavesFromMasterStream(server.slaves,
                        c->pending_querybuf,applied);
                sdsrange(c->pending_querybuf,applied,-1);
            }
        }
    }
}

void replSwapFinished(client *wc, robj *key, void *pd) {
    client *c;
    listNode *ln;
    list *repl_swapping_clients;

    UNUSED(pd);

    if (key) clientHoldKey(wc, key);

    /* Flag swap finished, note that command processing will be defered to
     * processRepl becasue there might be unfinished preceeding swap. */
    wc->swapping_count--;
    if (wc->swapping_count == 0) wc->CLIENT_REPL_SWAPPING = 0;

    processRepl();

    /* Dispatch repl command again for repl client blocked waiting free
     * worker repl client. */
    if (!listFirst(server.repl_swapping_clients) ||
            !listFirst(server.repl_worker_clients_free)) {
        return;
    }

    repl_swapping_clients = server.repl_swapping_clients;
    server.repl_swapping_clients = listCreate();
    while ((ln = listFirst(repl_swapping_clients))) {
        c = listNodeValue(ln);

        c->flags &= ~CLIENT_SWAPPING;
        replClientSwap(c);
        processInputBuffer(c);

        listDelNode(repl_swapping_clients,ln);
    }
    listRelease(repl_swapping_clients);
}

int replSwap(client *c) {
    int swap_count;
    getSwapsResult result = GETSWAPS_RESULT_INIT;
    getSwaps(c, &result);
    swap_count = clientSwapSwaps(c, &result, replSwapFinished, NULL);
    releaseSwaps(&result);
    getSwapsFreeResult(&result);
    return swap_count;
}

int replClientSwap(client *c) {
    client *wc;
    listNode *ln;

    serverAssert(!(c->flags & CLIENT_SWAPPING));

    if (!(ln = listFirst(server.repl_worker_clients_free))) {
        /* return swapping if there are no worker to dispatch, so command
         * processing loop would break out.
         * Note that peer client might register no rocks callback but repl
         * stream read and parsed, we need to processInputBuffer again. */
        listAddNodeTail(server.repl_swapping_clients, c);
        return 1;
    }

    wc = listNodeValue(ln);
    serverAssert(wc);
    serverAssert(!wc->CLIENT_REPL_SWAPPING || wc->flags & CLIENT_MULTI);

    /* dispatch repl commands to worker clients */
    replDispatch(wc, c);

    /* swap data for command, note that replicated commands would be processed
     * later in processRepl when all preceeding commands finished. */
    if (!wc->CLIENT_REPL_DISPATCHING) {
        wc->CLIENT_REPL_SWAPPING = replSwap(wc);

        listDelNode(server.repl_worker_clients_free, ln);
        listAddNodeTail(server.repl_worker_clients_used, wc);
    }

    /* process repl commands in received order (regardless of swap finished
     * order) to make sure slave is consistent with master. */
    processRepl();

    /* return dispatched(-1) when repl dispatched command to workers, caller
     * should skip call and continue command processing loop. */
    return -1;
}

/* ----------------------------- expire ------------------------------ */
/* Assumming that key is expired and deleted from db, we still need to del
 * from rocksdb. */
int rocksDeleteNoReply(client *c, robj *key) {
    int swap_count;
    getSwapsResult result = GETSWAPS_RESULT_INIT;
    getExpireSwaps(c, key, &result);
    swap_count = clientSwapSwaps(c, &result, NULL, NULL);
    releaseSwaps(&result);
    getSwapsFreeResult(&result);
    return swap_count;
}

int rocksDelete(redisDb *db, robj *key) {
    client *c = server.rksdel_clients[db->id];
    return rocksDeleteNoReply(c, key);
}

/* Must make sure expire key or key shell not evicted (propagate needed) */
void expireKey(client *c, robj *key, void *pd) {
    UNUSED(pd);
    redisDb *db = c->db;
    mstime_t when = getExpire(db, key);

    if (crdtPropagateExpire(db,key,server.lazyfree_lazy_expire,when) != C_OK) {
        return;
    }

    rocksDelete(db, key);

    notifyKeyspaceEvent(NOTIFY_EXPIRED, "expired",key,db->id);
    server.lazyfree_lazy_expire ? dbAsyncDelete(db,key) : dbSyncDelete(db,key);
}

/* Cases when clientExpireNoReply is called:
 * - active-expire: DEL swap will be append as if key is expired by dummy client.
 * - xxCommand: DEL swap will be append to scs of the key, bacause that key is
 *   holded before xxCommand, so scs of key will not have any PUT. so async
 *   DEL swap have the same effect of sync DEL.
 * - continueProcessCommand: same as xxCommand.
 * TODO opt: keys never evicted to rocksdb need not to be deleted from rocksdb. */
int clientExpireNoReply(client *c, robj *key) {
    int swap_count;
    getSwapsResult result = GETSWAPS_RESULT_INIT;
    getExpireSwaps(c, key, &result);
    swap_count = clientSwapSwaps(c, &result, expireKey, NULL);
    releaseSwaps(&result);
    getSwapsFreeResult(&result);
    return swap_count;
}

/* How key is expired:
 * 1. SWAP GET if expiring key is EVICTED (clientExpireNoReply), note that
 *    this expire key evicted would only happend for active expire, because
 *    key have already been loaded before cmd->proc, so xxCommand won't trigger
 *    SWAP GET.
 * 2. Do dbDelete & propagate & notify  (expireKey) 
 * 3. Delete expired key from rocksdb (rocksDelete). NOTE that although
 *    DEL swap appended to scs tail rather than scs head, but because PUT
 *    will not happend if scs is not empty, so PUT will not happen if DEL
 *    append to tail, thus key would not be evicted to before DEL. so DEL
 *    is technically started right away.
 *
 * Note that currently we can only generate ONE action for each swap, so we
 * can't do both GET+propagate & DEL+nop in step 1, so rocks DEL+nop is
 * defered untill GET+propagate finished.
 */
int dbExpire(redisDb *db, robj *key) {
    client *c = server.rksget_clients[db->id];
    int nswap = clientExpireNoReply(c, key);
    /* when expiring key is in db.dict, we don't need to swapin key, but still
     * we need to do expireKey to remove key from db and rocksdb. */
    if (nswap == 0) expireKey(c, key, NULL);
    return nswap;
}

/* `rksdel` `rksget` are fake commands used only to provide flags for swap_ana,
 * use `touch` command to expire key actively instead. */
void rksdelCommand(client *c) {
    addReply(c, shared.ok);
}

void rksgetCommand(client *c) {
    addReply(c, shared.ok);
}

/* ----------------------------- eviction ------------------------------ */
int clientEvictNoReply(client *c, robj *key) {
    int swap_count;
    getSwapsResult result = GETSWAPS_RESULT_INIT;
    getEvictionSwaps(c, key, &result);
    swap_count = clientSwapSwaps(c, &result, NULL, NULL);
    releaseSwaps(&result);
    getSwapsFreeResult(&result);
    return swap_count;
}

int dbEvict(redisDb *db, robj *key) {
    client *c = server.evict_clients[db->id];
    robj *o;

    if (server.scs && listLength(server.scs->swapclients)) {
        return 0;
    }

    /* Trigger evict only if key is PRESENT && !SWAPPING && !HOLDED */
    if ((o = lookupKey(db, key, LOOKUP_NOTOUCH)) == NULL ||
            o->refcount > 1 ||
            lookupEvict(db, key)) {
        return 0;
    }
    
    return clientEvictNoReply(c, key);
}

/* EVICT is a special command that getswaps returns nothing ('cause we don't
 * need to swap anything before command executes) but does swap out(PUT)
 * inside command func. Note that EVICT is the command of fake evict clients */
void evictCommand(client *c) {
    int i, nevict = 0;
    for (i = 1; i < c->argc; i++) {
        nevict += dbEvict(c->db, c->argv[i]);
    }
    addReplyLongLong(c, nevict);
}

/* ----------------------------- statistics ------------------------------ */
int swapsPendingOfType(int type) {
    long long pending;
    serverAssert(type < SWAP_TYPES);
    pending = server.swap_stats[type].started - server.swap_stats[type].finished;
    return pending > 0 ? (int)pending : 0;
}

void updateStatsSwapStart(int type, sds rawkey, sds rawval) {
    serverAssert(type < SWAP_TYPES);
    size_t rawkey_bytes = rawkey == NULL ? 0 : sdslen(rawkey);
    size_t rawval_bytes = rawval == NULL ? 0 : sdslen(rawval);
    server.swap_stats[type].started++;
    server.swap_stats[type].last_start_time = server.mstime;
    server.swap_stats[type].started_rawkey_bytes += rawkey_bytes;
    server.swap_stats[type].started_rawval_bytes += rawval_bytes;
}

void updateStatsSwapFinish(int type, sds rawkey, sds rawval) {
    serverAssert(type < SWAP_TYPES);
    size_t rawkey_bytes = rawkey == NULL ? 0 : sdslen(rawkey);
    size_t rawval_bytes = rawval == NULL ? 0 : sdslen(rawval);
    server.swap_stats[type].finished++;
    server.swap_stats[type].last_finish_time = server.mstime;
    server.swap_stats[type].finished_rawkey_bytes += rawkey_bytes;
    server.swap_stats[type].finished_rawval_bytes += rawval_bytes;
}

/*  WHY do we need both getswaps & getdataswaps?
 *  - getswaps return swap intentions analyzed from command without querying
 *  keyspace; while getdataswaps return swaps based on data type (e.g.
 *  return partial fields for crdt-hash eviction). so getswaps corresponds
 *  to redis command, while getdataswaps corresponds to data type.
 *  - merge getdataswaps into getswaps means that we need to define
 *  getswaps_proc for whole key commands(e.g. set/incr) and lookup keyspace
 *  inside getswap_proc to determin what swap should be returned.
 */

int getSwapsNone(struct redisCommand *cmd, robj **argv, int argc, getSwapsResult *result) {
    UNUSED(cmd);
    UNUSED(argc);
    UNUSED(argv);
    UNUSED(result);
    return 0;
}

/* Used by flushdb/flushall to get global scs(similar to table lock). */
int getSwapsGlobal(struct redisCommand *cmd, robj **argv, int argc, getSwapsResult *result) {
    UNUSED(cmd);
    UNUSED(argc);
    UNUSED(argv);
    getSwapsAppendResult(result, NULL, NULL, NULL);
    return 0;
}

/* Different from original replication stream process, slave.master client
 * might trigger swap and block untill rocksdb IO finish. because there is
 * only one master client so rocksdb IO will be done sequentially, thus slave
 * can't catch up with master. 
 * In order to speed up replication stream processing, slave.master client
 * dispatches command to multiple worker client and execute commands when 
 * rocks IO finishes. Note that replicated commands swap in-parallel but we
 * still processed in received order. */
int dbSwap(client *c) {
    if (!(c->flags & CLIENT_MASTER) && !(c->flags & CLIENT_CRDT_MASTER)) {
        /* normal client swap */
        return clientSwap(c);
    } else {
        /* repl client swap */
        return replClientSwap(c);
    }
}

void swapInit() {
    int i;
    char *swap_type_names[] = {"nop", "get", "put", "del"};

    server.debug_evict_keys = 0;
    server.swap_stats = zmalloc(SWAP_TYPES*sizeof(swapStat));
    for (i = 0; i < SWAP_TYPES; i++) {
        server.swap_stats[i].name = swap_type_names[i];
        server.swap_stats[i].started = 0;
        server.swap_stats[i].finished = 0;
        server.swap_stats[i].last_start_time = 0;
        server.swap_stats[i].last_finish_time = 0;
        server.swap_stats[i].started_rawkey_bytes = 0;
        server.swap_stats[i].finished_rawkey_bytes = 0;
        server.swap_stats[i].started_rawval_bytes = 0;
        server.swap_stats[i].finished_rawval_bytes = 0;
    }

    server.evict_clients = zmalloc(server.dbnum*sizeof(client*));
    for (i = 0; i < server.dbnum; i++) {
        client *c = createClient(-1);
        c->cmd = lookupCommandByCString("EVICT");
        c->db = server.db+i;
        server.evict_clients[i] = c;
    }

    server.rksdel_clients = zmalloc(server.dbnum*sizeof(client*));
    for (i = 0; i < server.dbnum; i++) {
        client *c = createClient(-1);
        c->db = server.db+i;
        c->cmd = lookupCommandByCString("RKSDEL");
        server.rksdel_clients[i] = c;
    }

    server.rksget_clients = zmalloc(server.dbnum*sizeof(client*));
    for (i = 0; i < server.dbnum; i++) {
        client *c = createClient(-1);
        c->db = server.db+i;
        c->cmd = lookupCommandByCString("RKSGET");
        server.rksget_clients[i] = c;
    }

    server.dummy_clients = zmalloc(server.dbnum*sizeof(client*));
    for (i = 0; i < server.dbnum; i++) {
        client *c = createClient(-1);
        c->db = server.db+i;
        server.dummy_clients[i] = c;
    }

    server.scs = swappingClientsCreate(NULL, NULL, NULL, NULL);

    server.repl_workers = 64;
    server.repl_swapping_clients = listCreate();
    server.repl_worker_clients_free = listCreate();
    server.repl_worker_clients_used = listCreate();
    for (i = 0; i < server.repl_workers; i++) {
        client *c = createClient(-1);
        listAddNodeTail(server.repl_worker_clients_free, c);
    }
}

/* ------------------------ parallel swap -------------------------------- */
parallelSwap *parallelSwapNew(int parallel) {
    int i;
    parallelSwap *ps = zmalloc(sizeof(parallelSwap));

    ps->parallel = parallel;
    ps->entries = listCreate();

    for (i = 0; i < parallel; i++) {
        int fds[2];
        swapEntry *e;

        if (pipe(fds)) {
            serverLog(LL_WARNING, "create future pipe failed: %s",
                    strerror(errno));
            goto err;
        }

        e = zmalloc(sizeof(swapEntry));
        e->inprogress = 0;
        e->pipe_read_fd = fds[0];
        e->pipe_write_fd = fds[1];
        e->pd = NULL;

        listAddNodeTail(ps->entries, e);
    }
    return ps;

err:
    listRelease(ps->entries);
    return NULL;
}

void parallelSwapFree(parallelSwap *ps) {
    listNode *ln;
    while ((ln = listFirst(ps->entries))) {
        swapEntry *e = listNodeValue(ln);
        close(e->pipe_read_fd);
        close(e->pipe_write_fd);
        zfree(e);
        listDelNode(ps->entries, ln);
    }
    listRelease(ps->entries);
    zfree(ps);
}

static int parallelSwapProcess(swapEntry *e) {
    if (e->inprogress) {
        char c;
        sds rawkey, rawval;
        if (read(e->pipe_read_fd, &c, 1) != 1) {
            serverLog(LL_WARNING, "wait swap entry failed: %s",
                    strerror(errno));
            return C_ERR;
        }
        e->inprogress = 0;
        RIOReap(e->r, &rawkey, &rawval);
        return e->cb(rawkey, rawval, e->pd);
    }
    return C_OK;
}

/* Submit one swap (task). swap will start and finish in submit order. */
int parallelSwapSubmit(parallelSwap *ps, sds rawkey, parallelSwapFinishedCb cb, void *pd) {
    listNode *ln;
    swapEntry *e;
    static int rocksdist = 0;
    /* wait and handle previous swap */
    if (!(ln = listFirst(ps->entries))) return C_ERR;
    e = listNodeValue(ln);
    if (parallelSwapProcess(e)) return C_ERR;
    listRotateHeadToTail(ps->entries);
    /* load new swap */
    e->cb = cb;
    e->pd = pd;
    e->inprogress = 1;
    e->r = rocksIOSubmitSync(rocksdist++, ROCKS_GET, rawkey, NULL,
            e->pipe_write_fd);
    return C_OK;
}

int parallelSwapDrain(parallelSwap *ps) {
    listIter li;
    listNode *ln;

    listRewind(ps->entries, &li);
    while((ln = listNext(&li))) {
        swapEntry *e = listNodeValue(ln);
        if ((parallelSwapProcess(e)))
            return C_ERR;
    }

    return C_OK;
}

