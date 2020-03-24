/*
 * Copyright (c) 2009-2012, Salvatore Sanfilippo <antirez at gmail dot com>
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

/*-----------------------------------------------------------------------------
 * Pubsub low level API
 *----------------------------------------------------------------------------*/

void freePubsubPattern(void *p) {
    pubsubPattern *pat = p;

    decrRefCount(pat->pattern);
    zfree(pat);
}

int listMatchPubsubPattern(void *a, void *b) {
    pubsubPattern *pa = a, *pb = b;

    return (pa->client == pb->client) &&
           (equalStringObjects(pa->pattern,pb->pattern));
}

/* Return the number of channels + patterns a client is subscribed to. */
int clientSubscriptionsCount(client *c) {
    return dictSize(c->pubsub_channels)+
           listLength(c->pubsub_patterns);
}
int clientCrdtSubscriptionsCount(client *c) {
    return dictSize(c->crdt_pubsub_channels) +
        listLength(c->crdt_pubsub_patterns);
}

/* Subscribe a client to a channel. Returns 1 if the operation succeeded, or
 * 0 if the client was already subscribed to that channel. */
int pubsubSubscribeChannel(struct redisServer* srv, client *c, robj *channel) {
    dictEntry *de;
    list *clients = NULL;
    int retval = 0;
    dict* pubsub_channels;
    if(srv == &crdtServer) {
        pubsub_channels = c->crdt_pubsub_channels;
    } else {
        pubsub_channels = c->pubsub_channels;
    }
    /* Add the channel to the client -> channels hash table */
    if (dictAdd(pubsub_channels,channel,NULL) == DICT_OK) {
        retval = 1;
        incrRefCount(channel);
        /* Add the client to the channel -> list of clients hash table */
        de = dictFind(srv->pubsub_channels,channel);
        if (de == NULL) {
            clients = listCreate();
            dictAdd(srv->pubsub_channels,channel,clients);
            incrRefCount(channel);
        } else {
            clients = dictGetVal(de);
        }
        listAddNodeTail(clients,c);
    }
    /* Notify the client */
    if(srv == &crdtServer) {
        addReply(c,shared.mbulkhdr[3]);
        addReply(c,shared.crdtsubscribebulk);
        addReplyBulk(c,channel);
        addReplyLongLong(c, clientCrdtSubscriptionsCount(c));
    } else {
        addReply(c,shared.mbulkhdr[3]);
        addReply(c,shared.subscribebulk);
        addReplyBulk(c,channel);
        addReplyLongLong(c,clientSubscriptionsCount(c));
    
    }
    return retval;
}

/* Unsubscribe a client from a channel. Returns 1 if the operation succeeded, or
 * 0 if the client was not subscribed to the specified channel. */
int pubsubUnsubscribeChannel(struct redisServer *srv, client *c, robj *channel, int notify) {
    dictEntry *de;
    list *clients;
    listNode *ln;
    int retval = 0;
    dict* pubsub_channels = srv == &crdtServer? c->crdt_pubsub_channels: c->pubsub_channels;

    /* Remove the channel from the client -> channels hash table */
    incrRefCount(channel); /* channel may be just a pointer to the same object
                            we have in the hash tables. Protect it... */
    if (dictDelete(pubsub_channels,channel) == DICT_OK) {
        retval = 1;
        /* Remove the client from the channel -> clients list hash table */
        de = dictFind(srv->pubsub_channels,channel);
        serverAssertWithInfo(c,NULL,de != NULL);
        clients = dictGetVal(de);
        ln = listSearchKey(clients,c);
        serverAssertWithInfo(c,NULL,ln != NULL);
        listDelNode(clients,ln);
        if (listLength(clients) == 0) {
            /* Free the list and associated hash entry at all if this was
             * the latest client, so that it will be possible to abuse
             * Redis PUBSUB creating millions of channels. */
            dictDelete(srv->pubsub_channels,channel);
        }
    }
    /* Notify the client */
    if (notify) {
        if (srv == &crdtServer) {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.uncrdtsubscribebulk);
            addReplyBulk(c,channel);
            addReplyLongLong(c,dictSize(c->crdt_pubsub_channels)+
                        listLength(c->crdt_pubsub_patterns));
        } else {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.unsubscribebulk);
            addReplyBulk(c,channel);
            addReplyLongLong(c,dictSize(c->pubsub_channels)+
                        listLength(c->pubsub_patterns));
        }
        

    }
    decrRefCount(channel); /* it is finally safe to release it */
    return retval;
}

