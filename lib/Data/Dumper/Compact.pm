package Data::Dumper::Compact;

use List::Util qw(sum);
use Data::Dumper::Concise;
use Mu;
use namespace::clean;

sub dump {
  my ($self, $to_dump) = @_;
  $self = $self->new unless ref($self);
  $self->format($self->render($to_dump));
}

sub render {
  my ($self, $r) = @_;
  $self = $self->new unless ref($self);
  if (ref($r) eq 'HASH') {
    return [ hash => { map +($_ => $self->render($r->{$_})), keys %$r } ];
  } elsif (ref($r) eq 'ARRAY') {
    return [ array => [ map $self->render($_), @$r ] ];
  }
  (my $thing = Dumper($r)) =~ s/\n\Z//;;
  if (my ($string) = $thing =~ /^"(.*)"$/) {
    return [ string => $string ];
  }
  return [ thing => $thing ];
}

sub format {
  my ($self, $to_format) = @_;
  $self = $self->new unless ref($self);
  local $self->{width} = 78;
  $self->_format($to_format)."\n";
}

sub _format {
  my ($self, $to_format) = @_;
  my ($type, $payload) = @$to_format;
  my $formatted = $self->${\"_format_${type}"}($payload)
}

sub _format_array {
  my ($self, $payload) = @_;
  if ($self->{oneline}) {
    return join(' ', '[', join(', ', map $self->_format($_), @$payload), ']');
  }
  my @oneline = do {
    local $self->{oneline} = 1;
    map {
      $_->[0] eq 'string' && $_->[1] =~ /^-[a-zA-Z]\w*$/
        ? $_->[1].' =>'
        : $self->_format($_).','
    } @$payload
  };
  if (!grep /\n/, @oneline) {
    s/,$// or $_ = $self->_format($payload->[-1])
      for local $oneline[-1] = $oneline[-1];
    my $try = join(' ', '[', @oneline, ']');
    if (length $try <= $self->{width}) {
      return $try;
    }
  }
  local $self->{width} = $self->{width} - 2;
  my @lines;
  my @bits;
  foreach my $idx (0..$#$payload) {
    my $spare = $self->{width} - sum((scalar @bits)+1, map length($_), @bits);
    my $f = $oneline[$idx];
    if ($f !~ /\n/) {
      if (length($f) <= $spare) {
        push @bits, $f;
        next;
      }
      if (length($f) <= $self->{width}) {
        push(@lines, join(' ', @bits));
        @bits = ($f);
        next;
      }
      $f = $self->_format($payload->[$idx]).',';
    }
    if ($f =~ s/^(.{0,${spare}})\n//sm) {
      push @bits, $1;
    }
    push(@lines, join(' ', @bits));
    @bits = ();
    push(@lines, $f);
  }
  push @lines, join(' ', @bits) if @bits;
  s/^/  /mg for @lines;  
  return join("\n", '[', @lines, ']');
}

sub _format_hash {
  my ($self, $payload) = @_;
  my %k = (map +(
    $_ => ($_ =~ /^-?[a-zA-Z]\w+$/
      ? $_
        # stick a space on the front to force dumping of e.g. 123, then strip it
      : do { s/^" /"/, s/\n\Z// for my $s = Dumper(" $_"); $s }
    ).' =>'), keys %$payload
  );
  if ($self->{oneline}) {
    return join(' ', '{', join(', ',
      map $k{$_}.' '.$self->_format($payload->{$_}), keys %$payload
    ), '}');
  }
  join("\n",
    '{',
    (map {
      my ($key, $value) = ($_, $payload->{$_});
      (my $s = "$k{$key} ".$self->_format($value).',') =~ s/^/  /msg;
      $s;
    } sort keys %$payload),
    '}',
  );
}

sub _format_string { qq{"$_[1]"} }

sub _format_thing { $_[1] }

1;

=head1 ALGORITHM



=cut
