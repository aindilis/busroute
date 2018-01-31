package BR::Items;

use Class::MethodMaker
  new_with_init => 'new',
  get_set       => [ qw / Type Items / ];

sub init {
  my ($self,%args) = (shift,@_);
  $self->Type($args{Type} || "");
  $self->Items([]);
}

sub Add {
  my ($self,$item) = (shift,shift);
  push @{$self->Items}, $item;
}

sub Subtract {
  my ($self,$item) = (shift,shift);
  # delete $self->Items->{$item};
}

sub List {
  my ($self,$item) = (shift,shift);
  return @{$self->Items};
}

1;