/* Subscribe a client to a pattern. Returns 1 if the operation succeeded, or 0 if the client was already subscribed to that pattern. */
int pubsubSubscribePattern(struct redisServer *srv, client *c, robj *pattern) {
    int retval = 0;
    list* pubsub_patterns;
    if(srv == &crdtServer) {
        pubsub_patterns = c->crdt_pubsub_patterns;
    } else {
        pubsub_patterns = c->pubsub_patterns;
    }
    if (listSearchKey(pubsub_patterns,pattern) == NULL) {
        retval = 1;
        pubsubPattern *pat;
        listAddNodeTail(pubsub_patterns,pattern);
        incrRefCount(pattern);
        pat = zmalloc(sizeof(*pat));
        pat->pattern = getDecodedObject(pattern);
        pat->client = c;
        listAddNodeTail(srv->pubsub_patterns,pat);
    }
    /* Notify the client */
    if(srv == &crdtServer) {
        addReply(c,shared.mbulkhdr[3]);
        addReply(c,shared.crdtpsubscribebulk);
        addReplyBulk(c,pattern);
        addReplyLongLong(c,clientCrdtSubscriptionsCount(c));
    } else {
        addReply(c,shared.mbulkhdr[3]);
        addReply(c,shared.psubscribebulk);
        addReplyBulk(c,pattern);
        addReplyLongLong(c,clientSubscriptionsCount(c));
    }
    
    return retval;
}

/* Unsubscribe a client from a channel. Returns 1 if the operation succeeded, or
 * 0 if the client was not subscribed to the specified channel. */
int pubsubUnsubscribePattern(struct redisServer *srv, client *c, robj *pattern, int notify) {
    listNode *ln;
    pubsubPattern pat;
    int retval = 0;
    list* pubsub_patterns;
    if(srv == &crdtServer) {
        pubsub_patterns = c->crdt_pubsub_patterns;
    } else {
        pubsub_patterns = c->pubsub_patterns;
    }
    incrRefCount(pattern); /* Protect the object. May be the same we remove */
    if ((ln = listSearchKey(pubsub_patterns,pattern)) != NULL) {
        retval = 1;
        listDelNode(pubsub_patterns,ln);
        pat.client = c;
        pat.pattern = pattern;
        ln = listSearchKey(srv->pubsub_patterns,&pat);
        listDelNode(srv->pubsub_patterns,ln);
    }
    /* Notify the client */
    if (notify) {
        if(srv == &crdtServer) {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.crdtpunsubscribebulk);
            addReplyBulk(c,pattern);
            addReplyLongLong(c,clientCrdtSubscriptionsCount(c));
        } else {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.punsubscribebulk);
            addReplyBulk(c,pattern);
            addReplyLongLong(c,clientSubscriptionsCount(c));
        }
        
    }
    decrRefCount(pattern);
    return retval;
}

/* Unsubscribe from all the channels. Return the number of channels the
 * client was subscribed to. */
int pubsubUnsubscribeAllChannels(struct redisServer *srv, client *c, int notify) {
    dict* pubsub_channels = srv == &crdtServer ? c->crdt_pubsub_channels: c->pubsub_channels;
    dictIterator *di = dictGetSafeIterator(pubsub_channels);
    dictEntry *de;
    int count = 0;

    while((de = dictNext(di)) != NULL) {
        robj *channel = dictGetKey(de);

        count += pubsubUnsubscribeChannel(srv, c,channel,notify);
    }
    /* We were subscribed to nothing? Still reply to the client. */
    if (notify && count == 0) {
        if(srv == &crdtServer) {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.uncrdtsubscribebulk);
            addReply(c,shared.nullbulk);
            addReplyLongLong(c,clientCrdtSubscriptionsCount(c));
        }else{
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.unsubscribebulk);
            addReply(c,shared.nullbulk);
            addReplyLongLong(c,clientSubscriptionsCount(c));
        }
        
    }
    dictReleaseIterator(di);
    return count;
}

