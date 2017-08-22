#!/usr/bin/perl

#
# 8 juli 2014 Leo Bistmans
#
# Web view naar databank waar wifitags metingen beschikbaar zijn.
#
use Mojolicious::Lite;
use Mojo::UserAgent;
use HTML::FormatText;
use Time::Piece;
use Time::Seconds;
use Time::HiRes qw(usleep);
#use XML::Feed;
use DateTime;
use DBI;
use utf8;

our $VERSION = "1.0";

# turn off buffering
$| = 1;

# if the user wants to see extra debugging text
# set this value to 1
my $debug = 1;

# if the user wants to see SQL tracing set this value to 1
my $sql_debug = 1;

my $now_time = localtime();

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$hour = "0" . $hour if $hour < 10;
$mon  = $mon + 1;
$mon  = "0" . $mon if $mon < 10;
$year = $year + 1900;

my %months = (
    Jan => '00', Feb => '01', Mar => '02',
    Apr => '03', May => '04', Jun => '05',
    Jul => '06', Aug => '07', Sep => '08',
    Oct => '09', Nov => '10', Dec => '11'
);

# hypnotoad IP address and port to listen
app->config(
    hypnotoad => {
        listen => ['http://IPADDRESS:PORT'],
    }
);

my $pg_db = "WIFILOC"; # database name
my $user  = "wifiloc"; # database username
#my $pass  = "wifiloc"; # database user password
my $pass  = "dbpasswordhere"; # database user password

# database connection
my $dbh = DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass");
$dbh->{RaiseError}     = 1;
$dbh->{PrintError}     = 0;
$dbh->{pg_enable_utf8} = 1;

# add database tracing - SQL or DBD
if ( $sql_debug ) {
    $dbh->trace('SQL', '/home/wifiloc/sql_trace.log');
}

# ------------- NEWS HELPER FUNCTIONS -------------

# setup a help to the database handle
helper db => sub { $dbh };


