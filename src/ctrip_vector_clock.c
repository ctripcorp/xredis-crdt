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
#include "util.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
/**------------------------Vector Clock Inner Functions--------------------------------------*/

static inline clk *get_clock_unit(VectorClock *vc, char gid) {
    if(vc == NULL) {
        return NULL;
    }
    if (get_len(*vc) == 1 && get_gid(*get_clock_unit_by_index(vc, 0)) == gid) {
        return get_clock_unit_by_index(vc, 0);
    }
    for (char i = 0; i < get_len(*vc); i++) {
        clk *clock = (clk *)(get_clock_unit_by_index(vc, i));
        if ((char) get_gid(*clock) == gid) {
            return clock;
        }
    }
    return NULL;
}


/**------------------------Vector Clock Lifecycle--------------------------------------*/

#if defined(TCL_TEST)
    VectorClock
    newVectorClock(int numVcUnits) {
        if(numVcUnits == 0) return NULL;
        VectorClock result = vc_malloc(sizeof(VectorClockUnit) * numVcUnits + 1);
        result->len = numVcUnits;
        return result;
    }
    void
    freeVectorClock(VectorClock vc) {
        // printf("freeVectorClock %p \n", vc);
        vc_free(vc);
    }
    clk* clocks_address(VectorClock value) {
        return (clk*)(&value->vcu);
    }
#else
    VectorClock
    newVectorClock(int numVcUnits) {
        long long vc = 0ull;
        VectorClock result = LL2VC(vc);
        if(numVcUnits == 0) {
            return result;
        }
        if(numVcUnits > 1) {
            clk *clocks = vc_malloc(sizeof(clk) * numVcUnits);
            result.pvc.pvc = ULL(clocks);
        }
        set_len(&result, (char)numVcUnits);
        return result;
    }
    void
    freeVectorClock(VectorClock vc) {
        if (isNullVectorClock(vc) || (get_len(vc) < 2)) {
            return;
        }
        vc_free(clocks_address(vc));
    }
    clk* clocks_address(VectorClock value) {
        if(get_len(value) == 1) {
            return (clk*)(&value.unit);
        }
        return (clk*)value.pvc.pvc;
    }
#endif




VectorClock
addVectorClockUnit(VectorClock vc, int gid, long long logic_time) {
    clk *dst_clock = get_clock_unit(&vc, gid);
    if(dst_clock != NULL) {
        set_gid(dst_clock, (char)gid);
        set_logic_clock(dst_clock, logic_time);
        return vc;
    }
    VectorClock target = newVectorClock(get_len(vc) + 1);
    char vc_index = 0, tar_index = 0;
    while(vc_index < get_len(vc)) {
        clk *clock = get_clock_unit_by_index(&vc, vc_index);
        set_clock_unit_by_index(&target, tar_index++, *clock);
        vc_index ++;
    }
    clk wanted = init_clock((char)gid, logic_time);
    if(tar_index < get_len(target)) {
        set_clock_unit_by_index(&target, tar_index++, wanted);
    }
    sortVectorClock(target);
    freeVectorClock(vc);
    return target;
}



/**------------------------Vector Clock Util--------------------------------------*/
int isNullVectorClock(VectorClock vc) {
    return get_len(vc) == 0;
}
int isNullVectorClockUnit(VectorClockUnit unit) {
    return unit.clock == 0;
}
void set_clock_unit_by_index(VectorClock *vclock, char index, clk gid_logic_time) {
    clk *clock = get_clock_unit_by_index(vclock, index);
    // *clock = gid_logic_time;
    set_gid(clock, get_gid(gid_logic_time));
    set_logic_clock(clock, get_logic_clock(gid_logic_time));
}
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

void sortVectorClock(VectorClock vc) {
    if(get_len(vc) == 1) {
        return;
    }
    qsort(clocks_address(vc), get_len(vc), sizeof(clk), sort_vector_clock_unit);
}

clk
getVectorClockUnit(VectorClock vc, int gid) {
    long long unit = 0;
    if(isNullVectorClock(vc)) {
        return VCU(unit);
    }
    if (isNullVectorClock(vc) || get_len(vc) == 0) {
        return VCU(unit);
    }
    clk* result = get_clock_unit(&vc, gid);
    if(result == NULL) return VCU(unit);
    return *result;
}

void incrLogicClock(VectorClock *vc, int gid, int delta) {
    clk *clock = get_clock_unit(vc, gid);
    if(clock == NULL) {
        return;
    }
    long long logic_clock = get_logic_clock(*clock) + delta;
    set_logic_clock(clock, logic_clock);
}

static inline int count_all_gid_num(VectorClock dst, VectorClock src) {
    unsigned int gid_bit_map = 0u; int gid_num = 0;
    if(get_len(src) == 1) {
        unsigned char gid = (unsigned char) get_gid(*get_clock_unit_by_index(&src, 0));
        if(!((gid_bit_map >> gid) & 0x1u)) {
            gid_num ++;
            gid_bit_map |= (0x1u << gid);
        }
    } else {
        for (char i = 0; i < get_len(src); i++) {
            unsigned char gid = get_gid(*(get_clock_unit_by_index(&src, i)));
            if (!((gid_bit_map >> gid) & 0x1u)) {
                gid_num++;
                gid_bit_map |= (0x1u << gid);
            }
        }
    }
    if(get_len(dst) == 1) {
        unsigned char gid = (unsigned char) get_gid(*get_clock_unit_by_index(&dst, 0));
        if(!((gid_bit_map >> gid) & 0x1u)) {
            gid_num ++;
            gid_bit_map |= (0x1u << gid);
        }
    } else {
        for (int i = 0; i < get_len(dst); i++) {
            unsigned char gid = get_gid(*(get_clock_unit_by_index(&dst, i)));
            if (!((gid_bit_map >> gid) & 0x1u)) {
                gid_num++;
                gid_bit_map |= (0x1u << gid);
            }
        }
    }
    return gid_num;
}

