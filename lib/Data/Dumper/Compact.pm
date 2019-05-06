package Data::Dumper::Compact;

use List::Util qw(sum);
use Data::Dumper ();
use Mu;
use namespace::clean;

ro max_width => default => 78;

lazy width => sub { shift->max_width };

lazy indent_width => sub { length($_[0]->indent_by) };

sub _next_width { $_[0]->width - $_[0]->indent_width }

ro indent_by => default => '  ';

rw transforms => default => sub { [] };

sub add_transform { push(@{$_[0]->transforms}, $_[1]); $_[0] }

sub _indent {
  my ($self, $string) = @_;
  my $ib = $self->indent_by;
  $string =~ s/^/$ib/msg;
  $string;
}

lazy dumper => sub {
  my ($self) = @_;
  my $dd = Data::Dumper->new([]);
  $dd->Trailingcomma(1) if $dd->can('Trailingcomma');
  $dd->Terse(1)->Indent(1)->Useqq(1)->Deparse(1)->Quotekeys(0)->Sortkeys(1);
  my $indent_width = $self->indent_width;
  my $dp_new = do {
    require B::Deparse;
    my $orig = \&B::Deparse::new;
    sub { my ($self, @args) = @_; $self->$orig('-si'.$indent_width, @args) }
  };
  sub {
    no warnings 'redefine';
    local *B::Deparse::new = $dp_new;
    $dd->Values([ $_[0] ])->Dump
  },
};

sub _dumper { $_[0]->dumper->($_[1]) }

sub dump {
  my ($self, $to_dump, $options) = @_;
  ref($self) and local @{$self}{keys %{$options||{}}} = values %{$options||{}};
  ref($self) or $self = $self->new($options||{});
  $self->format($self->transform($self->transforms, $self->expand($to_dump)));
}

sub expand {
  my ($self, $r) = @_;
  if (ref($r) eq 'HASH') {
    return [ hash => [
      [ sort keys %$r ],
      { map +($_ => $self->expand($r->{$_})), keys %$r }
    ] ];
  } elsif (ref($r) eq 'ARRAY') {
    return [ array => [ map $self->expand($_), @$r ] ];
  }
  (my $thing = $self->_dumper($r)) =~ s/\n\Z//;;
  if (my ($string) = $thing =~ /^"(.*)"$/) {
    return [ ($string =~ /^-[a-zA-Z]\w*$/ ? 'key' : 'string') => $string ];
  }
  return [ thing => $thing ];
}

sub transform {
  my ($self, $tfspec, $data) = @_;
  return $data unless $tfspec;
  $self->_transform($tfspec, $data, []);
}

sub _transform {
  my ($self, $tfspec, $data, $path) = @_;
  my $type = $data->[0];
  if ($type eq 'hash') {
    my %h = %{$data->[1][1]};
    $data = [
      $data->[0],
      [
        $data->[1][0],
        +{ map +(
             $_ => $self->_transform($tfspec, $h{$_}, [ @$path, $_ ])
          ), keys %h
        },
      ]
    ];
  } elsif ($type eq 'array') {
    my @a = @{$data->[1]};
    $data = [
      $data->[0],
      [ map $self->_transform($tfspec, $a[$_], [ @$path, $_ ]), 0..$#a ]
    ];
  }
  foreach my $tf (ref($tfspec) eq 'ARRAY' ? @$tfspec : $tfspec) {
    next unless my $cb = ref($tf) eq 'HASH' ? $tf->{$type}||$tf->{_} : $tf;
    $data = $self->$cb($tfspec, $data, $path);
  }
  return $data;
}

sub format {
  my ($self, $to_format) = @_;
  return $self->_format($to_format)."\n";
  VERTICAL:
  local $self->{vertical} = 1;
  return $self->_format($to_format)."\n";
}

sub _format {
  my ($self, $to_format) = @_;
  my ($type, $payload) = @$to_format;
  if (!$self->{vertical} and $self->width <= 0) {
    no warnings 'exiting';
    goto VERTICAL;
  }
  return $self->${\"_format_${type}"}($payload);
}

sub _format_array {
  my ($self, $payload) = @_;
  if ($self->{vertical}) {
    return join("\n", '[',
      (map $self->_indent($self->_format($_)).',', @$payload),
    ']');
  }
  if ($self->{oneline}) {
    return join(' ', '[', join(', ', map $self->_format($_), @$payload), ']');
  }
  my @oneline = do {
    local $self->{oneline} = 1;
    map $self->_format($_).($_->[0] eq 'key' ? ' =>' : ','), @$payload;
  };
  if (!grep /\n/, @oneline) {
    s/,$// or $_ = $self->_format($payload->[-1])
      for local $oneline[-1] = $oneline[-1];
    my $try = join(' ', '[', @oneline, ']');
    return $try if length $try <= $self->{width};
  }
  local $self->{width} = $self->_next_width;
  if (@$payload == 1) {
    return $self->_format_single('[', ']', $self->_format($payload->[0]));
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
      if (length($f) <= $self->width) {
        push(@lines, join(' ', @bits));
        @bits = ($f);
        next;
      }
    }
    $f = $self->_format($payload->[$idx]).',';
    if ($f =~ s/^(.{0,${spare}})\n//sm) {
      push @bits, $1;
    }
    push(@lines, join(' ', @bits)) if @bits;
    @bits = ();
    if ($f =~ s/(?:\A|\n)(.{0,${\$self->width}})\Z//sm) {
      push @bits, $1;
    }
    push(@lines, $f);
  }
  push @lines, join(' ', @bits) if @bits;
  return join("\n", '[', (map $self->_indent($_), @lines), ']');
}

