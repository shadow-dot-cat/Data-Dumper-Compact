package JSON::Dumper::Compact;

use JSON::MaybeXS;
use Mu;
use curry;
use strictures 2;
use namespace::clean;

extends 'Data::Dumper::Compact';

lazy json_obj => sub {
  JSON->new
      ->allow_nonref(1)
      ->relaxed(1)
      ->filter_json_single_key_object(__bless__ => sub {
          bless($_[0][1], $_[0][0]);
        });
}, handles => [ 'decode' ];

sub _build_dumper { shift->json_obj->curry::encode }

sub _format_el { shift->_format(@_).',' }

sub _format_hashkey { $_[0]->json_obj->encode($_[1]).':' }

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

sub encode { shift->dump(@_) }

1;