static void commonMergeFunction(VectorClock *dst, VectorClock *src, int gid, int flag) {
    clk *dst_logic_clock = get_clock_unit(dst, gid);
    clk *src_logic_clock = get_clock_unit(src, gid);
    if(src_logic_clock == NULL) {
        return;
    }
    //dst does not hold the gid
    if(dst_logic_clock == NULL) {
        char dst_length = get_len(*dst);
        VectorClock result = newVectorClock(dst_length + 1);
        if(dst_length == 1) {
            set_clock_unit_by_index(&result, 0, *get_clock_unit_by_index(dst, 0));
        } else {
            for(int i = 0; i < dst_length; i++) {
                set_clock_unit_by_index(&result, i, *get_clock_unit_by_index(dst, (char)i));
            }
        }
        set_clock_unit_by_index(&result, dst_length, init_clock(gid, get_logic_clock(*src_logic_clock)));
        VectorClock* v = dst;
        freeVectorClock(*dst);
        *v = result;
        // clk *new_clocks = vc_malloc(sizeof(clk) * (dst_length + 1));
        // if (dst_length == 1) {
        //     new_clocks[0] = init_clock(get_gid(get_frist_unit(dst)), get_logic_clock(get_frist_unit(dst)));
        // } else {
        //     memcpy(new_clocks, clocks_address(*dst), dst_length * sizeof(clk));
        // }
        // new_clocks[(int)dst_length] = init_clock(gid, get_logic_clock(*src_logic_clock));

        // freeVectorClock(*dst);
        // dst->pvc.pvc = new_clocks;
        // set_len(dst, dst_length + 1);
        sortVectorClock(*dst);

    } else {
        long long logic_clock = 0;
        if(flag == CLOCK_UNIT_MAX) {
            logic_clock = max((get_logic_clock(*src_logic_clock)), (long long) (get_logic_clock(*dst_logic_clock)));
        } else if(flag == CLOCK_UNIT_ALIGN) {
            logic_clock = (long long) (get_logic_clock(*src_logic_clock));
        }
        set_gid(dst_logic_clock, gid);
        set_logic_clock(dst_logic_clock, logic_clock);
    }
}

void mergeLogicClock(VectorClock *dst, VectorClock *src, int gid) {
    commonMergeFunction(dst, src, gid, CLOCK_UNIT_MAX);
}

VectorClock
dupVectorClock(VectorClock vc) {
    char length = get_len(vc);
    VectorClock dup;
    dup = newVectorClock(length);
    if(length > 1) {
        memcpy(clocks_address(dup), clocks_address(vc), length * sizeof(clk));
    }else if(length == 1){
        set_clock_unit_by_index(&dup, 0, *get_clock_unit_by_index(&vc, 0));
    }
    return dup;
}

VectorClock
vectorClockMerge(VectorClock vclock1, VectorClock vclock2) {
    if (isNullVectorClock(vclock1) && isNullVectorClock(vclock2)) {
        return newVectorClock(0);
    }
    if (isNullVectorClock(vclock1)) {
        return dupVectorClock(vclock2);
    }
    if (isNullVectorClock(vclock2)) {
        return dupVectorClock(vclock1);
    }
    int gid_num = count_all_gid_num(vclock1, vclock2);
    VectorClock target;
    if(gid_num > 1) {
        target = newVectorClock(gid_num);
    } else {
        target = dupVectorClock(vclock2);
        long long logic_time = max((get_logic_clock(*get_clock_unit_by_index(&vclock2, 0))), (get_logic_clock(*get_clock_unit_by_index(&vclock1, 0))));
        set_logic_clock(get_clock_unit_by_index(&target, 0), logic_time);
        return target;
    }

    char index1 = 0, index2 = 0, tar_index = 0;

    sortVectorClock(vclock1);
    sortVectorClock(vclock2);
    while(index1 < get_len(vclock1) && index2 < get_len(vclock2)) {
        clk *src_clock = get_clock_unit_by_index(&vclock1, index1);
        clk *dst_clock = get_clock_unit_by_index(&vclock2, index2);
        if((char)get_gid(*src_clock) == (char)get_gid(*dst_clock)) {
            long long logic_clock = max((long long)(get_logic_clock(*src_clock)), (long long)(get_logic_clock(*dst_clock)));
            clk tar_clock = init_clock(get_gid(*src_clock), logic_clock);
            set_clock_unit_by_index(&target, tar_index++, tar_clock);
            index1 ++;
            index2 ++;
        } else if((char)get_gid(*src_clock) > (char)get_gid(*dst_clock)) {
            set_clock_unit_by_index(&target, tar_index++, *dst_clock);
            index2 ++;
        } else {
            set_clock_unit_by_index(&target, tar_index++, *src_clock);
            index1 ++;
        }
    }
    while(index1 < get_len(vclock1)) {
        clk *src_clock = get_clock_unit_by_index(&vclock1, index1);
        set_clock_unit_by_index(&target, tar_index++, *src_clock);
        index1++;
    }
    while(index2 < get_len(vclock2)) {
        clk *dst_clock = get_clock_unit_by_index(&vclock2, index2);
        set_clock_unit_by_index(&target, tar_index++, *dst_clock);
        index2++;
    }
    return target;
}

/**------------------------Vector Clock & sds convertion--------------------------------------*/

clk
sdsToVectorClockUnit(sds vcUnitStr) {
    int numElements;
    long long result = 0;
    sds *vcUnits = sdssplitlen(vcUnitStr, sdslen(vcUnitStr), VECTOR_CLOCK_UNIT_SEPARATOR, 1, &numElements);
    if(!vcUnits || numElements != 2) {
        sdsfreesplitres(vcUnits, numElements);
        return VCU(result);
    }
    long long ll_gid, ll_time;
    string2ll(vcUnits[0], sdslen(vcUnits[0]), &ll_gid);
    string2ll(vcUnits[1], sdslen(vcUnits[1]), &ll_time);
    sdsfreesplitres(vcUnits, numElements);
    return init_clock((char)ll_gid, ll_time);
}


