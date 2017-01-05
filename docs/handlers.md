
Message Handlers
================

There is a separate code directory containing message handler
customizations. This is found at \$KDBCODE/handlers. Much of the code is
derived from Simon Garland’s contributions to
[code.kx](http://code.kx.com/wiki/Contrib/UsingDotz)[^7].

Every external interaction with a process goes through a message
handler, and these can be modified to, for example, log or restrict
access. Passing through a bespoke function defined in a message handler
will add extra processing time and therefore latency to the message. All
the customizations we have provided aim to minimise additional latency,
but if a bespoke process is latency sensitive then some or all of the
customizations could be switched off. We would argue though that
generally it is better to switch on all the message handler functions
which provide diagnostic information, as for most non-latency sensitive
processes (HDBs, Gateways, some RDBs etc.) the extra information upon
failure is worth the cost. The message handlers can be globally switched
off by setting .proc.loadhandlers to 0b in the configuration file.

|     Script      |     NS     | Diag |                 Function                 |                 Modifies                 |
| :-------------: | :--------: | :--: | :--------------------------------------: | :--------------------------------------: |
|   logusage.q    |   .usage   |  Y   | Log all client interaction to an ascii log file and/or in-memory table. Messages can be logged before and after they are processed. Timer calls are also logged. Exclusion function list can be applied to .z.ps to disable logging of asynchronous real time updates | pw, po, pg, ps, pc, ws, ph, pp, pi, exit, timer |
| controlaccess.q |  .access   |  N   | Restrict access for set of users/user groups to a list of functions, and from a defined set of servers |        pw, pg, ps, ws, ph, pp, pi        |
| trackclients.q  |  .clients  |  Y   | Track client process details including then number of requests and cumulative data size returned |            po, pg, ps, ws, pc            |
| trackservers.q  |  .servers  |  Y   | Discover and track server processes including name, type and attribute information. This also contains the core of the code which can be used in conjunction with the discovery service. |                pc, timer                 |
|   zpsignore.q   | .zpsignore |  N   | Override async message handler based on certain message patterns |                    ps                    |
|  writeaccess.q  | .readonly  |  N   | Restrict client write access to prevent any modification to data in place. Also disables all HTTP access. |            pg, ps, ws, ph, pp            |



Each customization can be turned on or off individually from the
configuration file(s). Each script can be extensively customised using
the configuration file. Example customization for logusage.q, taken from
\$KDBCONFIG/settings/default.q is below. Please see default.q for the
remaining configuration of the other message handler files.

    /- Configuration used by the usage functions - logging of client interaction
    \d .usage
    enabled:1b		/- whether the usage logging is enabled
    logtodisk:1b		/- whether to log to disk or not
    logtomemory:1b		/- write query logs to memory
    ignore:1b		/- check the ignore list for functions to ignore
    ignorelist:(`upd;"upd")	/- the list of functions to ignore in async calls
    flushtime:1D00		/- default value for how long to persist the
    			/- in-memory logs. Set to 0D for no flushing
    suppressalias:0b	/- whether to suppress the log file alias creation
    logtimestamp:{[].z.d}	/- function to generate the log file timestamp suffix
    LEVEL:3			/- log level. 0=none;1=errors;2=errors+complete
    			/- queries;3=errors+before a query+after
    logroll:1b		/- Whether or not to roll the log file
    			/- automatically (on a daily schedule)


logusage.q
----------

logusage.q is probably the most important of the scripts from a
diagnostic perspective. It is a modified version of the logusage.q
script on code.kx.

In its most verbose mode it will log information to an in-memory table
(.usage.usage) and an on-disk ASCII file, both before and after every
client interaction and function executed on the timer. These choices
were made because:

-   logging to memory enables easy interrogation of client interaction;

-   logging to disk allows persistence if the process fails or locks up.
      ASCII text files allow interrogation using OS tools such as vi, grep
      or tail;

-   logging before a query ensures any query that adversely effects the
      process is definitely captured, as well as capturing some state
      information before the query execution;

-   logging after a query captures the time taken, result set size and
      resulting state;

-   logging timer calls ensures a full history of what the process is
      actually doing. Also, timer call performance degradation over time
      is a common source of problems in kdb+ systems.

The following fields are logged in .usage.usage:

| Field  |               Description                |
| :----: | :--------------------------------------: |
|  time  |   Time the row was added to the table    |
|   id   | ID of the query. Normally before and complete rows will be consecutive but it might not be the case if the incoming call invokes further external communication |
| timer  | Execution time. Null for rows with status=b (before) |
|  zcmd  |   .z handler the query arrived through   |
| status | Query status. One of b, c or e (before, complete, error) |
|   a    | Address of sender. .dotz.ipa can be used to convert from the integer format to a hostname |
|   u    |            Username of sender            |
|   w    |             Handle of sender             |
|  cmd   |               Command sent               |
|  mem   |            Memory statistics             |
|   sz   | Size of result. Null for rows with status of b or e |
| error  |              Error message               |




controlaccess.q
---------------

controlaccess.q is used to restrict client access to the process. It is
modified version of controlaccess.q from code.kx. The script allows
control of several aspects:

-   the host/ip address of the servers which are allowed to access the
    process;

-   definition of three user groups (default, poweruser and superuser)
      and the actions each group is allowed to do;

-   the group(s) each user is a member of, and any additional actions an
      individual user is allowed/disallowed outside of the group
      permissions;

-   the maximum size of the result set returned to a client.

The access restrictions are loaded from csv files. The permissions files
are stored in \$KDBCONFIG/permissions.

|       File        |               Description                |
| :---------------: | :--------------------------------------: |
|   \*\_hosts.csv   | Contains hostname and ip address (patterns) for servers which are allowed or disallowed access. If a server is not found in the list, it is disallowed |
|   \*\_users.csv   | Contains individual users and the user groups they are are a member of |
| \*\_functions.csv | Contains individual functions and whether each user group is allowed to execute them. ; separated user list enables functions to be allowed by individual users |



The permissions files are loaded using a similar hierarchical approach
as for the configuration and code loading. Three files can be provided-
default\_.csv, \[proctype\]\_.csv, and \[procname\]\_.csv. All of the
files will be loaded, but permissions for the same entity (hostpattern,
user, or function) defined in \[procname\]\_.csv will override those in
\[proctype\]\_.csv which will in turn override \[procname\]\_.csv.

When a client makes a query which is refused by the permissioning layer,
an error will be raised and logged in .usuage.usage if it is enabled.


trackclients.q
--------------

trackclients.q is used to track client interaction. It is a slightly
modified version of trackclients.q from code.kx, and extends the
functionality to handle interaction with the discovery service.

Whenever a client opens a connection to the q process, it will be
registered in the .clients.clients table. Various details are logged,
but from a diagnostic perspective the most important information are the
client details, the number of queries it has run, the last time it ran a
query, the number of failed queries and the cumulative size of results
returned to it.


trackservers.q
--------------

trackservers.q is used to register and maintain handles to external
servers. It is a heavily modified version of trackservers.q from
code.kx. It is explained more in section connectionmanagement.


zpsignore.q
-----------

zpsignore.q is used to check incoming async calls for certain patterns
and to bypass all further message handler checks for messages matching
the pattern. This is useful for handling update messages published to a
process from a data source.


writeaccess.q
-------------

writeaccess.q is used to restrict client write access to data within a
process. The script uses the reval function, released in KDB+ 3.3, to
prevent client queries from modifying any data in place. At present only
queries in the form of strings are passed through the reval function.
Additonally the script disables any form of HTTP access. If using
versions of KDB+ prior to 3.3, this feature must be disabled. An attempt
to use this feature on previous KDB+ versions will result in an error
and the relevant process exiting.


Diagnostic Reporting
--------------------

The message handler modifications provide a wealth of diagnostic
information including:

-   the timings and memory usage for every query run on a process;

-   failed queries;

-   clients trying to do things they are not permissioned for;

-   the clients which are querying often and/or regularly extracting
      large datasets;

-   the number of clients currently connected;

-   timer calls and how long they take.

Although not currently implemented, it would be straightforward to use
this information to implement reports on the behaviour of each process
and the overall health of the system. Similarly it would be
straightforward to set up periodic publication to a central repository
to have a single point for system diagnostic statistics.


Connection Management 
=====================

trackservers.q is used to register and maintain handles to external
servers. It is a heavily modified version of trackservers.q from
code.kx. All the options are described in the default config file. All
connections are tracked in the .servers.SERVERS table. When the handle
is used the count and last query time are updated.

    q).servers.SERVERS 
    procname     proctype  hpup                            w  hits startp                        lastp                         endp                          attributes                   
    ---------------------------------------------------------------------------------
    discovery1   discovery :aquaq:9996    0                                  2014.01.08D11:13:10.583056000                               ()!()                        
    discovery2   discovery :aquaq:9995 6  0    2014.01.07D16:44:47.175757000 2014.01.07D16:44:47.174408000                               ()!()                        
    rdb_europe_1 rdb       :aquaq:9998 12 0    2014.01.07D16:46:47.897910000 2014.01.07D16:46:47.892901000 2014.01.07D16:46:44.626293000 `datacentre`country!`essex`uk
    rdb1         rdb       :aquaq:5011 7  0    2014.01.07D16:44:47.180684000 2014.01.07D16:44:47.176994000                               `datacentre`country!`essex`uk
    rdb_europe_1 hdb       :aquaq:9997    0                                  2014.01.08D11:13:10.757801000                               ()!()                        
    hdb1         hdb       :aquaq:9999    0                                  2014.01.08D11:13:10.757801000                               ()!()                        
    hdb2         hdb       :aquaq:5013 8  0    2014.01.07D16:44:47.180684000 2014.01.07D16:44:47.176994000                               `datacentre`country!`essex`uk
    hdb1         hdb       :aquaq:5012 9  0    2014.01.07D16:44:47.180684000 2014.01.07D16:44:47.176994000                               `datacentre`country!`essex`uk
    
    q)last .servers.SERVERS 
    procname  | `hdb2
    proctype  | `hdb
    hpup      | `:aquaq:5013
    w         | 8i
    hits      | 0i
    startp    | 2014.01.08D11:51:01.928045000
    lastp     | 2014.01.08D11:51:01.925078000
    endp      | 0Np
    attributes| `datacentre`country!`essex`uk


Connections
-----------

Processes locate other processes based on their process type. The
location is done either statically using the process.csv file or
dynamically using a discovery service. It is recommended to use the
discovery service as it allows the process to be notified as new
processes become available.

The main configuration variable is .servers.CONNECTIONS, which dictates
which process type(s) to create connections to. .servers.startup\[\]
must be called to initialise the connections. When connections are
closed, the connection table is automatically updated. The process can
be set to periodically retry connections.


Process Attributes
------------------

Each process can report a set of attributes. When process A connects to
process B, process A will try to retrieve the attributes of process B.
The attributes are defined by the result of the .proc.getattributes
function, which is by default an empty dictionary. Attributes are used
to retrieve more detail about the capabilities of each process, rather
than relying on the broad brush process type and process name
categorization. Attributes can be used for intelligent query routing.
Potential fields for attributes include:

-   range of data contained in the process;

-   available tables;

-   instrument universe;

-   physical location;

-   any other fields of relevance.


Connection Passwords
--------------------

The password used by a process to connect to external processes is
retrieved using the .servers.loadpassword function call. By default,
this will read the password from a txt file contained in
\$KDBCONFIG/passwords. A default password can be used, which is
overridden by one for the process type, which is itself overridden by
one for the process name. For greater security, the
.servers.loadpassword function should be modified.


Retrieving and Using Handles
----------------------------

A function .servers.getservers is supplied to return a table of handle
information. .servers.getservers takes five parameters:

-   type-or-name: whether the lookup is to be done by type or name (can
    be either proctype or procname);

-   types-or-names: the types or names to retrieve e.g. hdb;

-   required-attributes: the dictionary of attributes to match on;

-   open-dead-connections: whether to re-open dead connections;

-   only-one: whether we only require one handle. So for example if 3
      services of the supplied type are registered, and we have an open
      handle to 1 of them, the open handle will be returned and the others
      left closed irrespective of the open-dead-connections parameter.

.servers.getservers will compare the required parameters with the
available parameters for each handle. The resulting table will have an
extra column called attribmatch which can be used to determine how good
a match the service is with the required attributes. attribmatch is a
dictionary of (required attribute key) ! (Boolean full match;
intersection of attributes).

    q).servers.SERVERS 
    procname     proctype  hpup                            w hits startp                        lastp                         endp attributes                   
    ---------------------------------------------------------------------------------
    discovery1   discovery :aquaq:9996   0                                  2014.01.08D11:51:01.922390000      ()!()                        
    discovery2   discovery :aquaq:9995 6 0    2014.01.08D11:51:01.923812000 2014.01.08D11:51:01.922390000      ()!()                        
    rdb_europe_1 rdb       :aquaq:9998   0                                  2014.01.08D11:51:38.347598000      ()!()                        
    rdb_europe_2 rdb       :aquaq:9997   0                                  2014.01.08D11:51:38.347598000      ()!()                        
    rdb1         rdb       :aquaq:5011 7 0    2014.01.08D11:51:01.928045000 2014.01.08D11:51:01.925078000      `datacentre`country!`essex`uk
    hdb3         hdb       :aquaq:5012 9 0    2014.01.08D11:51:38.349472000 2014.01.08D11:51:38.347598000      `datacentre`country!`essex`uk
    hdb2         hdb       :aquaq:5013 8 0    2014.01.08D11:51:01.928045000 2014.01.08D11:51:01.925078000      `datacentre`country!`essex`uk
    
    /- pull back hdbs.  Leave the attributes empty
    q).servers.getservers[`proctype;`hdb;()!();1b;f0b] 
    procname proctype lastp                         w hpup        attributes                    attribmatch
    -------------------------------------------------------------------------------
    hdb3     hdb      2014.01.08D11:51:38.347598000 9 :aquaq:5012 `datacentre`country!`essex`uk ()!()      
    hdb2     hdb      2014.01.08D11:51:01.925078000 8 :aquaq:5013 `datacentre`country!`essex`uk ()!()      
    
    /- supply some attributes
    q).servers.getservers[`proctype;`hdb;(enlist`country)!enlist`uk;1b;0b] 
    procname proctype lastp                         w hpup        attributes                    attribmatch           
    -------------------------------------------------------------------------------
    hdb3     hdb      2014.01.08D11:51:38.347598000 9 :aquaq:5012 `datacentre`country!`essex`uk (,`country)!,(1b;,`uk)
    hdb2     hdb      2014.01.08D11:51:01.925078000 8 :aquaq:5013 `datacentre`country!`essex`uk (,`country)!,(1b;,`uk)
    q).servers.getservers[`proctype;`hdb;`country`datacentre!`uk`slough;1b;0b]                                                                                                                                                                                                    
    procname proctype lastp                         w hpup        attributes                    attribmatch                                    
    -------------------------------------------------------------------------------
    hdb3     hdb      2014.01.08D11:51:38.347598000 9 :aquaq:5012 `datacentre`country!`essex`uk `country`datacentre!((1b;,`uk);(0b;`symbol$()))
    hdb2     hdb      2014.01.08D11:51:01.925078000 8 :aquaq:5013 `datacentre`country!`essex`uk `country`datacentre!((1b;,`uk);(0b;`symbol$()))

