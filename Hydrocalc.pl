#!/usr/bin/perl -Tw
use strict;
use YAML;
# set a constant PI = to pi
use constant PI => 4 * atan2(1, 1);
# set a value for nu, the kinematic viscosity of water
use constant nu => 0.000000131;
# set a value for the acceleration due to gravity
use constant g => 9.81;

#Declare vars for pipe diameter, gross head, pipe length, roughness,
#percentage of flow over Q95
#which are provide on the command line
my ($dia, $hg, $len, $eps, $perc, $limit, $percy) = @ARGV;
# perform a check to see we have the right number of vars passed in and give
# usage information if not.

my $usage = "This script requires 7 variables: Pipe diamter(m), gross head(m),
penstock length(m), pipe friction factor, % of flow allowed above Q95,
Qn for secondary %, % of flow allowed above Qn.

Something like Hydrocalc.pl 0.5 23 250 0.06 50 60 60\n";
my $count = @ARGV;
die $usage unless $count == 7;

# Declare three vars for stuffing results into.
my ($hydra, $low, $dyfi);

# we now need to open the three different flow rate files and calculate the 
# available flow based on the flow regime we're likely to have

open (LOW, '<',"lowflows.csv") or die "can't open lowflows";
open (HYDRA, '<',"hydra.csv") or die "can't open hydra";
#open (DYFI, '<',"Dyfi.csv") or die "can't open Dyfi";

while (<HYDRA>){
	next unless m/[\d\.]+,[\d\.]+,[\d\.]+,[\d\.-]+/;
	chomp $_;
	my @input = split(/,/);
	my $Q = $input[1];
	my $exceed = $input[2];
	# we need to take into account the flow regime allowed.
	# we're not allowed any of the Q95 flow 
	next if $exceed >= 95;
	# $limit contains the Qn of the exceedence above which we can take
	# $percy percent. $perc is the percentage we're allowed over Q95
	if ($exceed >= $limit){
		$Q = $Q*$percy/100;
	}else{
		$Q = $Q*$perc/100;
	}
	$hydra->{$exceed} = darcy($Q);
}

while (<LOW>){
	next unless m/[\d\.]+,[\d\.]/;
	chomp $_;
	my @input = split(/,/);
	my $Q = $input[1];
	my $exceed = $input[0];
	next if $exceed >= 95;
	if ($exceed >= $limit){
		$Q = $Q*$percy/100;
	}else{
		$Q = $Q*$perc/100;
	}
	$low->{$exceed} = darcy($Q);
}

print Dump( $hydra ), "\n";
print Dump( $low ), "\n";

# We want a function to calculate the Reynolds number

sub reynolds {
	my $Q = shift;
	return (4*$Q)/(PI*$dia*nu);
}

# then use the colebrook-white equation to get the Darcy friction factor

sub colebrook {
	my $Q = shift;
	my $Re = reynolds($Q);
	my $f = 1;
	my $fn = 0;
	# use a while loop to iteratively solve the c-w equation using steps of
	# 0.000001
	while ($f > $fn){
		$fn = (1/(-2.0*log10($eps/(3.7*$dia)+2.51/($Re*$f^0.5))))^2;
		$f = $f - 0.000001;
	}
	return $fn;
}

# and the darcy-weisbach equation to get the headloss

sub darcy {
	my $Q = shift;
	my $f = colebrook($Q);
	my $V = $Q/(PI*($dia/2)^2);
	return $f*$len*$V^2/($dia*2*g);
}

# and one so we can take log10 

sub log10 {
	my $n = shift;
	return log($n)/log(10);
}
