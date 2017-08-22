# wifiloc perl based TZSP wifi tag locator in Perl with Perl Mojolicious web interface.

# udps.pl 
Collects TZSP over udp packets from wifi access points.  One wifi tag broadcast can be heard by a number of wifi access points.  The TZSP data has relative signal strength, transmission sequence number, remaining battery level...

Cisco CCX standard as implemented by Vestac and RedpineSignals.
This Perl script registers every signal recepion into a Postgres database.

```
createdb WIFILOC

psql WIFILOC
psql (9.2.7)
Type "help" for help.

WIFILOC=#
WIFILOC=# CREATE TABLE INVENTORY(
WIFILOC(# TAGMAC varchar(24),
WIFILOC(# SIG int,
WIFILOC(# APMAC varchar(24),
WIFILOC(# TIMEUTC time with time zone,
WIFILOC(# SEQNR int);
CREATE TABLE
WIFILOC=#
WIFILOC=# CREATE TABLE LINKEDTO(
TAGMAC varchar(24) UNIQUE,
NAME text UNIQUE);
NOTICE:  CREATE TABLE / UNIQUE will create implicit index "linkedto_tagmac_key" for table "linkedto"
NOTICE:  CREATE TABLE / UNIQUE will create implicit index "linkedto_name_key" for table "linkedto"
CREATE TABLE
WIFILOC=#
WIFILOC=# CREATE TABLE BATTERY(
WIFILOC(# TAGMAC varchar(24),
WIFILOC(# TIMEUTC time with time zone,
WIFILOC(# LEVEL int,
WIFILOC(# TOLERANCE int);
CREATE TABLE
WIFILOC=#
```

Aerohive AP's can be instructed to deliver data over udp with commands like:
```
location tzsp enable
location tzsp server-config server 10.20.30.40 port 21001
location tzsp mcast-mac 01-40-96-00-00-03
```

Wireshark filter for tag mac address:
wlan.ta==00:23:26:00:12:92

# wifiloc.pl
Perl framework 
curl get.mojolicio.us | sh 
morbo wifiloc.pl

The web interface features:
* add name to tag mac address
* overview of all tags ( mac, name, batterylevel )
* a view of last received data per transmission sequence number, signal strength, channel, time.  The Hivemanager database is queried for wifi access point location and map.


