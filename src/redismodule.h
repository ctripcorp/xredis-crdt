#ifndef REDISMODULE_H
#define REDISMODULE_H

#include <sys/types.h>
#include <stdint.h>
#include <stdio.h>

/* ---------------- Defines common between core and modules --------------- */

/* Error status return values. */
#define REDISMODULE_OK 0
#define REDISMODULE_ERR 1

/* API versions. */
#define REDISMODULE_APIVER_1 1



#define REDISMODULE_LIST_HEAD 0
#define REDISMODULE_LIST_TAIL 1

/* Key types. */
#define REDISMODULE_KEYTYPE_EMPTY 0
#define REDISMODULE_KEYTYPE_STRING 1
#define REDISMODULE_KEYTYPE_LIST 2
#define REDISMODULE_KEYTYPE_HASH 3
#define REDISMODULE_KEYTYPE_SET 4
#define REDISMODULE_KEYTYPE_ZSET 5
#define REDISMODULE_KEYTYPE_MODULE 6

/* Reply types. */
#define REDISMODULE_REPLY_UNKNOWN -1
#define REDISMODULE_REPLY_STRING 0
#define REDISMODULE_REPLY_ERROR 1
#define REDISMODULE_REPLY_INTEGER 2
#define REDISMODULE_REPLY_ARRAY 3
#define REDISMODULE_REPLY_NULL 4

/* Postponed array length. */
#define REDISMODULE_POSTPONED_ARRAY_LEN -1

/* Expire */
#define REDISMODULE_NO_EXPIRE -1

/* Sorted set API flags. */
#define REDISMODULE_ZADD_XX      (1<<0)
#define REDISMODULE_ZADD_NX      (1<<1)
#define REDISMODULE_ZADD_ADDED   (1<<2)
#define REDISMODULE_ZADD_UPDATED (1<<3)
#define REDISMODULE_ZADD_NOP     (1<<4)

/* Hash API flags. */
#define REDISMODULE_HASH_NONE       0
#define REDISMODULE_HASH_NX         (1<<0)
#define REDISMODULE_HASH_XX         (1<<1)
#define REDISMODULE_HASH_CFIELDS    (1<<2)
#define REDISMODULE_HASH_EXISTS     (1<<3)

/* Context Flags: Info about the current context returned by RM_GetContextFlags */

/* The command is running in the context of a Lua script */
#define REDISMODULE_CTX_FLAGS_LUA 0x0001
/* The command is running inside a Redis transaction */
#define REDISMODULE_CTX_FLAGS_MULTI 0x0002
/* The instance is a master */
#define REDISMODULE_CTX_FLAGS_MASTER 0x0004
/* The instance is a slave */
#define REDISMODULE_CTX_FLAGS_SLAVE 0x0008
/* The instance is read-only (usually meaning it's a slave as well) */
#define REDISMODULE_CTX_FLAGS_READONLY 0x0010
/* The instance is running in cluster mode */
#define REDISMODULE_CTX_FLAGS_CLUSTER 0x0020
/* The instance has AOF enabled */
#define REDISMODULE_CTX_FLAGS_AOF 0x0040 //
/* The instance has RDB enabled */
#define REDISMODULE_CTX_FLAGS_RDB 0x0080 //
/* The instance has Maxmemory set */
#define REDISMODULE_CTX_FLAGS_MAXMEMORY 0x0100
/* Maxmemory is set and has an eviction policy that may delete keys */
#define REDISMODULE_CTX_FLAGS_EVICT 0x0200


/* A special pointer that we can use between the core and the module to signal
 * field deletion, and that is impossible to be a valid pointer. */
#define REDISMODULE_HASH_DELETE ((RedisModuleString*)(long)1)

/* Error messages. */
#define REDISMODULE_ERRORMSG_WRONGTYPE "WRONGTYPE Operation against a key holding the wrong kind of value"

#define REDISMODULE_POSITIVE_INFINITE (1.0/0.0)
#define REDISMODULE_NEGATIVE_INFINITE (-1.0/0.0)

#define REDISMODULE_NOT_USED(V) ((void) V)

/* Keyspace changes notification classes. Every class is associated with a
 * character for configuration purposes. */
