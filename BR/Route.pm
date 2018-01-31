package BR::Route;

use Data::Dumper;
use BR::Util;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       => [ qw / RouteSegments DurationAbs Length Transfers / ];

sub init {
  my ($self,%args) = @_;
  if ($args{Copy}) {
    my $r = $args{Copy};
    my @rs = @{$r->RouteSegments};
    $self->RouteSegments(\@rs);
    $self->DurationAbs($r->DurationAbs);
    $self->Length($r->Length);
    $self->Transfers($r->Transfers);
  } else {
    $self->RouteSegments($args{RouteSegments} || []);
    my $preseg;
    $self->Transfers(0);
    $self->DurationAbs(0);
    foreach my $seg (@{$self->RouteSegments}) {
      if (defined $preseg) {
	$self->DurationAbs($self->DurationAbs + $seg->FromTime($preseg->EndTime));
	if ($seg->Trip ne $preseg->Trip) {
	  $self->Transfers($self->Transfers + 1);
	}
      }
      $preseg = $seg;
    }
    $self->Length(scalar @{$self->RouteSegments});
  }
}

sub PushRouteSegment {
  my ($self,$segment) = @_;
  if (defined $self->RouteSegments->[-1]->Trip) {
    if (defined $segment->Trip) {
      if ($segment->Trip != $self->RouteSegments->[-1]->Trip) {
	$self->Transfers($self->Transfers + 1);
      }
    }
  }
  $self->DurationAbs($self->DurationAbs + $segment->FromTime($self->EndTime));
  push @{$self->RouteSegments},$segment;
  $self->Length($self->Length + 1);
}

sub Concat {
  my ($self,$route) = @_;
  # verify that the first segment of the other route is the last segment of this route
  if ($self->EndLoc == $route->StartLoc) {
    $self->Transfers($self->Transfers + $route->Transfers +
		     ($self->RouteSegments->[-1]->Trip !=
		     $route->RouteSegments->[-1]->Trip) ? 1 : 0);
    foreach my $seg (@{$route->RouteSegments}) {
      $self->DurationAbs($self->DurationAbs + $seg->FromTime($self->EndTime));
      push @{$self->RouteSegments}, $seg;
    }
    $self->Length($self->Length + $route->Length);
  }
}

sub Direction {
  my ($self,%args) = @_;
  return $self->RouteSegments->[0]->Direction;
}

sub Day {
  my ($self,%args) = @_;
  return $self->RouteSegments->[0]->Day;
}

sub StartLoc {
  my ($self,%args) = @_;
  return $self->RouteSegments->[0]->StartLoc;
}

sub EndLoc {
  my ($self,%args) = @_;
  return $self->RouteSegments->[-1]->EndLoc;
}

sub StartTime {
  my ($self,%args) = @_;
  return $self->RouteSegments->[0]->StartTime;
}

sub EndTime {
  my ($self,%args) = @_;
  return $self->RouteSegments->[-1]->EndTime;
}

sub Duration {
  my ($self,%args) = @_;
  return ConvertTimeToTime($self->DurationAbs);
}

sub FromTime {
  my ($self,$time) = (shift,shift);
  return ConvertTimeToAbs($self->StartTime) -
    ConvertTimeToAbs($time) +
      $self->DurationAbs;
}

