## Counter类型

#### 支持 API

| Redis API   | 目前进度 |
| :---------- | :------- |
| incrby      | **DONE** |
| incrbyfloat | **DONE** |
| incr        | **DONE** |
| decr        | **DONE** |
| set         | **DONE** |
| get         | **DONE** |
| mset        | **DONE** |
| mget        | **DONE** |

1. 支持数据类型
   1. String类型 
   2. INT (确定范围)
   3. FLOAT (确定范围)

#### CRDT API

| CRDT API     | 目前进度 | API 使用场景                         | 参数                                                         | 例子                                                         |
| :----------- | :------- | :----------------------------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| CRDT.Counter | **DONE** | Counter执行incrby等命令时发送的命令  | `CRDT.COUNTER <key> <gid> <timespace> <vectorClock> <type> <value_type:value>` | `incrby key 1CRDT.COUNTER key 1 10000 1:1  0  1:1type是用来区分执行命令是incrbyfloat还是incrby的value里前面的1表示类型为long long后面的1表示值` |
| CRDT.RC      | **DONE** | Counter 执行set命令时发送 的同步命令 | `CRDT.RC  <gid> <timespace> <vectorClock>  [<key> <type:value ,gid:vcu:type:value_>]... `| `set k 2CRDT.RC  2  10000 2:1;1:1  key 1:2,1:2:1:1 1:2,1:2:1:1中前面的1:2表示set执行数据类型是long long 值为21:2:1:1表示的是gid为1,vcu为2的删除的counter类型是long long 值为1为什么设计上会把这2个数据写在一个里面呢？由于要兼容mset所以 key后面只有一个数据解析上去判断是否有counter而redis企业版是通过 先通过一个参数来告诉你有几个参数然后再发送 值和counter类似与 2 1:2 1:2:1:1个人认为没必要分那么多参数增加发送的字节数（由于redis协议发送一个2 就多出$1\r\n2\r\n   如果发送参数多的话就会浪费更多字节以及创建更多的robj对象)` |
| CRDT.RC_DEL  | **DONE** | counter删除时执行的命令              | `crdt.rc_del <gid> <timespace> <vectorClock>  <fieldtype:fieldlen:fieldvalue,gid:vcu:type:value>` | `del kcrdt.rc_del 1 1000 1:2;2:1  3:1:k,1:2:1:13:1:k  3表示类型是sds,1表示长度是1, k是值1:2:1:1就是要删除的counter的数据可以看CRDT.RC内的解释 `|

#### 实现上需要注意的一些细节

1. set 保存的基础值是字符串 所以存入什么数据就可以取出什么数据。

2. 由于redis是支持在1.1+1.9 = 3 之后再使用incrby的   （我们这里也需要支持)

3. |      | A                 | B                 | C          |
   | :--- | :---------------- | :---------------- | :--------- |
   | t1   | incrbyfloat k 1.1 |                   |            |
   | t2   |                   | incrbyfloat k 1.9 |            |
   |      | 同步              |                   |            |
   | t3   |                   |                   | incrby k 2 |
   |      | 同步              |                   |            |
   |      | get k = 5         | get k = 5         | get k = 5  |

4. incrby的get之后值的上下限（LLONG_MIN/16- LLONG_MAX/16)  为了确保多个机房总和不超过LLONG_MAX和LLONG_MIN   (redis企业版的值是小于LLONG_MAX/16的具体的上限还没测）

   1. 可能存在add_counter > LLONG_MAX/16的情况  但是add_counter是不能超过LLONG_MAX的    （比如 add_counter 值  LLONG_MAX   而del_counter是LLONG_MAX-1是存在的,  用户get的时候显示的1,但是用户再执行incrby会失败） 

5. incrbyfloat （1.1+1.9 = 3）虽然返回是3且可执行incrby 但保存的是long double. （不然还要做long double数据类型转到int数据类型逻辑以及add, delete counter 类型不同）

6. 关于mset命令对于2个数据类型的处理 

   1. 先过滤相同key的操作  只执行最后设置key的数据  （避免在b操作时同一个key存在于2个类型中)
      1. 和执行2次set的区别  比如（mset k 1 k a) 最终是register数据类型,  如果set k 1  然后set k a  那么最终数据结构是counter
   2. 检查所有key对应的value是否为register,counter或者空,并分类register和counter2类
   3. 分别处理register和counter2类,最多发送2条命令给peer(crdt.mset 和crdt.mset_rc)

#### 还存在的问题

1. ##### 不支持和老的register数据转换以及协议互通,

用户效果 

|      | A       | B       |
| :--- | :------ | :------ |
| t1   | set k a | set k 1 |
|      | 同步    |         |
|      | k = a   | k = 1   |

原因: 假设可以支持类型转换

|      | A                                                            | B                                                            | C                                   |
| :--- | :----------------------------------------------------------- | :----------------------------------------------------------- | :---------------------------------- |
| t1   | set k a (register)1:1                                        | set k b (register)2:1                                        | set  k 1 (counter)3:1               |
|      | 同步                                                         |                                                              |                                     |
|      | 如果先收到B的消息lww判断出最后的可能就是A:a (1:1)B:null (2:1)C:1（3:1) | 同理 先收到A,虽然用户查询的结果是一致的但是保存的数据不一致（还没想到什么场景可能引发不一致,但是并无法确保没问题) | A:  a (1:1)B:  b (2:1)C:  1 （3:1） |