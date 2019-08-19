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
// Created by zhuchen on 2019-05-10.
//

#ifndef REDIS_VECTOR_CLOCK_H
#define REDIS_VECTOR_CLOCK_H

#include "sds.h"

// "<gid>:<clock>;<gid>:<clock>"
#define VECTOR_CLOCK_SEPARATOR ";"
#define VECTOR_CLOCK_UNIT_SEPARATOR ":"

#define min(x, y) x > y ? y : x

#define max(x, y) x > y ? x : y

typedef struct VectorClockUnit {
    long long gid;
    long long logic_time;
}__attribute__((packed, aligned(4))) VectorClockUnit;

typedef struct VectorClock {
    VectorClockUnit *clocks;
    int length;
}__attribute__((packed, aligned(4)))VectorClock;

/**------------------------Vector Clock Lifecycle--------------------------------------*/
VectorClock*
newVectorClock(int numVcUnits);

void
freeVectorClock(VectorClock *vc);

VectorClock*
addVectorClockUnit(VectorClock *vc, long long gid, long long logic_time);

VectorClock*
dupVectorClock(VectorClock *vc);

/**------------------------Vector Clock & sds convertion--------------------------------------*/
VectorClock*
sdsToVectorClock(sds vcStr);

sds
vectorClockToSds(VectorClock *vc);

/**------------------------Vector Clock Util--------------------------------------*/
void
sortVectorClock(VectorClock *vc);

VectorClock*
vectorClockMerge(VectorClock *vc1, VectorClock *vc2);

VectorClock*
vectorClockMergeMin(VectorClock *vc1, VectorClock *vc2);

VectorClockUnit*
getVectorClockUnit(VectorClock *vc, long long gid);

int
isVectorClockMonoIncr(VectorClock *current, VectorClock *future);

void
mergeVectorClockUnit(VectorClock *vc, VectorClockUnit *vcu);

#endif //REDIS_VECTOR_CLOCK_H
