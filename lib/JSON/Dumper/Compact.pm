package JSON::Dumper::Compact;

use Mojo::JSON qw(encode_json);
use Mu;
use strictures 2;
use namespace::clean;

extends 'Data::Dumper::Compact';

sub _build_dumper { \&encode_json }

sub _format_el { shift->_format(@_).',' }

sub _format_hashkey { encode_json($_[1]).':' }

sub _format_string { '"'.$_[1].'"' }

sub _format_thing { $_[1] }

around _expand_blessed => sub {
  my ($orig, $self) = (shift, shift);
  my ($blessed) = @_;
  return $self->expand($blessed->TO_JSON) if $blessed->can('TO_JSON');
  return $self->$orig(@_);
};

sub _format_blessed {
  my ($self, $payload) = @_;
  my ($content, $class) = @$payload;
  $self->_format([ hash => [
    [ '__bless__' ],
    { '__bless__' => [ array => [ [ string => $class ], $content ] ] },
  ] ]);
}

1;
