/*
 * ctrip.h
 *
 *  Created on: Sep 21, 2017
 *      Author: mengwenchao
 */

#ifndef SRC_CTRIP_H_
#define SRC_CTRIP_H_

#define XREDIS_CRDT_VERSION "1.0.18"
#define CONFIG_DEFAULT_SLAVE_REPLICATE_ALL 0

void xslaveofCommand(client *c);
void refullsyncCommand(client *c);
int rdbLoadCrdtInfoAuxFields(robj* auxkey, robj* auxval, CRDT_Master_Instance** currentMasterInstance, int* needIfRewriteConfig, sds* error);
int iAmMaster();
int iAmReStart();

/* CRDT Replications */
void crdtReplicationCron(void);
void crdtMergeCommand(client *c);
void crdtMergeDelCommand(client *c);
void crdtMergeStartCommand(client *c);
void crdtMergeEndCommand(client *c);
void peerofCommand(client *c);
int peerBackStream();
void cleanSlavePeerBackStream();
int lazyPeerof();
void peerChangeCommand(client *c);
void crdtReplicationSetMaster(int gid, char *ip, int port);
void crdtReplicationCacheMaster(client *c);
void crdtReplicationHandleMasterDisconnection(client *c);
void incrLocalVcUnit(long long delta);
void crdtPsyncCommand(client *c);
CRDT_Master_Instance *getPeerMaster(int gid);
void refreshVectorClock(client *c, sds vcStr);
long long getMyGidLogicTime(VectorClock vc);
long long getMyLogicTime();
void crdtReplicationUnsetMaster(int gid);
void crdtReplicationCloseAllMasters();
void debugCancelCrdt(client *c);
void crdtRoleCommand(client *c);
CRDT_Master_Instance *createPeerMaster(client *c, int gid);
void crdtOvcCommand(client *c);
void crdtAuthGidCommand(client *c);

void sendSelectCommandToSlave(int dictid);
void crdtAuthCommand(client *c);
void crdtReplicationCommand(client *c);
void setOfflinePeerSet(int gids);
void setOfflineGidCommand(client *c);
void getOfflineGidCommand(client *c);
void freeClientArgv(client* c);
void feedCrdtBacklog(robj **argv, int argc);
void replicationFeedAllSlaves(int dictid, robj **argv, int argc);
void replicationFeedStringToAllSlaves(int dictid, void* cmdbuf, size_t cmdlen);
void replicationFeedRobjToAllSlaves(int dictid, robj* cmd);
void crdtCancelReplicationHandshake(int gid);
void evictionTombstoneCommand(client *c);
void initVectorClockCache();
/* CRDT Command */
void crdtDelCommand(client *c);
struct CrdtObject *retrieveCrdtObject(robj *obj);
int isModuleCrdt(robj *obj);
moduleType* getModuleType(robj *obj);
long long getQps();
#endif /* SRC_CTRIP_H_ */
