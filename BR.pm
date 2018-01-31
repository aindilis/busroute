package BR;

use BR::Conf;
use BR::Items;
use BR::Route;
use BR::Location;
use BR::RouteSegment;
use BR::Util;
use BR::PDDL;
use BR::Geo;

use Manager::Dialog qw (SubsetSelect);

use Data::Dumper;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       =>
  [ qw
    / Config DataFile DataFileBaseName Locations Routes RouteSegments
      CurrentDay MemoizeLocations LocationHash
      ILocationHash Buses SP SPC MyTime Matches Costs MyPDDL
      TimeCutOff MyGeo
    / ];

sub init {
  my ($self,%args) = (shift,@_);
  $specification = "
	-s <loc>		Start location
	-e <loc>		Finish location
	-t <time>		Start time
	-T <time>		End time
	-D <day>		Day
	-d <files>...		Data files
	-u [<host> <port>]	Run as a UniLang agent
	-r <report>		Report type
	-o <file>		Output file
	--all			Show all segments
	--pddl			Export pddl file
	--timetables		Print time tables
";
  $self->Config(BR::Conf->new
		(Spec => $specification,
		 ConfFile => ""));
  my $conf = $self->Config->CLIConfig;
  if (exists $conf->{'-u'}) {
    $UNIVERSAL::agent->Register
      (Host => defined $conf->{-u}->{'<host>'} ?
       $conf->{-u}->{'<host>'} : "localhost",
       Port => defined $conf->{-u}->{'<port>'} ?
       $conf->{-u}->{'<port>'} : "9000");
  }

  if (! exists $conf->{-d}) {
    if (-d "/usr/share/busroute/data") {
      print "Please choose a datafile:\n";
      $datafile = Choose(split /\n/,`find /usr/share/busroute/data | grep raw.gz`)
    } else {
      $datafile = "";
    }
  }
  $self->DataFile($conf->{-d}->[0] || $datafile);
  $self->Buses({});
  $self->Routes(BR::Items->new(Type => "BR::Route"));
  $self->Locations(BR::Items->new(Type => "BR::Location"));
  $self->RouteSegments(BR::Items->new(Type => "BR::RouteSegment"));
  $self->MemoizeLocations({});
  $self->Matches([]);
  $self->Costs({});
  $self->Costs->{Transfers} = 10;
  $self->Costs->{Length} = 0.1;
  $self->Costs->{FromTime} = 3;
  $self->Costs->{TransferSafety} = 8;

  $datafile = $self->DataFile;
  if (!-f $datafile) {
    print "Can't find datafile: $datafile\n";
    exit(0);
  }

  my $locationhashfile = $datafile;
  $locationhashfile =~ s/\.gz$//;
  $self->DataFileBaseName($locationhashfile);
  $locationhashfile .= "\.lh";
  if (-f "$locationhashfile") {
    print "Loading LocationHash...\n";
    my $contents = `cat $locationhashfile`;
    my $hash = eval $contents;
    $self->LocationHash($hash);
    $self->ILocationHash({});
    foreach my $key (keys %{$self->LocationHash}) {
      $self->ILocationHash->{$self->LocationHash->{$key}} = $key;
    }
  }

  if ($datafile =~ /\.mdf$/) {
    $self->LoadMetaData;
  } else {
    print "Loading data...\n";
    my $counter = 0;
    my $command;
    if ($datafile =~ /\.gz$/i) {
      $command = "gzip -d -c"
    } else {
      $command = "cat";
    }
    my @lines = split /\n/,`$command $datafile`;
    my $wcl = scalar @lines;
    print "0/$wcl\n";
    foreach my $segment (@lines) {
      chomp $segment;
      if ($segment) {
	@sections = split /\s*,\s*/,$segment;
	my $seg = BR::RouteSegment->new
	  (Bus => $sections[0],
	   Day => $sections[1],
	   Direction => $sections[2],
	   StartLoc => $self->FastFindOrCreateLocation($sections[3]),
	   EndLoc => $self->FastFindOrCreateLocation($sections[4]),
	   StartTime => $sections[5],
	   EndTime => $sections[6],
	   Trip => $sections[7] || -2);
	$seg->StartLoc->DepartingRouteSegments->{$seg} = $seg;
	$self->RouteSegments->Add($seg);
      }
      ++$counter;
      if ( !($counter % 10000)) {
	print "$counter/$wcl\n";
      }
    }
    print "Installing departing segments...\n";
    foreach my $loc (@{$self->Locations->Items}) {
      $loc->SortedDepartingRouteSegments
	([sort {GreaterTime($a->StartTime,$b->StartTime)}
	  values %{$loc->DepartingRouteSegments}]);
    }
    print "$wcl/$wcl\n";
  }
}

