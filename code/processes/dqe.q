\d .dqe

dqedbdir:@[value;`dqedbdir;`:dqedb];
gmttime:@[value;`gmttime;1b];
partitiontype:@[value;`partitiontype;`date];
getpartition:@[value;`getpartition;
  {{@[value;`.dqe.currentpartition;
    (`date^partitiontype)$(.z.D,.z.d)gmttime]}}];
writedownperiodengine:@[value;`writedownperiodengine;0D01:00:00];

configcsv:@[value;`.dqe.configcsv;first .proc.getconfigfile["dqengineconfig.csv"]];
resultstab:([procs:`$();tab:`$()]tablecount:`long$();nullcount:`long$();anomcount:`long$());

init:{
  .lg.o[`init;"searching for servers"];
  .servers.startup[];                                                                                           /- Open connection to discovery
 .timer.once[.eodtime.nextroll;(`.u.end;.dqe.getpartition[]);"Running EOD on Engine"];                        /- set timer to call EOD
  
  .dqe.tosavedownengine:();                                                                                           /- store i numbers of rows to be saved down to DB
  }

updresultstab:{[proc;col;table;tabinput]                                                                        /- upadate results table with results
  .lg.o[`updresultstab;"Updating results table for ",(string table)," table from proc ",string proc];
  colfix:`$5_string col;                                                                                        /- remove namespace from query name
  ![`.dqe.resultstab;((=;`procs;enlist proc);(=;`tab;enlist table));0b;(enlist colfix)!enlist tabinput]         /- Update query results into table
  }

chkinresults:{[proc;table]                                                                                      /- check if record already exists for proc,table pair
  .lg.o[`chkresults;"Checking if ",(string proc),",",(string table)," is in resultstab"];
  if[not (proc;table) in key resultstab;
    .lg.o[`chkinresults;"adding null row for ",(string table)," table from proc ",string proc];
    colcount:-2+count cols resultstab;                                                                          /- get count of unkeyed columns from results table
    `.dqe.resultstab insert raze(proc;table,colcount#0N)]                                                       /- insert proc,table pair with nulls into other columns
  }

qpostback:{[proc;query;result]
  .lg.o[`qpostback;"Postback sucessful for ",string first proc];
  tab:key result;                                                                                               /- get table names from dictionary
  .dqe.chkinresults[first proc]'[tab];
  .dqe.updresultstab[first proc;query]'[tab;value result];
  }

runquery:{[query;params;querytype;rs]
  .lg.o[`runquery;"Starting query run for ",string query];
  if[1<count rs;.lg.e[`runquery"error: can only send query to one remote service, trying to send to ",string count rs];:()];
  if[not rs in exec procname from .servers.SERVERS;.lg.e[`runquery;"error: remote service must be a proctype";:()]];

  h:.dqe.gethandles[(),rs];
  .async.postback[h`w;((value query),params);.dqe.qpostback[h`procname;query]];
  }

loadtimer:{[d]
  d[`params]:value d[`params];
  d[`proc]:value raze d[`proc];
  functiontorun:(`.dqe.runquery;.Q.dd[`.dqe;d`query];d`params;d`querytype;d`proc);
  .timer.once[d`starttime;functiontorun;("Running check on ",string d[`proc])]
  }

configtimer:{[]
  t:.dqe.readdqeconfig[.dqe.configcsv;"S**SN"];
  t:update starttime:.z.d+starttime from t;
  {.dqe.loadtimer[x]}each t
  }

writedownengine:{
  if[not count .dqe.tosavedownengine;:()];
  .dqe.savedata[.dqe.dqedbdir;.dqe.getpartition[];.dqe.tosavedownengine;`.dqe;`resultstab];
  hdbs:distinct raze exec w from .servers.SERVERS where proctype=`dqedb;                                        /- get handles for DB's that need to reload
  .dqe.notifyhdb[.os.pth .dqe.dqedbdir]'[hdbs];                                                                 /- send message for BD's to reload
  }


\d .

.dqe.currentpartition:.dqe.getpartition[];                                                                      /- initialize current partition


.servers.CONNECTIONS:`ALL                                                                                       /- set to nothing so that is only connects to discovery

.u.end:{[pt]                                                                                                    /- setting up .u.end for dqe
  .dqe.endofday[.dqe.dqedbdir;.dqe.getpartition[];`resultstab;`.dqe;.dqe.tosavedownengine];
  hdbs:distinct raze exec w from .servers.SERVERS where proctype=`dqedb;                                        /- get handles for DB's that need to reload
  .dqe.notifyhdb[.os.pth .dqe.dqedbdir]'[hdbs];                                                                 /- send message for BD's to reloadi
  .timer.removefunc'[exec funcparam from .timer.timer where `.dqe.runcheck in' funcparam];                      /- clear check function timers
  .timer.removefunc'[exec funcparam from .timer.timer where `.u.end in' funcparam];                             /- clear EOD timer
  .timer.removefunc'[exec funcparam from .timer.timer where `.dqe.writedownengine in' funcparam];               /- clear writedown timer
  .dqe.currentpartition:pt+1;
  };

.dqe.init[]
.dqe.configtimer[]