// "<gid>:<clock>;<gid>:<clock>"
VectorClock
sdsToVectorClock(sds vcStr) {
    int numVcUnits, clockNum;
    sds *vcUnits = sdssplitlen(vcStr, sdslen(vcStr), VECTOR_CLOCK_SEPARATOR, 1, &numVcUnits);
    if(numVcUnits <= 0 || !vcUnits) {
        return newVectorClock(0);
    }
    clockNum = numVcUnits;
    sdstrim(vcUnits[numVcUnits-1], "");
    if(sdslen(vcUnits[numVcUnits-1]) < 1) {
        clockNum = numVcUnits - 1;
    }
    VectorClock result = newVectorClock(clockNum);
    if (clockNum == 1) {
        clk clock_unit = sdsToVectorClockUnit(vcUnits[0]);
        set_clock_unit_by_index(&result, 0, clock_unit);
    } else {
        for (int i = 0; i < clockNum; i++) {
            clk clock_unit = sdsToVectorClockUnit(vcUnits[i]);
            set_clock_unit_by_index(&result, (char) i, clock_unit);
        }
    }
    //clean up
    sdsfreesplitres(vcUnits, numVcUnits);
    return result;
}
void split(char *src,const char *separator,char **dest,int *num) {
      char *pNext;
      int count = 0;
      if (src == NULL)
         return;
      if (separator == NULL)
         return;    
      pNext = strtok(src,separator);
      while(pNext != NULL) {
           *dest++ = pNext;
           ++count;
          pNext = strtok(NULL,separator);  
     }  
     *num = count;
}
char *trim(char *str)
{
        char *p = str;
        char *p1;
        if(p)
        {
                p1 = p + strlen(str) - 1;
                while(*p && isspace(*p)) p++;
                while(p1 > p && isspace(*p1)) *p1-- = '\0';
        }
        return p;
}
clk
stringToVectorClockUnit(char* vcUnitStr) {
    int numElements = 0;
    long long result = 0;
    char* vcUnits[2];
    split(vcUnitStr,VECTOR_CLOCK_UNIT_SEPARATOR,vcUnits,&numElements);
    if(numElements != 2) {
        return VCU(result);
    }
    long long ll_gid, ll_time;
    string2ll(vcUnits[0], strlen(vcUnits[0]), &ll_gid);
    string2ll(vcUnits[1], strlen(vcUnits[1]), &ll_time);
    return init_clock((char)ll_gid, ll_time);
}

VectorClock 
stringToVectorClock(char* buf) {
    char* vcUnits[2<<GIDSIZE];
    int clockNum = 0;
    split(buf,VECTOR_CLOCK_SEPARATOR,vcUnits,&clockNum);
    if(clockNum == 0) {
        return newVectorClock(0);
    }
    vcUnits[clockNum-1] = trim(vcUnits[clockNum-1]);
    if(strlen(vcUnits[clockNum-1]) < 1) {
        clockNum = clockNum - 1;
    }
    VectorClock result = newVectorClock(clockNum);
    if (clockNum == 1) {
        clk clock_unit = stringToVectorClockUnit(vcUnits[0]);
        set_clock_unit_by_index(&result, 0, clock_unit);
    } else {
        for (int i = 0; i < clockNum; i++) {
            clk clock_unit = stringToVectorClockUnit(vcUnits[i]);
            set_clock_unit_by_index(&result, (char) i, clock_unit);
        }
    }
    return result;
}


