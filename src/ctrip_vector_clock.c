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

#include "ctrip_vector_clock.h"
#include "sds.h"
#include "util.h"
#include "zmalloc.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/**------------------------Vector Clock Inner Functions--------------------------------------*/

static inline clk *get_clock_unit(VectorClock *vc, char gid) {
    for (char i = 0; i < get_len(vc); i++) {
        clk *clock = (clk *)(get_clock_unit_by_index(vc, i));
        if ((char) get_gid(*clock) == gid) {
            return clock;
        }
    }
    return NULL;
}

void cloneVectorClock(VectorClock *dst, VectorClock *src) {
    char src_length = get_len(src);
    if(src_length == 1) {
        *dst = *src;
    } else {
        set_len(dst, src_length);
        clk *clocks = zmalloc( ((int) get_len(src)) * sizeof(clk));
        memcpy(clocks, clocks_address(*src), ((int) get_len(src)) * sizeof(clk));
    }
}


/**------------------------Vector Clock Lifecycle--------------------------------------*/


VectorClock*
newVectorClock(int numVcUnits) {
    VectorClock *result = zmalloc(sizeof(VectorClock));
    if(numVcUnits > 1) {
        *result = (VectorClock) zmalloc(sizeof(clk) * numVcUnits);
    }
    set_len(result, (char)numVcUnits);
    return result;
}

void
freeVectorClock(VectorClock *vc) {
    if (vc == NULL) {
        return;
    }
    if(get_len(vc) > 1) {
        zfree(clocks_address(*vc));
    }
    zfree(vc);
}

VectorClock*
addVectorClockUnit(VectorClock *vc, int gid, long long logic_time) {
    clk *dst_clock = get_clock_unit(vc, (char) gid);
    clk wanted = init_clock((clk)gid, (clk)logic_time);
    if(dst_clock != NULL) {
        if(get_len(vc) == 1) {
            set_len(vc, 1);
            set_clock_unit_only(vc, wanted);
        } else {
            set_clock_unit_only(dst_clock, wanted);
        }
        return vc;
    }
    VectorClock *target = newVectorClock(get_len(vc) + 1);
    char vc_index = 0, tar_index = 0;
    while(vc_index < get_len(vc)) {
        clk *clock = get_clock_unit_by_index(vc, vc_index);
        // if((char)gid < (char)(get_gid(*clock))) {
        //     set_clock_unit_by_index(target, tar_index++, wanted);
        // } else {
            set_clock_unit_by_index(target, tar_index++, *clock);
            vc_index ++;
        // }
    }
    if(tar_index < get_len(target)) {
        set_clock_unit_by_index(target, tar_index++, wanted);
    }
    sortVectorClock(target);
    freeVectorClock(vc);
    return target;
}

void
freeInnerClocks(VectorClock *vclock) {
    if(vclock == NULL || get_len(vclock) < 2) {
        return;
    }
    if(clocks_address(*vclock)) {
        zfree(clocks_address(*vclock));
    }
}

/**------------------------Vector Clock Util--------------------------------------*/

/* Sort comparators for qsort() */
static int sort_vector_clock_unit(const void *a, const void *b) {
    const clk *vcu_a = a, *vcu_b = b;
    /* We sort the vector clock unit by gid*/
    if (get_gid(*vcu_a) > get_gid(*vcu_b))
        return 1;
    else if (get_gid(*vcu_a) == get_gid(*vcu_b))
        return 0;
    else
        return -1;
}

void sortVectorClock(VectorClock *vc) {
    if(get_len(vc) == 1) {
        return;
    }
    qsort(clocks_address(*vc), get_len(vc), sizeof(clk), sort_vector_clock_unit);
}


clk*
getVectorClockUnit(VectorClock *vc, int gid) {
    if (vc == NULL || get_len(vc) == 0) {
        return NULL;
    }
    if (get_len(vc) == 1) {
        if ((int) get_gid(*vc) == gid) {
            return vc;
        } else {
            return NULL;
        }
    }

    clk *clock = get_clock_unit(vc, gid);
    if (clock != NULL) {
        return clock;
    }
    return NULL;
}

void incrLogicClock(VectorClock *vc, int gid, int delta) {
    clk *clock = get_clock_unit(vc, gid);
    if(clock == NULL) {
        return;
    }
    long long logic_clock = get_logic_clock(*clock) + delta;
    set_clock_unit_only(clock, init_clock(gid, logic_clock));

}

