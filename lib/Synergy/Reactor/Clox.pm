use v5.24.0;
package Synergy::Reactor::Clox;

use Moose;
use DateTime;
with 'Synergy::Role::Reactor';

use experimental qw(signatures);
use namespace::clean;
use List::Util qw(first uniq);

sub listener_specs {
  return {
    name      => 'clox',
    method    => 'handle_clox',
    exclusive => 1,
    predicate => sub ($self, $e) { $e->was_targeted && $e->text eq 'clox' },
  };
}

has time_zone_names => (
  is  => 'ro',
  isa => 'HashRef',
  default => sub {  {}  },
);

sub handle_clox ($self, $event, $rch) {
  $event->mark_handled;

  my $now = DateTime->now;

  my @tzs = sort {; $a cmp $b }
            uniq
            grep {; defined }
            map  {; $_->time_zone }
            $self->hub->user_directory->users;

  @tzs = ('America/New_York') unless @tzs;

  my $tz_nick = $self->time_zone_names;
  my $user_tz = ($event->from_user && $event->from_user->time_zone)
             // '';

  my @times;

  my @tz_objs = map {; DateTime::TimeZone->new(name => $_) } @tzs;

  for my $tz (
    sort {; $a->offset_for_datetime($now) <=> $b->offset_for_datetime($now) }
    @tz_objs
  ) {
    my $tz_name = $tz->name;
    my $tz_now = $now->clone;
    $tz_now->set_time_zone($tz);

    use utf8;
    my $str = $tz_now->day_name . ", "
            . ($tz_nick->{$tz_name} ? $tz_now->format_cldr("H:mm")
                                    : $tz_now->format_cldr("H:mm vvv"));

    $str = "$tz_nick->{$tz_name} $str" if $tz_nick->{$tz_name};

    $str .= " \N{LEFTWARDS ARROW} you are here"
      if $tz_name eq $user_tz;

    push @times, $str;
  }

  my $sit = $now->clone;
  $sit->set_time_zone('+0100');

  my $beats
    = $sit->ymd('-') . '@'
    . int(($sit->second + $sit->minute * 60 + $sit->hour * 3600) / 86.4);

  my $reply = "In Internet Time\N{TRADE MARK SIGN} it's $beats.  That's...\n";
  $reply .= join q{}, map {; "> $_\n" } @times;

  # $rch->reply($reply);

  my $slack = $rch->channel->slack;
  warn "$slack";

  my $channel = $rch->default_address;
  my $attachments = [
    {
      title => 'times around the world',
      text => join("\n", @times),
      color => '#ab91d6',
    }
  ];


  use JSON 2 ();
  state $JSON = JSON->new->canonical;

  #$slack->send_rich_message($channel, 'hello');
  $slack->api_call('chat.postMessage', {
    channel => $channel,
    as_user => 1,
    fallback => 'fallback text',
    attachments => $JSON->encode($attachments),
  });


}

1;