sub Execute {
  my $self = shift;
  my $conf = $self->Config->CLIConfig;
  # $self->MyGeo(BR::Geo->new);
  if (exists $conf->{'-r'}) {
    if (uc($conf->{'-r'}) eq "DEPARTURE") {
      $self->DoReport($self->DepartureReport());
    }
    if (uc($conf->{'-r'}) eq "DIRECTROUTE") {
      $self->DoReport($self->DirectRouteReport());
    }
  } elsif (exists $conf->{'-p'}) {
    $self->ScheduleReport();
  } elsif (exists $conf->{'--pddl'}) {
    $self->MyPDDL(BR::PDDL->new);
    my ($A,$B) = $self->GetStartAndEndLoc;
    my $day = exists $conf->{-D} ? $conf->{-D} : $self->Today;
    my $to = $self->GetAllRoutesFromAToB
      (Day => $day,
       A => $A,
       B => $B);
    my $from = $self->GetAllRoutesFromAToB
      (Day => $day,
       A => $B,
       B => $A);
    $self->MyPDDL->FillTemplate(Routes => [(@$to,@$from)]);
  } elsif (exists $conf->{'--timetables'}) {
    $self->TimeTables;
  } elsif (! exists $conf->{'-u'}) {
    while (1) {
      $self->FindAllBestRoutes();
    }
  } else {
    # run as an agent, do whatever asked and report back
    
  }
}

sub DoReport {
  my ($self,$report) = (shift,shift);
  my $conf = $self->Config->CLIConfig;
  if (exists $conf->{'-o'}) {
    my $OUT;
    open(OUT,">$conf->{'-o'}");
    print OUT $report;
    close(OUT);
  } else {
    print $report;
  }
}

sub SaveMetaData {
  my ($self,%args) = (shift,@_);
  my $OUT;
  open (OUT,">".$tmpfile)
    or die "Cannot open tmpfile: $tmpfile\n";
  print OUT Dumper([$self->Locations,$self->Routes,$self->RouteSegments]);
  close(OUT);
}

sub LoadMetaData {
  my ($self,%args) = (shift,@_);
  my ($loc,$rout,$routseg) = @{eval `cat $datafile`};
  $self->Locations($loc);
  $self->Routes($rout);
  $self->RouteSegments($routseg);
}

sub DepartureReport {
  my ($self,%args) = (shift,@_);

  # A  travel times  report lists  all travel  times of  direct routes
  # between  two locations.   If  there are  no  direct routes  during
  # certain times, it lists indirect routes with travel time.a
  my $page = "";
  my $lochash = {};
  my $l1 = $self->LookupLocationByName($conf->{-s} || Query("Please enter inbound location regex: "));
  if ($l1) {
    $lochash->{I} = $l1;
    my $l2 = $self->LookupLocationByName($conf->{-e} || Query("Please enter outbound location regex: "));
    if ($l2) {
      $lochash->{O} = $l2;
      $page .= "--------------------------------------------------------------------------------\n\n";
      $page .= "ALL DEPARTURES FROM LOCATION REPORT\n";
      $page .= "Inbound: ".$l1->Name."\n";
      $page .= "Outbound: ".$l2->Name."\n";
      $page .= "\n--------------------------------------------------------------------------------\n\n";

      my $mapping = {
		     I => "Inbound",
		     O => "Outbound",
		     W => "Weekday",
		     Sa => "Saturday",
		     S => "Sunday",
		     H => "Holiday",
		    };

      foreach my $direction (qw (I O)) {
	$page .= "Direction: $mapping->{$direction}\n\n";

	foreach my $day (qw(W Sa S H)) {
	  $page .= "Day: $mapping->{$day}\n\n";
	  my @segs;
	  foreach my $seg ($lochash->{$direction}->ListDepartingConstrainedBy
			   (Direction => $direction,
			    Day => $day)) {
	    push @segs, $seg;
	  }
	  $page .= $self->PrintOut(@segs);
	}
	$page .= "--------------------------------------------------------------------------------\n\n";
      }
    }
  }
  return $page;
}

