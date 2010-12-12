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

# Declare three vars for stuffing input into.
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
	$hydra->{$input[2]} = $input[1];
}
while (<$lowin>){
	next unless m/[\d\.]+,[\d\.]/;
	chomp $_;
	my @input = split(/,/);
	$low->{$input[0]} = $input[1];
}

# we need a var with a sensible set of shaft speeds in it. Ideally we'd like
# 1500rpm but we can also easily do 2x that, and 3/4 2/3 1/2 1/3 1/4 with 
# a belt drive.
my @speeds = (3000,1500,1125,1000,750,500,375);

# So we want to know the maximum annual energy output of a turbine
# installed on a river with the flows specified in the input files. 
# we need to choose a design flow and then iterate through flows 
# calculating the energy output until we find the maximum output.
# a good starting point is probably the 50% exceedence and the max
# flowrate is for exceedence = 1.99%
my ($energy,$answer);
for(my $Qdesign = $hydra->{'50.00'}; $Qdesign < $hydra->{'1.99'};
		$Qdesign += 0.01){
	# so then we calculate the power output for that flow
	my ($power,$head) = power($Qdesign,50);
	# from that we can workout which turbines we might use. We want to step
	# through the @speeds array and call the specific speed sub to give us
	# a list of possible trbines to use.
	my @turbines;
	foreach (@speeds){
		push (@turbines, speed($_,$power,$head));
	}
	# we need to set $answer->{$turbine} to a low value for the first iteration
	foreach (@turbines){
		$answer->{'hydra'}->{$_}->{'nrg'} = 0;
	}
	# then we step through the generated list of turbines and workout the
	# annual energy output.
	foreach my $turbine (@turbines){
		# The step through the exceedence array and tot up the energy.
		foreach my $key (keys (%$hydra)){
			# the flowrate can't be more than the design flowrate so we use
			# the Tenary operatory to ensure that.
			my $Q = $hydra->{$key} < $Qdesign ? $hydra->{$key} : $Qdesign;
			my ($p,$hn) = power($Q,$key);
			my $eff = eff($Qdesign,$hydra->{$key},$turbine);
			$energy->{$turbine} += ((100-$key)/100)*$p*$eff;
		}
	# check to see if we've found a better Design flow and if so set the 
	# answer energy and answer flowrate for the turbines in question.
		unless ($answer->{'hydra'}->{$turbine}->{'nrg'} > $energy->{$turbine}){
		 	$answer->{'hydra'}->{$turbine}->{'nrg'} =  $energy->{$turbine};
			$answer->{'hydra'}->{$turbine}->{'QDesign'} = $Qdesign;
		}
	}
}
# and then do all that again with the lowflows stuff
for(my $Qdesign = $low->{'50'}; $Qdesign < $low->{'5'};
		$Qdesign += 0.01){
	my ($power,$head) = power($Qdesign,50);
	my @turbines;
	foreach (@speeds){
		push (@turbines, speed($_,$power,$head));
	}
	foreach (@turbines){
		$answer->{'low'}->{$_}->{'nrg'} = 0;
	}
	foreach my $turbine (@turbines){
		foreach my $key (keys (%$low)){
			my $Q = $low->{$key} < $Qdesign ? $low->{$key} : $Qdesign;
			my ($p,$hn) = power($low->{$key},$key);
			my $eff = eff($Qdesign,$low->{$key},$turbine);
			$energy->{$turbine} += ((100-$key)/100)*$p*$eff;
		}
		unless ($answer->{'low'}->{$turbine}->{'nrg'} > $energy->{$turbine}){
		 	$answer->{'low'}->{$turbine}->{'nrg'} =  $energy->{$turbine};
			$answer->{'low'}->{$turbine}->{'QDesign'} = $Qdesign;
		}
	}
}

# print out the answer

print Dump($answer);

# We need a specific speed subroutine that works out the specific speed of
# the turbine and returns what types of turbine would be suitable for that
# specific speed.
sub speed {
	my $rpm = shift;
	my $power = shift;
	my $h = shift;
	my $speed = 1.2*$rpm*$power**0.5/$h**1.5;	
	my @turbines;
	if ($speed > 12 && $speed < 30){push (@turbines,'pelton');}
	if ($speed > 20 && $speed < 70){push (@turbines,'turgo');}
	if ($speed > 20 && $speed < 80){push (@turbines,'cross');}
	if ($speed > 80 && $speed < 400){push (@turbines,'francis');}
	if ($speed > 340 && $speed < 1000){push (@turbines,'prop');}
	return @turbines;
}


# we need a turbine efficiency subroutine that takes a design flowrate,
# an actual flowrate and a turbine type and does a cubic spline on the
# table of part-efficiences returning the effciency for that flowrate
sub eff {
	my $Qdesign = shift;
	my $Q = shift;
	my $turbine = shift;
	# the pelton and the turgo share the same efficiency curve.
	$turbine = 'pelton' if $turbine eq 'turgo';
	# now we need to set up 'tables' for the cubic spline code to work on.
	# these valus have been read from the graph in the Micro Hydro design
	# book pg 156 which plots flow-fration against effciency.
	my $table;
	# first for the pelton/turgo
	push (@{$table->{'pelton'}->{'ff'}},
			(0.07,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'pelton'}->{'eff'}},
			(0,0.68,0.82,0.85,0.86,0.86,0.86,0.85,0.85,0.82,0.8));
	# then for an engineered cross-flow.
	push (@{$table->{'cross'}->{'ff'}},
			(0.07,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'cross'}->{'eff'}},
			(0,0.63,0.75,0.78,0.79,0.80,0.81,0.81,0.79,0.78,0.82));
	# Frances
	push (@{$table->{'francis'}->{'ff'}},
			(0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'francis'}->{'eff'}},
			(0,0.40,0.59,0.70,0.78,0.86,0.91,0.91,0.86));
	# Prop
	push (@{$table->{'prop'}->{'ff'}}, (0.36,0.4,0.5,0.6,0.7,0.8,0.9,1.0));
	push (@{$table->{'prop'}->{'eff'}},
			(0,0.12,0.35,0.50,0.68,0.76,0.85,0.90));
	# we now need to create a Maths::Spline object for the correct turbine
	my $spline=new Math::Spline
			($table->{$turbine}->{'ff'},$table->{$turbine}->{'eff'});
	# and return the value for the part-flow in question.
	return $spline->evaluate($Q/$Qdesign);
}

# We need a subroutine to calculate the power input to the turbine for a
# given flowrate.
sub power {
	my $Q = shift;
	my $exceed = shift;
	# call the flowr subroutine to scale the flow rate based on the flow
	# regime.
	$Q = flowr($Q, $exceed);
	# break out of calc and return 0 if the flowrate is 0
	return 0 if $Q == 0;
	# call the darcy sub to work out head loss due to friction
	my $hf = darcy($Q);
	# call the turbulence sub to work out head loss due to valves, bends &c.
	my $ht = turb($Q);
	# so the net head is the gross head minus the losses.
	my $hn = $hg-$ht-$hf ;
	# if the nethead/grosshead is less than 0.9 then we need to consider a
	# fatter pipe.
	die 'Warning unaccaptable losses', $hn/$hg, "remains try a fatter pipe \n" 
		if $hn/$hg < 0.9;
	# now we can calulate the input power to the turbine at this flowrate
	# and return it.
	return (10*$Q*$hn,$hn);
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