int lllen(long long v) {
    int len = 0;
    if(v < 0) {
        v = -v;
        len = 1;
    }
    do {
        len += 1;
        v /= 10;
    } while(v);
    return len;
}
size_t vectorClockToStringLen(VectorClock vc) {
    if(isNullVectorClock(vc) || get_len(vc) < 1) {
        return 0;
    }
    int length = get_len(vc);
    size_t buflen = 0;
    buflen += (int)get_gid(*get_clock_unit_by_index(&vc, 0)) >= 10? 3: 2;
    buflen += lllen(get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    for (int i = 1; i < length; i++) {
        clk *vc_unit = get_clock_unit_by_index(&vc, i);
        buflen += (int) get_gid(*vc_unit) >= 10? 4:3;
        buflen += lllen(get_logic_clock(*vc_unit));
    }
    return buflen;
}
size_t vectorClockToString(char* buf, VectorClock vc) {
    int length = get_len(vc);
    if(isNullVectorClock(vc) || length < 1) {
        buf[0] = '\0';
        return 0;
    }
    size_t buflen = 0;
    buflen += sprintf(buf, "%d:%lld", (int)get_gid(*get_clock_unit_by_index(&vc, 0)), get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    for (int i = 1; i < length; i++) {
        clk *vc_unit = get_clock_unit_by_index(&vc, i);
        buflen += sprintf(buf + buflen, ";%d:%lld", (int) get_gid(*vc_unit), get_logic_clock(*vc_unit));
    }
    return buflen;
}
sds
vectorClockToSds(VectorClock vc) {
    if(isNullVectorClock(vc) || get_len(vc) < 1) {
        return sdsempty();
    }
    int length = get_len(vc);
    sds vcStr = sdsempty();
    if(length == 1) {
        vcStr = sdscatprintf(vcStr, "%d:%lld", (int)get_gid(*get_clock_unit_by_index(&vc, 0)), get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    } else {
        for (int i = 0; i < length; i++) {
            clk *vc_unit = get_clock_unit_by_index(&vc, i);
            vcStr = sdscatprintf(vcStr, "%d:%lld", (int) get_gid(*vc_unit), get_logic_clock(*vc_unit));
            if (i != length - 1) {
                vcStr = sdscat(vcStr, VECTOR_CLOCK_SEPARATOR);
            }
        }
    }
    return vcStr;
}


int
isVectorClockMonoIncr(VectorClock current, VectorClock future) {
    if (isNullVectorClock(current) || isNullVectorClock(future)) {
        return 0;
    }
    char current_length = get_len(current), future_length = get_len(future);
    if (current_length > future_length) {
        return 0;
    }

    for (int i = 0; i < current_length; i++) {
        clk *vcu1 = get_clock_unit_by_index(&current, i);
        clk *vcu2 = get_clock_unit(&future, get_gid(*vcu1));
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

VectorClock
getMonoVectorClock(VectorClock src, int gid) {
    VectorClock dst = newVectorClock(1);
    clk *clock = get_clock_unit(&src, gid);
    if (clock == NULL) {
       return newVectorClock(0);
    } else {
        // dst.unit = *clock;
        clk* f = get_clock_unit_by_index(&dst, 0);
        set_logic_clock(f, get_logic_clock(*clock));
        set_gid(f, get_gid(*clock));
    }
    set_len(&dst, 1);
    return dst;
}

void cleanVectorClock(VectorClock *vclock) {
    char length = get_len(*vclock);
    if(length == 1) {
        set_logic_clock(get_clock_unit_by_index(vclock, 0), 0);
    } else {
        int index = 0;
        while(index < length) {
            clk *src_clock = get_clock_unit_by_index(vclock, index);
            set_logic_clock(src_clock, 0);
            index++;
        }
    }
}

VectorClock
mergeMinVectorClock(VectorClock vclock1, VectorClock vclock2) {
    if (isNullVectorClock(vclock1) && isNullVectorClock(vclock2)) {
        return newVectorClock(0);
    }
    if (isNullVectorClock(vclock1)) {
        VectorClock result = dupVectorClock(vclock2);
        cleanVectorClock(&result);
        return result;
    }
    if (isNullVectorClock(vclock2)) {
        VectorClock result = dupVectorClock(vclock1);
        cleanVectorClock(&result);
        return result;
    }

    char clock1_length = get_len(vclock1), clock2_length = get_len(vclock2);
    int gid_nums = count_all_gid_num(vclock1, vclock2);

    VectorClock target;
    if(gid_nums > 1) {
        target = newVectorClock(gid_nums);
    } else {
        target = dupVectorClock(vclock2);
        long long logic_time = min(get_logic_clock(*get_clock_unit_by_index(&vclock2, 0)),get_logic_clock(*get_clock_unit_by_index(&vclock1, 0)));
        clk* f = get_clock_unit_by_index(&target, 0);
        set_logic_clock(f, logic_time);
        return target;
    }
    set_len(&target, (char) gid_nums);
    int index1 = 0, index2 = 0, tar_index = 0;

    sortVectorClock(vclock1);
    sortVectorClock(vclock2);
    while(index1 < clock1_length && index2 < clock2_length) {
        clk *src_clock = get_clock_unit_by_index(&vclock1, index1);
        clk *dst_clock = get_clock_unit_by_index(&vclock2, index2);
        if((char)get_gid(*src_clock) == (char)get_gid(*dst_clock)) {
            long long logic_clock = min((long long)(get_logic_clock(*src_clock)), (long long)(get_logic_clock(*dst_clock)));
            clk tar_clock = init_clock((char)get_gid(*src_clock), (long long)logic_clock);
            set_clock_unit_by_index(&target, tar_index++, tar_clock);
            index1 ++;
            index2 ++;
        } else if((char)get_gid(*src_clock) > (char)get_gid(*dst_clock)) {
            long long logic_clock = 0;
            clk tar_clock = init_clock((char)get_gid(*dst_clock), (long long)logic_clock);
            set_clock_unit_by_index(&target, tar_index++, tar_clock);
            index2 ++;
        } else {
            long long logic_clock = 0;
            clk tar_clock = init_clock((char)get_gid(*src_clock), (long long)logic_clock);
            set_clock_unit_by_index(&target, tar_index++, tar_clock);
            index1 ++;
        }
    }
    while(index1 < clock1_length) {
        clk *src_clock = get_clock_unit_by_index(&vclock1, index1);
        clk tar_clock = init_clock((char)get_gid(*src_clock), 0);;
        set_clock_unit_by_index(&target, tar_index++, tar_clock);
        index1++;
    }
    while(index2 < clock2_length) {
        clk *dst_clock = get_clock_unit_by_index(&vclock2, index2);
        clk tar_clock = init_clock((char)get_gid(*dst_clock), 0);
        set_clock_unit_by_index(&target, tar_index++, tar_clock);
        index2++;
    }
    set_len(&target, (char) gid_nums);
    return target;
}

VectorClock
purgeVectorClock(VectorClock targe, VectorClock src) {
    if (isNullVectorClock(targe)) {
        return targe;
    }
    if (isNullVectorClock(src)) {
        return targe;
    }
    int len = get_len(targe);
    clk c[len];
    int index = 0;
    for(int i = 0; i < len; i++) {
        clk* vcu1 = get_clock_unit_by_index(&targe, i);
        unsigned char gid = (unsigned char) get_gid(*get_clock_unit_by_index(&targe, i));
        clk* vcu2 = get_clock_unit(&src, gid);
        if (vcu2 == NULL && (get_logic_clock(*vcu1)) != 0) {
            c[index] = *vcu1;
            index++;
        }
        if (vcu2 != NULL && ((long long) (get_logic_clock(*vcu2))) < ((long long) (get_logic_clock(*vcu1)))) {
            c[index] = *vcu1;
            index ++;
        }
    }
    VectorClock result = newVectorClock(index);
    for(int i = 0; i < index; i++) {
        set_clock_unit_by_index(&result, i, c[i]);
    }
    freeVectorClock(targe);
    sortVectorClock(result);
    return result;
}

#if defined(VECTOR_CLOCK_TEST_MAIN)

#include <stdlib.h>

#include <stdio.h>

#include "testhelp.h"
#include "limits.h"


int testSdsConvert2VectorClockUnit(void) {
    printf("========[testSdsConvert2VectorClockUnit]==========\r\n");
    sds vcStr = sdsnew("1:123");
    clk clock = sdsToVectorClockUnit(vcStr);

    printf("[gid]%d\n", get_gid(clock));
    printf("[logic_time]%lld\n", get_logic_clock(clock));
    test_cond("[sds to vcu][gid]", 1 == get_gid(clock));
    test_cond("[sds to vcu][clock]", 123 == ((long long)(get_logic_clock(clock))));
    return 0;
}

int testSdsConvert2VectorClock(void) {
    printf("========[testSdsConvert2VectorClock]==========\r\n");

    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock vc = sdsToVectorClock(vcStr);
    printf("[test-3]");
    int i = 0;
    clk *clock = get_clock_unit_by_index(&vc, i);
    test_cond("[first vc]gid equals", 1 == get_gid(*clock));
    test_cond("[first vc]logic_time equals", 123 == (long long)get_logic_clock(*clock));

    i = 1;
    clock = get_clock_unit_by_index(&vc, i);
    test_cond("[second vc]gid equals", 2 == get_gid(*clock));
    test_cond("[second vc]logic_time equals", 234 == (long long)get_logic_clock(*clock));

    i = 2;
    clock = get_clock_unit_by_index(&vc, i);
    test_cond("[third vc]gid equals", 3 == get_gid(*clock));
    test_cond("[third vc]logic_time equals", 345 == (long long)get_logic_clock(*clock));

    vcStr = sdsnew("1:123");
    vc = sdsToVectorClock(vcStr);
    test_cond("[one clock unit]length", 1 == get_len(vc));
    test_cond("[one clock unit]", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit]", 123 == get_logic_clock(*get_clock_unit_by_index(&vc, 0)));

    vcStr = sdsnew("1:123;");
    vc = sdsToVectorClock(vcStr);
    test_cond("[one clock unit;]length", 1 == get_len(vc));
    test_cond("[one clock unit;]gid equals", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit;]logic_time equals", 123 == (long long)get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    return 0;
}
int testStringConvert2VectorClockUnit(void) {
    printf("========[testStringConvert2VectorClockUnit]==========\r\n");
    // sds vcStr = sdsnew("1:123");
    
    char vcStr[6] = "1:123\0";
    clk clock = stringToVectorClockUnit(vcStr);

    printf("[gid]%d\n", get_gid(clock));
    printf("[logic_time]%lld\n", get_logic_clock(clock));
    test_cond("[string to vcu][gid]", 1 == get_gid(clock));
    test_cond("[string to vcu][clock]", 123 == ((long long)(get_logic_clock(clock))));

    char vcStr1[10] = "1:123\0";
    clock = stringToVectorClockUnit(vcStr1);

    printf("[gid]%d\n", get_gid(clock));
    printf("[logic_time]%lld\n", get_logic_clock(clock));
    test_cond("[string to vcu][gid]", 1 == get_gid(clock));
    test_cond("[string to vcu][clock]", 123 == ((long long)(get_logic_clock(clock))));
    return 0;
}

int testStringConvert2VectorClock(void) {
    printf("========[testStringConvert2VectorClock]==========\r\n");

    // sds vcStr = sdsnew("1:123;2:234;3:345");
    char vcStr[18] = "1:123;2:234;3:345\0";
    VectorClock vc = stringToVectorClock(vcStr);
    int i = 0;
    clk *clock = get_clock_unit_by_index(&vc, i);
    test_cond("[first vc]gid equals", 1 == get_gid(*clock));
    test_cond("[first vc]logic_time equals", 123 == (long long)get_logic_clock(*clock));

    i = 1;
    clock = get_clock_unit_by_index(&vc, i);
    test_cond("[second vc]gid equals", 2 == get_gid(*clock));
    test_cond("[second vc]logic_time equals", 234 == (long long)get_logic_clock(*clock));

    i = 2;
    clock = get_clock_unit_by_index(&vc, i);
    test_cond("[third vc]gid equals", 3 == get_gid(*clock));
    test_cond("[third vc]logic_time equals", 345 == (long long)get_logic_clock(*clock));

    // vcStr = sdsnew("1:123");
    char vcStr1[6] = "1:123\0";
    vc = stringToVectorClock(vcStr1);
    test_cond("[one clock unit]length", 1 == get_len(vc));
    test_cond("[one clock gid]", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    printf("faild %lld\r\n", get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit]:", 123 == get_logic_clock(*get_clock_unit_by_index(&vc, 0)));

    // vcStr = sdsnew("1:123;");
    char vcStr2[7] = "1:123;\0";
    vc = stringToVectorClock(vcStr2);
    test_cond("[one clock unit;]length", 1 == get_len(vc));
    test_cond("[one clock unit;]gid equals", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit;]logic_time equals", 123 == (long long)get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    
    char vcStr3[8] = "1:123; \0";
    vc = stringToVectorClock(vcStr3);
    test_cond("[one clock unit;]length", 1 == get_len(vc));
    test_cond("[one clock unit;]gid equals", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit;]logic_time equals", 123 == (long long)get_logic_clock(*get_clock_unit_by_index(&vc, 0)));

    char vcStr4[99] = "1:123;\0";
    vc = stringToVectorClock(vcStr4);
    test_cond("[one clock unit;]length", 1 == get_len(vc));
    test_cond("[one clock unit;]gid equals", 1 == get_gid(*get_clock_unit_by_index(&vc, 0)));
    test_cond("[one clock unit;4]logic_time equals", 123 == (long long)get_logic_clock(*get_clock_unit_by_index(&vc, 0)));
    
    return 0;
}
int testFreeVectorClock(void) {
    printf("========[testFreeVectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock vc = sdsToVectorClock(vcStr);
    freeVectorClock(vc);
    return 0;
}

int testvectorClockToSds(void) {
    printf("========[testvectorClockToSds]==========\r\n");
    sds vcStr = sdsnew("1:123");
    VectorClock vc = newVectorClock(1);
    set_clock_unit_by_index(&vc, 0, init_clock(1, 123));
    sds dup = vectorClockToSds(dupVectorClock(vc));
    printf("expected: %s, actual: %s \r\n", vcStr, dup);
    test_cond("[testvectorClockToSds]", sdscmp(vcStr, dup) == 0);
    freeVectorClock(vc);
    vcStr = sdsnew("1:123;2:234;3:345");
    vc = sdsToVectorClock(vcStr);
    dup = vectorClockToSds(vc);
    printf("expected: %s, actual: %s \r\n", vcStr, dup);
    test_cond("[testvectorClockToSds]", sdscmp(vcStr, dup) == 0);
    freeVectorClock(vc);
    return 0;
}

int testvectorClockToString(void) {
    printf("========[testvectorClockToString]==========\r\n");
    sds vcStr = sdsnew("1:123");
    VectorClock vc = newVectorClock(1);
    set_clock_unit_by_index(&vc, 0, init_clock(1, 123));
    char dup[100];
    size_t len = vectorClockToString(dup, dupVectorClock(vc));
    printf("expected: %s, actual: %s \r\n", vcStr, dup);
    test_cond("[testvectorClockToString]", strcmp(vcStr, dup) == 0);
    test_cond("[testvectorClockToString] len", len == 5);
    test_cond("[testvectorClockToStringLen] len", vectorClockToStringLen(vc) == 5);
    freeVectorClock(vc);
    vcStr = sdsnew("1:123;2:234;3:345");
    vc = sdsToVectorClock(vcStr);
    len = vectorClockToString(dup, vc);
    printf("expected: %s, actual: %s \r\n", vcStr, dup);
    test_cond("[testvectorClockToString]", strcmp(vcStr, dup) == 0);
    test_cond("[testvectorClockToString] len", len == 17);
    test_cond("[testvectorClockToStringLen] len", vectorClockToStringLen(vc) == 17);
    freeVectorClock(vc);
    return 0;
}

int testSortVectorClock(void) {
    printf("========[testSortVectorClock]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock vc = sdsToVectorClock(vcStr);
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
    VectorClock vc = sdsToVectorClock(vcStr);
    test_cond("[testDupVectorClock] length", get_len(vc) == 3);
    test_cond("[testDupVectorClock] gid-1", get_gid(*get_clock_unit_by_index(&vc, 0)) == 1);
    test_cond("[testDupVectorClock] clock-1", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);

    test_cond("[testDupVectorClock] gid-2", get_gid(*get_clock_unit_by_index(&vc, 1)) == 2);
    test_cond("[testDupVectorClock] clock-2", get_logic_clock(*get_clock_unit_by_index(&vc, 1)) == 234);

    test_cond("[testDupVectorClock] gid-3", get_gid(*get_clock_unit_by_index(&vc, 2)) == 3);
    test_cond("[testDupVectorClock] clock-3", get_logic_clock(*get_clock_unit_by_index(&vc, 2)) == 345);

    VectorClock dup = dupVectorClock(vc);
    sds dupSds = vectorClockToSds(dup);

    test_cond("[testDupVectorClock]", sdscmp(vcStr, dupSds) == 0);
    // test_cond("[testDupVectorClock] value", dup != vc);
    freeVectorClock(vc);
    freeVectorClock(dup);

    return 0;
}

int testAddVectorClockUnit(void) {
    printf("========[testAddVectorClockUnit]==========\r\n");
    sds vcStr = sdsnew("1:123;2:234;3:345");
    VectorClock vc = sdsToVectorClock(vcStr);

    vc = addVectorClockUnit(vc, 11, 50);

    printf("result: %s\r\n", vectorClockToSds(vc));
    test_cond("[testAddVectorClockUnit]", sdscmp(sdsnew("1:123;2:234;3:345;11:50"), vectorClockToSds(vc)) == 0);
    return 0;
}

int testNewVectorClock(void) {
    printf("========[testNewVectorClock]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 1);
    vc = newVectorClock(2);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 2);
    vc = newVectorClock(3);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 3);
    return 0;
}

int testfreeVectorClock(void) {
    printf("========[testfreeVectorClock]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 1);
    freeVectorClock(vc);

    vc = newVectorClock(2);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 2);
    freeVectorClock(vc);

    vc = newVectorClock(3);
    test_cond("[testNewVectorClock][length equals]", get_len(vc) == 3);
    freeVectorClock(vc);
    return 0;
}

int test_set_clock_unit_by_index(void) {
    printf("========[test_set_clock_unit_by_index]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 1);
    set_clock_unit_by_index(&vc, 0, init_clock(1, 123));
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 1);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 0)) == 1);
    test_cond("[test_set_clock_unit_by_index][logic time equals-2]", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);
    freeVectorClock(vc);

    printf("========[test_set_clock_unit_by_index] - 2==========\r\n");
    vc = newVectorClock(2);
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 2);
    set_clock_unit_by_index(&vc, 0, init_clock(1, 123));
    set_clock_unit_by_index(&vc, 1, init_clock(2, 234));
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 2);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 0)) == 1);
    test_cond("[test_set_clock_unit_by_index][logic time equals-2]", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);

    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 2);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 1)) == 2);
    test_cond("[test_set_clock_unit_by_index][logic time equals-2]", get_logic_clock(*get_clock_unit_by_index(&vc, 1)) == 234);
    freeVectorClock(vc);

    printf("========[test_set_clock_unit_by_index] - 3==========\r\n");
    vc = newVectorClock(3);
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 3);
    set_clock_unit_by_index(&vc, 0, init_clock(1, 123));
    set_clock_unit_by_index(&vc, 1, init_clock(2, 234));
    set_clock_unit_by_index(&vc, 2, init_clock(3, 567));
    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 3);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 0)) == 1);
    test_cond("[test_set_clock_unit_by_index][logic time equals-3]", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);

    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 3);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 1)) == 2);
    test_cond("[test_set_clock_unit_by_index][logic time equals-3]", get_logic_clock(*get_clock_unit_by_index(&vc, 1)) == 234);

    test_cond("[test_set_clock_unit_by_index][length equals]", get_len(vc) == 3);
    test_cond("[test_set_clock_unit_by_index][gid equals]", get_gid(*get_clock_unit_by_index(&vc, 2)) == 3);
    test_cond("[test_set_clock_unit_by_index][logic time equals-3]", get_logic_clock(*get_clock_unit_by_index(&vc, 2)) == 567);
    freeVectorClock(vc);
    return 0;
}