sub DirectRouteReport {
  my ($self,%args) = (shift,@_);
  # A  travel times  report lists  all travel  times of  direct routes
  # between  two locations.   If  there are  no  direct routes  during
  # certain times, it lists indirect routes with travel time.a
  return $self->DepartureReport();
}

sub PrintOut {
  my ($self,@segs) = (shift,@_);
  my $count = 0;
  my $page = "";
  if (@segs) {
    foreach my $seg (@segs) {
      my $item = sprintf("%6s",$seg->StartTime)."(".$seg->Bus.")";
      $page .= "$item";
      ++$count;
      if ($count % 6) {
	$page .= " ";
      } else {
	$page .= "\n";
      }
    }
    if ($count % 6) {
      $page .= "\n";
    }
  }
  $page .= "\n";
  return $page;
}

sub ScheduleReport {
  my ($self,%args) = (shift,@_);
  my $l1 = $self->LookupLocationByName($conf->{-s} || Query("Please enter start location regex: "));
  if ($l1) {
    my $route = Query("Please enter bus route: ");

    foreach my $seg ($self->RouteSegments->List) {
      if ($seg->Bus eq $route) {
	push @matches, $seg;
      }
    }

    foreach my $dir (qw(I O)) {
      print "Direction: $dir\n";
      foreach my $day (qw (W Sa S H)) {
	print "Day: $day\n";
	my %times;
	foreach my $seg (@matches) {
	  if ($seg->StartLoc eq $l1) {
	    if ($seg->Day eq $day) {
	      if ($seg->Direction eq $dir) {
		$times{$seg->StartTime} = 1;
	      }
	    }
	  }
	}
	print join (" ",sort {GreaterTime($a,$b)} keys %times);
	print "\n";
      }
    }
  }
}

sub FastFindOrCreateLocation {
  my ($self,$name) = (shift,shift);
  if (defined $self->ILocationHash) {
    $name = $self->ILocationHash->{$name};
  }
  if (exists $self->MemoizeLocations->{$name}) {
    return $self->MemoizeLocations->{$name};
  } else {
    my $loc = BR::Location->new(Name => $name);
    $self->Locations->Add($loc);
    $self->MemoizeLocations->{$name} = $loc;
  }
}


sub FindOrCreateLocation {
  my ($self,$name) = (shift,shift);
  my %matches;
  foreach my $location ($self->Locations->List) {
    if ($location->Name eq $name) {
      $matches{$location->Name} = $location;
    }
  }
  if (scalar keys %matches) {
    return $matches{Choose(keys %matches)};
  } else {
    my $loc = BR::Location->new(Name => $name);
    $self->Locations->Add($loc);
    return $loc;
  }
}

sub LookupLocationByName {
  my ($self,$regex,$l1) = (shift,shift,shift);
  my %matches;
  if ($regex) {
    foreach my $location ($l1 ? $l1->Reachable : $self->Locations->List) {
      if ($location->Name =~ /$regex/i) {
	$matches{$location->Name} = $location;
      }
    }
    if (scalar keys %matches) {
      # if all the matches share the same intersection, return the
      # regex if it is a match or the first match
      my $autochoose = 1;
      my @keys = sort keys %matches;
      my $last = $matches{$keys[0]}->Intersection;
      foreach my $key (@keys) {
	if ($matches{$key}->Intersection ne $last) {
	  $autochoose = 0;
	}
      }
      if ($autochoose) {
	if (exists $matches{$regex}) {
	  return $matches{$regex};
	} else {
	  return $matches{$keys[0]};
	}
      } else {
	return $matches{Choose(sort keys %matches)};
      }
    } else {
      print "Location not found: $regex\n";
    }
  }
  return 0;
}

