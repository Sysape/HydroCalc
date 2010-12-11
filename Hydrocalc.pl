#!/usr/bin/perl -Tw
use strict;
use YAML;
use Math::Spline;
# set a constant PI = to pi
use constant PI => 4 * atan2(1, 1);
# set a value for nu, the kinematic viscosity of water
use constant nu => 0.000000131;
# set a value for the acceleration due to gravity
use constant g => 9.81;

#Declare vars for pipe diameter, gross head, pipe length, roughness,
#percentage of flow over Q95
#which are provide on the command line
my ($dia, $hg, $len, $eps, $perc, $limit, $percy, $sigmak) = @ARGV;
# perform a check to see we have the right number of vars passed in and give
# usage information if not.

my $usage = "This script requires 8 variables: Pipe diamter(m), gross head(m),
penstock length(m), pipe friction factor, % of flow allowed above Q95,
Qn for secondary %, % of flow allowed above Qn, Sum of headloss coeffcients.

Something like Hydrocalc.pl 0.5 23 250 0.06 50 60 60 1.15\n";
my $count = @ARGV;
die $usage unless $count == 8;

# Declare three vars for stuffing results into.
my ($hydra, $low, $dyfi);

# we now need to open the three different flow rate files.

open (my $lowin, '<',"lowflows.csv") or die "can't open lowflows";
open (my $hydrain, '<',"hydra.csv") or die "can't open hydra";
#open (DYFI, '<',"Dyfi.csv") or die "can't open Dyfi";

# We want to stuff the files into a hash of arrays, all nicely cleaned up
# and then w**k with the array as we need to do many passes over the data.

while (<$hydrain>){
	next unless m/[\d\.]+,[\d\.]+,[\d\.]+,[\d\.-]+/;
	chomp $_;
	my @input = split(/,/);
	push (@{$hydra->{'Q'}}, $input[1]);
	push (@{$hydra->{'exceed'}}, $input[2]);
}
while (<$lowin>){
	next unless m/[\d\.]+,[\d\.]/;
	chomp $_;
	my @input = split(/,/);
	push (@{$low->{'Q'}}, $input[1]);
	push (@{$low->{'exceed'}}, $input[0]);
}

# Just a quick hacky test for the effciency spline calc.
for (my $Q = 0; $Q < 25; $Q++){
	my $output = eff(24,$Q,'pelton');
	print $output,"\n";
}
	

# we need a turbine efficiency subroutine that takes a design flworate,
# an actual flowrate and a turbine type and does a cubic spline on the
# table of part-efficiences returning the effciency for that flowrate
sub eff {
	my $Qdesign = shift;
	my $Q = shift;
	my $turbine = shift;
	# now we need to set up 'tables' for the cubic spline code to work on.
	# these valus have been read from the graph in the Micro Hydro design
	# book pg 156 which plots flow-fration against effciency.
	my $table;
	# first for the pelton/turgo
	push (@{$table->{'pelton'}->{'ff'}},
			(0.07,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'pelton'}->{'eff'}},
			(0,0.68,0.82,0.85,0.86,0.86,0.86,0.85,0.85,0.82));
	# then for an engineered cross-flow.
	push (@{$table->{'cross'}->{'ff'}},
			(0.07,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'cross'}->{'eff'}},
			(0,0.63,0.75,0.78,0.79,0.80,0.81,0.81,0.79,0.78,0.82));
	# Frances
	push (@{$table->{'frances'}->{'ff'}},
			(0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'frances'}->{'eff'}},
			(0,0.40,0.59,0.70,0.78,0.86,0.91,0.91,0.86));
	# Prop
	push (@{$table->{'prop'}->{'ff'}}, (0.36,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'prop'}->{'eff'}},
			(0,0.12,0.35,0.50,0.68,0.76,0.85,0.90));
	# we now need to create a Maths::Spline object for the correct turbine
	my $spline=new Math::Spline
			($table->{$turbine}->{'ff'},$table->{$turbine}->{'eff'});
	# and return the value for the part-flow in question.
	print 'Foo:',$spline->evaluate('0.7222'),"\n";
	return $spline->evaluate($Q/$Qdesign);
}

# We need a subroutine to calculate the power input to the turbine for a
# given flowrate.
sub power {
	my $Q = shift;
	# call the flowr subroutine to scale the flow rate based on the flow
	# regime.
	$Q = flowr($Q);
	# call the darcy sub to work out head loss due to friction
	my $hf = darcy($Q);
	# call the turbulence sub to work out head loss due to valves, bends &c.
	my $ht = turb($Q);
	# so the net head is the gross head minus the losses.
	my $hn = $hg-$ht-$hf ;
	# now we can calulate the input power to the turbine at this flowrate
	# and return it.
	return 10*$Q*$hn;
}

# we need to take into account the flow regime allowed. We're not allowed
# any of the Q95 flow and the commandline vars in $perc, $limit, $percy 
# define the % over Q95 and the % over $limit we are allowed to take.
# this subroutine takes a pair of values, the flow rate and the exceedence
# for that flow rate and then modifies $Q to take into account the flow 
# regime and then returns that.
sub flowr {
	my $Q = shift;
	my $exceed = shift;
	$Q = 0 if $exceed >= 95;
	# $limit contains the Qn of the exceedence above which we can take
	# $percy percent. $perc is the percentage we're allowed over Q95
	if ($exceed >= $limit){
		$Q = $Q*$percy/100;
	}else{
		$Q = $Q*$perc/100;
	}
	return $Q;
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
		$fn = (1/(-2.0*log10($eps/(3.7*$dia)+2.51/($Re*$f**0.5))))**2;
		$f = $f - 0.000001;
	}
	return $fn;
}

# and the darcy-weisbach equation to get the headloss

sub darcy {
	my $Q = shift;
	my $f = colebrook($Q);
	my $V = $Q/(PI*($dia/2)**2);
	return ($f*$len*$V**2)/($dia*2*g);
}

# and one so we can take log10 

sub log10 {
	my $n = shift;
	return log($n)/log(10);
}

# and one for turbulent losses
sub turb {
	my $Q = shift;
	my $v = (4*$Q)/(PI*$dia**2);
	return $v**2*($sigmak)/(2*g);
}