/* Unsubscribe from all the patterns. Return the number of patterns the
 * client was subscribed from. */
int pubsubUnsubscribeAllPatterns(struct redisServer *srv,client *c, int notify) {
    listNode *ln;
    listIter li;
    int count = 0;
    list* pubsub_patterns;
    if(srv == &crdtServer) {
        pubsub_patterns = c->crdt_pubsub_patterns;
    } else {
        pubsub_patterns = c->pubsub_patterns;
    }
    listRewind(pubsub_patterns,&li);
    while ((ln = listNext(&li)) != NULL) {
        robj *pattern = ln->value;

        count += pubsubUnsubscribePattern(srv, c,pattern,notify);
    }
    if (notify && count == 0) {
        if(srv == &crdtServer) {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.crdtpunsubscribebulk);
            addReply(c,shared.nullbulk);
            addReplyLongLong(c,clientCrdtSubscriptionsCount(c));
        } else {
            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.punsubscribebulk);
            addReply(c,shared.nullbulk);
            addReplyLongLong(c,clientSubscriptionsCount(c));
        }
        /* We were subscribed to nothing? Still reply to the client. */
        
    }
    return count;
}

int pubsubPublishMessage(struct redisServer *srv, robj *channel, robj *message) {
    int receivers = 0;
    dictEntry *de;
    listNode *ln;
    listIter li;

    /* Send to clients listening for that channel */
    de = dictFind(srv->pubsub_channels,channel);
    if (de) {
        list *list = dictGetVal(de);
        listNode *ln;
        listIter li;

        listRewind(list,&li);
        while ((ln = listNext(&li)) != NULL) {
            client *c = ln->value;

            addReply(c,shared.mbulkhdr[3]);
            addReply(c,shared.messagebulk);
            addReplyBulk(c,channel);
            addReplyBulk(c,message);
            receivers++;
        }
    }
    /* Send to clients listening to matching channels */
    if (listLength(srv->pubsub_patterns)) {
        listRewind(srv->pubsub_patterns,&li);
        channel = getDecodedObject(channel);
        while ((ln = listNext(&li)) != NULL) {
            pubsubPattern *pat = ln->value;

            if (stringmatchlen((char*)pat->pattern->ptr,
                                sdslen(pat->pattern->ptr),
                                (char*)channel->ptr,
                                sdslen(channel->ptr),0)) {
                addReply(pat->client,shared.mbulkhdr[4]);
                addReply(pat->client,shared.pmessagebulk);
                addReplyBulk(pat->client,pat->pattern);
                addReplyBulk(pat->client,channel);
                addReplyBulk(pat->client,message);
                receivers++;
            }
        }
        decrRefCount(channel);
    }
    return receivers;
}

/*-----------------------------------------------------------------------------
 * Pubsub commands implementation
 *----------------------------------------------------------------------------*/

void crdtSubscribeCommand(client *c) {
    int j;
    for (j = 1;j < c->argc; j++) 
        pubsubSubscribeChannel(&crdtServer, c, c->argv[j]);
    c->flags |= CLIENT_PUBSUB;
}

void subscribeCommand(client *c) {
    int j;

    for (j = 1; j < c->argc; j++)
        pubsubSubscribeChannel(&server, c,c->argv[j]);
    c->flags |= CLIENT_PUBSUB;
}
void unCrdtSubscribeCommand(client* c) {
    if (c->argc == 1) {
        pubsubUnsubscribeAllChannels(&crdtServer,c,1);
    } else {
        int j;

        for (j = 1; j < c->argc; j++)
            pubsubUnsubscribeChannel(&crdtServer, c,c->argv[j],1);
    }
    if (clientCrdtSubscriptionsCount(c) == 0) c->flags &= ~CLIENT_PUBSUB;
}
void unsubscribeCommand(client *c) {
    if (c->argc == 1) {
        pubsubUnsubscribeAllChannels(&server, c,1);
    } else {
        int j;

        for (j = 1; j < c->argc; j++)
            pubsubUnsubscribeChannel(&server, c,c->argv[j],1);
    }
    if (clientSubscriptionsCount(c) == 0) c->flags &= ~CLIENT_PUBSUB;
}