//vector_clock, num of clocks, gid(int), clock(unsigned long long), gid, clock, gid, clock
void init(VectorClock *vc, int num, ...) {
    if(num > 1) {
        *vc = (unsigned long long) zmalloc(sizeof(clk) * num);
    }
    va_list valist;
    int i;
    va_start(valist, num);
    for (i = 0; i < num; i++) {
        char gid = va_arg(valist, int);
        unsigned long long logic_clock = va_arg(valist, unsigned long long);
        if (num == 1) {
            set_clock_unit_only(vc, init_clock(gid, logic_clock));
        } else {
            set_clock_unit_by_index(vc, i, init_clock(gid, logic_clock));
        }
    }
    va_end(valist);
    set_len(vc, (char) num);
}

static inline int count_all_gid_num(VectorClock *dst, VectorClock *src) {
    unsigned int gid_bit_map = 0u; int gid_num = 0;
    if(get_len(src) == 1) {
        unsigned char gid = (unsigned char) get_gid(*src);
        if(!((gid_bit_map >> gid) & 0x1u)) {
            gid_num ++;
            gid_bit_map |= (0x1u << gid);
        }
    } else {
        for (char i = 0; i < get_len(src); i++) {
            unsigned char gid = get_gid(*(get_clock_unit_by_index(src, i)));
            if (!((gid_bit_map >> gid) & 0x1u)) {
                gid_num++;
                gid_bit_map |= (0x1u << gid);
            }
        }
    }
    if(get_len(dst) == 1) {
        unsigned char gid = (unsigned char) get_gid(*dst);
        if(!((gid_bit_map >> gid) & 0x1u)) {
            gid_num ++;
            gid_bit_map |= (0x1u << gid);
        }
    } else {
        for (int i = 0; i < get_len(dst); i++) {
            unsigned char gid = get_gid(*(get_clock_unit_by_index(dst, i)));
            if (!((gid_bit_map >> gid) & 0x1u)) {
                gid_num++;
                gid_bit_map |= (0x1u << gid);
            }
        }
    }
    return gid_num;
}

void merge(VectorClock *dst, VectorClock *src) {
    if (dst == NULL || src == NULL) {
        return;
    }
    if(get_len(dst) == 1 && get_len(src) == 1
        && (get_gid(*src) == get_gid(*dst))) {
        clk logic_time = max((long long)(get_logic_clock(*dst)), (long long)(get_logic_clock(*src)));
        set_clock_unit_only(dst, init_clock((clk) get_gid(*dst), (clk) logic_time));
        return;
    }
    int gid_num = count_all_gid_num(dst, src);
    clk *new_clocks = NULL;
    int free_prev_array = 0;
    if(get_len(dst) != 1) {
        free_prev_array = 1;
    }
    new_clocks = zmalloc(sizeof(clk) * (gid_num));
    
    int src_index = 0, dst_index = 0, tar_index = 0;

    while(src_index < get_len(src) && dst_index < get_len(dst)) {
        clk *src_clock = get_clock_unit_by_index(src, (char) src_index);
        clk *dst_clock = get_clock_unit_by_index(dst, (char) dst_index);
        if(get_gid(*src_clock) == get_gid(*dst_clock)) {
            long long logic_clock = max((long long)(get_logic_clock(*src_clock)), (long long)(get_logic_clock(*dst_clock)));
            clk tar_clock = init_clock((clk)get_gid(*src_clock), (clk)logic_clock);
            new_clocks[tar_index++] = tar_clock;
            src_index ++;
            dst_index ++;
        } else if(get_gid(*src_clock) > get_gid(*dst_clock)) {
            new_clocks[tar_index++] = *dst_clock;
            dst_index ++;
        } else {
            new_clocks[tar_index++] = *src_clock;
            src_index ++;
        }
    }
    while(src_index < get_len(src)) {
        new_clocks[tar_index++] = *(get_clock_unit_by_index(src, (char)src_index));
        src_index++;
    }
    while(dst_index < get_len(dst)) {
        new_clocks[tar_index++] = *(get_clock_unit_by_index(dst, (char)dst_index));
        dst_index++;
    }

    if(free_prev_array) {
        zfree(clocks_address(*dst));
    }
    *dst = (unsigned long long) new_clocks;
    sortVectorClock(dst);
    set_len(dst, (char) gid_num);
}

