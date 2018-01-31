sub FindMatchingIntersections {
  my ($self,%args) = (shift,@_);
  # here are the various techniques for finding matching intersections
  # ?i1 AT ?i2 : ?i2 AT ?i1
  # ?i1 AT ?i2 : ?i1 OPP ?i2
  # ?i1 AT ?i2 : ?i1 AT ?i2  (Far Side)
  # ?i1 AT ?i2 : ?i1 AT ?i2  (Near Side)
  my @similar = ();
  if ($i =~ /(.+) (AT|OPP) (.+)  \((.+) Side\)/) {
    my $spec = $2;
    if ($spec eq "AT") {
      $ospec = "OPP";
    } elsif ($spec eq "OPP") {
      $ospec = "AT";
    }
    my $side = $4;
    if ($side eq "Near") {
      $oside = "Far";
    } elsif ($side eq "Far") {
      $oside = "Near";
    }
    push @similar, "$2 $spec $1";
    push @similar, "$1 $ospec $2";
    push @similar, "$1 AT $2  ($oside Side)";
    push @similar, "$1 OPP $2  ($oside Side)";
    push @similar, "$2 AT $1  ($oside Side)";
    push @similar, "$2 OPP $1  ($oside Side)";
  } elsif ($i =~ /(.+) (AT|OPP) (.+)/) {
    my $spec = $2;
    if ($spec eq "AT") {
      $ospec = "OPP";
    } elsif ($spec eq "OPP") {
      $ospec = "AT";
    }
    push @similar, "$2 $spec $1";
    push @similar, "$1 $ospec $2";
    push @similar, "$1 AT $2  ($oside Side)";
    push @similar, "$1 OPP $2  ($oside Side)";
    push @similar, "$2 AT $1  ($oside Side)";
    push @similar, "$2 OPP $1  ($oside Side)";
  }
}

sub LatLongLookup {
  my ($self,%args) = (shift,@_);
  # lookup  the lat  and  long of  an  intersection, make  sure it  is
  # consistent with travel times
}


  if (0 && $l1) {
    my $mydate = $conf->{-t} || Query("Please enter time: ") || $date;
    foreach my $seg (values %{$l1->DepartingRouteSegments}) {
      if ($seg->Day eq $UNIVERSAL::br->CurrentDay) {
	if (GreaterTime($seg->StartTime,$mydate) >= 0) {
	  my $newroute = BR::Route->new(RouteSegments => [ $seg ]);
	  push @q, $newroute;
	}
      }
    }
    while (@q) {
      my $route = shift @q;
      my $change = 0;
      # $route->Print;
      my $tl = $route->EndLoc;
      my $tn = $tl->Name;
      $lochash->{$tn} = $tl;
      if (! exists $self->SP->{$tn}) {
	$self->SP->{$tn} = $route;
	$change = 1;
      } elsif (GreaterTime($self->SP->{$tn}->EndTime,$route->EndTime)) {
	$self->SP->{$tn} = $route;
	$change = 1;
      }
      if ($change) {
	# now we may push all of our routes on to the queue
	foreach my $seg (values %{$tl->DepartingRouteSegments}) {
	  if ($seg->Day eq $UNIVERSAL::br->CurrentDay) {
	    if (GreaterTime($seg->StartTime,$route->EndTime) >= 0) {
	      my $newroute = BR::Route->new
		(RouteSegments => [ @{$route->RouteSegments}, $seg ]);
	      push @q, $newroute;
	    }
	  }
	}
      }
    }
  }