#define REDISMODULE_NOTIFY_KEYSPACE (1<<0)    /* K */
#define REDISMODULE_NOTIFY_KEYEVENT (1<<1)    /* E */
#define REDISMODULE_NOTIFY_GENERIC (1<<2)     /* g */
#define REDISMODULE_NOTIFY_STRING (1<<3)      /* $ */
#define REDISMODULE_NOTIFY_LIST (1<<4)        /* l */
#define REDISMODULE_NOTIFY_SET (1<<5)         /* s */
#define REDISMODULE_NOTIFY_HASH (1<<6)        /* h */
#define REDISMODULE_NOTIFY_ZSET (1<<7)        /* z */
#define REDISMODULE_NOTIFY_EXPIRED (1<<8)     /* x */
#define REDISMODULE_NOTIFY_EVICTED (1<<9)     /* e */
#define REDISMODULE_NOTIFY_STREAM (1<<10)     /* t */
#define REDISMODULE_NOTIFY_ALL (NOTIFY_GENERIC | NOTIFY_STRING | NOTIFY_LIST | NOTIFY_SET | NOTIFY_HASH | NOTIFY_ZSET | NOTIFY_EXPIRED | NOTIFY_EVICTED | NOTIFY_STREAM) /* A flag */


/* ------------------------- End of common defines ------------------------ */

#ifndef REDISMODULE_CORE

typedef long long mstime_t;

/* Incomplete structures for compiler checks but opaque access. */
typedef struct RedisModuleCtx RedisModuleCtx;
typedef struct RedisModuleKey RedisModuleKey;
typedef struct RedisModuleString RedisModuleString;
typedef struct RedisModuleCallReply RedisModuleCallReply;
typedef struct RedisModuleIO RedisModuleIO;
typedef struct RedisModuleType RedisModuleType;
typedef struct RedisModuleDigest RedisModuleDigest;
typedef struct RedisModuleBlockedClient RedisModuleBlockedClient;

typedef int (*RedisModuleCmdFunc) (RedisModuleCtx *ctx, RedisModuleString **argv, int argc);

typedef void *(*RedisModuleTypeLoadFunc)(RedisModuleIO *rdb, int encver);
typedef void (*RedisModuleTypeSaveFunc)(RedisModuleIO *rdb, void *value);
typedef void (*RedisModuleTypeRewriteFunc)(RedisModuleIO *aof, RedisModuleString *key, void *value);
typedef size_t (*RedisModuleTypeMemUsageFunc)(const void *value);
typedef void (*RedisModuleTypeDigestFunc)(RedisModuleDigest *digest, void *value);
typedef void (*RedisModuleTypeFreeFunc)(void *value);

#define REDISMODULE_TYPE_METHOD_VERSION 1
typedef struct RedisModuleTypeMethods {
    uint64_t version;
    RedisModuleTypeLoadFunc rdb_load;
    RedisModuleTypeSaveFunc rdb_save;
    RedisModuleTypeRewriteFunc aof_rewrite;
    RedisModuleTypeMemUsageFunc mem_usage;
    RedisModuleTypeDigestFunc digest;
    RedisModuleTypeFreeFunc free;
} RedisModuleTypeMethods;