sub Print {
  my ($self,%args) = @_;
  print "(ROUTE\n".
    "\t(:STARTLOC\t".$self->StartLoc->Name .")\n".
      "\t(:STARTINT\t".$self->StartLoc->Intersection .")\n".
	"\t(:ENDLOC\t". $self->EndLoc->Name .")\n".
	  "\t(:ENDINT\t". $self->EndLoc->Intersection .")\n".
	    "\t(:STARTTIME\t". $self->StartTime .")\n".
	      "\t(:ENDTIME\t". $self->EndTime .")\n".
		"\t(:DURATION\t".$self->Duration.")\n".
		  "\t(:FROMTIME\t".ConvertTimeToTime
		    ($self->FromTime($UNIVERSAL::br->MyTime)).")\n".
		      "\t(:TRANSFERS\t".$self->Transfers.")\n".
			"\t(:LENGTH\t".$self->Length.")\n".
			  "\t(:QUALITY\t".$self->Quality.")\n".
			    "\t(:PLAN\n";

  my $curbus = $self->RouteSegments->[0]->Bus;
  my $curdirection = $self->RouteSegments->[0]->Direction;
  my $curtrip = $self->RouteSegments->[0]->Trip;
  print "\t\t(BOARD\t$curbus\t$curdirection\t".$self->StartTime."\t".
    $self->StartLoc->Name.")\n";
  my $top = scalar @{$self->RouteSegments};
  if ($top > 1) {
    for (my $i = 1; $i < $top; ++$i) {
      if ($self->RouteSegments->[$i]->Trip ne $curtrip) {

	print "\t\t(EXIT\t$curbus\t$curdirection\t".$self->RouteSegments->[$i-1]->EndTime."\t".
	  $self->RouteSegments->[$i-1]->EndLoc->Name.")\n";

	$curbus = $self->RouteSegments->[$i]->Bus;
	$curdirection = $self->RouteSegments->[$i]->Direction;
	$curtrip = $self->RouteSegments->[$i]->Trip;

	print "\t\t(BOARD\t$curbus\t$curdirection\t".$self->RouteSegments->[$i]->StartTime."\t".
	  $self->RouteSegments->[$i]->StartLoc->Name.")\n";

      } else {
	if (exists $UNIVERSAL::br->Config->CLIConfig->{'--all'}) {
	  print "\t\t(STAY\t$curbus\t$curdirection\t".$self->RouteSegments->[$i]->StartTime."\t".
	    $self->RouteSegments->[$i]->StartLoc->Name.")\n";
	}
      }
    }
  }
  print "\t\t(EXIT\t$curbus\t$curdirection\t".$self->EndTime."\t".
    $self->EndLoc->Name.")\n";
  print "\t)\n";
  print ")\n\n";
}

sub OneLineSummary {
  my ($self) = @_;
  return "<route".
    " sl=".$self->StartLoc->Name.
      " el=".$self->EndLoc->Name.
	" q=".$self->Quality.
	  " l=".$self->Length.
	    " t=".$self->Transfers.
	      " f=".$self->FromTime($UNIVERSAL::br->MyTime).
		" s=".$self.
		  ">";
}

sub Quality {
  my ($self) = @_;
  return
    $UNIVERSAL::br->Costs->{FromTime} * $self->FromTime($UNIVERSAL::br->MyTime) +
      $UNIVERSAL::br->Costs->{Length} * $self->Length +
	$UNIVERSAL::br->Costs->{Transfers} * $self->Transfers;
}

# sub BreakRouteIntoTrips {
#   my ($self,%args) = @_;
#   # this  function breaks  the  route into  separate  routes for  each
#   # different trip
#   my $top = scalar @{$self->RouteSegments};
#   if ($top > 1) {
#     for (my $i = 1; $i < $top; ++$i) {
#       if ($self->RouteSegments->[$i]->Trip ne $curtrip) {

# 	push @routes, BR::Route->new();
# 	print "\t\t(EXIT\t$curbus\t$curdirection\t".$self->RouteSegments->[$i-1]->EndTime."\t".
# 	  $self->RouteSegments->[$i-1]->EndLoc->Name.")\n";

# 	$curbus = $self->RouteSegments->[$i]->Bus;
# 	$curdirection = $self->RouteSegments->[$i]->Direction;
# 	$curtrip = $self->RouteSegments->[$i]->Trip;

# 	print "\t\t(BOARD\t$curbus\t$curdirection\t".$self->RouteSegments->[$i]->StartTime."\t".
# 	  $self->RouteSegments->[$i]->StartLoc->Name.")\n";

#       } else {
# 	if (exists $UNIVERSAL::br->Config->CLIConfig->{'--all'}) {
# 	  print "\t\t(STAY\t$curbus\t$curdirection\t".$self->RouteSegments->[$i]->StartTime."\t".
# 	    $self->RouteSegments->[$i]->StartLoc->Name.")\n";
# 	}
#       }
#     }
#   }
# }

sub AllLocations {
  my ($self) = @_;
  push @loc, $self->RouteSegments->[0]->StartLoc;
  foreach my $rs (@{$self->RouteSegments}) {
    push @loc, $rs->EndLoc;
  }
  return \@loc;
}

sub DisplayUsingGoogleMaps {
  my ($self) = @_;
  foreach my $loc (@{$self->AllLocations}) {
    print $loc->Intersection.", Pittsburgh, PA\n";
  }
}

1;
