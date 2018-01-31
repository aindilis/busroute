package BR::Location;

use BR::Util;
use Data::Dumper;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       =>
  [ qw / Name Intersection DepartingRouteSegments SortedDepartingRouteSegments Marked / ];

sub init {
  my ($self,%args) = (shift,@_);
  $self->Name($args{Name} || "");
  $self->Name2Intersection;
  $self->DepartingRouteSegments($args{DepartingRouteSegments} || {});
  $self->Marked(0);
}

sub Name2Intersection {
  my ($self,%args) = (shift,@_);
  my $name = $self->Name;
  if ($name =~ /^(.+?)( (Ave|St|Rd|Blvd)\.)? (AT|OPP) (.+?)(  \((.+) Side\).*)?$/) {
    @l = ($1,$5);
    $self->Intersection(join " and ", (sort @l));
  } else {
    print "No match $name\n";
    $self->Intersection($name);
  }
  # print $self->Intersection."\n";
}


sub ListDepartingRouteSegments {
  my ($self,%args) = (shift,@_);
  return values %{$self->DepartingRouteSegments};
}

sub ListDepartingConstrainedBy {
  my ($self,%args) = (shift,@_);
  my @ret;
  my $day = exists $args{Day} ? $args{Day} : $UNIVERSAL::br->CurrentDay;
  foreach my $seg (@{$self->SortedDepartingRouteSegments}) {
    if (! defined $args{Direction} || $seg->Direction eq $args{Direction}) {
      if ($seg->Day eq $day) {
	push @ret, $seg;
      }
    }
  }
  return @ret;
}

sub ListDepartingAfter {
  my ($self,%args) = (shift,@_);
  my @ret;
  foreach my $seg ($self->ListDepartingConstrainedBy(%args)) {
    if (GreaterTime($seg->StartTime,$args{Time}) >= 0 and
       GreaterTime
	(ConvertTimeToHours
	 (ConvertTimeToAbs($args{Time}) + 4),
	 $seg->StartTime)) {
      push @ret, $seg;
    }
  }
  return @ret;
}

sub Reachable {
  my ($self) = (shift);
  $UNIVERSAL::br->UnmarkAllLocations;
  my @connected;
  my @queue = ($self);
  while (my $loc = shift @queue) {
    foreach my $seg ($loc->ListDepartingRouteSegments) {
      if (!($seg->EndLoc->Marked)) {
	push @connected,$seg->EndLoc;
	$seg->EndLoc->Marked(1);
	push @queue,$seg->EndLoc;
      }
    }
  }
  return @connected;
}

1;

