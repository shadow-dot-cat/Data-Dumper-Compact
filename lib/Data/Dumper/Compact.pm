package Data::Dumper::Compact;

use List::Util qw(sum);
use Data::Dumper ();
use Mu;
use namespace::clean;

ro 'width' => default => 78;

lazy dumper => sub {
  my $dd = Data::Dumper->new([]);
  $dd->Trailingcomma(1) if $dd->can('Trailingcomma');
  $dd->Terse(1)->Indent(1)->Useqq(1)->Deparse(1)->Quotekeys(0)->Sortkeys(1);
  sub { $dd->Values([ $_[0] ])->Dump },
};

sub _dumper { $_[0]->dumper->($_[1]) }

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
  (my $thing = $self->_dumper($r)) =~ s/\n\Z//;;
  if (my ($string) = $thing =~ /^"(.*)"$/) {
    return [ string => $string ];
  }
  return [ thing => $thing ];
}

sub format {
  my ($self, $to_format) = @_;
  $self = $self->new unless ref($self);
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
    return $try if length $try <= $self->{width};
  }
  local $self->{width} = $self->{width} - 2;
  if (@$payload == 1) {
    my ($first, @lines) = split /\n/, $self->_format($payload->[0]);
    return join("\n", '[', "  $lines[0]", ']') if @lines == 1;
    my $last = $lines[-1] =~ /^[\}\]]$/ ? (pop @lines).' ': '';
    return join("\n", '[ '.$first, (map "  $_", @lines), $last.']');
  }
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
    $_ => ($_ =~ /^-?[a-zA-Z_]\w*$/
      ? $_
        # stick a space on the front to force dumping of e.g. 123, then strip it
      : do {
           s/^" //, s/"\n\Z// for my $s = $self->_dumper(" $_");
           $self->_format_string($s)
        }
    ).' =>'), keys %$payload
  );
  my $oneline = do {
    local $self->{oneline} = 1;
    join(' ', '{', join(', ',
      map $k{$_}.' '.$self->_format($payload->{$_}), sort keys %$payload
    ), '}');
  };
  return $oneline if $self->{oneline};
  return $oneline if $oneline !~ /\n/ and length($oneline) <= $self->{width};
  my $width = local $self->{width} = $self->{width} - 2;
  my @f = map {
    my $s = $k{$_}.' '.$self->_format(my $p = $payload->{$_});
    $s =~ /^(.{0,${width}})(?:\n|$)/sm
      ? $s
      : $k{$_}."\n".do {
          local $self->{width} = $self->{width} - 2;
          (my $f = $self->_format($p)) =~ s/^/  /msg;
          $f
        }
  } sort keys %$payload;
  if (@f == 1) {
    my ($first, @lines) = split /\n/, $f[0];
    return join("\n", '{', "  $first", '}') unless @lines;
    my $last = $lines[-1] =~ /^[\}\]]$/ ? (pop @lines).' ': '';
    return join("\n", '{ '.$first, (map "  $_", @lines), $last.'}');
  }
  return join("\n",
    '{',
    (map {
      (my $s = $_) =~ s/^/  /msg;
      $s.',';
    } @f),
    '}',
  );
}

sub _format_string {
  my ($self, $str) = @_;
  my $q = $str =~ /[\\']/ ? q{"} : q{'};
  my $w = $self->{width} - 2;
  return $q.$str.$q if length($str) <= $w;
  $w--;
  my @f;
  while (length(my $chunk = substr($str, 0, $w, ''))) {
    push @f, $q.$chunk.$q;
  }
  return join("\n.", @f);
}

sub _format_thing { $_[1] }

1;

=head1 ALGORITHM



=cut
