# incr命令


|  环境     |   3次采样    | 平均qps|
| ----  | ----  | ---- |
|  普通redis     |  117455 <br> 130996 <br> 110182   |  119544     |
|  普通redis + 2个slave     |  105171 <br> 98535 <br> 100405   |   101370    |
|  企业版双向同步redis(3个机房相互连接 没有slave)    | 102816 <br> 93378 <br> 102742    |  99645     |
|  单个双向同步redis     |  97098 <br> 92310 <br> 101847    |  97085     |
|  双向同步redis(3个机房相互连接 没有slave)    |  89106 <br> 85651 <br> 76065    |   83607    |