单个机房时string类型 

|  场景   | 数据结构占用  | 具体 |  
|  ----  | ----  | ---- |  
| 普通redis	| 16	| robj(16) | 
| 双向同步（lww) 单个机房 |	56| robj(16) + moduleValue(16) + 最终数据结构24( type(0.5) + gid (0.5)+ time(7)+vc(8) + value*(8)) | 
| 双向同步（lww) 多机房	| 56 + n*8	| vcu(8) * n |