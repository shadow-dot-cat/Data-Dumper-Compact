package Data::Dumper::Compact;

use strict;
use warnings;
use Data::Dumper::Concise;

sub dump {
  my ($self, $to_dump) = @_;
  $self->format($self->render($to_dump));
}

sub render {
  my ($self, $r) = @_;
  if (ref($r) eq 'HASH') {
    return [ hash => [ map +($_ => $self->render($r->{$_})), sort keys %$r ] ];
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
  $self->_format($to_format);
}

sub _format {
  my ($self, $to_format) = @_;
  my ($type, $payload) = @$to_format;
  return $self->${\"_format_${type}"}($payload);
}

sub _format_array {
  my ($self, $payload) = @_;
  join("\n",
    '[',
    (map {
      (my $s = $self->_format($_).',') =~ s/^/  /msg;
      $s;
    } @$payload),
    ']',
  );
}

sub _format_hash {
  my ($self, $payload) = @_;
  my @pairs = map [ @{$payload}[$_*2,$_*2+1] ], 0..$#{$payload}/2;
  join("\n",
    '{',
    (map {
      my ($key, $value) = @$_;
      my $key_s = ($key =~ /^-?[a-zA-Z]\w+$/
        ? $key
          # stick a space on the front to force dumping of e.g. 123, then strip it
        : do { (my $s = Dumper(" ${key}")) =~ s/^" /"/; $s }
      );
      (my $s = "${key_s} => ".$self->_format($value).',') =~ s/^/  /msg;
      $s;
    } @pairs),
    '}',
  );
}

sub _format_string { $_[1] }

sub _format_thing { $_[1] }

1;

=head1 ALGORITHM



=cut