.servers.getservers will try to automatically re-open connections if
required.

    q).servers.getservers[`proctype;`rdb;()!();1b;0b] 
    2014.01.08D12:01:06.023146000|aquaq|gateway1|INF|conn|attempting to open handle to :aquaq:9998
    2014.01.08D12:01:06.023581000|aquaq|gateway1|INF|conn|connection to :aquaq:9998 failed: hop: Connection refused
    2014.01.08D12:01:06.023597000|aquaq|gateway1|INF|conn|attempting to open handle to :aquaq:9997
    2014.01.08D12:01:06.023872000|aquaq|gateway1|INF|conn|connection to :aquaq:9997 failed: hop: Connection refused
    procname proctype lastp                         w hpup         attributes                    attribmatch
    -------------------------------------------------------------------------------
    rdb1     rdb      2014.01.08D11:51:01.925078000 7 :aquaq:5011 `datacentre`country!`essex`uk ()!()      
    
    /- If we only require one connection, and we have one open,then it doesn't retry connections
    q).servers.getservers[`proctype;`rdb;()!();1b;1b] 
    procname proctype lastp                         w hpup        attributes                    attribmatch
    -------------------------------------------------------------------------------
    rdb1     rdb      2014.01.08D11:51:01.925078000 7 :aquaq:5011 `datacentre`country!`essex`uk ()!()      