#define REDISMODULE_GET_API(name) \
    RedisModule_GetApi("RedisModule_" #name, ((void **)&RedisModule_ ## name))

#define REDISMODULE_API_FUNC(x) (*x)


void *REDISMODULE_API_FUNC(RedisModule_Alloc)(size_t bytes);
void *REDISMODULE_API_FUNC(RedisModule_Realloc)(void *ptr, size_t bytes);
void REDISMODULE_API_FUNC(RedisModule_Free)(void *ptr);
void REDISMODULE_API_FUNC(RedisModule_ZFree)(void *ptr);
void *REDISMODULE_API_FUNC(RedisModule_Calloc)(size_t nmemb, size_t size);
char *REDISMODULE_API_FUNC(RedisModule_Strdup)(const char *str);
int REDISMODULE_API_FUNC(RedisModule_GetApi)(const char *, void *);
int REDISMODULE_API_FUNC(RedisModule_CreateCommand)(RedisModuleCtx *ctx, const char *name, RedisModuleCmdFunc cmdfunc, const char *strflags, int firstkey, int lastkey, int keystep);
void REDISMODULE_API_FUNC(RedisModule_SetModuleAttribs)(RedisModuleCtx *ctx, const char *name, int ver, int apiver);
void REDISMODULE_API_FUNC(RedisModule_SetOvc)(RedisModuleCtx *ctx, long long vc);
long long REDISMODULE_API_FUNC(RedisModule_GetOvc)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_IsModuleNameBusy)(const char *name);
int REDISMODULE_API_FUNC(RedisModule_WrongArity)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithLongLong)(RedisModuleCtx *ctx, long long ll);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithLongDouble)(RedisModuleCtx *ctx, long double ld);
int REDISMODULE_API_FUNC(RedisModule_GetSelectedDb)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_SelectDb)(RedisModuleCtx *ctx, int newid);
int REDISMODULE_API_FUNC(RedisModule_CrdtSelectDb)(RedisModuleCtx *ctx, int gid,int newid);
void *REDISMODULE_API_FUNC(RedisModule_OpenKey)(RedisModuleCtx *ctx, RedisModuleString *keyname, int mode);
void *REDISMODULE_API_FUNC(RedisModule_DbGetValue)(RedisModuleCtx *ctx, RedisModuleString *keyname, RedisModuleType* type,int* error);
void *REDISMODULE_API_FUNC(RedisModule_DbDelete)(RedisModuleCtx *ctx, void* keyname);
void *REDISMODULE_API_FUNC(RedisModule_DbEntryGetVal)(RedisModuleCtx *ctx, void* de);
void *REDISMODULE_API_FUNC(RedisModule_DbEntrySetVal)(RedisModuleCtx *ctx, RedisModuleString* keyname, void* de, RedisModuleType* type, void* val);
void *REDISMODULE_API_FUNC(RedisModule_DbAddOrFind)(RedisModuleCtx *ctx, RedisModuleString *keyname, RedisModuleType* type);
int REDISMODULE_API_FUNC(RedisModule_DbSetValue)(RedisModuleCtx *ctx, RedisModuleString *keyname, RedisModuleType* type,void* val);
void *REDISMODULE_API_FUNC(RedisModule_GetKey)(void *db, RedisModuleString *keyname, int mode);
uint64_t REDISMODULE_API_FUNC(RedisModule_GetModuleTypeId)(RedisModuleType* moduletype);
int REDISMODULE_API_FUNC(RedisModule_SaveModuleValue)(void* rdb, RedisModuleType* moduletype, void* data);
int REDISMODULE_API_FUNC(RedisModule_SaveLen)(void* rdb, uint64_t value);
uint64_t REDISMODULE_API_FUNC(RedisModule_LoadLen)(void* rdb);
void* REDISMODULE_API_FUNC(RedisModule_LoadModuleValue)(RedisModuleType* type, void* rdb);
RedisModuleType* REDISMODULE_API_FUNC(RedisModule_GetModuleTypeById)(uint64_t id);
void REDISMODULE_API_FUNC(RedisModule_CloseKey)(RedisModuleKey *kp);
int REDISMODULE_API_FUNC(RedisModule_KeyType)(RedisModuleKey *kp);
size_t REDISMODULE_API_FUNC(RedisModule_ValueLength)(RedisModuleKey *kp);
int REDISMODULE_API_FUNC(RedisModule_ListPush)(RedisModuleKey *kp, int where, RedisModuleString *ele);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_ListPop)(RedisModuleKey *key, int where);
RedisModuleCallReply *REDISMODULE_API_FUNC(RedisModule_Call)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
const char *REDISMODULE_API_FUNC(RedisModule_CallReplyProto)(RedisModuleCallReply *reply, size_t *len);
void REDISMODULE_API_FUNC(RedisModule_FreeCallReply)(RedisModuleCallReply *reply);
int REDISMODULE_API_FUNC(RedisModule_CallReplyType)(RedisModuleCallReply *reply);
long long REDISMODULE_API_FUNC(RedisModule_CallReplyInteger)(RedisModuleCallReply *reply);
size_t REDISMODULE_API_FUNC(RedisModule_CallReplyLength)(RedisModuleCallReply *reply);
RedisModuleCallReply *REDISMODULE_API_FUNC(RedisModule_CallReplyArrayElement)(RedisModuleCallReply *reply, size_t idx);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_CreateString)(RedisModuleCtx *ctx, const char *ptr, size_t len);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_CreateStringFromLongLong)(RedisModuleCtx *ctx, long long ll);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_CreateStringFromString)(RedisModuleCtx *ctx, const RedisModuleString *str);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_CreateStringPrintf)(RedisModuleCtx *ctx, const char *fmt, ...);
void REDISMODULE_API_FUNC(RedisModule_FreeString)(RedisModuleCtx *ctx, RedisModuleString *str);
const char *REDISMODULE_API_FUNC(RedisModule_StringPtrLen)(const RedisModuleString *str, size_t *len);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithError)(RedisModuleCtx *ctx, const char *err);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithSimpleString)(RedisModuleCtx *ctx, const char *msg);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithArray)(RedisModuleCtx *ctx, long len);
void REDISMODULE_API_FUNC(RedisModule_ReplySetArrayLength)(RedisModuleCtx *ctx, long len);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithStringBuffer)(RedisModuleCtx *ctx, const char *buf, size_t len);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithString)(RedisModuleCtx *ctx, RedisModuleString *str);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithNull)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithOk)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithDouble)(RedisModuleCtx *ctx, double d);
int REDISMODULE_API_FUNC(RedisModule_ReplyWithCallReply)(RedisModuleCtx *ctx, RedisModuleCallReply *reply);
int REDISMODULE_API_FUNC(RedisModule_StringToLongLong)(const RedisModuleString *str, long long *ll);
int REDISMODULE_API_FUNC(RedisModule_StringToDouble)(const RedisModuleString *str, double *d);
int REDISMODULE_API_FUNC(RedisModule_StringToLongDouble)(const RedisModuleString *str, long double *d);
void *REDISMODULE_API_FUNC(RedisModule_GetSds)(const RedisModuleString *str);
void REDISMODULE_API_FUNC(RedisModule_AutoMemory)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_Replicate)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_ReplicateVerbatim)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_CrdtReplicateVerbatim)(int gid, RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_ReplicateStraightForward)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_CrdtReplicate)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_CrdtReplicateAlsoNormReplicate)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_ReplicationFeedAllSlaves)(int dbId, const char *cmdname, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_ReplicationFeedStringToAllSlaves)(int dbId, void* cmd, size_t cmdlen);
int REDISMODULE_API_FUNC(RedisModule_ReplicationFeedRobjToAllSlaves)(int dbId, RedisModuleString* cmd);
int REDISMODULE_API_FUNC(RedisModule_IncrCrdtConflict)(int type);
int REDISMODULE_API_FUNC(RedisModule_CrdtMultiWrappedReplicate)(RedisModuleCtx *ctx, const char *cmdname, const char *fmt, ...);
const char *REDISMODULE_API_FUNC(RedisModule_CallReplyStringPtr)(RedisModuleCallReply *reply, size_t *len);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_CreateStringFromCallReply)(RedisModuleCallReply *reply);
int REDISMODULE_API_FUNC(RedisModule_DeleteKey)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_DeleteTombstone)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_UnlinkKey)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_StringSet)(RedisModuleKey *key, RedisModuleString *str);
char *REDISMODULE_API_FUNC(RedisModule_StringDMA)(RedisModuleKey *key, size_t *len, int mode);
int REDISMODULE_API_FUNC(RedisModule_StringTruncate)(RedisModuleKey *key, size_t newlen);
mstime_t REDISMODULE_API_FUNC(RedisModule_GetExpire)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_SetExpire)(RedisModuleKey *key, mstime_t expire);
void REDISMODULE_API_FUNC(RedisModule_SaveRobj)(void* rdb, void* value);
void REDISMODULE_API_FUNC(RedisModule_SaveInt)(void* rdb, int value);
int REDISMODULE_API_FUNC(RedisModule_ZsetAdd)(RedisModuleKey *key, double score, RedisModuleString *ele, int *flagsptr);
int REDISMODULE_API_FUNC(RedisModule_ZsetIncrby)(RedisModuleKey *key, double score, RedisModuleString *ele, int *flagsptr, double *newscore);
int REDISMODULE_API_FUNC(RedisModule_ZsetScore)(RedisModuleKey *key, RedisModuleString *ele, double *score);
int REDISMODULE_API_FUNC(RedisModule_ZsetRem)(RedisModuleKey *key, RedisModuleString *ele, int *deleted);
void REDISMODULE_API_FUNC(RedisModule_ZsetRangeStop)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_ZsetFirstInScoreRange)(RedisModuleKey *key, double min, double max, int minex, int maxex);
int REDISMODULE_API_FUNC(RedisModule_ZsetLastInScoreRange)(RedisModuleKey *key, double min, double max, int minex, int maxex);
int REDISMODULE_API_FUNC(RedisModule_ZsetFirstInLexRange)(RedisModuleKey *key, RedisModuleString *min, RedisModuleString *max);
int REDISMODULE_API_FUNC(RedisModule_ZsetLastInLexRange)(RedisModuleKey *key, RedisModuleString *min, RedisModuleString *max);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_ZsetRangeCurrentElement)(RedisModuleKey *key, double *score);
int REDISMODULE_API_FUNC(RedisModule_ZsetRangeNext)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_ZsetRangePrev)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_ZsetRangeEndReached)(RedisModuleKey *key);
int REDISMODULE_API_FUNC(RedisModule_HashSet)(RedisModuleKey *key, int flags, ...);
int REDISMODULE_API_FUNC(RedisModule_HashGet)(RedisModuleKey *key, int flags, ...);
int REDISMODULE_API_FUNC(RedisModule_IsKeysPositionRequest)(RedisModuleCtx *ctx);
void REDISMODULE_API_FUNC(RedisModule_KeyAtPos)(RedisModuleCtx *ctx, int pos);
unsigned long long REDISMODULE_API_FUNC(RedisModule_GetClientId)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_GetContextFlags)(RedisModuleCtx *ctx);
void *REDISMODULE_API_FUNC(RedisModule_PoolAlloc)(RedisModuleCtx *ctx, size_t bytes);
RedisModuleType *REDISMODULE_API_FUNC(RedisModule_CreateDataType)(RedisModuleCtx *ctx, const char *name, int encver, RedisModuleTypeMethods *typemethods);
int REDISMODULE_API_FUNC(RedisModule_ModuleTypeSetValue)(RedisModuleKey *key, RedisModuleType *mt, void *value);
int REDISMODULE_API_FUNC(RedisModule_ModuleTypeLoadRdbAddValue)(RedisModuleKey *key, RedisModuleType *mt, void *value);
RedisModuleType *REDISMODULE_API_FUNC(RedisModule_ModuleTypeGetType)(RedisModuleKey *key);
void *REDISMODULE_API_FUNC(RedisModule_ModuleTypeGetValue)(RedisModuleKey *key);
void REDISMODULE_API_FUNC(RedisModule_SaveUnsigned)(RedisModuleIO *io, uint64_t value);
uint64_t REDISMODULE_API_FUNC(RedisModule_LoadUnsigned)(RedisModuleIO *io);
void REDISMODULE_API_FUNC(RedisModule_SaveSigned)(RedisModuleIO *io, int64_t value);
int64_t REDISMODULE_API_FUNC(RedisModule_LoadSigned)(RedisModuleIO *io);
void REDISMODULE_API_FUNC(RedisModule_EmitAOF)(RedisModuleIO *io, const char *cmdname, const char *fmt, ...);
void REDISMODULE_API_FUNC(RedisModule_SaveString)(RedisModuleIO *io, RedisModuleString *s);
void REDISMODULE_API_FUNC(RedisModule_SaveStringBuffer)(RedisModuleIO *io, const char *str, size_t len);
RedisModuleString *REDISMODULE_API_FUNC(RedisModule_LoadString)(RedisModuleIO *io);
char *REDISMODULE_API_FUNC(RedisModule_LoadStringBuffer)(RedisModuleIO *io, size_t *lenptr);
void *REDISMODULE_API_FUNC(RedisModule_LoadSds)(RedisModuleIO *io, size_t *lenptr);
void REDISMODULE_API_FUNC(RedisModule_SaveDouble)(RedisModuleIO *io, double value);
double REDISMODULE_API_FUNC(RedisModule_LoadDouble)(RedisModuleIO *io);
void REDISMODULE_API_FUNC(RedisModule_SaveFloat)(RedisModuleIO *io, float value);
float REDISMODULE_API_FUNC(RedisModule_LoadFloat)(RedisModuleIO *io);
void REDISMODULE_API_FUNC(RedisModule_Log)(RedisModuleCtx *ctx, const char *level, const char *fmt, ...);
void REDISMODULE_API_FUNC(RedisModule_Debug)( const char *level, const char *fmt, ...);
size_t REDISMODULE_API_FUNC(RedisModule_ModuleMemory)();
size_t REDISMODULE_API_FUNC(RedisModule_UsedMemory)();
size_t REDISMODULE_API_FUNC(RedisModule_GetModuleValueMemorySize)(void* ptr);
size_t REDISMODULE_API_FUNC(RedisModule_ModuleAllKeySize)();
size_t REDISMODULE_API_FUNC(RedisModule_ModuleAllKeyMemory)();
void REDISMODULE_API_FUNC(RedisModule_LogIOError)(RedisModuleIO *io, const char *levelstr, const char *fmt, ...);
int REDISMODULE_API_FUNC(RedisModule_StringAppendBuffer)(RedisModuleCtx *ctx, RedisModuleString *str, const char *buf, size_t len);
void REDISMODULE_API_FUNC(RedisModule_RetainString)(RedisModuleCtx *ctx, RedisModuleString *str);
int REDISMODULE_API_FUNC(RedisModule_StringCompare)(RedisModuleString *a, RedisModuleString *b);
RedisModuleCtx *REDISMODULE_API_FUNC(RedisModule_GetContextFromIO)(RedisModuleIO *io);
long long REDISMODULE_API_FUNC(RedisModule_Milliseconds)(void);
void REDISMODULE_API_FUNC(RedisModule_DigestAddStringBuffer)(RedisModuleDigest *md, unsigned char *ele, size_t len);
void REDISMODULE_API_FUNC(RedisModule_DigestAddLongLong)(RedisModuleDigest *md, long long ele);
void REDISMODULE_API_FUNC(RedisModule_DigestEndSequence)(RedisModuleDigest *md);
/* Experimental APIs */
long long REDISMODULE_API_FUNC(RedisModule_CurrentVectorClock)(void);
long long REDISMODULE_API_FUNC(RedisModule_CurrentGid)(void);
int REDISMODULE_API_FUNC(RedisModule_CheckGid)(int gid);
void REDISMODULE_API_FUNC(RedisModule_IncrLocalVectorClock) (long long delta);
void REDISMODULE_API_FUNC(RedisModule_MergeVectorClock) (int gid, long long vclock);
int REDISMODULE_API_FUNC(RedisModule_ModuleTombstoneSetValue) (RedisModuleKey *key, RedisModuleType *mt, void *value);
int REDISMODULE_API_FUNC(RedisModule_ModuleTombstoneLoadRdbAddValue) (RedisModuleKey *key, RedisModuleType *mt, void *value);
void *REDISMODULE_API_FUNC(RedisModule_ModuleTypeGetTombstone)(RedisModuleKey *key);
void REDISMODULE_API_FUNC(RedisModule_NotifyKeyspaceEvent)(RedisModuleCtx *ctx,int type, char *event, RedisModuleString *key);
int REDISMODULE_API_FUNC(RedisModule_CrdtPubsubPublishMessage)(RedisModuleString *channel, RedisModuleString *message);