static void commonMergeFunction(VectorClock *dst, VectorClock *src, int gid, int flag) {
    clk *dst_logic_clock = getVectorClockUnit(dst, gid);
    clk *src_logic_clock = getVectorClockUnit(src, gid);
    if(src_logic_clock == NULL) {
        return;
    }
    //dst does not hold the gid
    if(dst_logic_clock == NULL) {
        char dst_length = get_len(dst);
        clk *new_clocks = zmalloc(sizeof(clk) * (dst_length + 1));
        if (dst_length == 1) {
            new_clocks[0] = *dst;
        } else {
            memcpy(new_clocks, clocks_address(*dst), dst_length * sizeof(clk));
            zfree(clocks_address(*dst));
        }
        new_clocks[dst_length-1] = init_clock((clk)gid, (clk)*src_logic_clock);
        *dst = (unsigned long long) new_clocks;
        set_len(dst, dst_length + 1);
        sortVectorClock(dst);
        
    } else {
        long long logic_clock = 0;
        if(flag == CLOCK_UNIT_MAX) {
            logic_clock = max((long long) (get_logic_clock(*src_logic_clock)), (long long) (get_logic_clock(*dst_logic_clock)));
        } else if(flag == CLOCK_UNIT_ALIGN) {
            logic_clock = (long long) (get_logic_clock(*src_logic_clock));
        }
        clk tar_clock = init_clock((clk)gid, (clk)logic_clock);
        *dst_logic_clock = tar_clock;
    }
}

void mergeLogicClock(VectorClock *dst, VectorClock *src, int gid) {
    commonMergeFunction(dst, src, gid, CLOCK_UNIT_MAX);
}

VectorClock*
dupVectorClock(VectorClock *vc) {
    char length = get_len(vc);
    VectorClock *dup = newVectorClock(length);
    if(length == 1) {
        *dup = *vc;
    } else {
        memcpy(clocks_address(*dup), clocks_address(*vc), length * sizeof(clk));
    }
    return dup;
}

VectorClock*
vectorClockMerge(VectorClock *vclock1, VectorClock *vclock2) {
    if (vclock1 == NULL && vclock2 == NULL) {
        return NULL;
    }
    if (vclock1 == NULL) {
        return dupVectorClock(vclock2);
    }
    if (vclock2 == NULL) {
        return dupVectorClock(vclock1);
    }
    int gid_num = count_all_gid_num(vclock1, vclock2);
    VectorClock *target;
    if(gid_num > 1) {
        target = newVectorClock(gid_num);
    } else {
        target = dupVectorClock(vclock2);
        clk logic_time = max((long long)(get_logic_clock(*vclock2)), (long long)(get_logic_clock(*vclock1)));
        set_clock_unit_only(target, init_clock((clk)get_gid(*vclock2), (clk)logic_time));
        return target;
    }

    char index1 = 0, index2 = 0, tar_index = 0;

    sortVectorClock(vclock1);
    sortVectorClock(vclock2);
    while(index1 < get_len(vclock1) && index2 < get_len(vclock2)) {
        clk *src_clock = get_clock_unit_by_index(vclock1, index1);
        clk *dst_clock = get_clock_unit_by_index(vclock2, index2);
        if((char)get_gid(*src_clock) == (char)get_gid(*dst_clock)) {
            long long logic_clock = max((long long)(get_logic_clock(*src_clock)), (long long)(get_logic_clock(*dst_clock)));
            clk tar_clock = init_clock((clk)get_gid(*src_clock), (clk)logic_clock);
            set_clock_unit_by_index(target, tar_index++, tar_clock);
            index1 ++;
            index2 ++;
        } else if((char)get_gid(*src_clock) > (char)get_gid(*dst_clock)) {
            set_clock_unit_by_index(target, tar_index++, *dst_clock);
            index2 ++;
        } else {
            set_clock_unit_by_index(target, tar_index++, *src_clock);
            index1 ++;
        }
    }
    while(index1 < get_len(vclock1)) {
        clk *src_clock = get_clock_unit_by_index(vclock1, index1);
        set_clock_unit_by_index(target, tar_index++, *src_clock);
        index1++;
    }
    while(index2 < get_len(vclock2)) {
        clk *dst_clock = get_clock_unit_by_index(vclock2, index2);
        set_clock_unit_by_index(target, tar_index++, *dst_clock);
        index2++;
    }
    return target;
}

