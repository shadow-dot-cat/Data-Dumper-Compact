package Devel::DDCWarn;

use strictures 2;
use Data::Dumper::Compact;

use Exporter 'import';

our @EXPORT = qw(Df Dto DtoT Dwarn Derr DwarnT DerrT);

my $ddc = Data::Dumper::Compact->new;

sub Df {
  return '' unless @_;
  if (@_ == 1) {
    $ddc->dump($_[0]);
  } else {
    $ddc->format([ list => [ map $ddc->expand($_), @_ ] ]);
  }
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
  $to->(Df($tag => @_));
  return wantarray ? @_ : $_[0];
}

my $W = sub { warn $_[0] };

sub Dwarn { Dto($W, @_) }
sub DwarnT { DtoT($W, @_) }

my $E = sub { print STDERR $_[0] };

sub Derr { Dto($E, @_) }
sub DerrT { DtoT($E, @_) }

1;
