#############################################################################
#
# BR::Conf
# Application Configuration Management
# Copyright(c) 2004, Andrew John Dougherty (ajd@frdcsa.org)
# Distribute under the GPL
#
############################################################################

package BR::Conf;

use strict;
use Carp;
use Config::General;
use Getopt::Declare;

use vars qw($VERSION);
$VERSION = '1.00';
use Class::MethodMaker
  new_with_init => 'new',
  get_set       => [ qw / Config RCConfig RCFile ConfFile CLIConfig Specs / ];

sub init {
  my ($self,%args) = (shift,@_);
  my (%options, %config);

  # parse CLI options
  my $spec = $args{Spec};
  # $spec =~ s/\&lt/\</g;
  # $spec =~ s/\&gt/\>/g;
  $self->CLIConfig(new Getopt::Declare($spec));

  # parse config file
  $self->RCFile($self->Readable($self->ConfFile) || "");
  if ($self->RCFile) {
    $self->Config(new Config::General($self->RCFile));
    $self->RCConfig($self->Config->getall);
  }
}

sub Readable {
  return $_[0] if -r $_[0];
}

1;
