package BR::PDDL;

use Verber::Ext::PDDL;

use Data::Dumper;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       => [ qw / PDDL / ];

sub init {
  my ($self,%args) = (shift,@_);
  $self->PDDL
    (Verber::Ext::PDDL->new
     (System => "busroute"));
}

# simple program to translate bus route info into pddl

sub FillTemplate {
  my ($self,%args) = (shift,@_);
  foreach my $route (@{$args{Routes}}) {
    my $bus = "Bus-".$route->RouteSegments->[0]->Bus."-".
      $route->RouteSegments->[0]->Trip;

    # add buses and stops
    my $s1 = $self->PDDL->Clean($route->StartLoc->Intersection);
    my $s2 = $self->PDDL->Clean($route->EndLoc->Intersection);
    $self->PDDL->AddType($bus,"bus");
    $self->PDDL->AddType($s1,"stop");
    $self->PDDL->AddType($s2,"stop");

    # quick inline  time conversion
    my $entry = $route->StartTime;
    my $time;
    if ($entry =~ /^([0-9]+):([0-9]+)([ap])$/) {
      if ($1 == 12) {
	$time = ($2 / 60.0) + ($3 eq "a" ? 0 : 12);
      } else {
	$time = $1 + ($2 / 60.0) + ($3 eq "a" ? 0 : 12);
      }
    } else {
      print "<<<$entry>>>?\n";
      $time = "-1";
    }

    # maybe actually calculate this out

    $self->PDDL->AddInit("(= (transit-time $bus $s1 $s2) ".
			 $route->DurationAbs.")");

    $self->PDDL->AddInit("(at $time (at $bus $s1))");
    $self->PDDL->AddInit("(at ". ($time + 0.01) ." (not (at $bus $s1)))");

    $self->PDDL->AddInit("(at ". ($time + $route->DurationAbs).
			 " (at $bus $s2))");
    $self->PDDL->AddInit("(at ". ($time + $route->DurationAbs + 0.01) .
			 " (not (at $bus $s2)))");
  }
  print "Exporting pddl\n";
  $self->PDDL->Export;
}

1;