/* Experimental APIs */
#ifdef REDISMODULE_EXPERIMENTAL_API
RedisModuleBlockedClient *REDISMODULE_API_FUNC(RedisModule_BlockClient)(RedisModuleCtx *ctx, RedisModuleCmdFunc reply_callback, RedisModuleCmdFunc timeout_callback, void (*free_privdata)(void*), long long timeout_ms);
int REDISMODULE_API_FUNC(RedisModule_UnblockClient)(RedisModuleBlockedClient *bc, void *privdata);
int REDISMODULE_API_FUNC(RedisModule_IsBlockedReplyRequest)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_IsBlockedTimeoutRequest)(RedisModuleCtx *ctx);
void *REDISMODULE_API_FUNC(RedisModule_GetBlockedClientPrivateData)(RedisModuleCtx *ctx);
int REDISMODULE_API_FUNC(RedisModule_AbortBlock)(RedisModuleBlockedClient *bc);
RedisModuleCtx *REDISMODULE_API_FUNC(RedisModule_GetThreadSafeContext)(RedisModuleBlockedClient *bc);
void REDISMODULE_API_FUNC(RedisModule_FreeThreadSafeContext)(RedisModuleCtx *ctx);
void REDISMODULE_API_FUNC(RedisModule_ThreadSafeContextLock)(RedisModuleCtx *ctx);
void REDISMODULE_API_FUNC(RedisModule_ThreadSafeContextUnlock)(RedisModuleCtx *ctx);
#endif

