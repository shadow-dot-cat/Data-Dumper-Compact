package Data::Dumper::Compact;

use List::Util qw(sum);
use Data::Dumper ();
use Mu;
use namespace::clean;

sub import {
  my ($class, $ddc, $opts) = @_;
  return unless ($ddc||'') eq 'ddc';
  my $targ = caller;
  my $cb = $class->new($opts||{})->dump_cb;
  no strict 'refs';
  *{"${targ}::ddc"} = $cb;
}

ro max_width => default => 78;

lazy width => sub { shift->max_width }, init_arg => undef;

lazy indent_width => sub { length($_[0]->indent_by) };

sub _next_width { $_[0]->width - $_[0]->indent_width }

ro indent_by => default => '  ';

ro transforms => default => sub { [] };

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
  my ($self, $data, $opts) = @_;
  # if we're an object, localize anything provided in the options,
  # and also blow away the dependent attributes if indent_by is changed
  ref($self) and $opts
    and (local @{$self}{keys %$opts} = values %$opts, 1)
    and $opts->{indent_by}
    and delete @{$self}{grep !$opts->{$_}, qw(indent_width dumper)};
  ref($self) or $self = $self->new($opts||{});
  $self->format($self->transform($self->transforms, $self->expand($data)));
}

sub dump_cb {
  my ($self) = @_;
  return sub { $self->dump(@_) };
}

sub expand {
  my ($self, $data) = @_;
  if (ref($data) eq 'HASH') {
    return [ hash => [
      [ sort keys %$data ],
      { map +($_ => $self->expand($data->{$_})), keys %$data }
    ] ];
  } elsif (ref($data) eq 'ARRAY') {
    return [ array => [ map $self->expand($_), @$data ] ];
  }
  (my $thing = $self->_dumper($data)) =~ s/\n\Z//;;
  if (my ($string) = $thing =~ /^"(.*)"$/) {
    return [ ($string =~ /^-[a-zA-Z]\w*$/ ? 'key' : 'string') => $string ];
  }
  return [ thing => $thing ];
}

sub transform {
  my ($self, $tfspec, $exp) = @_;
  return $exp unless $tfspec;
  local $self->{transforms} = $tfspec;
  $self->_transform($exp, []);
}

