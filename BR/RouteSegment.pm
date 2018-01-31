package BR::RouteSegment;

use BR::Util;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       =>
  [ qw / Bus Day Direction StartLoc EndLoc StartTime EndTime Trip / ];

sub init {
  my ($self,%args) = (shift,@_);
  $self->Bus($args{Bus} || "");
  $self->Day($args{Day} || "");
  $self->Direction($args{Direction} || "");
  $self->StartLoc($args{StartLoc} || "");
  $self->EndLoc($args{EndLoc} || "");
  $self->StartTime($args{StartTime} || "");
  $self->EndTime($args{EndTime} || $self->StartTime || "");
  $self->Trip($args{Trip} || "");
}

sub DurationAbs {
  my ($self,%args) = (shift,@_);
  my $tmp = ConvertTimeToAbs($self->EndTime) -
    ConvertTimeToAbs($self->StartTime);
  if ($tmp < 0) {
    $tmp = 24.0 + $tmp;
  }
  return $tmp;
}

sub FromTime {
  my ($self,$time) = (shift,shift);
  return ConvertTimeToAbs($self->StartTime) -
    ConvertTimeToAbs($time) +
      $self->DurationAbs;
}

sub OneLineSummary {
  my ($self) = (shift);
  return "<seg".
    " sl=".$self->StartLoc->Name.
      " el=".$self->EndLoc->Name.
	  " d=".$self->DurationAbs.
	    " f=".$self->FromTime($UNIVERSAL::br->MyTime).
	      " b=".$self->Bus.
		" t=".$self->Trip.
		  " s=".$self.
		    ">";
}


1;
