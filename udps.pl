#!/usr/bin/perl

use IO::Socket::INET;
use DBI;

# flush after every write
$| = 1;


my ($socket,$received_data);
my ($peeraddress,$peerport);

#  we call IO::Socket::INET->new() to create the UDP Socket and bound 
# to specific port number mentioned in LocalPort and there is no need to provide 
# LocalAddr explicitly as in TCPServer.
$socket = new IO::Socket::INET (
	LocalPort => '21001',
	Proto => 'udp',
	) or die "ERROR in Socket Creation : $!\n";

while(1)
{
#my tagmac, sig, apmac, timeutc, seq, level, tolerance;
	my $timeutc;

# read operation on the socket
$socket->recv($recieved_data,1024);

#get the peerhost and peerport at which the recent data received.
$peer_address = $socket->peerhost();
$peer_port = $socket->peerport();

	@timedata = localtime();
	my $detijd = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",  
				$timedata[5]+1900, $timedata[4]+1, $timedata[3],
				$timedata[2], $timedata[1], $timedata[0]);
	printf ( "%s AP %s reported %d bytes\n", $detijd, $peer_address, length( $recieved_data ));


#   print "-$recieved_data-\n";
	my( $hex ) = unpack( 'H*', $recieved_data );
	print "-$hex-\n";

# 01 00 00 12 0A 01 C2 0B - 01 A8 12 01 01 3C 06 00 19 77 14 40 40
# 01 version
#    00 type
#       00 12 type 802.11
#             0A 01 C2 signal
#                      0B   01 A8 noise
#                                 12 01 01 channel
#                                          3C 06 sensor addr
# 29 02 XX YY length before snapshot?

	my $tagmac = substr( $hex, 72, 12 );
	my $sig = bytetodec( substr( $hex, 12, 2 ));
	my $apmac = substr( $hex, 30, 12 );
	my $seq = ( 16 * hex ( substr( $hex, 98, 2 ) ))
                      + hex ( substr( $hex, 96, 1 )
                );

	my ( $level, $tolerance ) = bat( substr( $hex, 134, 2 )); 

# toon
	printf "Version %s ", substr( $hex, 0, 2 );
	printf "Signal  %d ", bytetodec( substr( $hex, 12, 2 ));
	printf "Noise   %d ", bytetodec( substr( $hex, 18, 2 ));
	my $channel = hex ( substr( $hex, 24, 2 ) );
	printf "Channel %s ", $channel;
	printf "AP mac  %s ", substr( $hex, 30, 12 );
	printf "Tag mac %s ", substr( $hex, 72, 12 );
	my $multi = 
		 ( 16 * hex ( substr( $hex, 98, 2 ) )) 
		      + hex ( substr( $hex, 96, 1 ) 
                );
	printf "Sequence %s ", $multi ;
#	printf "fragment %s ", substr( $hex, 97, 1 );
#	printf "Battery  %s ", substr( $hex, 134, 2 );
	my ( $batval, $battol ) = bat( substr( $hex, 134, 2 ));
	printf ( "%s tol %s ", $batval, $battol );
	printf "Bat day  %s ",   hex ( substr( $hex, 136, 4 ));
	printf "Activedays %s ", hex ( substr( $hex, 140, 8 ));

	my $zoekredpinebat = substr( $hex, 122, 4 );
	if ( $zoekredpinebat =~ '0207' ) 
	{ 
		my $redpinbat = substr( $hex, 126, 2 );
#		printf "*** Redpine bat %s ", $redpinbat ;
		for ($redpinbat) {
			if    (/50/) { $level = 100; }
			elsif (/38/) { $level = 70; }
			elsif (/30/) { $level = 60; }
			elsif (/28/) { $level = 50; }
			elsif (/20/) { $level = 40; }
			elsif (/18/) { $level = 30; }
			elsif (/10/) { $level = 20; }
		}
	}

	pumpsql ( $tagmac, $sig, $apmac, $detijd, $seq, $level, $tolerance, $channel );
	
	print "\n"


}

$socket->close();

sub bytetodec ()
{
 my $byte = shift;

# print "*$byte*\n";

my $hex= "ff" . $byte;
my $unsigned= hex($hex);
my $signed= $unsigned;
$signed -= 0x10000   if  $signed & 0x8000;

return $signed;
}

sub bat ()
{
	my $getal = shift;
	my $getal = hex ( $getal );

#	print "\ndecimaal: " . $getal . "\n";
#	printf ( "binair           %08b\n", $getal );
	my $left = $getal<<1;
#	printf ( "na shift left  1 %08b\n", $left );
	my $right = $left>>4;
#	printf ( "na shift right 3 %08b\n", $right );
#	printf ( "decimaal:        %d  \n", $right * 10 );

#	print "tol\n";
#	printf ( "binair           %08b\n", $getal );
	my $mask = $getal & 7 ; # 0000 0111 
#	printf ( "masked out       %08b\n", $mask );

return ( $right * 10, $mask * 10);
}


sub pumpsql ( )
{
my (   $tagmac, $sig, $apmac, $timeutc, $seq, $level, $tolerance, $channel   ) = @_;
printf( "\n pumpsql() with values: %s %s, %s, %s, %s %s %s %s\n", 
	$tagmac, $sig, $apmac, $timeutc, $seq, $level, $tolerance, $channel );

my $dbh = DBI->connect("DBI:Pg:dbname=WIFILOC;host=localhost", "wifiloc", "dbpasswordhere", {'PrintError'=> 0, 'RaiseError' => 0}); 

if (!$dbh)
{
 printf ("wifiloc SQL db connect failure: %s\n", $DBI::errstr );
return;
}

# 3nov2014 if new tag, tell Zabbix
my $rows = $dbh->prepare("select count(tagmac) from inventory where tagmac = ?;");
$rows->execute($tagmac);
my @rowq = $rows->fetchrow_array();
# print "result:$rowq[0]\n";

if ( $rowq[0] == 0 )
{
 print "new tag $tagmac telling Zabbix\n";
 qx ( /usr/sbin/zabbix-sender -z zabbix.your.domain -s wifiloc -k tagmac.new -o $tagmac );
}
$rows->finish();

my $rows = $dbh->do("INSERT INTO INVENTORY ( tagmac, sig, apmac, timeutc, seqnr, kanaal ) VALUES ( '$tagmac', '$sig', '$apmac', '$timeutc', '$seq', '$channel')");
if ( $rows != 1 )
{
	print "$rows row(s) affected for inventory\n";
}

my $rows = $dbh->do("INSERT INTO BATTERY ( tagmac, timeutc, level, tolerance ) VALUES ( '$tagmac', '$timeutc', '$level', '$tolerance')");
if ( $rows != 1 )
{
	print "$rows row(s) affected for battery\n";
}

$dbh->disconnect();



return;
}