/*****=============basic tests===============**/
int testGetLength() {
    printf("========[testGetLength]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[testGetLength]", get_len(vc) == 1);

    vc = newVectorClock(2);
    test_cond("[testGetLength]", get_len(vc) == 2);

    vc = newVectorClock(3);
    test_cond("[testGetLength]", get_len(vc) == 3);
    return 0;
}

int testSetLength() {
    printf("========[testSetLength]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[testGetLength]", get_len(vc) == 1);

    set_len(&vc, 2);
    test_cond("[testGetLength]", get_len(vc) == 2);

    set_len(&vc, 3);
    test_cond("[testGetLength]", get_len(vc) == 3);
    return 0;
}

int testIsMulti() {
    printf("========[testIsMulti]==========\r\n");
    VectorClock vc = newVectorClock(1);
    test_cond("[testGetLength]", ismulti(vc) == 0);

    set_len(&vc, 2);
    test_cond("[testGetLength]", ismulti(vc) == 1);

    set_len(&vc, 3);
    test_cond("[testGetLength]", ismulti(vc) == 1);
    return 0;
}

int testGid() {
    printf("========[testGid]==========\r\n");
    VectorClock vc = newVectorClock(1);
    // set_gid(&vc, 10);
    set_gid(get_clock_unit_by_index(&vc, 0), 10);
    test_cond("[testGid-1]", get_gid(*get_clock_unit_by_index(&vc, 0)) == 10);

    vc = newVectorClock(2);
    clk *clock = get_clock_unit_by_index(&vc, 1);
    set_gid(clock, 11);
    test_cond("[testGid-2]", get_gid(*clock) == 11);
    return 0;
}