/**------------------------Vector Clock & sds convertion--------------------------------------*/

clk
sdsToVectorClockUnit(sds vcUnitStr) {
    int numElements;
    sds *vcUnits = sdssplitlen(vcUnitStr, sdslen(vcUnitStr), VECTOR_CLOCK_UNIT_SEPARATOR, 1, &numElements);
    if(!vcUnits || numElements != 2) {
        sdsfreesplitres(vcUnits, numElements);
        return LOGIC_CLOCK_UNDEFINE;
    }
    long long ll_gid, ll_time;
    string2ll(vcUnits[0], sdslen(vcUnits[0]), &ll_gid);
    string2ll(vcUnits[1], sdslen(vcUnits[1]), &ll_time);

    sdsfreesplitres(vcUnits, numElements);
    return init_clock((clk)ll_gid, (clk)ll_time);
}

void
sdsCpToVectorClock(sds src, VectorClock *dst) {
    int numVcUnits, clockNum;
    sds *vcUnits = sdssplitlen(src, sdslen(src), VECTOR_CLOCK_SEPARATOR, 1, &numVcUnits);
    if(numVcUnits <= 0 || !vcUnits) {
        return;
    }
    clockNum = numVcUnits;
    sdstrim(vcUnits[numVcUnits-1], "");
    if(sdslen(vcUnits[numVcUnits-1]) < 1) {
        clockNum = numVcUnits - 1;
    }

    if (clockNum == 1) {
        set_clock_unit_only(dst, sdsToVectorClockUnit(vcUnits[0]));
    } else {
        *dst = (unsigned long long) zmalloc(sizeof(clk) * clockNum);
        for (int i = 0; i < clockNum; i++) {
            set_clock_unit_by_index(dst, i, sdsToVectorClockUnit(vcUnits[i]));
        }
    }
    set_len(dst, (char) clockNum);
    //clean up
    sdsfreesplitres(vcUnits, numVcUnits);
}

// "<gid>:<clock>;<gid>:<clock>"
VectorClock*
sdsToVectorClock(sds vcStr) {
    int numVcUnits, clockNum;
    printf("[0]");
    sds *vcUnits = sdssplitlen(vcStr, sdslen(vcStr), VECTOR_CLOCK_SEPARATOR, 1, &numVcUnits);
    printf("[1]");
    if(numVcUnits <= 0 || !vcUnits) {
        return NULL;
    }
    printf("[2]");
    clockNum = numVcUnits;
    sdstrim(vcUnits[numVcUnits-1], "");
    printf("[3]");
    if(sdslen(vcUnits[numVcUnits-1]) < 1) {
        clockNum = numVcUnits - 1;
    }
    printf("[4]");
    VectorClock *result = newVectorClock(clockNum);
    printf("[5]");
    if (clockNum == 1) {
        set_clock_unit_only(result, sdsToVectorClockUnit(vcUnits[0]));
    } else {
        for (char i = 0; i < clockNum; i++) {
            set_clock_unit_by_index(result, i, sdsToVectorClockUnit(vcUnits[i]));
        }
    }
    //clean up
    sdsfreesplitres(vcUnits, numVcUnits);
    return result;
}




sds
vectorClockToSds(VectorClock *vc) {
    if(!vc || get_len(vc) < 1) {
        return sdsempty();
    }
    int length = get_len(vc);
    sds vcStr = sdsempty();
    if(length == 1) {
        vcStr = sdscatprintf(vcStr, "%d:%lld", (int)get_gid(*vc), get_logic_clock(*vc));
    } else {
        for (int i = 0; i < length; i++) {
            clk *vc_unit = get_clock_unit_by_index(vc, i);
            vcStr = sdscatprintf(vcStr, "%d:%lld", (int) get_gid(*vc_unit), get_logic_clock(*vc_unit));
            if (i != length - 1) {
                vcStr = sdscat(vcStr, VECTOR_CLOCK_SEPARATOR);
            }
        }
    }
    return vcStr;
}