helper select_linkedto => sub {
    my $self = shift;

    DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass")
		 or exit -1;


	my $get_feeds = $self->db->prepare('
		    select
			    linkedto.tagmac, linkedto.name
		    from
			    linkedto
		    order by 
			    linkedto.name asc
		');
	
	$get_feeds->execute()
#		 or die "<br>Database unreachable<br>\n";
		 or exit -1;
	return $get_feeds->fetchall_arrayref;

};

helper add_linkedto => sub {
    my $self      = shift;
    my $tagmac = shift;
    my $name  = shift;
    
	DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass");

# mac adres in 123456789012 remove : - space, etcetera
	$tagmac =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg ; # replace html encoded '%20' by space ' ' 
							 # e in eg is to execute expression chr(hex())
	$tagmac =~ s/[\s+\-+\/+\:+]//g;      # remove whitespaces dash - backslash \ double:point :
	$tagmac = lc $tagmac;

# name remove / because it we use the name in URL's later
	$name =~ s/\/+/-/g;    # replace a/b/c to a-b-c

# tagmac duplicate check
	my $duplitag = $self->db->prepare( 'select count(tagmac) from linkedto where tagmac = ?');
	$duplitag->execute( $tagmac );
	my @tagcount = $duplitag->fetchrow_array();

# name duplicate check
	my $dupliname = $self->db->prepare( 'select count(name) from linkedto where name = ?');
	$dupliname->execute( $name );
	my @namecount = $dupliname->fetchrow_array();

	if ( ( $tagcount[0] + $namecount[0] ) >= 1 ) {

# FIXME warn about failed duplicate insert

	} else { 

	my $insert_linkedto = eval { $self->db->prepare('insert into linkedto (tagmac, name) values (?, ?)') } || return undef;
    	$insert_linkedto->execute($tagmac, $name);

	}
};

helper update_news_item => sub {
    my $self        = shift;
    my $action      = shift;
    my $tagname     = shift;
    my $tagmac      = shift;
    my $update;
    
	DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass");

print $action, " ", $tagmac, " ", $tagname, "\n";
        
    if ( $action eq "Save Edit" ) {
        $update = $self->db->prepare('update linkedto set name = ? where tagmac = ?');
    	$update->execute($tagname, $tagmac);
    } elsif ( $action eq "Delete Tag" ) {
        $update = $self->db->prepare('delete from linkedto where tagmac = ?');
    	$update->execute($tagmac);
    } 
};

helper show_trace_by_tagmac => sub {
    my $self = shift;
    my $tagmac = shift;

    DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass");

#  select realmname, location from maptabel where macaddress = upper(( select apmac from inventory where tagmac ='002346001216' order by timeutc desc limit 1 ));
#  select maptabel.realmname,maptabel.location, inventory.timeutc, inventory.sig from maptabel, inventory where inventory.tagmac = '00234600122c' limit 20;
#  my $blah = $self->db->prepare("select * from inventory where tagmac = ? order by timeutc desc limit 20;");
# select maptabel.realmname,maptabel.location, inventory.timeutc, inventory.sig, inventory.seqnr from maptabel, inventory where ( inventory.tagmac = '002346001201' and inventory.timeutc = '2014-10-01 15:32:21' and inventory.sig = -56 and inventory.seqnr = 400 and  maptabel.macaddress = inventory.apmac );

    my $blah = $self->db->prepare(" select maptabel.realmname,maptabel.location, inventory.timeutc, inventory.sig, inventory.seqnr, inventory.kanaal, maptabel.map_container_id from maptabel, inventory where upper ( inventory.tagmac ) = upper ( ? ) and upper ( maptabel.macaddress ) = upper ( inventory.apmac) order by inventory.timeutc desc limit 20;");
    $blah->execute( $tagmac );
    return $blah->fetchall_arrayref;
};

helper getbat => sub {
    my $self = shift;
    my $tagmac = shift;

    DBI->connect_cached("dbi:Pg:dbname=$pg_db", "$user", "$pass");

    my $mylevel = $self->db->prepare(" select level, timeutc from battery where tagmac = ? order by battery.timeutc desc limit 1;" );
    $mylevel->execute ( $tagmac );

    my $row = $mylevel->fetchrow_arrayref;
    return @$row[0];
};

app->select_linkedto;

# ------------- NEWS ROUTES -------------

# show all linkedto tags 
any '/' => sub {
	my $self = shift;
	
	my $rows = $self->select_linkedto;
	$self->stash( feed_rows => $rows );
	$self->render('list_linkedto');
};

get '/view_linkedto/:linkedto_tagmac/:linkedto_name' => sub {
    my $self      = shift;
    my $linkedto_tagmac  = $self->param('linkedto_tagmac');
    my $linkedto_name    = $self->param('linkedto_name');
    
    my $linkedto_rows = $self->select_linkedto($linkedto_tagmac);
    $self->stash(news_rows       => $linkedto_rows);
    $self->stash(linkedto_tagmac => $linkedto_tagmac);
    $self->stash(linkedto_name   => $linkedto_name);    
    $self->render('view_linkedto');
};

get '/showtrace' => sub {
    my $self      = shift;
    my $tagmac  = $self->param('tagmac');

    my $showtrace_rows = $self->show_trace_by_tagmac( $tagmac );

#   print "showtrace_rows: @$showtrace_rows\n";
    my @str = $showtrace_rows;
    $self->stash( showtrace_rows => $showtrace_rows );
#   $self->stash( tagmac => $tagmac );
    $self->render( 'showtrace' );
};

# add a tagmac, name to the linkedto 
get '/add_linkedto' => sub {
    my $self      = shift;
#    my $feed_name = $self->param('feed_name');
#    my $feed_url  = $self->param('feed_url');

#    $self->add_news_feed($feed_name, $feed_url);
    return $self->render('add_linkedto');
};

post '/add_linkedto_item' => sub {
    my $self      = shift;
    my $tagmac = $self->param('tagmac');
    my $name  = $self->param('name');

    $self->add_linkedto($tagmac, $name);
# na aanvullen, opnieuw lijst tonen:
    my $rows = $self->select_linkedto;
    $self->stash( feed_rows => $rows );
    return $self->render( 'list_linkedto');
};

post '/update_news' => sub {
    my $self        = shift; 
    my $action          = $self->param('action');
    my $linkedto_name   = $self->param('linkedto_name');
    my $linkedto_tagmac = $self->param('linkedto_tagmac');

print "action:",$action, ":\n";
print "linkedto_name:",$linkedto_name, ":\n";
print "linkedto_tagmac:",$linkedto_tagmac, ":\n";

    $self->update_news_item($action,$linkedto_name, $linkedto_tagmac);
#   return $self->render(text => 'done', status => 200);
##
##    my $rows = $self->select_linkedto;
##    $self->stash( feed_rows => $rows );
##    return $self->render( 'list_feeds' );
return $self->redirect_to('/');
};

get '/add_linkedto' => sub {
    my $self      = shift;
# toon invul scherm voor mac &  ( device of hostname )     
return $self->render('add_linkedto');
};

app->start;

# ------------- HTML TEMPLATES -------------

__DATA__
@@list_linkedto.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title>Tags LinkedTo</title>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes" name="viewport"></meta>
        <style>
            %= include 'rss_style'
        </style>
    </head>
    <body>
        %= include 'header'
			<table>
			<tr><td>tagmac</td><td>name</td><td>battery</td></tr>
        % foreach my $row ( @$feed_rows ) {
			% my ($linkedto_tagmac, $linkedto_name) = @$row;

			% my $level = getbat( $linkedto_tagmac );
			
			<tr><td>
			<div class='feedlink'>    <%= $linkedto_tagmac %></td><td>   <a href='/view_linkedto/<%= $linkedto_tagmac %>/<%= $linkedto_name %>'><%= $linkedto_name %> </a>
			</div><br>

		        % if ( $level == 0 || $level == 10 || $level == 20 ) {
				</td><td><b><%= $level %>%</b></td>
			%  } else {
				</td><td><%= $level %>%</td>
			% }
			</tr>
        % }
			</table>
        %= include 'footer'
    </body>
</html>

@@view_linkedto.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title>Linkedto Tags</title>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes" name="viewport"></meta>
        <style>
            %= include 'rss_style'
        </style>
        <script>
	    var highval=0;
	    var refresh=0;
	    function togglehigh( highval ) {
		if ( document.tagview.highval.checked == true )
		{
			highval=1;
		}
		else
		{
			highval=0;
		}
	    }

	    function togglerefresh( highval ) {
		if ( document.tagview.refresh.checked == true )
		{
			refresh=1;
		}
		else
		{
			refresh=0;
		}
	    }

            function changeState(state, id, highval, refresh ) {
                var xmlhttp;
                
                if (window.XMLHttpRequest) {
                    xmlhttp = new XMLHttpRequest();
                } else {
                    xmlhttp = new ActiveXObject("Microsoft.XMLHTTP");
                }

	        xmlhttp.onreadystatechange = function() {

                if (xmlhttp.readyState == 4 && xmlhttp.status == 200) {
			document.getElementById("target").innerHTML =  xmlhttp.responseText;

                }
                }

		xmlhttp.open("GET","/showtrace?tagmac=" + id, true);
                xmlhttp.send();
            }


</script>
    </head>
    <body onload="changeState('showtrace', '<%= $linkedto_tagmac %>')">
        <a id='top'></a>
        %= include 'header'
        <p />
        <div class='header'>

                    <form name="tagview" action="<%=url_for('/update_news')->to_abs%>" method="post" class="formWithButtons">
			<table>
			<tr><td>Name</td><td>Tag</td></tr>
			<tr><td>
                        <input type='text' size='30' name='linkedto_name'   value='<%= $linkedto_name %>'>
			</td><td>
                        <input type='text' size='12' name='linkedto_tagmac' value='<%= $linkedto_tagmac %>' READONLY>
                        <input type='submit' name='action' value='Save Edit'>
                        <input type='submit' name='action' value='Delete Tag'>
			</td></tr>
			<tr><td><center>
            		<button type="button" onClick="changeState('showtrace', '<%= $linkedto_tagmac %>', highval, refresh )">Show Tag Location</button>
			</center>
			</td>
			<td>
<!--
				refresh every minute:	<input type="checkbox" name="refresh" onclick="togglerefresh();" />
				highest signals:	<input type="checkbox" name="highval" onClick="togglehigh();" />
-->
			</td>
			</tr>
			</table>
                    </form>
        </div>
	<div id='target'>

	</div>
        %= include 'footer'
    </body>
</html>

@@ showtrace.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title>Show Trace</title>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes" name="viewport"></meta>
        <style>
            %= include 'rss_style'
        </style>
    </head>
    <body>
		% my %sighash;
		% my $strongsig = -100;
		% my $oldseq = 0;
        	% foreach my $row ( @$showtrace_rows ) {
		% 	my ( $kaart, $lokaal, $timeutc, $sig, $seqnr, $kanaal) = @$row;
		% 	if ( $oldseq != $seqnr ) {
		%		$sighash { $seqnr } = -100;
		%	}

		%	if ( $sig > $sighash { $seqnr } ) {
	 	%		$sighash{ $seqnr} = $sig;			
		%		$oldseq = $seqnr ;		
		%       }
		%}
	<table>
			<tr><td>sig</td><td>location</td><td>map</td><td>time</td><td>seq</td><td>channel</td></tr>
			% my $oudseq = 0;
		        % my $toggle = 0;
			% my $seqbold = 0;

        % foreach my $row ( @$showtrace_rows ) {
			% my ( $kaart, $lokaal, $timeutc, $sig, $seqnr, $kanaal, $mapid) = @$row;

			% $kaart =~ s/_hivexxx//;
			% $lokaal =~ s/change_me//;

			% if ( $oudseq == $seqnr ) {
			%	$toggle = 0;
			% } else {
			%	$toggle = 1;
			% }

			% if ( $toggle == 1 ) {
			%       if ( $seqbold == 0 ) {
			%  		$seqbold = 1;
			%	} else {
			%  		$seqbold = 0;
			% 	}
			% }
		
			<tr>
			% if ( $sighash { $seqnr } == $sig ) {
				<td><b><%= $sig %></b></td>
				<td><b><%= $lokaal %><b></td>
			% } else {
				<td><%= $sig %></td>
			 	<td><%= $lokaal %></td>
			% }
			<td>
			<a href='https://hivemanager.your.domain/hm/maps.action?operation=mapclient&selectedMapId=<%= $mapid %>'><%= $kaart %> </a>
			</td>
			<td><%= $timeutc %></td>
			% if ( $seqbold == 1 ){
				<td><b><%= $seqnr %><b></td>
			% } else {
				<td><%= $seqnr %></td>
			% }
			% $oudseq = $seqnr;

			<td><%= $kanaal %></td>
			</tr>
        % }
	</table>
    </body>
</html>

@@ add_linkedto.html.ep
<!DOCTYPE html>
<html>
    <head>
        <title>Add linkedto</title>
        <meta content="width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes" name="viewport"></meta>
        <style>
            %= include 'rss_style'
        </style>
    </head>
    <body>
        %= include 'header'
        <form action="<%=url_for('/add_linkedto_item')->to_abs%>" method="post">
        <table>
        <tr><td>
        Tag mac address:</td><td> <input type="text" name="tagmac">
        </td></tr>
	<tr><td>
        Device name:</td><td> <input type="text" name="name">
        </td></tr>
        <tr><td><input type="submit" value="Add Name to Tag"> 
	</td></tr>
        </table>
        </form>
        %= include 'footer'
    </body>
</html>

@@ header.html.ep
<div style='padding-bottom: 40px;'>
<ul>
<li><a href="<%=url_for('/add_linkedto')->to_abs%>">Add Tag</a></li>
<li><a href="<%=url_for('/')->to_abs%>">View</a></li>
</ul>
</div>
<div class='clear'></div>

@@ footer.html.ep
<p />
<div class='clear'></div>
<ul>
<li><a href='#top'>Top</a></li>
<li><a href="<%=url_for('/add_linkedto')->to_abs%>">Add Tag</a></li>
<li><a href="<%=url_for('/')->to_abs%>">View</a></li>
</ul>
<div style='padding-bottom: 40px;'></div>

@@ rss_style.html.ep
@media all and (orientation: portrait) and (max-device-width: 480px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 

        max-width: 480px;
        font-size: 14px;
#        background-color: black;
        color: black ;
        margin-left: 10px;
    }
}

