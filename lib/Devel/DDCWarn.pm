package Devel::DDCWarn;

use strictures 2;
use Data::Dumper::Compact;

use base qw(Exporter);

our @EXPORT = map +($_, $_.'T'), qw(Df Dto Dwarn Derr);

our $ddc = Data::Dumper::Compact->new;

sub import {
  my ($class, @args) = @_;
  my $opts;
  if (@args and ref($args[0]) eq 'HASH') {
    $opts = shift @args;
  } else {
    while (@args and $args[0] =~ /^-(.*)$/) {
      my $k = $1;
      my $v = (shift(@args), shift(@args));
      $opts->{$k} = $v;
    }
  }
  $ddc = Data::Dumper::Compact->new($opts) if $opts;
  return if @args == 1 and $args[0] eq ':none';
  $class->export_to_level(1, @args);
}

sub _ef {
  map +(@_ > 1 ? [ list => $_ ] : $_->[0]),
    [ map $ddc->expand($_), @_ ];
}

sub Df { $ddc->format(_ef(@_)) }

sub DfT {
  my ($tag, @args) = @_;
  $ddc->format([ list => [ [ key => $tag ], _ef(@args) ] ]);
}

sub _dto {
  my ($fmt, $noret, $to, @args) = @_;
  return unless @args > $noret;
  $to->($fmt->(@args));
  return wantarray ? @args[$noret..$#args] : $args[$noret];
}

sub Dto { _dto(\&Df, 0, @_) }
sub DtoT { _dto(\&DfT, 1, @_) }

my $W = sub { warn $_[0] };

sub Dwarn { Dto($W, @_) }
sub DwarnT { DtoT($W, @_) }

my $E = sub { print STDERR $_[0] };

sub Derr { Dto($E, @_) }
sub DerrT { DtoT($E, @_) }

1;

=head1 NAME

Devel::DDCWarn - Easy printf-style debugging with L<Data::Dumper::Concise>

=head1 SYNOPSIS

  use Devel::DDCWarn;
  
  my $x = Dwarn some_sub_call(); # warns and returns value
  my @y = Derr other_sub_call(); # prints to STDERR and returns value
  
  my $x = DwarnT X => some_sub_call(); # warns with tag 'X' and returns value
  my @y = DerrT X => other_sub_call(); # similar

=head1 EXPORTS

All of these subroutines are exported by default.

L<Data::Dumper::Compact> is referred to herein as DDC.

=head2 Dwarn

  my $x = Dwarn make_x();
  my @y = Dwarn make_y_array();

C<warn()>s the L</Df> DDC dump of its input, then returns the first element
in scalar context or all arguments in list context.

=head2 Derr

  my $x = Derr make_x();
  my @y = Derr make_y_array();

prints the L</Df> DDC dump of its input to STDERR, then returns the first
element in scalar context or all arguments in list context.

=head2 DwarnT

  my $x = Dwarn TAG => make_x();
  my @y = Dwarn TAG => make_y_array();

Like L</Dwarn>, but passes its first argument, the tag, through to L</DfT>
but skips it for the return value.

=head2 DerrT

  my $x = Derr TAG => make_x();
  my @y = Derr TAG => make_y_array();

Like L</Derr>, but accepts a tag argument that is included in the output
but is skipped for the return value.

=head2 Dto

  Dto(sub { warn $_[0] }, @args);

Like L</Dwarn>, but instead of warning, calls the subroutine passed as the
first argument - this function is low level but still returns the C<@args>.

=head2 DtoT

  DtoT(sub { err $_[0] }, $tag, @args);

The tagged version of L<Dto>.

=head2 Df

  my $x = Df($thing);
  my $y = Df(@other_things);

A single value is returned formatted by DDC. Multiple values are transformed
to a DDC list.

=head2 DfT

  my $x = Df($tag => $thing);
  my $y = Df($tag => @other_things);

A tag plus a single value is formatted as a two element list. A tag plus
multiple values is formatted as a list containing the tag and a list of the
values.

=cut