There are two other functions supplied for retrieving server details,
both of which are based on .servers.getservers. .servers.gethandlebytype
returns a single handle value, .servers.gethpupbytype returns a single
host:port value. Both will re-open connections if there are not any
valid connections. Both take two parameters:

-   types: the type to retrieve e.g. hdb;

-   selection-algorithm: can be one of any, last or roundrobin.


Connecting To Non-TorQ Processes
--------------------------------

Connections to non-torq (external) processes can also be established.
This is useful if you wish to integrate TorQ with an existing
infrastructure. Any process can connect to external processes, or it can
be managed by the discovery service only. Every external process should
have a type and name in the same way as TorQ processes, to enable them
to be located and used as required.

Non-TorQ processes need to be listed by default in
\$KDBCONFIG/settings/nontorqprocess.csv. This file has the same format
as the standard process.csv file. The location of the non-TorQ process
file can be adjusted using the .servers.NONTORQPROCESSFILE variable. To
enable connections, set .servers.TRACKNONTORQPROCESS to 1b.

Example of nontorqprocess.csv file:

    host,port,proctype,procname
    aquaq,5533,hdb,extproc01
    aquaq,5577,hdb,extproc02


Manually Adding And Using Connections
-------------------------------------

Connections can also be manually added and used. See .api.p“.servers.\*”
for details.


IPC types
---------

In version kdb+ v3.4, two new IPC connection types were added. These new
types are unix domain sockets and SSL/TLS (tcps). The incoming
connections to a proctype can be set by updating .servers.SOCKETTYPE.

In the settings example below, everything that connects to the
tickerplant will use unix domain sockets.

    \d .servers 
    SOCKETTYPE:enlist[`tickerplant]!enlist `unix 

Attempting to open a unix domain socket connection to a process which
has an older kdb+ version will fail. We allow for processes to fallback
to tcp if this happens by setting .servers.SOCKETFALLBACK to true. It
will not fallback if the connection error message returned is one of the
following : timeout, access. It will also not fallback for SSL/TLS
(tcps) due to security concerns.

At the time of writing, using unix domain sockets syntax on windows will
appear to work whilst it’s actually falling back to tcp in the
background. This can be misleading so we disabled using them on windows.