sub _format_hash {
  my ($self, $payload) = @_;
  my ($keys, $hash) = @$payload;
  my %k = (map +(
    $_ => ($_ =~ /^-?[a-zA-Z_]\w*$/
      ? $_
        # stick a space on the front to force dumping of e.g. 123, then strip it
      : do {
           s/^" //, s/"\n\Z// for my $s = $self->_dumper(" $_");
           $self->_format_string($s)
        }
    ).' =>'), @$keys
  );
  if ($self->{vertical}) {
    return join("\n", '{',
      (map $self->_indent($k{$_}.' '.$self->_format($hash->{$_}).','), @$keys),
    '}');
  }
  my $oneline = do {
    local $self->{oneline} = 1;
    join(' ', '{', join(', ',
      map $k{$_}.' '.$self->_format($hash->{$_}), @$keys
    ), '}');
  };
  return $oneline if $self->{oneline};
  return $oneline if $oneline !~ /\n/ and length($oneline) <= $self->{width};
  my $width = local $self->{width} = $self->_next_width;
  my @f = map {
    my $s = $k{$_}.' '.$self->_format(my $p = $hash->{$_});
    $s =~ /\A(.{0,${width}})(?:\n|\Z)/
      ? $s
      : $k{$_}."\n".do {
          local $self->{width} = $self->_next_width;
          $self->_indent($self->_format($p));
        }
  } @$keys;
  if (@f == 1) {
    return $self->_format_single('{', '}', $f[0]);
  }
  return join("\n",
    '{',
    (map $self->_indent($_).',', @f),
    '}',
  );
}

sub _format_key { $_[1] }

sub _format_string {
  my ($self, $str) = @_;
  my $q = $str =~ /[\\']/ ? q{"} : q{'};
  my $w = $self->{vertical} ? 20 : $self->_next_width;
  return $q.$str.$q if length($str) <= $w;
  $w--;
  my @f;
  while (length(my $chunk = substr($str, 0, $w, ''))) {
    push @f, $q.$chunk.$q;
  }
  return join("\n.", @f);
}

sub _format_thing { $_[1] }

sub _format_single {
  my ($self, $l, $r, $to_format) = @_;
  my ($first, @lines) = split /\n/, $to_format;
  return join("\n", $l, $self->_indent($first), $r) unless @lines;
  (my $pad = $self->indent_by) =~ s/^ //;
  my $last = $lines[-1] =~ /^[\}\]]/ ? (pop @lines).$pad: '';
  return join("\n",
    $l.($l eq '{' ? ' ' : $pad).$first,
    (map $self->_indent($_), @lines),
    $last.$r
  );
}

1;

=head1 ALGORITHM



=cut