int testLogicClock() {
    printf("========[testLogicClock]==========\r\n");
    VectorClock vc = newVectorClock(1);
    set_gid(get_clock_unit_by_index(&vc, 0),10);
    // set_gid(&vc, 10);
    set_logic_clock(get_clock_unit_by_index(&vc, 0), 12345);
    test_cond("[testLogicClock-1]", get_gid(*get_clock_unit_by_index(&vc, 0)) == 10);
    test_cond("[testLogicClock-1]", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 12345);

    vc = newVectorClock(2);
    clk *clock = get_clock_unit_by_index(&vc, 1);
    set_gid(clock, 11);
    set_logic_clock(clock, 1234567890l);
    test_cond("[testLogicClock-2]", get_logic_clock(*clock) == 1234567890l);
    return 0;
}

int testIncrLogicClock() {
    printf("========[testIncrLogicClock]==========\r\n");
    VectorClock vc = newVectorClock(1);
    set_gid(get_clock_unit_by_index(&vc, 0), 10);
    set_logic_clock(get_clock_unit_by_index(&vc, 0), 12345);
    test_cond("[testIncrLogicClock-1]gid", get_gid(*get_clock_unit_by_index(&vc, 0)) == 10);
    test_cond("[testIncrLogicClock-1]logic clock", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 12345);
    printf("get_len(*vc) %lld\n",(long long)get_len(vc));
    incrLogicClock(&vc, 10, 1);
    printf("get_len(*vc) %lld\n",(long long)get_len(vc));
    test_cond("[testIncrLogicClock-1]logic clock-2", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 12346);
    incrLogicClock(&vc, 2, 1);
    test_cond("[testIncrLogicClock-1]logic clock-3", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 12346);
    incrLogicClock(&vc, 10, 1);
    test_cond("[testIncrLogicClock-1]logic clock-4", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 12347);

    vc = sdsToVectorClock(sdsnew("1:123;2:456;3:789"));
    incrLogicClock(&vc, 10, 1);
    test_cond("[testIncrLogicClock-2]logic len", get_len(vc) == 3);
    test_cond("[testIncrLogicClock-2]logic clock-1", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);
    test_cond("[testIncrLogicClock-2]logic clock-2", get_logic_clock(*get_clock_unit_by_index(&vc, 1)) == 456);
    test_cond("[testIncrLogicClock-2]logic clock-3", get_logic_clock(*get_clock_unit_by_index(&vc, 2)) == 789);

    incrLogicClock(&vc, 3, 1);
    test_cond("[testIncrLogicClock-2]logic clock-1", get_logic_clock(*get_clock_unit_by_index(&vc, 0)) == 123);
    test_cond("[testIncrLogicClock-2]logic clock-2", get_logic_clock(*get_clock_unit_by_index(&vc, 1)) == 456);
    test_cond("[testIncrLogicClock-2]logic clock-3", get_logic_clock(*get_clock_unit_by_index(&vc, 2)) == 790);
    return 0;
}