sub GetTime {
  my ($self,%args) = (shift,@_);
  my $time = `date "+%I:%M%P"`;
  chomp $time;
  $time =~ s/^0//;
  $time =~ s/m$//;
  return $self->Config->CLIConfig->{-t} || $self->QueryTime() || $time;
}

sub QueryTime {
  my ($self) = (shift);
  my $t;
  do {
    $t = Query("Please enter time: ")
  } while ($t !~ /^(by )?([0-9]?[0-9]:[0-9][0-9][ap])?$/i and
	   print "Please either leave blank or enter a time (don't forget trailing a or p)\n");
  return $t;
}

sub FindAllBestRoutes {
  my ($self,%args) = (shift,@_);
  my $conf = $self->Config->CLIConfig;

  print "Selecting locations...\n";
  my $sfn = 0;
  my $debug = 0;
  my $day = $self->Today;
  $UNIVERSAL::br->CurrentDay(exists $conf->{-D} ? $conf->{-D} : $day);
  my ($l1,$l2) = $self->GetStartAndEndLoc;
  if ($l1 and $l2) {
    # here is a perhaps faster approach that does the same thing
    my $mytime = $self->GetTime;
    $self->MyTime($mytime);
    print "$mytime\n";
    $self->PlanRoute
      (Day => $day,
       Time => $mytime,
       StartLoc => $l1,
       EndLoc => $l2);

    $self->PrintSolutions(L1 => $l1,
			  L2 => $l2);
  }
}

sub PrintSolutions {
  my ($self,%args) = (shift,@_);
  if (scalar @{$self->Matches}) {
    print "DISPLAYING SOLUTION(S)\n";
    foreach my $lm (@{$self->Matches}) {
      print "From now: ".
	ConvertTimeToTime($self->SP->{$lm->Name}->FromTime($self->MyTime)).
	  "\n";
      $self->SP->{$lm->Name}->Print;
      $self->SP->{$lm->Name}->DisplayUsingGoogleMaps;
    }
    $self->Matches([]);
  } else {
    print "NO SOLUTIONS FOUND from ".$args{L1}->Intersection." to ".
      $args{L2}->Intersection."\n";
  }
}

sub GetStartAndEndLoc {
  my ($self,%args) = (shift,@_);
  my $conf = $self->Config->CLIConfig;
  my $l1 = $self->LookupLocationByName
    ($conf->{-s} ||
     Query("Please enter start location regex: "));
  if ($l1) {
    my $l2 = $self->LookupLocationByName
      ($conf->{-e} ||
       Query("Please enter end location regex: "),$l1);
    if ($l2) {
      return ($l1,$l2);
    }
  }
}

sub GetAllSolutions {
  my ($self,%args) = (shift,@_);
  my @sol;
  foreach my $lm (@{$self->Matches}) {
    push @sol, $self->SP->{$lm->Name};
  }
  return \@sol;
}

sub GetAllRoutesFromAToB {
  my ($self,%args) = (shift,@_);
  my ($l1,$l2,$day) = ($args{A},$args{B},$args{Day});
  $UNIVERSAL::br->CurrentDay($day);
  my @routes;
  my $conf = $self->Config->CLIConfig;
  my $sfn = 0;
  my $debug = 0;
  if ($l1 and $l2) {
    # only here we start the time off as early as possible...
    my $mytime = "4:00a";
    $self->MyTime($mytime);
    print "Generating all routes from ".
      $l1->Intersection." to ".$l2->Intersection."\n";
    my $done = 0;
    do {
      print "After $mytime ---\n";
      $self->Matches([]);
      $self->PlanRoute
	(Day => $day,
	 Time => $mytime,
	 StartLoc => $l1,
	 EndLoc => $l2);
      # now if there are results, we simply adjust my time, replan

      # for all  the matches, we're gonna  have to sort  that out, but
      # for now just take the first, and set the time to be 1 minute after that

      my @sol = @{$self->GetAllSolutions};
      if (@sol) {
	my $r = shift @sol;
	print "--- next is ".$r->StartTime.".\n";
	push @routes, $r;
	$mytime = $self->AddTime($r->StartTime,(2.0/60.0));
	$self->MyTime($mytime);
	$self->SP({});
      } else {
	print "--- there are no more trips\n";
	$done = 1;
      }
    } while (! $done);
  }
  return \@routes;
}

