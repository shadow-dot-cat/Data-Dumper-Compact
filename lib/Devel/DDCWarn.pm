package Devel::DDCWarn;

use strictures 2;
use Data::Dumper::Compact;

use base qw(Exporter);

our @EXPORT = qw(Df Dto DtoT Dwarn Derr DwarnT DerrT);

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

sub Dto {
  my $to = shift;
  return unless @_;
  $to->(Df(@_));
  return wantarray ? @_ : $_[0];
}

sub DtoT {
  my ($to, $tag) = (shift, shift);
  return unless @_;
  $to->(DfT($tag => @_));
  return wantarray ? @_ : $_[0];
}

my $W = sub { warn $_[0] };

sub Dwarn { Dto($W, @_) }
sub DwarnT { DtoT($W, @_) }

my $E = sub { print STDERR $_[0] };

sub Derr { Dto($E, @_) }
sub DerrT { DtoT($E, @_) }

1;
