#!/usr/bin/perl -Tw
use strict;
# import a library which knows the value of g
use Astro::Constants::MKS qw(:short);
# set a constant PI = to pi
use constant PI => 4 * atan2(1, 1);
use constant nu => 0.000000131;

#Declare vars for pipe diameter, gross head, roughness, percentage of flow over
#Q95
#which are provide on the command line
my ($dia, $hg, $eps $percy) = @ARGV;
# Declare vars for flow rate, head loss, net head, velocity, Reynolds number,
# Darcey friction factor
my ($Q, $hl, $hn, $V, $Re, $f);

# we now need to open the three different flow rate files and calculate the 
# available flow based on the flow regime we're likely to have

open (LOW "<lowflows.csv") or die "can't open lowflows";
open (HYDRA "<hydra.csv") or die "can't open hydra";
open (DYFI "<Dyfi.csv") or die "can't open Dyfi";

while (<LOW>){
	

# We want a function to calculate the Reynolds number

sub reynolds {
	my ($Q, $D) = @_;
	return (4*$Q)/(PI*$D*nu);
}

sub 
