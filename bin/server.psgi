# -*- perl -*-
use strict;
use warnings;
use Path::Tiny;
use Wanage::HTTP;
use Warabe::App;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

$Wanage::HTTP::UseXForwardedFor = 1;
my $RootPath = path (__FILE__)->parent->parent->absolute;

return sub {
  delete $SIG{CHLD} if defined $SIG{CHLD} and not ref $SIG{CHLD}; # XXX

  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);

  $http->set_response_header
      ('Strict-Transport-Security' => 'max-age=2592000; includeSubDomains; preload');

  return $app->execute_by_promise (sub {
    my $path = $app->path_segments;

    return $app->send_redirect
        ('https://suika.suikawiki.org/~wakaba/-temp/wkchat' . $app->http->url->{path},
         status => 301);
  });
};

=head1 LICENSE

Copyright 2015-2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