sub AddTime {
  my ($self,$t1,$t2) = (shift,shift,shift);
  # print "$t1\n";
  # print "$t2\n";
  my $t3 = ConvertTimeToAbs($t1) + $t2;
  # print "$t3\n";
  my $t4 = ConvertTimeToHours($t3);
  # print "$t4\n";
  return $t4;
}

sub PlanRoute {
  my ($self,%args) = (shift,@_);
  my ($day,$mytime,$l1,$l2,$cutoff,$factor) =
    ($args{Day}, $args{Time}, $args{StartLoc}, $args{EndLoc},
     $args{CutOff} || 2, $args{Factor} || 2);
  do {
    print "Cutoff: $cutoff\n";
    $self->TimeCutOff($cutoff / $self->Costs->{FromTime});
    $self->SP({});
    $self->SPC({});
    my @q;
    foreach my $lm ($self->ListMatchingIntersections($l1)) {
      $self->SP->{$lm->Name} = BR::Route->new
	(RouteSegments =>
	 [ BR::RouteSegment->new
	   (Bus => "none",
	    Day => "none",
	    Direction => "none",
	    StartLoc => $lm,
	    EndLoc => $lm,
	    StartTime => $mytime,
	    EndTime => $mytime,
	    Trip => -1) ],
	 Time => $mytime);
      ++$self->SPC->{$lm->Name};
      foreach my $seg ($lm->ListDepartingAfter
		       (Time => $mytime)) {
	my $newroute = BR::Route->new(RouteSegments => [ $seg ],
				      Time => $mytime);
	$self->SP->{$seg->EndLoc->Name} = $newroute;
	++$self->SPC->{$seg->EndLoc->Name};
	push @q, $newroute;
      }
    }
    my $size = 0;
    my $counter = 0;
    my $diff = 0;
    while (@q) {
      ++$counter;
      if ( !($counter % 25)) {
	$diff = $size;
	$size = scalar @q;
	$diff = $size - $diff;
	if ($debug) {
	  print "$size\t$diff\n";
	  print "Coverage: ".(scalar keys %{$self->SPC})."/".
	    (scalar $self->Locations->List)."\n";
	}
	foreach my $lm ($self->ListMatchingIntersections($l2)) {
	  if (exists $self->SP->{$lm->Name}) {
	    $self->SP->{$lm->Name}->Print if $debug;
	    if (! $sfn) {
	      print "Solution found, optimizing...\n";
	      $sfn = 1;
	    }
	    ++$self->SPC->{$lm->Name};
	  }
	}
	if ($diff > 0) {
	  print "Resorting routes...\n" if $debug;
	  @q = sort {$self->SortBetterRoute($a,$b,$mytime)} @q;
	  print "Done resorting routes...\n" if $debug;
	}
      }
      # now we may push all of our routes on to the queue
      my $route = shift @q;
      # $route->Print;
      my @links = $route->EndLoc->ListDepartingAfter
	(Time => $route->EndTime);
      if (@links) {
	foreach my $seg (@links) {
	  # print $seg->OneLineSummary."\n";
	  my $tl = $seg->EndLoc;
	  my $tn = $tl->Name;
	  if ((! exists $self->SP->{$tn}) or
	      ($self->SP->{$tn} ne $route)) {

	    my $newroute = BR::Route->new
	      (Copy => $route,
	       Time => $mytime);
	    $newroute->PushRouteSegment($seg);

	    my $dothisfuckingthing = 0;
	    if (exists $self->SP->{$tn}) {
	      if ($newroute->Quality < $self->SP->{$tn}->Quality) {
		$dothisfuckingthing = 1;
	      }
	    } else {
	      if ($newroute->Quality < $cutoff) {
		$dothisfuckingthing = 1;
	      }
	    }
	    if ($dothisfuckingthing) {
	      $self->SP->{$tn} = $newroute;
	      ++$self->SPC->{$tn};
	      # print $newroute->OneLineSummary.">\n";
	      push @q, $newroute;
	    }
	  }
	}
      }
    }
    # now we have the shortest paths to all destinations, just list
    # their names and times
    #       foreach my $key (keys %{$self->SP}) {
    # print "<key: ".$key."><time: ".$self->SP->{$key}->EndTime.">\n";
    #       }
    $cutoff *= $factor;
  } while ($self->ContinueLooping($l2,$cutoff));
}