/**------------------------Vector Clock Merge--------------------------------------*/

int testMergeLogicClock(void) {
    printf("========[testMergeLogicClock]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    VectorClock vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    VectorClock vc2 = sdsToVectorClock(sdsnew("1:200;2:500;3:100"));
    mergeLogicClock(&vc, &vc2, 1);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    //second, dst is covering every little corner of src
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    vc2 = sdsToVectorClock(sdsnew("1:200"));
    mergeLogicClock(&vc, &vc2, 1);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    vc2 = sdsToVectorClock(sdsnew("2:500"));
    mergeLogicClock(&vc, &vc2, 2);
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:100"));
    vc2 = sdsToVectorClock(sdsnew("2:500;3:100;5:100"));
    mergeLogicClock(&vc, &vc2, 3);
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:100;3:100"), vectorClockToSds(vc)) == 0);

    //forth, dst is diff with src, but they are all single
    vc = sdsToVectorClock(sdsnew("2:500"));
    vc2 = sdsToVectorClock(sdsnew("1:500"));
    mergeLogicClock(&vc, &vc2, 1);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:500;2:500"), vectorClockToSds(vc)) == 0);

    //fifth, dst is inserting into src
    vc = sdsToVectorClock(sdsnew("1:100;3:300"));
    vc2 = sdsToVectorClock(sdsnew("2:500"));
    mergeLogicClock(&vc, &vc2, 2);
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    return 0;
}


int testMergeMinVectorClock(void) {
     printf("========[testMergeMinVectorClock]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    VectorClock vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    VectorClock new_vc = mergeMinVectorClock(vc, sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
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
    printf("[result]%s\n", vectorClockToSds(new_vc));
    test_cond("[testvectorClockMerge][merge-only-6]", sdscmp(sdsnew("1:100;2:0"), vectorClockToSds(new_vc)) == 0);
    freeVectorClock(vc);
    freeVectorClock(new_vc);
    return 0;
}

int testGetMonoVectorClock(void) {
    printf("========[testGetMonoVectorClock]==========\r\n");
    VectorClock vc = sdsToVectorClock(sdsnew("1:123;3:300"));
    VectorClock new_vc = getMonoVectorClock(vc, 1);
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("1:123"), vectorClockToSds(new_vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:123;2:234;3:300"));
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("2:234"), vectorClockToSds(getMonoVectorClock(vc, 2))) == 0);

    vc = sdsToVectorClock(sdsnew("1:123;2:234;3:300;4:456;5:567"));
    test_cond("[testGetMonoVectorClock]", sdscmp(sdsnew("4:456"), vectorClockToSds(getMonoVectorClock(vc, 4))) == 0);

    return 0;
}

int testIsVectorClockMonoIncr(void) {
    printf("========[testIsVectorClockMonoIncr][multi]==========\r\n");
    VectorClock current = sdsToVectorClock(sdsnew("1:123;3:300"));
    VectorClock future = sdsToVectorClock(sdsnew("1:123;3:299"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 0);

    current = sdsToVectorClock(sdsnew("1:123;3:300"));
    future = sdsToVectorClock(sdsnew("1:123;3:301"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 1);

    current = sdsToVectorClock(sdsnew("1:123"));
    future = sdsToVectorClock(sdsnew("1:123;3:301"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 1);

    printf("========[testIsVectorClockMonoIncr][single]==========\r\n");

    current = sdsToVectorClock(sdsnew("1:123"));
    future = sdsToVectorClock(sdsnew("1:123"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 1);

    current = sdsToVectorClock(sdsnew("2:123"));
    future = sdsToVectorClock(sdsnew("1:123"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 0);

    current = sdsToVectorClock(sdsnew("1:345"));
    future = sdsToVectorClock(sdsnew("1:123"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 0);

    current = sdsToVectorClock(sdsnew("1:123"));
    future = sdsToVectorClock(sdsnew("1:345"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 1);


    printf("========[testIsVectorClockMonoIncr][un-aligned]==========\r\n");
    current = sdsToVectorClock(sdsnew("1:123"));
    future = sdsToVectorClock(sdsnew("1:123;3:301"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 1);

    current = sdsToVectorClock(sdsnew("1:123;3:301"));
    future = sdsToVectorClock(sdsnew("1:123"));
    test_cond("[testGetMonoVectorClock]", isVectorClockMonoIncr(current, future) == 0);

    return 0;
}

int testVectorClockMerge(void) {
    printf("========[testVectorClockMerge]==========\r\n");
    VectorClock vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:500;3:300"), vectorClockToSds(vc)) == 0);

    vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:99")));
    printf("%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][add]", sdscmp(sdsnew("1:100;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = vectorClockMerge(sdsToVectorClock(sdsnew("1:100;2:200;3:300")), sdsToVectorClock(sdsnew("1:200;3:100;4:400")));
    printf("%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][add-merge]", sdscmp(sdsnew("1:200;2:200;3:300;4:400"), vectorClockToSds(vc)) == 0);

    printf("========[testVectorClockMerge-2]==========\r\n");
    //first, we have equvlent src and dst, just 1 vcu merge
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("1:200;2:500;3:100")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //second, dst is covering every little corner of src
    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("1:200")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(vc)) == 0);

    vc = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("2:500")));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:100"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("2:500;3:100;5:100")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:100;2:500;3:100;5:100"), vectorClockToSds(vc)) == 0);

    //third, dst is diff with src
    vc = sdsToVectorClock(sdsnew("1:113"));
    VectorClock v2 = sdsToVectorClock(sdsnew("2:110;1:111"));
    vc = vectorClockMerge(vc, v2);

    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:113;2:110"), vectorClockToSds(vc)) == 0);


    //forth, dst is diff with src, but they are all single
    vc = sdsToVectorClock(sdsnew("2:500"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("1:500")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][new-income]", sdscmp(sdsnew("1:500;2:500"), vectorClockToSds(vc)) == 0);

    //fifth, dst is inserting into src
    vc = sdsToVectorClock(sdsnew("1:100;3:300"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("2:500")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:100;2:500;3:300"), vectorClockToSds(vc)) == 0);

    //sixth, dst/src is single and same
    vc = sdsToVectorClock(sdsnew("1:100"));
    vc = vectorClockMerge(vc, sdsToVectorClock(sdsnew("1:500")));
    printf("[result]%s\n", vectorClockToSds(vc));
    test_cond("[testvectorClockMerge][merge-only]", sdscmp(sdsnew("1:500"), vectorClockToSds(vc)) == 0);

    return 0;
}

int testUpdateProcessVectorClock(void) {
    printf("========[testUpdateProcessVectorClock]==========\r\n");
    VectorClock iam = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    VectorClock other = sdsToVectorClock(sdsnew("1:200;2:199;3:100"));
    updateProcessVectorClock(&iam, &other, 2, 2);
    printf("%s\n", vectorClockToSds(iam));
    test_cond("[testvectorClockMerge][iam-update-myself]", sdscmp(sdsnew("1:100;2:199;3:300"), vectorClockToSds(iam)) == 0);

    printf("========[testUpdateProcessVectorClock-2]==========\r\n");
    iam = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    other = sdsToVectorClock(sdsnew("1:200;2:199;3:100"));
    updateProcessVectorClock(&iam, &other, 3, 2);
    printf("%s\n", vectorClockToSds(iam));
    test_cond("[testvectorClockMerge][iam-update-myself]", sdscmp(sdsnew("1:100;2:200;3:300"), vectorClockToSds(iam)) == 0);

    printf("========[testUpdateProcessVectorClock-3]==========\r\n");
    iam = sdsToVectorClock(sdsnew("1:100"));
    other = sdsToVectorClock(sdsnew("1:200;2:199;3:100"));
    updateProcessVectorClock(&iam, &other, 3, 1);
    printf("%s\n", vectorClockToSds(iam));
    test_cond("[testvectorClockMerge][iam-update-myself]", sdscmp(sdsnew("1:100;3:100"), vectorClockToSds(iam)) == 0);

    printf("========[testUpdateProcessVectorClock-4]==========\r\n");
    iam = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    other = sdsToVectorClock(sdsnew("1:200"));
    updateProcessVectorClock(&iam, &other, 1, 2);
    printf("%s\n", vectorClockToSds(iam));
    test_cond("[testvectorClockMerge][iam-update-myself]", sdscmp(sdsnew("1:200;2:200;3:300"), vectorClockToSds(iam)) == 0);
    return 0;
}
int testPurgeVectorClock(void) {
    printf("========[testPurgeVectorClock]==========\r\n");
    VectorClock iam = sdsToVectorClock(sdsnew("1:100;2:200;3:300"));
    VectorClock other = sdsToVectorClock(sdsnew("1:200;2:199;3:100"));
    VectorClock r = purgeVectorClock(iam, other);
    test_cond("[testPurgeVectorClock][iam]", sdscmp(sdsnew("2:200;3:300"), vectorClockToSds(r)) == 0);
    printf("========[testPurgeVectorClock-2]==========\r\n");
    iam = sdsToVectorClock(sdsnew("1:100"));
    other = sdsToVectorClock(sdsnew("1:200"));
    r = purgeVectorClock(iam, other);
    test_cond("[testPurgeVectorClock][iam]", sdscmp(sdsnew(""), vectorClockToSds(r)) == 0);
    printf("========[testPurgeVectorClock-3]==========\r\n");
    iam = sdsToVectorClock(sdsnew("1:200"));
    other = sdsToVectorClock(sdsnew("1:100"));
    r = purgeVectorClock(iam, other);
    test_cond("[testPurgeVectorClock][iam]", sdscmp(sdsnew("1:200"), vectorClockToSds(r)) == 0);
}
int vectorClockTest(void) {
    int result = 0;
    {
        result |= testGetLength();
        result |= testSetLength();
        result |= testIsMulti();
        result |= testGid();
        result |= testLogicClock();
        result |= test_set_clock_unit_by_index();

        result |= testSdsConvert2VectorClockUnit();
        result |= testSdsConvert2VectorClock();
        result |= testStringConvert2VectorClockUnit();
        result |= testStringConvert2VectorClock();
        result |= testDupVectorClock();
        result |= testAddVectorClockUnit();
        result |= testvectorClockToSds();
        result |= testvectorClockToString();

        result |= testNewVectorClock();
        result |= testfreeVectorClock();
        result |= testFreeVectorClock();

        result |= testSortVectorClock();
        result |= testIncrLogicClock();

        result |= testMergeLogicClock();
        result |= testMergeMinVectorClock();
        result |= testGetMonoVectorClock();
        result |= testIsVectorClockMonoIncr();
        result |= testVectorClockMerge();
        result |= testUpdateProcessVectorClock();
        result |= testPurgeVectorClock();
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