sub _transform {
  my ($self, $exp, $path) = @_;
  my ($type, $payload) = @$exp;
  if ($type eq 'hash') {
    my %h = %{$payload->[1]};
    $payload = [
      $payload->[0],
      { map +(
          $_ => $self->_transform($h{$_}, [ @$path, $_ ])
        ), keys %h
      },
    ];
  } elsif ($type eq 'array') {
    my @a = @$payload;
    $payload = [ map $self->_transform($a[$_], [ @$path, $_ ]), 0..$#a ];
  }
  my $tfspec = $self->transforms;
  foreach my $tf (ref($tfspec) eq 'ARRAY' ? @$tfspec : $tfspec) {
    next unless my $cb = ref($tf) eq 'HASH' ? $tf->{$type}||$tf->{_} : $tf;
    ($type, $payload) = @{
      $self->$cb($type, $payload, $path)
      || [ $type, $payload ]
    };
  }
  return [ $type, $payload ];
}

sub format {
  my ($self, $exp) = @_;
  return $self->_format($exp)."\n";
  VERTICAL:
  local $self->{vertical} = 1;
  return $self->_format($exp)."\n";
}

sub _format {
  my ($self, $exp) = @_;
  my ($type, $payload) = @$exp;
  if (!$self->{vertical} and $self->width <= 0) {
    no warnings 'exiting';
    goto VERTICAL;
  }
  return $self->${\"_format_${type}"}($payload);
}

sub _format_list {
  my ($self, $payload) = @_;
  my @plain = grep !/\s/, map $_->[1], grep $_->[0] eq 'string', @$payload;
  if (@plain == @$payload) {
    my $try = 'qw('.join(' ', @plain).')';
    return $try if $self->{oneline} or length($try) <= $self->{width};
  }
  return $self->_format_arraylike('(', ')', $payload);
}

sub _format_array {
  my ($self, $payload) = @_;
  $self->_format_arraylike('[', ']', $payload);
}

sub _format_el {
  my ($self, $el) = @_;
  return $el->[1].' =>' if $el->[0] eq 'key';
  return $self->_format($el).',';
}

sub _format_arraylike {
  my ($self, $l, $r, $payload) = @_;
  if ($self->{vertical}) {
    return join("\n", $l,
      (map $self->_indent($self->_format($_).','), @$payload),
    $r);
  }
  if ($self->{oneline}) {
    my @pl = @$payload;
    my $last = pop @pl;
    my @el = map $self->_format_el($_), @pl;
    return join(' ', $l, join(' ', @el, $self->_format($last)), $r);
  }
  my @oneline = do {
    local $self->{oneline} = 1;
    map $self->_format_el($_), @$payload;
  };
  if (!grep /\n/, @oneline) {
    s/,$// or $_ = $self->_format($payload->[-1])
      for local $oneline[-1] = $oneline[-1];
    my $try = join(' ', $l, @oneline, $r);
    return $try if length $try <= $self->{width};
  }
  local $self->{width} = $self->_next_width;
  if (@$payload == 1) {
    return $self->_format_single($l, $r, $self->_format($payload->[0]));
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
    $f = $self->_format_el($payload->[$idx]);
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
  return join("\n", $l, (map $self->_indent($_), @lines), $r);
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

sub _format_key { shift->_format_string(@_) }

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
  my ($self, $l, $r, $raw) = @_;
  my ($first, @lines) = split /\n/, $raw;
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

=head1 NAME

Data::Dumper::Compact - Vertically compact width-limited data formatter

=head1 SYNOPSIS

Basic usage as a function:

  use Data::Dumper::Compact 'ddc';
  
  warn ddc($some_data_structure);
  
  warn ddc($some_data_structure, \%options);

Slightly more clever usage as a function:

  use Data::Dumper::Compact ddc => \%default_options;
  
  warn ddc($some_data_structure);
  
  warn ddc($some_data_structure, \%extra_options);

OO usage:

  use Data::Dumper::Compact;
  
  warn Data::Dumper::Compact->dump($data, \%options);
  
  my $ddc = Data::Dumper::Compact->new(\%options);
  
  warn $ddc->dump($data);
  
  warn $ddc->dump($data, \%extra_options);

=head1 OPTIONS

=head2 max_width

Represents the width that DDC will attempt to keep as the maximum (if
something overflows it in spite of our best efforts, DDC will fall back to
a more vertically sprawling format to at least overflow as little as
feasible).

Default: C<78>

=head2 indent_by

The string to indent by. To set e.g. 4 space indent, pass C<' 'x4>.

Default: C<'  '>

=head2 indent_width

How many characters one indent should be considered to be. Generally you
only need to manually set this if your L</ident_by> is C<"\t">.

Default: C<length($self->indent_by)>

=head2 transforms

Set of transforms to apply on every L</dump> operation. See L</transform>
for more information.

Default: C<[]>

=head2 dumper

The dumper function to be used for dumping things DDC doesn't understand,
such as coderefs, regexprefs, etc.

Defaults to the same options as L<Data::Dumper::Concise> with a little bit
of extra cleverness to make L<B::Deparse> use the correct indentation, since
for some reason L<Data::Dumper> doesn't (at the time of writing) do that.

If you supply it yourself, it needs to be a single argument coderef - you
could for example use C<\&Data::Dumper::Dumper> though that would almost
certainly be pointless.

=head1 EXPORTS

=head2 ddc

  use Data::Dumper::Compact 'ddc';
  use Data::Dumper::Compact 'ddc' => \%options;

If the first argument to C<use>/C<import()> is 'ddc', a subroutine C<ddc()>
is installed in the calling package which behaves like calling L</dump>.

If the second argument is a hashref, it becomes the options passed to L</new>.

This function is not exported by default.

=head1 METHODS

=head2 new

  Data::Dumper::Concise->new;
  Data::Dumper::Concise->new(%options);
  Data::Dumper::Concise->new(\%options);

Constructor. Takes a hash or hashref of L</OPTIONS>

=head2 dump

  Data::Dumper::Concise->dump($data, \%options?);
  
  $ddc->dump($data, \%merge_options?);

This is the method you're going to want to call most of the time, and ties
together the rest of the functionality into a single data-structure-to-string
bundle. With just a data argument, it's equivalent to:

  $ddc->format( $ddc->transform( $ddc->transforms, $ddc->expand($data) );

In class method form, options provided are passed to L</new>; in instance
method form, options if provided are merged into C<$ddc> just for this
invocation.

=head2 dump_cb

  my $cb = $ddc->dump_cb;

Returns a subroutine reference that's a curried call to L</dump>:
  
  $cb->($data, \%extra_options); # equivalent to $ddc->dump(...)

Mostly useful for if you want to create a custom C<ddc()> like thing:

  use Data::Dumper::Compact;
  BEGIN { *Dumper = Data::Dumper::Compact->new->dump_cb }

=head2 expand

  my $exp = $ddc->expand($data);

Expands a data structure to DDC tagged data. The result is, recursively,

  [ $type, $payload ]

where if $type is one of C<string>, C<key>, or C<thing>, the payload is a
simple string (C<thing> meaning something unknown and therefore delegated to
L</dumper>). If the type is an array:

  [ array => \@values ]

and if the type is a hash:

  [ hash => [ \@keys, \%value_map ] ]

where the keys provide an order for formatting, and the value map is a
hashref of keys to expanded values.

=head2 add_transform

  $ddc->add_transform(sub { ... });
  $ddc->add_transform({ hash => sub { ... }, _ => sub { ... });

Appends a transform to C<$ddc->transforms>, see L</transform> for behaviour.

=head2 transform

  $ddc->transform($tfspec, $exp);

=head2 format

=cut