@media all and (orientation: portrait) and (max-device-width: 720px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 
        max-width: 720px;
        font-size: 14px;
#        background-color: black;
        color: black;
        margin-left: 10px;
   }
}
    
@media all and (orientation: portrait) and (max-device-width: 1280px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 
        max-width: 1280px;
        font-size: 14px;
#        background-color: black;
        color: black;
        margin-left: 10px;
    }
}
    
@media all and (orientation: landscape) and (max-device-width: 480px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 
        max-width: 480px;
        font-size: 14px;
#        background-color: black;
        color: black;
        margin-left: 10px;
   }
}
    
@media all and (orientation: landscape) and (max-device-width: 720px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 
        max-width: 720px;
        font-size: 14px;
#        background-color: black;
        color: black;
        margin-left: 10px;
   }
}

@media all and (orientation: landscape) and (max-device-width: 1280px) {
    body {
    background: none repeat scroll 0% 0% rgb(240, 240, 240);
    background-color: grey;
    font: 9pt "Helvetica Neue",Helvetica,Arial,FreeSans,sans-serif;
    color: black; 
        max-width: 1280px;
        font-size: 14px;
#        background-color: black;
        color: black;
        margin-left: 10px;
   }
}

fieldset {
   border-style: none;
   float: left;
}

.news {
    white-space: pre-line;
}

.header {
    margin-top: 2em;
    margin-bottom: 2em;
}

.feedlink {
    margin-top: .1em;
}

ul {
    float:left;
    padding:0;
    margin:0;
    list-style-type:none;
}

li {
    display:inline;
    padding-right: 20px;
}

.column {
   padding-left: 5px;
   padding-right: 5px;
}

.clear {
   clear: both;
   padding-bottom: 10px;
   margin-bottom: 10px;
}

tr:nth-child(even) {
    background: #FEF9ED;
}

tr:nth-child(odd) {
    background: #FEE0C6;
}


a:link { color:red }
a:visited { color:blue }
.formWithButtons { display:inline; }


__END__