sub ContinueLooping {
  my ($self,$l2,$cutoff) = (shift,shift,shift);
  my $match = 0;
  foreach my $lm ($self->ListMatchingIntersections($l2)) {
    if (exists $self->SP->{$lm->Name}) {
      push @{$self->Matches}, $lm;
      $match = 1;
    }
  }
  if (! $match) {
    if ($cutoff < 100) {
      return 1;
    }
  }
  return 0;
}

sub ListMatchingIntersections {
  my ($self,$lm) = (shift,shift);
  # print "List matching\n";
  my @matches;
  foreach my $ll ($self->Locations->List) {
    if ($ll->Intersection eq $lm->Intersection) {
      push @matches, $ll;
    }
  }
  # print "Done list matching\n";
  return @matches;
}

sub SortBetterRoute {
  my ($self, $a, $b, $mytime) = (shift,shift,shift,shift);
  if (exists $self->SPC->{$a->EndLoc->Name}) {
    if (exists $self->SPC->{$b->EndLoc->Name}) {
      if ($self->SPC->{$a->EndLoc->Name} == 1) {
	if ($self->SPC->{$b->EndLoc->Name} == 1) {
	  return $self->BetterRoute($a,$b,$mytime);
	} else {
	  return 1;
	}
      } else {
	if ($self->SPC->{$b->EndLoc->Name} == 1) {
	  return -1;
	} else {
	  return $self->BetterRoute($a,$b,$mytime);
	}
      }
    } else {
      return -1;
    }
  } elsif (exists $self->SPC->{$b->EndLoc->Name}) {
    return 1;
  } else {
    return $self->BetterRoute($a,$b,$mytime);
  }
}

sub BetterRoute {
  my ($self,$a,$b,$mytime) = (shift,shift,shift,shift);
  return $a->Quality <=> $b->Quality;
}

sub UnmarkAllLocations {
  my ($self,%args) = (shift,@_);
  foreach my $loc ($self->Locations->List) {
    $loc->Marked(0);
  }
}

sub TimeTables {
  my ($self,%args) = (shift,@_);
  # return time tables for a specific bus
  print "Please select buses for which to print timetables:\n";
  foreach my $bus
    (SubsetSelect(Set => $self->ListBuses,
		  Selection => {})) {
      print "$bus\n";
    }
}

sub ListBuses {
  my ($self,%args) = (shift,@_);
  if (! scalar keys %{$self->Buses}) {
    print "Building bus list\n";
    foreach my $rs ($self->RouteSegments->Items) {
      print Dumper($rs);
      $self->Buses->{$rs->Bus} = 1;
    }
  }
  return sort keys %{$self->Buses};
}

sub Today {
  my ($self,%args) = (shift,@_);
  my $day = `date "+%a"`;
  chomp $day;
  if ($day eq "Sun") {
    $day = "S";
  } elsif ($day eq "Sat") {
    $day = "Sa";
  } elsif (1) {
    $day = "W";
  } else {
    $day = "H";
  }
  return $day;
}

