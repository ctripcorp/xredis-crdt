proc print_log_file {log} {
    set fp [open $log r]
    set content [read $fp]
    close $fp
    puts $content
}

set uname_M [exec uname -m]
set uname_S [exec uname -s]
#defulat （long double 128）
set max_float 1.1897314953572318e+4932
set half_max_float_str 1.1897314953572318e+4931
# half_max_float_str eq half_max_float 
set half_max_float 118973149535723180001005827942350234012095372731779929049078861666869832222375384889889082666164158875512947276647015718952408664750174163564465060849681379712214346073163488192524425337214446999491753215668529536754662235087400444524043813368055398420406950064788728293009887127925587587039585003059882192560088750969096330913993922236808687739828795930499635386282172686553360719933031340693660342864149184590169467689164608668720231866360483407911277612381170033864848117017527069650236372993194637384931483211388324484730185758910764816788607679058412097887842509439195096470068477268107590609025980924846418650936748999034978845140419504909119290571288114206428388205350587630836969842951198742846803643147154235787223030438031927311168420728453570594218589722956794841698366981645283567414604017097024978924895437061676614807950293690216327095380720076044413911424013062859309635463075305972297039297208521890008970567912756070121867791827916302183350022147268972630521634340298350470955677258024956506093004731857699910393695186051813191415961669416420857356031265150565340471023103910034708702337524108134197862013590497129399865293359851745786358130321559643852740370661651276027379133111515016456131825416829066331915461476189717319460357129240223167121016745123592373072207948231491771339275964328830399298903795914370030196463122870338582566087121068109668031755880469121016578695236563829125082016624109705193614153824902595237230250461314480296438584883832244685622239959870400617938288648875505371393713522707223329656003664693198976235662907328968662150643682349238796026153068763747587366129574352012135804746519618261300305802125689980557953831033118049529256540557007252141587297479736568787767016129615961982992252899989893580092415941139571458946916577828388557392157122684340140986757220044032417375025573726314575117067828245570295025326694533873854713116060689195131583549739249248266814087395849856461514461274523790781843002813011536375256818001908829366454330284117930721095057904409050634630295938281854999289080679167342369779529080772612072896219708746836803963229776429020521026755067518177695794795811795028012874273698697046423054654730261208399153738091738880828893318617959901923797537193274312220763256445344192478760594887442447353804304624737386290791223607752671123535113827837369689580157124917289603700983823592170920127300331532179941601007882623058111545758048304819434276377082211403305761676653553003943935384209086983032887075878206423938097835892053621912468470040172280382889496904339193343882243325671621698312696228608066011486699345925564591137264038982862857209237425019479886412639795434887853248235319419678207574249978908276110364694864753385741034014507644555079723411820872725381050793910131955667938167191670928135542486230015923417548436191821235697693217586291137053660795632435085981781813743207569876205525871706323883913042404638663688406019563510393557341645764385538711364163851899899619645633874845655285972615710730240542059328520551757347082051272696241863534150711255998843988342918013121848346096919877828692769143690313553583589685969129171363947306563871130503769231840068060954543899538030965910741602910763537527022135738348550200995096942129035369985288212198809627018177032303752664439720607642664768329278328079120054031119665843423678782506360942826117246203219917344853975990452976491170375284659027697376899171015541696451133092499438484713331409761780078149435378706042055896821135984135868923043140418827351481457906568732284912427673236159177747019263496868490918465313233499247042918911161440744145019560187168549268507321408608141610973036131576906872502508982044752857993051470937150468285390090108451818839137675000132206482109140252667856007321738604448379334828470404810072543676082387475074895228869727898843346632384079858647481691429564626169392870101295241956490384990834767748220134878593534201387416852656633520840654622980332774151572516424660451268897344065395244221755809447146790464586583814269921233522158669548674604355141125302219839620539556324050805080204409038825097576119627820314691914729479295486928213171352348219563396715453409644316190469145386616271881654692728381592858020543812990374004023436412853518109798860983800971491713974350204715091109840593937479899101323691124426890076763034858295118317419492315572424108290454599051829143939172438608496523567786003490303303394315978893791120961380818834968590913516222285814072622439389758816408352521526779351831378001958663628837424749279227699987770974886410044918863259770275494170652530619220200749826005209824362507577661470195237867025936680634500391447172041674877465056687624848589524027198003927381776196420485467173082160213434424281734865362845346266555228398081620131720986503041305985073978470717681938539403591345619480788129471865964356516405523960044276714541825283209241488796699826371583106089693261207072159471136443213098064940849932485017976304566272
if {$uname_S eq "Darwin"} {
    if {$uname_M eq "arm64"} {
        # long double (64)
        set max_float 1.7976931348623157e+308
        # 1.7976931348623157e+307
        set half_max_float_str 1.7976931348623157e+307
        set half_max_float 17976931348623157580412819756850388593900235011794141176754562789180111453639664485361928830517704263393537268510363518759043843737070229269956251768752166883397940628862983287625967246810352023792017211936260189893797509826303293149283469713429932049693599732425511693654044437030940398714664210204414967808
        # set half_max_float 179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368
    }
} elseif {$uname_S eq "Linux"} {
    # long double（128）
    if {$uname_M eq "aarch64"} {
        #arm
        set half_max_float 118973149535723180000000000000000001288872647151514646154330733881622356518468028364817053411982300652397094364292284952038157411354382407614051575098146205352487825628708090262720617454663401580082639239762990248627621838390145415188448880513599399836634918787133538485407784746430934793089675737086530069343982680780455234150999446029892743143015986268721984323013494635780427843447172247403616211266527527876430541774869994478216623028778800194078795623687060380644066071089891901127773759105586754966277762334846106977374150397179791503322192178353679200359961794706469577075313143382585998612354791348689318065308897240599379766377747565498317698698496991927162945408522194153515825458859922348355495632002945884362612893919502378149251721008440804934597234173458178451583478452253757362635171755428549122085354102023457722408273394449002500272724320583351198456575630016187620376817858872526372072369001079593803189605214230039455891789031796711415366738168881729127071274728284647557009755085279097918681445658016198686349706905925339220989538803558151411601634298882308148344455370426116800536160206725343835358686265740788864139471176663965344824231193857312243584010817518402245833997527414941662213963286333120379500346261641722771241618048939334912908177900147805990848235730053215043041568317185735383056265281214627767724923277794061682483867699547958831530906386555416358874688265103356623256264640578936573196722508893593193209198668940828467789745631693357873170782241504137554042829905427128400748906740124986829011930762450780216556027490510304452851900697855221314528617270923979186160654613936714304518417116334742205342755157955803969864574509934996767844881782054557366248694049951081846210893887193230222921737798225325439770631763284425480364376041129099646078319195050902125930879310920875492997451908313376808567201835472997122976610944182067798565527545595887528938799752158519331980525055843116077470701325985625608495393989409651280656053099541828323398129619481667128272594063605587975089544638262321160180022650805898631113835259790127636125289833732319275456264895860557681453001196578447199808677909670742510358015975772199461886127396385428620881118129709736460728081189773173918899480835983418081282928670417417953833589793280842389967849549144863086572256601586428766665883740248452492641332062545340487294375808405717445293677745284857739609270732395721582364187291974783367397362846056215406703013672212984149883289187209773996335220461414875293868044133647888092569502381892308082901464073884423599699578725644314222677860013184447916819700641066477035799168347854704694127159154566621070476898648783813154299893513778616522750755245613630721505938658671820961618032594867512126249587483882119765551493400615674602656431472405108817354099057328551599731511674897146197805439411020243403272513399085345261818007702865417823534309803524962261206248522826896208007811230138569324927417163132142901708267885784965469678341837312919264755911349833285295349377179472613481148569853573920776820186287044645659160179687807609996520360311472366147279777845962359900021518927535593180836318311186158979972788959429544990931845865583662882335468107211228006273090049464731741923274029090017867546343829387195930059945236429200776911586880645801033131079924786951050623604098485946211315123590429049374532921553836252129704966537521643002181767147450864675185813762766723509360400517288401294737121924857656797801798440882650058022743579593090797102130948012111132459717373157908951557413762339745617234487539531386851059629602535303169100856976430705749668310033049722681437017415763268494610321494899442827375432746551548870744961783512614717499912246483899620962674024138981933660751872088049354679848504990982311516413749955036510886295358049906872898453331621886909355800902303530556086440955598873471747773999278993549459527536177752189546087836843785397394212220744934381194934223839378048953666423152429841168640303760828063710179479653530627306145336293553246136313002341039788187106262953453746791487073460005771277053468434566985327932220916601414136953559897628159341204109158911433638436517971431989195950195618396866971263069473810859726450715543641410564384233061238308723484670592273837059964738155782068103099540671956552152197885047948431708505926198673793145228975840244564910673042143417654457244720367241899620718008456514298099772104412389768196756272502311874476044484408961233403198645712167339353040669272230216874795183773710105842975357591159543071403812522917136740771466073552320206988637738516933448172971342411759844439904118850910500326902132909421818159735645965626040619526719000017448504676393401998069934375997657741931443097654081039887289563611530052487419134602940585976227951731758965208013675201316481267272723925163968032114343439312924742267986382180477516962098199146080557547005522425982848559148769624953172717272494495728211120643797125582974909604788436992
    } 
}
set min_float -$max_float

