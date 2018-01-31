Busroute

http://frdcsa.org/frdcsa/internal/busroute

Command line bus planner

Effective Bus Route Planner that Interfaces with Verber

Effective bus route planner module that interfaces with the Verber
planner.  PROVIDES support for two basic kinds of actions,
boarding, staying on, and exiting a bus, and walking between
locations (currently only bus activities implemented.)


<p>Overview</p>

<p>This  is a  bus  scheduler in  the  sense that  you  give it  a
<em>start  address</em>,  a  <em>destination address</em>,  and  a
<em>time</em>, and it  returns a robust bus plan  to get you there
ASAP.  There  are also now  several different kinds of  reports it
can generate.  (Perhaps we could also give it a dialog system.) It
is  also useful as  a transportation  planning module  for Verber,
because export to PDDL works.</p>

<p>The system further aims to  integrate with a map routing system
such as  the open source Roadnav  or TMRS systems,  to provide the
ability  to   calculate  the  quickest  plan  to   reach  a  given
location.</p>

<b>Example:</b>

<pre>
./busroute -d data/daily.raw.gz -s "Murray Ave. AT Beacon" -e "Forbes Ave. AT Craig" -t 9:00p
61C test
Loading LocationHash...
Loading data...
168310/168310
Creating adjacency matrix...
Sorting departing segments...
Installing departing segments...
Selecting locations...
Cutoff: 0.1
Cutoff: 0.2
Cutoff: 0.4
Cutoff: 0.8
Cutoff: 1.6
Cutoff: 3.2
PATH FOUND: Optimizing...
(ROUTE
	(:STARTLOC	Murray Ave. AT Beacon  (Near Side))
	(:STARTINT	Beacon and Murray)
	(:ENDLOC	Forbes Ave. AT Craig)
	(:ENDINT	Craig and Forbes)
	(:STARTTIME	9:03p)
	(:ENDTIME	9:16p)
	(:DURATION	0:13)
	(:FROMTIME	0:16)
	(:QUALITY	2.2)
	(:PLAN
		(BOARD	61C	I	9:03p	Murray Ave. AT Beacon  (Near Side))
		(EXIT	61C	I	9:16p	Forbes Ave. AT Craig)
	)
)
</pre>

<p>
  This system  has been substantially rewritten  and expanded.  It
  loads much  faster, now incorporating all stops.   It plans with
  equivalence  sets of start  and goal  locations (to  account for
  multiple  sides  and so  forth).   It  incorporates  a new  plan
  quality  system adding  costs to  transfers, too  short  or long
  transfer delays, plan length, and ETA.  The planner is optimal.
</p>
<p>
  It  now  generates  direct  route  reports.  It  also  has  been
  interfaced with Verber, generating pddl2.2 domains.
</p>