void crdtPsubscribeCommand(client *c) {
    int j;

    for (j = 1; j < c->argc; j++)
        pubsubSubscribePattern(&crdtServer,c,c->argv[j]);
    c->flags |= CLIENT_PUBSUB;
}

void psubscribeCommand(client *c) {
    int j;

    for (j = 1; j < c->argc; j++)
        pubsubSubscribePattern(&server,c,c->argv[j]);
    c->flags |= CLIENT_PUBSUB;
}

void punsubscribeCommand(client *c) {
    if (c->argc == 1) {
        pubsubUnsubscribeAllPatterns(&server,c,1);
    } else {
        int j;

        for (j = 1; j < c->argc; j++)
            pubsubUnsubscribePattern(&server,c,c->argv[j],1);
    }
    if (clientSubscriptionsCount(c) == 0) c->flags &= ~CLIENT_PUBSUB;
}

void crdtPunsubscribeCommand(client *c) {
    if (c->argc == 1) {
        pubsubUnsubscribeAllPatterns(&crdtServer,c,1);
    } else {
        int j;

        for (j = 1; j < c->argc; j++)
            pubsubUnsubscribePattern(&crdtServer,c,c->argv[j],1);
    }
    if (clientCrdtSubscriptionsCount(c) == 0) c->flags &= ~CLIENT_PUBSUB;
}

void publishCommand(client *c) {
    int receivers = pubsubPublishMessage(&server,c->argv[1], c->argv[2]);
    if(server.cluster_enabled) 
        clusterPropagatePublish(c->argv[1], c->argv[2]);
    else
        forceCommandPropagation(c, PROPAGATE_REPL);
    addReplyLongLong(c, receivers);
}
void pubsub(struct redisServer *srv, client *c) {
    if (!strcasecmp(c->argv[1]->ptr,"channels") &&
        (c->argc == 2 || c->argc ==3))
    {
        /* PUBSUB CHANNELS [<pattern>] */
        sds pat = (c->argc == 2) ? NULL : c->argv[2]->ptr;
        dictIterator *di = dictGetIterator(srv->pubsub_channels);
        dictEntry *de;
        long mblen = 0;
        void *replylen;

        replylen = addDeferredMultiBulkLength(c);
        while((de = dictNext(di)) != NULL) {
            robj *cobj = dictGetKey(de);
            sds channel = cobj->ptr;

            if (!pat || stringmatchlen(pat, sdslen(pat),
                                       channel, sdslen(channel),0))
            {
                addReplyBulk(c,cobj);
                mblen++;
            }
        }
        dictReleaseIterator(di);
        setDeferredMultiBulkLength(c,replylen,mblen);
    } else if (!strcasecmp(c->argv[1]->ptr,"numsub") && c->argc >= 2) {
        /* PUBSUB NUMSUB [Channel_1 ... Channel_N] */
        int j;

        addReplyMultiBulkLen(c,(c->argc-2)*2);
        for (j = 2; j < c->argc; j++) {
            list *l = dictFetchValue(srv->pubsub_channels,c->argv[j]);

            addReplyBulk(c,c->argv[j]);
            addReplyLongLong(c,l ? listLength(l) : 0);
        }
    } else if (!strcasecmp(c->argv[1]->ptr,"numpat") && c->argc == 2) {
        /* PUBSUB NUMPAT */
        addReplyLongLong(c,listLength(srv->pubsub_patterns));
    } else {
        addReplyErrorFormat(c,
            "Unknown PUBSUB subcommand or wrong number of arguments for '%s'",
            (char*)c->argv[1]->ptr);
    }
}
/* PUBSUB command for Pub/Sub introspection. */
void pubsubCommand(client *c) {
    pubsub(&server, c);
}
void crdtPubsubCommand(client *c) {
    pubsub(&crdtServer, c);
}