/* This is included inline inside each Redis module. */
static int RedisModule_Init(RedisModuleCtx *ctx, const char *name, int ver, int apiver) __attribute__((unused));
static int RedisModule_Init(RedisModuleCtx *ctx, const char *name, int ver, int apiver) {
    void *getapifuncptr = ((void**)ctx)[0];
    RedisModule_GetApi = (int (*)(const char *, void *)) (unsigned long)getapifuncptr;
    REDISMODULE_GET_API(Alloc);
    REDISMODULE_GET_API(ModuleMemory);
    REDISMODULE_GET_API(UsedMemory);
    REDISMODULE_GET_API(GetModuleValueMemorySize);
    REDISMODULE_GET_API(ModuleAllKeySize);
    REDISMODULE_GET_API(ModuleAllKeyMemory);
    REDISMODULE_GET_API(Calloc);
    REDISMODULE_GET_API(Free);
    REDISMODULE_GET_API(ZFree);
    REDISMODULE_GET_API(Realloc);
    REDISMODULE_GET_API(Strdup);
    REDISMODULE_GET_API(CreateCommand);
    REDISMODULE_GET_API(SetModuleAttribs);
    REDISMODULE_GET_API(SetOvc);
    REDISMODULE_GET_API(GetOvc);
    REDISMODULE_GET_API(IsModuleNameBusy);
    REDISMODULE_GET_API(WrongArity);
    REDISMODULE_GET_API(ReplyWithLongLong);
    REDISMODULE_GET_API(ReplyWithLongDouble);
    REDISMODULE_GET_API(ReplyWithError);
    REDISMODULE_GET_API(ReplyWithSimpleString);
    REDISMODULE_GET_API(ReplyWithArray);
    REDISMODULE_GET_API(ReplySetArrayLength);
    REDISMODULE_GET_API(ReplyWithStringBuffer);
    REDISMODULE_GET_API(ReplyWithString);
    REDISMODULE_GET_API(ReplyWithNull);
    REDISMODULE_GET_API(ReplyWithOk);
    REDISMODULE_GET_API(ReplyWithCallReply);
    REDISMODULE_GET_API(ReplyWithDouble);
    REDISMODULE_GET_API(ReplySetArrayLength);
    REDISMODULE_GET_API(GetSelectedDb);
    REDISMODULE_GET_API(SelectDb);
    REDISMODULE_GET_API(CrdtSelectDb);
    REDISMODULE_GET_API(OpenKey);
    REDISMODULE_GET_API(DbAddOrFind);
    REDISMODULE_GET_API(DbDelete);
    REDISMODULE_GET_API(DbEntryGetVal);
    REDISMODULE_GET_API(DbEntrySetVal);
    REDISMODULE_GET_API(DbGetValue);
    REDISMODULE_GET_API(DbSetValue);
    REDISMODULE_GET_API(SaveModuleValue);
    REDISMODULE_GET_API(GetModuleTypeId);
    REDISMODULE_GET_API(LoadLen);
    REDISMODULE_GET_API(SaveLen);
    REDISMODULE_GET_API(LoadModuleValue);
    REDISMODULE_GET_API(GetModuleTypeById);
    REDISMODULE_GET_API(GetKey);
    REDISMODULE_GET_API(CloseKey);
    REDISMODULE_GET_API(KeyType);
    REDISMODULE_GET_API(ValueLength);
    REDISMODULE_GET_API(ListPush);
    REDISMODULE_GET_API(ListPop);
    REDISMODULE_GET_API(StringToLongLong);
    REDISMODULE_GET_API(StringToDouble);
    REDISMODULE_GET_API(StringToLongDouble);
    REDISMODULE_GET_API(GetSds);
    REDISMODULE_GET_API(Call);
    REDISMODULE_GET_API(CallReplyProto);
    REDISMODULE_GET_API(FreeCallReply);
    REDISMODULE_GET_API(CallReplyInteger);
    REDISMODULE_GET_API(CallReplyType);
    REDISMODULE_GET_API(CallReplyLength);
    REDISMODULE_GET_API(CallReplyArrayElement);
    REDISMODULE_GET_API(CallReplyStringPtr);
    REDISMODULE_GET_API(CreateStringFromCallReply);
    REDISMODULE_GET_API(CreateString);
    REDISMODULE_GET_API(CreateStringFromLongLong);
    REDISMODULE_GET_API(CreateStringFromString);
    REDISMODULE_GET_API(CreateStringPrintf);
    REDISMODULE_GET_API(FreeString);
    REDISMODULE_GET_API(StringPtrLen);
    REDISMODULE_GET_API(AutoMemory);
    REDISMODULE_GET_API(Replicate);
    REDISMODULE_GET_API(ReplicateVerbatim);
    REDISMODULE_GET_API(CrdtReplicateVerbatim);
    REDISMODULE_GET_API(ReplicateStraightForward);
    REDISMODULE_GET_API(CrdtReplicate);
    REDISMODULE_GET_API(CrdtReplicateAlsoNormReplicate);
    REDISMODULE_GET_API(ReplicationFeedAllSlaves);
    REDISMODULE_GET_API(ReplicationFeedStringToAllSlaves);
    REDISMODULE_GET_API(ReplicationFeedRobjToAllSlaves);
    REDISMODULE_GET_API(IncrCrdtConflict);
    REDISMODULE_GET_API(CrdtMultiWrappedReplicate);
    REDISMODULE_GET_API(DeleteKey);
    REDISMODULE_GET_API(DeleteTombstone);
    REDISMODULE_GET_API(UnlinkKey);
    REDISMODULE_GET_API(StringSet);
    REDISMODULE_GET_API(StringDMA);
    REDISMODULE_GET_API(StringTruncate);
    REDISMODULE_GET_API(GetExpire);
    REDISMODULE_GET_API(SetExpire);
    REDISMODULE_GET_API(SaveRobj);
    REDISMODULE_GET_API(SaveInt);
    REDISMODULE_GET_API(SetExpire);
    REDISMODULE_GET_API(ZsetAdd);
    REDISMODULE_GET_API(ZsetIncrby);
    REDISMODULE_GET_API(ZsetScore);
    REDISMODULE_GET_API(ZsetRem);
    REDISMODULE_GET_API(ZsetRangeStop);
    REDISMODULE_GET_API(ZsetFirstInScoreRange);
    REDISMODULE_GET_API(ZsetLastInScoreRange);
    REDISMODULE_GET_API(ZsetFirstInLexRange);
    REDISMODULE_GET_API(ZsetLastInLexRange);
    REDISMODULE_GET_API(ZsetRangeCurrentElement);
    REDISMODULE_GET_API(ZsetRangeNext);
    REDISMODULE_GET_API(ZsetRangePrev);
    REDISMODULE_GET_API(ZsetRangeEndReached);
    REDISMODULE_GET_API(HashSet);
    REDISMODULE_GET_API(HashGet);
    REDISMODULE_GET_API(IsKeysPositionRequest);
    REDISMODULE_GET_API(KeyAtPos);
    REDISMODULE_GET_API(GetClientId);
    REDISMODULE_GET_API(GetContextFlags);
    REDISMODULE_GET_API(PoolAlloc);
    REDISMODULE_GET_API(CreateDataType);
    REDISMODULE_GET_API(ModuleTypeSetValue);
    REDISMODULE_GET_API(ModuleTypeLoadRdbAddValue);
    REDISMODULE_GET_API(ModuleTypeGetType);
    REDISMODULE_GET_API(ModuleTypeGetValue);
    REDISMODULE_GET_API(SaveUnsigned);
    REDISMODULE_GET_API(LoadUnsigned);
    REDISMODULE_GET_API(SaveSigned);
    REDISMODULE_GET_API(LoadSigned);
    REDISMODULE_GET_API(SaveString);
    REDISMODULE_GET_API(SaveStringBuffer);
    REDISMODULE_GET_API(LoadString);
    REDISMODULE_GET_API(LoadSds);
    REDISMODULE_GET_API(LoadStringBuffer);
    REDISMODULE_GET_API(SaveDouble);
    REDISMODULE_GET_API(LoadDouble);
    REDISMODULE_GET_API(SaveFloat);
    REDISMODULE_GET_API(LoadFloat);
    REDISMODULE_GET_API(EmitAOF);
    REDISMODULE_GET_API(Log);
    REDISMODULE_GET_API(Debug);
    REDISMODULE_GET_API(LogIOError);
    REDISMODULE_GET_API(StringAppendBuffer);
    REDISMODULE_GET_API(RetainString);
    REDISMODULE_GET_API(StringCompare);
    REDISMODULE_GET_API(GetContextFromIO);
    REDISMODULE_GET_API(Milliseconds);
    REDISMODULE_GET_API(DigestAddStringBuffer);
    REDISMODULE_GET_API(DigestAddLongLong);
    REDISMODULE_GET_API(DigestEndSequence);
    REDISMODULE_GET_API(CurrentVectorClock);
    REDISMODULE_GET_API(CurrentGid);
    REDISMODULE_GET_API(CheckGid);
    REDISMODULE_GET_API(IncrLocalVectorClock);
    REDISMODULE_GET_API(MergeVectorClock);
    REDISMODULE_GET_API(ModuleTombstoneSetValue);
    REDISMODULE_GET_API(ModuleTombstoneLoadRdbAddValue);
    REDISMODULE_GET_API(ModuleTypeGetTombstone);
    REDISMODULE_GET_API(NotifyKeyspaceEvent);
    REDISMODULE_GET_API(CrdtPubsubPublishMessage);

#ifdef REDISMODULE_EXPERIMENTAL_API
    REDISMODULE_GET_API(GetThreadSafeContext);
    REDISMODULE_GET_API(FreeThreadSafeContext);
    REDISMODULE_GET_API(ThreadSafeContextLock);
    REDISMODULE_GET_API(ThreadSafeContextUnlock);
    REDISMODULE_GET_API(BlockClient);
    REDISMODULE_GET_API(UnblockClient);
    REDISMODULE_GET_API(IsBlockedReplyRequest);
    REDISMODULE_GET_API(IsBlockedTimeoutRequest);
    REDISMODULE_GET_API(GetBlockedClientPrivateData);
    REDISMODULE_GET_API(AbortBlock);
#endif

    if (RedisModule_IsModuleNameBusy && RedisModule_IsModuleNameBusy(name)) return REDISMODULE_ERR;
    RedisModule_SetModuleAttribs(ctx,name,ver,apiver);
    return REDISMODULE_OK;
}

#else

/* Things only defined for the modules core, not exported to modules
 * including this file. */
#define RedisModuleString robj

#endif /* REDISMODULE_CORE */
#endif /* REDISMOUDLE_H */
