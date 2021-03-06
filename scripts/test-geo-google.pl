#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use Geo::Google;

#My office
my $gonda_addr = '695 Charles E Young Dr S, Westwood, CA 90024';
#Stan's Donuts
my $stans_addr = '10948 Weyburn Ave, Westwood, CA 90024';

#Instantiate a new Geo::Google object.
my $geo = Geo::Google->new();

#Create Geo::Google::Location objects.  These contain
#latitude/longitude coordinates, along with a few other details
#about the locus.
my ( $gonda ) = $geo->location( address => $gonda_addr );
my ( $stans ) = $geo->location( address => $stans_addr );
print $gonda->latitude, " / ", $gonda->longitude, "\n";
print $stans->latitude, " / ", $stans->longitude, "\n";

#Create a Geo::Google::Path object.
my ( $donut_path ) = $geo->path($gonda,$stans);

#A path contains a series of Geo::Google::Segment objects with
#text labels representing turn-by-turn driving directions between
#the two loci.
my @segments = $donut_path->segments();

#This is the human-readable directions for the first leg of the
#journey.
print $segments[0]->text(),"\n";

#Geo::Google::Segment objects contain a series of
#Geo::Google::Location objects -- one for each time the segment
#deviates from a straight line to the end of the segment.
my @points = $segments[1]->points;
print $points[0]->latitude, " / ", $points[0]->longitude, "\n";

#Now how about some coffee nearby?
my @coffee = $geo->near($stans,'coffee');
#Too many.  How about some Coffee Bean & Tea Leaf?
@coffee = grep { $_->title =~ /Coffee.*?Bean/i } @coffee;

#Still too many.  Let's find the closest with a little trig and
#a Schwartzian transform
my ( $coffee ) = map { $_->[1] }
  sort { $a->[0] <=> $b->[0] }
  map { [ sqrt(
	       ($_->longitude - $stans->longitude)**2
	       +
	       ($_->latitude - $stans->latitude)**2
	      ), $_ ] } @coffee;