start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
    set master [srv 0 client]
    # set master [redis "127.0.0.1" 6679]
    set master_gid 1
    set master_host [srv 0 host]
    set master_port [srv 0 port]
    set master_log [srv 0 stdout]
    $master config crdt.set repl-diskless-sync-delay 1
    $master config set repl-diskless-sync-delay 1
    $master crdt.debug_gc rc 0
    test "incrby or incrbyfloat max" {
        test "max" {
            test "incrby max + 1" {
                $master set incrby_max1 576460752303423486
                $master incrby incrby_max1 1
                assert_equal [ $master get incrby_max1] 576460752303423487
                catch {$master incrby incrby_max1 1} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_max1] 576460752303423487
                catch { $master incr incrby_max1 } error
                assert_match "ERR increment or decrement would overflow" $error
                $master decr incrby_max1 
                assert_equal [ $master get incrby_max1] 576460752303423486
            }
            test "incrby 1 + max" {
                $master set incrby_max2 1
                catch {$master incrby incrby_max2 576460752303423487} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_max2] 1
                $master incrby incrby_max2 576460752303423486
                assert_equal [ $master get incrby_max2] 576460752303423487

                catch { $master incr incrby_max2 } error
                assert_match "ERR increment or decrement would overflow" $error
                $master incrby incrby_max2 -1 
                assert_equal [ $master get incrby_max2] 576460752303423486
            }

            test "incrby + max" {
                catch {$master incrby incrby_max3  576460752303423488} error
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_max3] {}
                $master incrby incrby_max3  576460752303423487
                assert_equal [ $master get incrby_max3] 576460752303423487

                catch { $master incr incrby_max3 } error
                assert_match "ERR increment or decrement would overflow" $error
                $master incrby incrby_max3 -1 
                assert_equal [ $master get incrby_max3] 576460752303423486
            
            }


        }
        test "incrby min" {
            test "incrby min - 1" {
                $master set incrby_min1 -576460752303423487
                $master incrby incrby_min1 -1
                assert_equal [ $master get incrby_min1] -576460752303423488
                catch {$master incrby incrby_min1 -1} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min1] -576460752303423488

                catch {$master decr incrby_min1} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min1] -576460752303423488
                $master incr incrby_min1
                assert_equal [ $master get incrby_min1] -576460752303423487
            }
            
            test "incrby - 1 - min " {
                $master set incrby_min2 -1
                catch {$master incrby incrby_min2 -576460752303423488} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min2] -1
                $master incrby incrby_min2 -576460752303423487
                assert_equal [ $master get incrby_min2] -576460752303423488

                catch {$master decr incrby_min2} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min2] -576460752303423488
                $master incrby incrby_min2 1
                assert_equal [ $master get incrby_min2] -576460752303423487 
            }
            test "incrby min " {
                catch {$master incrby incrby_min3 -576460752303423489} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min3] {}
                $master incrby incrby_min3 -576460752303423488
                assert_equal [ $master get incrby_min3] -576460752303423488

                catch {$master decr incrby_min3} error 
                assert_match "ERR increment or decrement would overflow" $error
                assert_equal [ $master get incrby_min3] -576460752303423488
                $master incrby incrby_min3 1
                assert_equal [ $master get incrby_min3] -576460752303423487 
            }
        }
        
        test "max2" {
            for {set j 0} {$j < 16} {incr j} {
                $master incrby incrby_max20 576460752303423487
                $master del incrby_max20 
            }
            $master incrby incrby_max20 15
            $master del incrby_max20 
            assert_equal [$master get incrby_max20] {}
            catch {$master incrby incrby_max20 1} error
            assert_match "ERR increment or decrement would overflow" $error
            $master incrby incrby_max20 -1
            # puts [$master crdt.datainfo incrby_max20]
            assert_equal [ $master get incrby_max20] -1
        }

        test "min2" {
            for {set j 0} {$j < 16} {incr j} {
                $master incrby incrby_min20 -576460752303423488
                $master del incrby_min20 
            }
            # puts [$master crdt.datainfo incrby_min20]
            assert_equal [$master get incrby_min20] {}
            catch {$master incrby incrby_min20 -1} error
            assert_match "ERR increment or decrement would overflow" $error
            $master incrby incrby_min20 1
            assert_equal [$master get incrby_min20] 1
        }

        test "float  min value" {
            $master set float_min_value "4.9E-324"
            $master incrbyfloat float_min_value 1
            assert_equal [$master get float_min_value ] 1


            $master set float_min_value2 0
            $master incrbyfloat float_min_value2 "4.9E-324"
            assert_equal [$master get float_min_value2 ] 0

        }
        if {$uname_M ne "arm64"} {
            test "max float + incrbyfloat" {
                $master set max_float 1
                $master set max_float $max_float
                catch {$master incrbyfloat max_float 1 } error
                assert_match "ERR value is not a valid float" $error
                catch {$master incrby max_float 1} error 
                assert_match "ERR value is not an integer or out of range" $error
                
                

                $master set max_float2 1.1
                catch {$master incrbyfloat max_float2 $max_float } error
                assert_match  "ERR value is not a valid float" $error
                assert_equal [$master incrbyfloat max_float2 $half_max_float_str] $half_max_float
                catch {$master incrby max_float2 1} error 
                assert_match "ERR value is not an integer or out of range" $error
            }

            test "min float" {
                $master set min_float -1
                $master set min_float $min_float
                catch {$master incrbyfloat min_float -1 } error
                assert_match "ERR value is not a valid float" $error
                catch {$master incrby min_float -1} error 
                assert_match "ERR value is not an integer or out of range" $error

                $master set min_float2 -1
                catch {$master incrbyfloat min_float2 $min_float } error
                assert_match "ERR value is not a valid float" $error
                assert_equal [$master incrbyfloat min_float2 -$half_max_float_str] -$half_max_float
                catch {$master incrby min_float2 -1} error 
                assert_match "ERR value is not an integer or out of range" $error
            }
        }
        
        
        test "float + incrbyfloat 1" {
            $master set max_float20 $half_max_float_str
            assert_equal [$master incrbyfloat max_float20 1 ] $half_max_float
            assert_equal [$master get max_float20] $half_max_float
        }
        test "float + incrbyfloat " {
            $master set max_float30 1
            assert_equal [$master incrbyfloat max_float30 $half_max_float_str] $half_max_float
        }

        test "float  incrbyfloat2 1" {
            $master set max_float40 $half_max_float
            assert_equal [$master incrbyfloat max_float40 1 ] $half_max_float
            assert_equal [$master get max_float40] $half_max_float
        }
        test "float  incrbyfloat2 " {
            $master set max_float50 1
            $master incrbyfloat max_float50 $half_max_float 
        }
        test "string + incrby" {
            $master set str_incrby 1
            $master set str_incrby "abc"
            catch {$master incrby  str_incrby 1 } error
            puts $error
        }
        test "string + incrbyfloat" {
            $master set str_incrbyfloat 1
            $master set str_incrbyfloat "abc"
            catch {$master incrbyfloat str_incrbyfloat 1 } error
            puts $error
        }   
             
    }
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        # set peer_port "6679"
        # set peer [redis $peer_host $peer_port]
        $peer select 9
        set peer_log [srv 0 stdout]
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer crdt.debug_gc rc 0
        $peer peerof $master_gid $master_host $master_port
        $master peerof $peer_gid $peer_host $peer_port 
        wait_for_peer_sync $peer 
        wait_for_peer_sync $master 
        test "test float" {
            $master set peer_float 1
            $peer set peer_float 1
            $master incrbyfloat peer_float $half_max_float_str
            $peer incrbyfloat peer_float $half_max_float_str
            after 1000
            assert_equal [$master get peer_float] [$peer get peer_float]
            assert {[$master get peer_float]  != {}}
        }
    }
    test "incrbyfloat + incrby" {
        test "incrbyfloat 1.1 + 1.9 = 3" {
            $master incrbyfloat incrbyfloat2int 1.1
            $master incrbyfloat incrbyfloat2int 1.9
            assert_equal [ $master get incrbyfloat2int] 3
            $master incrby incrbyfloat2int 1
            assert_equal [ $master get incrbyfloat2int] 4
        }
        
    }
    start_server {tags {"crdt-set"} overrides {crdt-gid 2} config {crdt.conf} module {crdt.so} } {
        set peer [srv 0 client]
        set peer_gid 2
        set peer_host [srv 0 host]
        set peer_port [srv 0 port]
        $peer config crdt.set repl-diskless-sync-delay 1
        $peer config set repl-diskless-sync-delay 1
        $peer peerof $master_gid $master_host $master_port
        $peer crdt.debug_gc rc 0
        wait_for_peer_sync $peer
        test "command" {
            test "before" {
                test "set" {
                    test "set " {
                        $master set kv1000 1.0 
                    }
                    test "set + set" {
                        $master set kv1010 1.0   
                        $master set kv1010 3.0 
                    }
                    test " incrbyfloat + set" {
                        $master  incrbyfloat kv1020 1.0   
                        $master set kv1020 3.0  
                    }
                    test "del + set" {
                        test "del(set) + set" {
                            $master set kv1030 1.0   
                            $master del kv1030  
                            $master set kv1030 2.0 
                        }
                        test "del( incrbyfloat) + set" {
                            $master  incrbyfloat kv1031 1.0   
                            $master del kv1031  
                            $master set kv1031 2.0 
                        }
                        test "del(set +  incrbyfloat) + set" {
                            $master set kv1032 1.0  
                            $master  incrbyfloat kv1032 1.0   
                            $master del kv1032  
                            $master set kv1032 2.0 
                        }
                        
                    }
                    
                }
                test " incrbyfloat" {
                    test " incrbyfloat " {
                        $master  incrbyfloat kv1100 1.0  
                    }
                    test " incrbyfloat +  incrbyfloat" {
                        $master  incrbyfloat kv1110 1.0 
                        $master  incrbyfloat kv1110 2.0 
                    }
                    test "set +  incrbyfloat" {
                        $master set kv1120 3.0  
                        $master  incrbyfloat kv1120 1.0  
                    }
                    test "del +  incrbyfloat" {
                        test "del(set) +  incrbyfloat" {
                            $master set kv1130 1.0   
                            $master del kv1130  
                            $master  incrbyfloat kv1130 2.0 
                        }
                        test "del( incrbyfloat) +  incrbyfloat" {
                            $master  incrbyfloat kv1131 1.0   
                            $master del kv1131  
                            $master  incrbyfloat kv1131 2.0 
                        }
                        test "del(set +  incrbyfloat) +  incrbyfloat" {
                            $master set kv1132 1.0  
                            $master  incrbyfloat kv1132 1.0   
                            $master del kv1132  
                            $master  incrbyfloat kv1132 2.0 
                        }
                    }
                    
                }
                test "del" {
                    test "del (set)" {
                        $master set kv1200 1.0 
                        $master del kv1200 
                    }
                    test "del ( incrbyfloat)" {
                        $master  incrbyfloat kv1201 1.0 
                        $master del kv1201 
                    }
                    test "del (set + zincby)" {
                        $master  incrbyfloat kv1202 1.0 
                        $master del kv1202 
                    }
                }

                test "max" {
                    for {set j 0} {$j < 16} {incr j} {
                        $master incrby peer_incrby_max 576460752303423487
                        $master del peer_incrby_max 
                    }
                    for {set j 0} {$j < 16} {incr j} {
                        $peer incrby peer_incrby_max 576460752303423487
                        $peer del peer_incrby_max 
                    }
                    $master incrby peer_incrby_max 15
                    $master del peer_incrby_max 
                    $peer incrby peer_incrby_max 15
                    $peer del peer_incrby_max
                    $master incrby peer_incrby_max -1
                    $peer incrby peer_incrby_max -1
                }
                test "min" {
                    for {set j 0} {$j < 16} {incr j} {
                        $master incrby peer_incrby_min -576460752303423488
                        $master del peer_incrby_min 
                    }
                    for {set j 0} {$j < 16} {incr j} {
                        $peer incrby peer_incrby_min -576460752303423488
                        $peer del peer_incrby_min 
                    }
                    $master incrby peer_incrby_min 1
                    $peer incrby peer_incrby_min 1
                }
            }
            
            after 5000
            test "after" {
                test "set" {
                    test "set " {
                        assert_equal [$master crdt.datainfo  kv1000] [$peer crdt.datainfo kv1000]
                    }
                    test "set + set" {
                        assert_equal [$master crdt.datainfo  kv1010] [$peer crdt.datainfo kv1010]
                    }
                    test " incrbyfloat + set" {
                        assert_equal [$master crdt.datainfo  kv1020] [$peer crdt.datainfo kv1020]
                    }
                    test "del + set" {
                        assert_equal [$master crdt.datainfo  kv1030] [$peer crdt.datainfo kv1030]
                        assert_equal [$master crdt.datainfo  kv1031] [$peer crdt.datainfo kv1031]
                        assert_equal [$master crdt.datainfo  kv1032] [$peer crdt.datainfo kv1032]
                    }
                    
                }
                test " incrbyfloat" {
                    test " incrbyfloat " {
                        assert_equal [$master crdt.datainfo  kv1100] [$peer crdt.datainfo kv1100]
                    }
                    test " incrbyfloat +  incrbyfloat" {
                        assert_equal [$master crdt.datainfo  kv1110] [$peer crdt.datainfo kv1110]
                    }
                    test "set +  incrbyfloat" {
                        assert_equal [$master crdt.datainfo  kv1120] [$peer crdt.datainfo kv1120]
                    }
                    test "del +  incrbyfloat" {
                        assert_equal [$master crdt.datainfo  kv1130] [$peer crdt.datainfo kv1130]
                        assert_equal [$master crdt.datainfo  kv1131] [$peer crdt.datainfo kv1131]
                        assert_equal [$master crdt.datainfo  kv1132] [$peer crdt.datainfo kv1132]
                    }
                    
                }
                test "del" {
                    test "del2 (set)" {
                        assert_equal [$master crdt.datainfo  kv1200] [$peer crdt.datainfo kv1200]
                    }
                    test "del ( incrbyfloat)" {
                        assert_equal [$master crdt.datainfo  kv1201] [$peer crdt.datainfo kv1201]
                    }
                    test "del (set + zincby)" {
                        assert_equal [$master crdt.datainfo  kv1202] [$peer crdt.datainfo kv1202]
                    }
                }
                test "max" {
                    assert_equal [$peer get peer_incrby_max] -2
                }
                test "min" {
                    # puts [$master crdt.datainfo peer_incrby_max]
                    assert_equal [$peer get peer_incrby_min] 2
                }
            }
        }
        

        test "slave" {
            start_server {tags {"crdt-set"} overrides {crdt-gid 1} config {crdt.conf} module {crdt.so} } {
                set slave [srv 0 client]
                set slave_gid 2
                set slave_host [srv 0 host]
                set slave_port [srv 0 port]
                set slave_log [srv 0 stdout]
                $slave crdt.debug_gc rc 0
                $slave slaveof $master_host $master_port
                
                wait_for_sync $slave
                
                    test "check value" {
                        test "set" {
                            test "set " {
                                assert_equal [$master crdt.datainfo  kv1000] [$slave crdt.datainfo kv1000]
                            }
                            test "set + set" {
                                assert_equal [$master crdt.datainfo  kv1010] [$slave crdt.datainfo kv1010]
                            }
                            test " incrbyfloat + set" {
                                assert_equal [$master crdt.datainfo  kv1020] [$slave crdt.datainfo kv1020]
                            }
                            test "del + set" {
                                assert_equal [$master crdt.datainfo  kv1030] [$slave crdt.datainfo kv1030]
                                assert_equal [$master crdt.datainfo  kv1031] [$slave crdt.datainfo kv1031]
                                assert_equal [$master crdt.datainfo  kv1032] [$slave crdt.datainfo kv1032]
                            }
                            
                        }
                        test " incrbyfloat" {
                            test " incrbyfloat " {
                                assert_equal [$master crdt.datainfo  kv1100] [$slave crdt.datainfo kv1100]
                            }
                            test " incrbyfloat +  incrbyfloat" {
                                assert_equal [$master crdt.datainfo  kv1110] [$slave crdt.datainfo kv1110]
                            }
                            test "set +  incrbyfloat" {
                                assert_equal [$master crdt.datainfo  kv1120] [$slave crdt.datainfo kv1120]
                            }
                            test "del +  incrbyfloat" {
                                assert_equal [$master crdt.datainfo  kv1130] [$slave crdt.datainfo kv1130]
                                assert_equal [$master crdt.datainfo  kv1131] [$slave crdt.datainfo kv1131]
                                assert_equal [$master crdt.datainfo  kv1132] [$slave crdt.datainfo kv1132]
                            }
                            
                        }
                        test "del" {
                            test "del3 (set)" {
                                assert_equal [$master crdt.datainfo  kv1200] [$slave crdt.datainfo kv1200]
                            }
                            test "del ( incrbyfloat)" {
                                assert_equal [$master crdt.datainfo  kv1201] [$slave crdt.datainfo kv1201]
                            }
                            test "del (set + zincby)" {
                                assert_equal [$master crdt.datainfo  kv1202] [$slave crdt.datainfo kv1202]
                            }
                        }
                        
                    }
                
            }
        }
        

    }
}