sub ProcessMessage {
  my ($self,%args) = (shift,@_);
  my $m = $args{Message};
  my $it = $m->Contents;
  if ($it) {
    # process the args in very much the same fashion as the regular args
    # for now, just do something simple
    if ($it =~ /^start (.*)$/) {
      my $f = $self->MyFilterManager->AddFilter
	(Specification => $1);
      my $ret = $self->MySourceManager->Search
	(Filter => $f,
	 Sources => $conf->{-s});
      my $contents = join("\n",map {$_->SPrint} @$ret);
      $self->SendMessage(Contents => $contents);
    } elsif ($it =~ /^search all$/) {
      my @all;
      foreach my $f ($self->MyFilterManager->MyFilters->Values) {
	my $ret = $self->MySourceManager->Search
	  (Filter => $f,
	   Sources => $conf->{-s});
	push @all, @$ret;
      }
      my $contents = join("\n",map {$_->SPrint} @all);
      $self->SendMessage(Contents => $contents);
    } elsif ($it =~ /^list$/) {
      $self->SendMessage
	(Contents => join("\n",map {$_->SPrint}
			  $self->MyFilterManager->MyFilters->Values));
    } elsif ($it =~ /^(-a\s*(.*?))?\s*(-n\s*(.*?))?\s*(-d\s*(.*?))?\s*(-D\s*(.*?))?$/) {
      my $criteria = {};
      $criteria->{Any} = $2 if $1;
      $criteria->{Name} = $4 if $3;
      $criteria->{ShortDesc} = $6 if $5;
      $criteria->{LongDesc} = $8 if $7;
      my $ret = $self->MySourceManager->Search
	(Criteria => $criteria,
	 Sources => $conf->{-s});
      my $contents = join("\n",map {$_->SPrint} @$ret);
      $self->SendMessage(Contents => $contents);
    } elsif ($it =~ /^system (.*)$/i) {
      # lookup this particular system and produce its contents
      my $ret = $self->MySourceManager->Search
	(Criteria => {Name => "^$1\$"},
	 Sources => []);
      foreach my $sys (@$ret) {
	$sys->SPrintFull;
      }
    } elsif ($it =~ /^reload$/i) {
      $self->MySourceManager->LoadSources;
    } elsif ($it =~ /^update$/i) {
      $self->MySourceManager->UpdateSources;
    } elsif ($it =~ /^(quit|exit)$/i) {
      $UNIVERSAL::agent->Deregister;
      exit(0);
    }
  }
}

sub SendMessage {
  my ($self,%args) = @_;
  $UNIVERSAL::agent->Send
    (Handle => $UNIVERSAL::agent->Client,
     Message => UniLang::Util::Message->new
     (Sender => "BusRoute",
      Receiver => "UniLang",
      Date => undef,
      Contents => $args{Contents}));
}

1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

BR - Perl bus route planning system

=head1 SYNOPSIS

  use BR;
  use UniLang::Agent::Agent;
  use UniLang::Util::Message;
  $UNIVERSAL::agent = UniLang::Agent::Agent->new(Name => "CLEAR",
					       ReceiveHandler => \&Receive);
  $UNIVERSAL::br = BR->new();
  $UNIVERSAL::br->Execute();
  sub Receive {}

=head1 REQUIRES

Requires the following modules be installed:

=over 4

=item L<Verber::Modules::Ext>

=back

=head1 DESCRIPTION

The BR  class is designed to provide  the base class for  a system for
composing  itineraries from bus  schedules, as  in autobuses  and city
bus.    It  is  being   generalized  to   handle  multiple   modes  of
transportation (subway, train, boat, car, airplane, etc).

=head2 EXPORT

None by default.

=head1 METHODS

=over 4

=item C<new()>

Class constructor.  Returns a reference to an initialized BusRoute object.

=back

=head1 SEE ALSO

=over 4

=item L<BR::Location>

=item L<BR::Util>

=item L<BR::Route>

=item L<BR::RouteSegment>

See FRDCSA ( L<http://shops.sf.net/> )

=back

=head1 AUTHOR

Andrew J. Dougherty E<lt>andrewdo@andrew.cmu.edu<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005 by Andrew J. Dougherty

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