int
isVectorClockMonoIncr(VectorClock *current, VectorClock *future) {
    if (current == NULL || future == NULL) {
        return 0;
    }
    char current_length = get_len(current), future_length = get_len(future);
    if (current_length > future_length) {
        return 0;
    }

    for (int i = 0; i < current_length; i++) {
        clk *vcu1 = get_clock_unit_by_index(current, i);
        clk *vcu2 = get_clock_unit(future, get_gid(*vcu1));
        if (vcu2 == NULL && (get_logic_clock(*vcu1)) != 0) {
            return 0;
        }
        if (vcu2 != NULL && ((long long) (get_logic_clock(*vcu2))) < ((long long) (get_logic_clock(*vcu1)))) {
            return 0;
        }
    }
    return 1;
}

void
updateProcessVectorClock(VectorClock *dst, VectorClock *src, int gid, int currentGid) {
    if(gid == currentGid) {
        commonMergeFunction(dst, src, gid, CLOCK_UNIT_ALIGN);
    } else {
        commonMergeFunction(dst, src, gid, CLOCK_UNIT_MAX);
    }
}

VectorClock*
getMonoVectorClock(VectorClock *src, int gid) {
    VectorClock *dst = newVectorClock(1);
    clk *result = get_clock_unit(src, gid);
    if (result == NULL) {
        *dst = LOGIC_CLOCK_UNDEFINE;
    } else {
        *dst = *result;
    }
    set_len(dst, 1);
    return dst;
}

void cleanVectorClock(VectorClock *vclock) {
    char length = get_len(vclock);
    if(length == 1) {
        set_clock_unit_only(vclock, init_clock((clk)get_gid(*vclock), 0));
    } else {
        int index = 0;
        while(index < length) {
            clk *src_clock = get_clock_unit_by_index(vclock, index);
            *src_clock = init_clock((clk)get_gid(*src_clock), (clk)0);
            // set_clock_unit_by_index(vclock, index, tar_clock);
            index++;
        }
    }
}

VectorClock*
mergeMinVectorClock(VectorClock *vclock1, VectorClock *vclock2) {
    if (vclock1 == NULL && vclock2 == NULL) {
        return NULL;
    }
    if (vclock1 == NULL) {
        VectorClock* result = dupVectorClock(vclock2);
        cleanVectorClock(result);
        return result;
    }
    if (vclock2 == NULL) {
        VectorClock* result = dupVectorClock(vclock1);
        cleanVectorClock(result);
        return result;
    }

    char clock1_length = get_len(vclock1), clock2_length = get_len(vclock2);
    int gid_nums = count_all_gid_num(vclock1, vclock2);

    VectorClock *target;
    if(gid_nums > 1) {
        target = newVectorClock(gid_nums);
    } else {
        target = dupVectorClock(vclock2);
        clk logic_time = min((long long)(get_logic_clock(*vclock2)), (long long)(get_logic_clock(*vclock1)));
        set_clock_unit_only(target, init_clock((clk)get_gid(*vclock2), (clk)logic_time));
        return target;
    }
    set_len(target, (char) gid_nums);
    int index1 = 0, index2 = 0, tar_index = 0;
    
    sortVectorClock(vclock1);
    sortVectorClock(vclock2);
    while(index1 < clock1_length && index2 < clock2_length) {
        clk *src_clock = get_clock_unit_by_index(vclock1, index1);
        clk *dst_clock = get_clock_unit_by_index(vclock2, index2);
        if((char)get_gid(*src_clock) == (char)get_gid(*dst_clock)) {
            long long logic_clock = min((long long)(get_logic_clock(*src_clock)), (long long)(get_logic_clock(*dst_clock)));
            clk tar_clock = init_clock((clk)get_gid(*src_clock), (clk)logic_clock);
            set_clock_unit_by_index(target, tar_index++, tar_clock);
            index1 ++;
            index2 ++;
        } else if((char)get_gid(*src_clock) > (char)get_gid(*dst_clock)) {
            long long logic_clock = 0;
            clk tar_clock = init_clock((clk)get_gid(*dst_clock), (clk)logic_clock);
            set_clock_unit_by_index(target, tar_index++, tar_clock);
            index2 ++;
        } else {
            long long logic_clock = 0;
            clk tar_clock = init_clock((clk)get_gid(*src_clock), (clk)logic_clock);
            set_clock_unit_by_index(target, tar_index++, tar_clock);
            index1 ++;
        }
    }
    while(index1 < clock1_length) {
        clk *src_clock = get_clock_unit_by_index(vclock1, index1);
        clk tar_clock = init_clock((clk)get_gid(*src_clock), (clk)0);;
        set_clock_unit_by_index(target, tar_index++, tar_clock);
        index1++;
    }
    while(index2 < clock2_length) {
        clk *dst_clock = get_clock_unit_by_index(vclock2, index2);
        clk tar_clock = init_clock((clk)get_gid(*dst_clock), (clk)0);
        set_clock_unit_by_index(target, tar_index++, tar_clock);
        index2++;
    }
    set_len(target, (char) gid_nums);
    return target;
}


