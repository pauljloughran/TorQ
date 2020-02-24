\d .dqe

dqedbdir:@[value;`dqedbdir;`:dqedb];
gmttime:@[value;`gmttime;1b];
partitiontype:@[value;`partitiontype;`date];
getpartition:@[value;`getpartition;
  {{@[value;`.dqe.currentpartition;
    (`date^partitiontype)$(.z.D,.z.d)gmttime]}}];

configcsv:@[value;`.dqe.configcsv;first .proc.getconfigfile["dqengineconfig.csv"]];
resultstab:([]procs:`$();funct:`$();table:`$();column:`$();resvalue:`long$());

init:{
  .lg.o[`init;"searching for servers"];
  .servers.startup[];                                                                                           /- Open connection to discovery
  }

updresultstab:{[proc;fn;params;tab;resinput]                                                                    /- upadate results table with results
  .lg.o[`updresultstab;"Updating results for ",(string fn)," from proc ",string proc];
  if[not 11h=abs type params`col; params[`col]:`];
  `.dqe.resultstab insert (proc;`$5_string fn;tab;params`col;resinput)
  }

qpostback:{[proc;query;params;querytype;result]
  .lg.o[`qpostback;"Postback sucessful for ",string first proc];
  .dqe.updresultstab[first proc;query;params]'[$[`table=querytype;key result;`];value result];
  }

runquery:{[query;params;querytype;rs]
  temp:(`,(value value query)[1])!(::), params;
  .lg.o[`runquery;"Starting query run for ",string query];
  if[1<count rs;.lg.e[`runquery"error: can only send query to one remote service, trying to send to ",string count rs];:()];
  if[not rs in exec procname from .servers.SERVERS;.lg.e[`runquery;"error: remote service must be a proctype";:()]];

  h:.dqe.gethandles[(),rs];
  .async.postback[h`w;((value query),params);.dqe.qpostback[h`procname;query;temp;querytype]];
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
    
\d .

.dqe.currentpartition:.dqe.getpartition[];                                                                      /- initialize current partition


.servers.CONNECTIONS:`ALL                                                                                       /- set to nothing so that is only connects to discovery

.u.end:{[pt]                                                                                                    /- setting up .u.end for dqe
  .dqe.endofday[.dqe.dqedbdir;.dqe.getpartition[];`resultstab;`.dqe];
  hdbs:distinct raze exec w from .servers.SERVERS where proctype=`dqedb;                                        /- get handles for DB's that need to reload
  .dqe.notifyhdb[1_string .dqe.dqedbdir]'[hdbs];                                                                /- send message for BD's to reload
  .dqe.currentpartition:pt+1;
  };

.dqe.init[]
.dqe.configtimer[]
