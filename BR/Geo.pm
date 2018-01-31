package BR::Geo;

use Manager::Dialog qw (QueryUser Choose);
use Data::Dumper;

use DBI;
use Geo::Distance;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       =>
  [ qw
    / LatLongFile RoadNameHash LocationHash MyGeo StopNameHashFile DBH
    / ];

sub init {
  my ($self,%args) = (shift,@_);
  $self->LatLongFile
    ($UNIVERSAL::br->DataFileBaseName.
     ".latlong");
  $self->StopNameHashFile
    ($UNIVERSAL::br->DataFileBaseName.
     ".lh");
  $self->RoadNameHash({});
  $self->LocationHash({});
  $self->LoadLatLongData;
  $self->MyGeo(Geo::Distance->new);
}

sub LoadLatLongData {
  my ($self,%args) = (shift,@_);
  if (! -e $self->LatLongFile) {
    $self->CreateLatLongFile;
  }
  $self->LoadLatLongFile;
}

sub CreateLatLongFile {
  my ($self,%args) = (shift,@_);
  $self->LoadTigerData;
  $self->GenerateLocationHash;
  my $OUT;
  open(OUT,">".$self->LatLongFile) or die "ouch\n";
  print Dumper($self->LocationHash);
  print OUT Dumper($self->LocationHash);
  close(OUT);
}

sub LoadLatLongFile {
  my ($self,%args) = (shift,@_);
  if (! defined $self->LocationHash) {
    my $f = $self->LatLongFile;
    my $c = `cat $f`;
    my $e = eval $c;
    $self->LocationHash($e);
  }
}

sub LoadTigerData {
  my ($self,%args) = (shift,@_);
  my $number = "42003";
  my ($regex,$cnt) = $self->GenRegex();
  # print "$regex\n$cnt\n";
  print "Loading Tiger Route data\n";
  my $tigerdatadir = "data/zones/pittsburgh/tigerdata";
  foreach my $l (split /\n/, `cat $tigerdatadir/TGR$number.RT1`) {
    if ($l =~ /$regex/) {

      my $roadname = $4;
      if ($roadname) {
	$roadname =~ s/^\s*//;
	$roadname =~ s/\s*$//;
      }

      my $s1 = $13;
      if ($s1) {
	$s1 =~ s/^\s*//;
	$s1 =~ s/\s*$//;
      }

      my $s2 = $14;
      if ($s2) {
	$s2 =~ s/^\s*//;
	$s2 =~ s/\s*$//;
      }

      if (! exists $self->RoadNameHash->{$roadname}) {
	$self->RoadNameHash->{$roadname} = {};
      }
      $self->RoadNameHash->{$roadname}->{$s1} = 1;
      $self->RoadNameHash->{$roadname}->{$s2} = 1;
    }
  }
  print "Done\n";
}

sub GenerateLocationHash {
  my ($self,%args) = (shift,@_);
  my $f = $self->StopNameHashFile;
  my $c = `cat $f`;
  my $lh = eval $c;
  print Dumper($lh);
  my $size = scalar keys %$lh;
  my $cnt = 0;
  foreach my $k (keys %$lh) {
    if (!($cnt % 10)) {
      print "$cnt/$size\n";
    }
    ++$cnt;
    my ($s1,$s2) = $self->Name2Intersection(Name => $k);
    $s1 = $self->GetStreetname($s1);
    my $matches = {};
    if ($s1) {
      $s2 = $self->GetStreetname($s2);
      if ($s2) {
	# now attempt to find a shared latlong data point for these two
	foreach my $latlong (keys %{$self->RoadNameHash->{$s1}}) {
	  if (exists $self->RoadNameHash->{$s2}->{$latlong}) {
	    # -79912672+40446768
	    # to this:
	    # -79.912672, +40.446768
	    $latlong =~ s/(.{3})(.{6})(.{3})(.{6})/$1.$2, $3.$4/;
	    $matches->{$latlong} = 1;
	  }
	}
      }
    }
    if (scalar keys %$matches) {
      foreach my $key (keys %$matches) {
	$self->LocationHash->{"$s1 and $s2"} = $key;
      }
    } else {
      $self->LocationHash->{"$s1 and $s2"} = "no match";
    }
  }
}

sub Name2Intersection {
  my ($self,%args) = (shift,@_);
  my $name = $args{Name};
  if ($name =~ /^(.+?)( (Ave|St|Rd|Blvd)\.)? (AT|OPP) (.+?)(  \((.+) Side\).*)?$/) {
    @l = ($1,$5);
    return sort @l;
  } else {
    print "No match $name\n";
  }
}

sub GetStreetname {
  my ($self,$retval) = (shift,shift);
  # attempt to find matching keys
  my @matches;
  foreach my $key (keys %{$self->RoadNameHash}) {
    # print "<$key>\n";
    if ($key =~ /^$retval$/i) {
      return $key;
    } elsif ($key =~ /$retval/i) {
      push @matches, $key;
    }
  }
  if (scalar @matches == 0) {
    return "";
  } elsif (scalar @matches == 1) {
    my $streetname = Choose(@matches);
    if (! $streetname) {
      print "";
    } else {
      return $streetname;
    }
  } else {
    return "";
  }
}

sub GenRegex {
  my ($self,%args) = (shift,@_);
  my $sample = "10604  #51671428 #A  #Steiner                       #Ave".
    "   #A41       #2201       #2299       #2200       #229800001512215122".
      "              #42420030038351283512          #8351283512488400488400".
	"10051004 #-79865570+40371569 #-79865970+40371069";
  my $regex;
  my @items = split /\#/,$sample;
  foreach my $e (@items) {
    $regex .= "(.{".length($e)."})";
  }
  return ($regex,scalar @items);
}

sub ComputeNearestBusStop {
  my ($self,%args) = (shift,@_);
  # given an address, compute the nearest busstop to that address
  my $latlong = $args{LatLong} || $self->LookupLatLong($args{Address});
  $self->Geo->formula('hsin');
  $self->Geo->reg_unit( 'toad_hop', 200120 );
  $self->Geo->reg_unit( 'frog_hop' => 6 => 'toad_hop' );
  my $locations = $self->Geo->closest
    ( $unit, $unit_count, $lon, $lat, $source, $options);
  print Dumper($locations);
}

1;
