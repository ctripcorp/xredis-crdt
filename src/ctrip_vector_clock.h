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

/**
 * To shrink down mem usage, an unsigned long long will stand for [gid, clock]
 * where, higher 4 bits is allocated for gid (16 gid in total)
 * and,   lower 60 bits represents the logical clk
 * */
typedef unsigned long long clk;
#define VectorClockUnit clk
typedef struct VectorClock {
    char length;
    union clocks {
        clk single;
        clk *multi;
    } clocks;
}__attribute__((packed, aligned(1)))VectorClock;

#define APPEND(x, y) x ## y
#define ULL(x) APPEND(x, ull)
//#define null NULL
#define CLOCK_UNIT_MAX 0
#define CLOCK_UNIT_ALIGN 1

#define LOGIC_CLOCK_UNDEFINE ULL(0xFFFFFFFFFFFFFFFF)

#define LOGIC_CLOCK_TEMPLATE 0xFFFFFFFFFFFFFFF
#define LOGIC_CLOCK_BITS 60u
#define get_logic_clock(clock) (clock & ULL(LOGIC_CLOCK_TEMPLATE))
#define get_gid(clock) ((clock >> LOGIC_CLOCK_BITS) & 0xF)
#define init_clock(gid, logic_clk) ((clk)gid << LOGIC_CLOCK_BITS) | (ULL(LOGIC_CLOCK_TEMPLATE) & logic_clk)
#define clock_overlap(gid, logic_clk) (gid > 0xF || (long long)logic_clk > LOGIC_CLOCK_TEMPLATE) ? 1 : 0
#define get_clock_unit_by_index(vclock, index) (index < vclock->length ? (vclock->length == 1 ? &(vclock->clocks.single) : ((unsigned long long *)vclock->clocks.multi + index)) : NULL)
#define set_clock_unit_by_index(vclock, index, clock)  *((unsigned long long *)vclock->clocks.multi + index) = clock

/**------------------------Vector Clock Lifecycle--------------------------------------*/
VectorClock*
mergeMinVectorClock(VectorClock *vclock1, VectorClock *vclock2);

void
cloneVectorClock(VectorClock *dst, VectorClock *src);

VectorClock*
newVectorClock(int numVcUnits);

void
freeVectorClock(VectorClock *vc);

void
freeInnerClocks(VectorClock *vc);

VectorClock*
addVectorClockUnit(VectorClock *vc, int gid, long long logic_time);

VectorClock*
dupVectorClock(VectorClock *vc);

/**------------------------Vector Clock & sds convertion--------------------------------------*/
VectorClock*
sdsToVectorClock(sds vcStr);

sds
vectorClockToSds(VectorClock *vc);

void
sdsCpToVectorClock(sds src, VectorClock *dst);


/**------------------------Vector Clock Util--------------------------------------*/

clk*
getVectorClockUnit(VectorClock *vc, int gid);

void
incrLogicClock(VectorClock *vc, int gid, int delta);

//vector_clock, length, gid, clock, gid, clock, gid, clock
void
init(VectorClock *vc, int num, ...);

void
merge(VectorClock *dst, VectorClock *src);

// for key's vector clock update
void
mergeLogicClock(VectorClock *dst, VectorClock *src, int gid);

VectorClock*
getMonoVectorClock(VectorClock *src, int gid);

void
sortVectorClock(VectorClock *vc);

int
isVectorClockMonoIncr(VectorClock *current, VectorClock *future);

VectorClock*
vectorClockMerge(VectorClock *vclock1, VectorClock *vclock2);

/**------------------------Replication Usage--------------------------------------*/
void
updateProcessVectorClock(VectorClock *dst, VectorClock *src, int gid, int currentGid);

#endif //REDIS_VECTOR_CLOCK_H