#if defined(VECTOR_CLOCK_TEST_MAIN)

#include <stdlib.h>

#include <stdio.h>

#include "testhelp.h"
#include "limits.h"


int testSdsConvert2VectorClockUnit(void) {
    printf("========[testSdsConvert2VectorClockUnit]==========\r\n");
//    sds vcStr = sdsnew("1:123");
//    clk clock = sdsToVectorClockUnit(vcStr);
//
//    printf("[gid]%d\n", get_gid(clock));
//    printf("[logic_time]%lld\n", get_logic_clock(clock));
//    test_cond("[sds to vcu][gid]", 1 == get_gid(clock));
//    test_cond("[sds to vcu][clock]", 123 == ((long long)(get_logic_clock(clock))));
    return 0;
}

int testSdsConvert2VectorClock(void) {
    printf("========[testSdsConvert2VectorClock]==========\r\n");
    printf("[test-1]\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    printf("[test-2]\n");
//    VectorClock *vc = sdsToVectorClock(vcStr);
//    printf("[test-3]");
//    int i = 0;
//    clk *clock = get_clock_unit_by_index(vc, i);
//    test_cond("[first vc]gid equals", 1 == get_gid(*clock));
//    test_cond("[first vc]logic_time equals", 123 == (long long)get_logic_clock(*clock));

//    i = 1;
//    clock = get_clock_unit_by_index(vc, i);
//    test_cond("[second vc]gid equals", 2 == get_gid(*clock));
//    test_cond("[second vc]logic_time equals", 234 == (long long)get_logic_clock(*clock));
//
//    i = 2;
//    clock = get_clock_unit_by_index(vc, i);
//    test_cond("[third vc]gid equals", 3 == get_gid(*clock));
//    test_cond("[third vc]logic_time equals", 345 == (long long)get_logic_clock(*clock));
//
//    vcStr = sdsnew("1:123");
//    vc = sdsToVectorClock(vcStr);
//    test_cond("[one clock unit]length", 1 == get_len(vc));
//    test_cond("[one clock unit]", 1 == get_gid(*vc));
//    test_cond("[one clock unit]", 123 == (long long)get_logic_clock(*vc));
//
//    vcStr = sdsnew("1:123;");
//    vc = sdsToVectorClock(vcStr);
//    test_cond("[one clock unit;]length", 1 == get_len(vc));
//    test_cond("[one clock unit;]gid equals", 1 == get_gid(*vc));
//    test_cond("[one clock unit;]logic_time equals", 123 == (long long)get_logic_clock(*vc));
    return 0;
}

int testFreeVectorClock(void) {
    printf("========[testFreeVectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = sdsToVectorClock(vcStr);
    freeVectorClock(vc);
    return 0;
}


int testStrCmp(void) {
    sds psync = sdsnew("CRDT.PSYNC");
    if (!strcasecmp(psync,"psync")) {
        printf("psync: %d\r\n", strcasecmp(psync,"psync"));
    } else if (!strcasecmp(psync,"crdt.psync")) {
        printf("crdt.psync: %d\r\n", strcasecmp(psync,"crdt.psync"));
    }


    return 0;
}

int testvectorClockToSds(void) {
    printf("========[testvectorClockToSds]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = sdsToVectorClock(vcStr);
    sds dup = vectorClockToSds(vc);
    printf("expected: %s, actual: %s \r\n", vcStr, dup);
    test_cond("[testvectorClockToSds]", sdscmp(vcStr, dup) == 0);
    freeVectorClock(vc);
    return 0;
}

int testSortVectorClock(void) {
    printf("========[testSortVectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = sdsToVectorClock(vcStr);
    sortVectorClock(vc);
    sds dup = vectorClockToSds(vc);
    test_cond("[testSortVectorClock][positive-case]", sdscmp(vcStr, dup) == 0);

    sds vcStr2 = sdsnew("2:234;3:345;1:123");
    vc = sdsToVectorClock(vcStr2);
    sortVectorClock(vc);
    dup = vectorClockToSds(vc);
    test_cond("[testSortVectorClock][real-sort-case]", sdscmp(vcStr, dup) == 0);

    sds vcStr3 = sdsnew("3:345;1:123;2:234");
    vc = sdsToVectorClock(vcStr3);
    sortVectorClock(vc);
    dup = vectorClockToSds(vc);
    test_cond("[testSortVectorClock][real-sort-case]", sdscmp(sdsnew("1:123;2:234;3:345"), dup) == 0);

    return 0;
}

int testDupVectorClock(void) {
    printf("========[testDupVectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = sdsToVectorClock(vcStr);
    VectorClock *dup = dupVectorClock(vc);
    sds dupSds = vectorClockToSds(dup);

    test_cond("[testDupVectorClock]", sdscmp(vcStr, dupSds) == 0);
    return 0;
}

int testAddVectorClockUnit(void) {
    printf("========[testAddVectorClockUnit]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = sdsToVectorClock(vcStr);

    vc = addVectorClockUnit(vc, 11, 50);

    printf("result: %s\r\n", vectorClockToSds(vc));
    test_cond("[testAddVectorClockUnit]", sdscmp(sdsnew("1:123;2:234;3:345;11:50"), vectorClockToSds(vc)) == 0);
    return 0;
}

int testvectorClockMerge(void) {
    printf("========[testvectorClockMerge]==========\r\n");
    VectorClock *vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:500;3:300"), vectorClockToSds(vc)) == 0);

    vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:99")));
    printf("%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][add]", sdscmp(sdsnew("1:100;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:200;3:100;4:400")));
    printf("%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][add-merge]", sdscmp(sdsnew("1:200;2:200;3:300;4:400"), vectorClockToSds(vc)) == 0);

    return 0;
}

int testMergeLogicClock(void) {
    printf("========[testMergeLogicClock]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    VectorClock *vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("1:200;2:500;3:100")), 1);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    //second, dst is covering every little corner of src
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("1:200")), 1);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("2:500")), 2);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:100"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("2:500;3:100;5:100")), 3);
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:100;3:100"), vectorClockToSds(vc)) == 0);

    //forth, dst is diff with src, but they are all single
    vc = sdsToVectorClock(sdsnew("2:500"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("1:500")), 1);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:500;2:500"), vectorClockToSds(vc)) == 0);

    //fifth, dst is inserting into src
    vc = sdsToVectorClock(sdsnew("1:100;3:300"));
    mergeLogicClock(vc, sdsToVectorClock(sdsnew("2:500")), 2);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    return 0;

}

int testMerge(void) {
    printf("========[testMerge]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    VectorClock *vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    merge(vc, sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //second, dst is covering every little corner of src
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    merge(vc, sdsToVectorClock(sdsnew("1:200")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    merge(vc, sdsToVectorClock(sdsnew("2:500")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:100"));
    merge(vc, sdsToVectorClock(sdsnew("2:500;3:100;5:100")));
     printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:100;2:500;3:100;5:100"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:113"));
    VectorClock* v2 =  sdsToVectorClock(sdsnew("2:110;1:111"));
    merge(vc, v2);
    free(v2);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:113;2:110"), vectorClockToSds(vc)) == 0);
    free(vc);

    //forth, dst is diff with src, but they are all single
    vc = sdsToVectorClock(sdsnew("2:500"));
    merge(vc, sdsToVectorClock(sdsnew("1:500")));
     printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:500;2:500"), vectorClockToSds(vc)) == 0);

    //fifth, dst is inserting into src
    vc = sdsToVectorClock(sdsnew("1:100;3:300"));
    merge(vc, sdsToVectorClock(sdsnew("2:500")));
     printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);


    //sixth, dst/src is single and same
    vc = sdsToVectorClock(sdsnew("1:100"));
    merge(vc, sdsToVectorClock(sdsnew("1:500")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:500"), vectorClockToSds(vc)) == 0);

    return 0;

}

int testInit(void) {
    VectorClock *vc = zmalloc(sizeof(VectorClock));
    init(vc, 1, 1, 200);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200"), vectorClockToSds(vc)) == 0);

    vc = zmalloc(sizeof(VectorClock));
    init(vc, 2, 1, 200, 2, 300);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:300"), vectorClockToSds(vc)) == 0);

    vc = zmalloc(sizeof(VectorClock));
    init(vc, 3, 1, 200, 3, 400, 4, 500);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;3:400;4:500"), vectorClockToSds(vc)) == 0);


    return 0;

}

int testSdsCp2VectorClock(void) {
    printf("========[testSdsCp2VectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock *vc = zmalloc(sizeof(VectorClock));
    printf("[test-1]\n");
    sdsCpToVectorClock(vcStr, vc);
    int i = 0;
    printf("%s\n", vectorClockToSds(vc));
    clk *clock = get_clock_unit_by_index(vc, i);
    test_cond("[first vc]gid equals", 1 == get_gid(*clock));
    test_cond("[first vc]logic_time equals", 123 == (long long)get_logic_clock(*clock));

    i = 1;
    clock = get_clock_unit_by_index(vc, i);
    test_cond("[second vc]gid equals", 2 == get_gid(*clock));
    test_cond("[second vc]logic_time equals", 234 == (long long)get_logic_clock(*clock));

    i = 2;
    clock = get_clock_unit_by_index(vc, i);
    test_cond("[third vc]gid equals", 3 == get_gid(*clock));
    test_cond("[third vc]logic_time equals", 345 == (long long)get_logic_clock(*clock));

    vcStr = sdsnew("1:123");
    vc = zmalloc(sizeof(VectorClock));
    sdsCpToVectorClock(vcStr, vc);
    test_cond("[one clock unit]length", 1 == get_len(vc));
    test_cond("[one clock unit]", 1 == get_gid(*vc));
    test_cond("[one clock unit]", 123 == (long long)get_logic_clock(*vc));

    vcStr = sdsnew("1:123;");
    vc = zmalloc(sizeof(VectorClock));
    sdsCpToVectorClock(vcStr, vc);
    test_cond("[one clock unit;]length", 1 == get_len(vc));
    test_cond("[one clock unit;]gid equals", 1 == get_gid(*vc));
    test_cond("[one clock unit;]logic_time equals", 123 == (long long)get_logic_clock(*vc));
    return 0;
}

int testGetMonoVectorClock(void) {
    printf("========[testGetMonoVectorClock]==========\r\n");
    VectorClock *vc = sdsToVectorClock(sdsnew("1:123;3:300"));
    VectorClock *new_vc = getMonoVectorClock(vc, 1);
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("1:123"), vectorClockToSds(new_vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:123;2:234;3:300"));
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("2:234"), vectorClockToSds(getMonoVectorClock(vc, 2))) == 0);

    vc = sdsToVectorClock(sdsnew("1:123;2:234;3:300;4:456;5:567"));
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("4:456"), vectorClockToSds(getMonoVectorClock(vc, 4))) == 0);

    return 0;
}

int testMergeMinVectorClock(void) {
     printf("========[testMergeMinVectorClock]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    VectorClock *vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    VectorClock *new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:200;3:100"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    //second, dst is covering every little corner of src
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("1:200")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:0;3:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("2:500")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:0;2:200;3:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:100"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("2:500;3:100;5:100")));
    printf("[result]%s\n", vectorClockToSds(new_vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:0;2:0;3:0;5:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    //forth, dst is diff with src, but they are all single
    vc = sdsToVectorClock(sdsnew("2:500"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("1:500")));
    printf("[result]%s\n", vectorClockToSds(new_vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:0;2:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    //fifth, dst is inserting into src
    vc = sdsToVectorClock(sdsnew("1:100;3:300"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("2:500")));
    printf("[result]%s\n", vectorClockToSds(new_vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:0;2:0;3:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);

    //sixth, dst/src is single and same
    vc = sdsToVectorClock(sdsnew("1:100"));
    new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("1:200;2:300")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);
    return 0;
}

int vectorClockTest(void) {
    int result = 0;
    {
        result |= testSdsConvert2VectorClockUnit();
        result |= testSdsConvert2VectorClock();

    }
    test_report();
    return result;
}
#endif

#ifdef VECTOR_CLOCK_TEST_MAIN
int main(void) {
    return vectorClockTest();
}
#endif
