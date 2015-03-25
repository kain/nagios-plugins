#!/usr/bin/perl -T
#############################################################################
#                                                                           #
# This script was initially developed by Anstat Pty Ltd for internal use    #
# and has kindly been made available to the Open Source community for       #
# redistribution and further development under the terms of the             #
# GNU General Public License: http://www.gnu.org/licenses/gpl.html          #
#                                                                           #
#############################################################################
#                                                                           #
# This script is supplied 'as-is', in the hope that it will be useful, but  #
# neither Anstat Pty Ltd nor the authors make any warranties or guarantees  #
# as to its correct operation, including its intended function.             #
#                                                                           #
# Or in other words:                                                        #
#       Test it yourself, and make sure it works for YOU.                   #
#                                                                           #
#############################################################################
# Author: George Hansper               e-mail:  Name.Surname@anstat.com.au  #
#############################################################################

use strict;
use Getopt::Std;

my $printer;
my @printers;
my ($ok, $crit, $warn, $exitcode );
my $message = "";
my @msgs;
my $status;
my @jobs;
my $n_jobs;
my $no_jobs;
my $scheduler;
my @exclude;

my $job_critical=50;
my $job_warning=20;
my $host;

my $rcsid = '$Id$';
my $rcslog = '
  $Log: check_lpstat.pl,v $
  Revision 1.1  2005/10/06 03:19:12  georgeh
  Initial revision

';

####################################################
# Command-line Option Processing
my %optarg;
my $getopt_result;

$getopt_result = getopts('VhH:c:w:x:', \%optarg) ;

if ( $getopt_result <= 0 || $optarg{'h'} == 1 ) {
	print STDERR "Check printers and print-queue length\n\n";
	print STDERR "Usage: $0 \[-h|-V] | \[-H cups_host] \[-w nn_warn] \[-c nn_crit] \[-x exclude_printer]\n" ;
	print STDERR "\t-h\t... print this help message and exit\n" ;
	print STDERR "\t-V\t... print version and log, and exit\n" ;
	print STDERR "\t-H host ... print server host to query\n" ;
	print STDERR "\t-w nnn  ... warning  threshhold for number of jobs in a print queue\n" ;
	print STDERR "\t            default: $job_warning\n" ;
	print STDERR "\t-c nnn  ... critical threshhold for number of jobs in a print queue\n" ;
	print STDERR "\t            default: $job_critical\n" ;
	print STDERR "\t-x printer ... ignore this printer\n" ;
	print STDERR "\nExample:\n";
	print STDERR "\t$0 -w 10 -c 20 -x bung1 -x slow1\n";
	exit 1;
}

if( $optarg{'V'} == 1 ) {
	print STDERR $rcsid . "\n";
	print STDERR $rcslog . "\n";
	exit 0;
}

if( $optarg{'H'} ne undef ) {
	$optarg{'H'} =~ /([-a-z0-9_.]+)/mi;
	$host="$1";
	#print STDERR "host: $optarg{'H'}->$host \n";
	$host=" -h $host ";
}

if( $optarg{'w'} ne undef ) {
	if( $optarg{'w'} > 0 ) {
		$job_critical=$optarg{'w'}
	} else {
		print STDERR "Ignoring non-numeric '-w " . $optarg{'w'} . "'\n";
	}
}

if( $optarg{'c'} ne undef ) {
	if( $optarg{'c'} > 0 ) {
		$job_critical=$optarg{'c'}
	} else {
		print STDERR "Ignoring non-numeric '-c " . $optarg{'c'} . "'\n";
	}
}

if( $optarg{'x'} ne undef ) {
	@exclude = (@exclude, $optarg{'x'});
}

####################################################
$ENV{PATH}="/bin:/usr/bin";

####################################################
# Check scheduler is running
####################################################
if( ! open(LPSTAT_R, "lpstat $host -r|") ) {
	print STDERR "Could not execute lpstat command\n";
	exit 2;
}

$scheduler = <LPSTAT_R>;

if ( $scheduler !~ /is running/mi) {
	# No scheduler/daemon - abort
	$crit=1;
	chomp $scheduler;
	@msgs = (@msgs, "scheduler is not running");
	print "CRITICAL - " . (join ", ",@msgs) . "\n";
	exit 2;
}

####################################################
# Check printers are accepting jobs
####################################################
# Get list of printers, showing which are accepting jobs...
if( ! open(LPSTAT_A, "lpstat $host -a|") ) {
	print STDERR "Could not execute lpstat command\n";
	exit 2;
}

while(<LPSTAT_A>) {
	chomp;
	/(\S+) (.*) since/mi ;
	$printer = $1;
	$status = $2;
	if( grep /^$printer$/, @exclude ) {
		next;
	}
	if( /accepting/ ) {
		@printers = ( @printers, $printer );
		if ($status =~ /not/i ) {
			$crit=1;
			@msgs = (@msgs, "$printer: $status");
		}
		#print $_;
	}
}
close(LPSTAT_A);

#print STDERR (join " :: ", @printers);
#print STDERR "\n";

####################################################
# Check printers are enabled
####################################################
# Get list of printers, showing which are enabled/disabled...
if( ! open(LPSTAT_P, "lpstat $host -p|") ) {
	print STDERR "Could not execute lpstat command\n";
	exit 2;
}

while(<LPSTAT_P>) {
	if ( /^printer\s+(\S+)\s.*disabled/mi ) {
		$printer=$1;
		if( grep /^$printer$/, @exclude ) {
			next;
		}
		$crit=1;
		@msgs = (@msgs, "$printer: disabled");
	}
}
close(LPSTAT_P);

# Get list of jobs for each printer...
$no_jobs=1;
foreach $printer ( @printers ) { 

	if( grep /^$printer$/, @exclude ) {
		next;
	}

	if( ! open(LPSTAT, "lpstat $host -o $printer|") ) {
		print STDERR "Could not execute command: 'lpstat -o $printer' \n";
		exit 2;
	}
	@jobs = ( <LPSTAT> );
	$n_jobs = @jobs;
	if( $n_jobs >= $job_critical ) {
		$crit=1;
	} elsif( $n_jobs >= $job_warning ) {
		$warn=1;
	}
	if ( $n_jobs > 0 ) {
		@msgs = (@msgs, "$printer: $n_jobs jobs");
		$no_jobs=0;
	}
}

if( $no_jobs ) {
	@msgs = (@msgs, "No jobs queued");
}

####################################################
# Result analysis and output
if($crit) {
	$message = "CRITICAL - ";
	$exitcode = 2;
} elsif($warn) {
	$message = "WARNING - ";
	$exitcode = 1;
} else {
	$message = "OK - ";
	$exitcode = 0;
}

print $message . (join ", ",@msgs) . "\n";
exit $exitcode;