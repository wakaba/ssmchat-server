# -*- perl -*-
use strict;
use warnings;
use Path::Tiny;
use Wanage::URL;
use Wanage::HTTP;
use Warabe::App;
use Promised::Command;

$ENV{LANG} = 'C';
$ENV{TZ} = 'UTC';

$Wanage::HTTP::UseXForwardedFor = 1;
my $RootPath = path (__FILE__)->parent->parent->absolute;

sub send_file ($$$) {
  my ($app, $file, $mime) = @_;
  return $app->throw_error (404) unless $file->is_file;
  $app->http->set_response_header ('Content-Type' => $mime) if defined $mime;
  $app->http->set_response_last_modified ($file->stat->mtime);
  $app->http->send_response_body_as_ref (\($file->slurp));
  return $app->http->close_response_body;
} # send_file

sub run_cgi ($$$) {
  my ($app, $script_name, $file_path) = @_;
  my $cmd = Promised::Command->new ([$RootPath->child ('perl'), $file_path]);
  $cmd->envs->{REQUEST_METHOD} = $app->http->request_method;
  $cmd->envs->{QUERY_STRING} = $app->http->original_url->{query};
  $cmd->envs->{CONTENT_LENGTH} = $app->http->request_body_length;
  $cmd->envs->{CONTENT_TYPE} = $app->http->get_request_header ('Content-Type');
  $cmd->envs->{HTTP_ACCEPT_LANGUAGE} = $app->http->get_request_header ('Accept-Language');
  $cmd->envs->{HTTP_ACCEPT_ENCODING} = $app->http->get_request_header ('Accept-Encoding');
  $cmd->envs->{HTTP_ORIGIN} = $app->http->get_request_header ('Origin');
  $cmd->envs->{SERVER_NAME} = $app->http->url->{host};
  $cmd->envs->{SERVER_PORT} = $app->http->url->{port};
  $cmd->envs->{SCRIPT_NAME} = $script_name;
  $cmd->envs->{REMOTE_ADDR} = $app->http->client_ip_addr->as_text;
  #$cmd->envs->{PATH_INFO} = join '/', '', @$path[1..$#$path];
  $cmd->wd ($file_path->parent);
  $cmd->stdin ($app->http->request_body_as_ref);
  my $stdout = '';
  my $out_mode = '';
  $cmd->stdout (sub {
    if ($out_mode eq 'body') {
      $app->http->send_response_body_as_ref (\($_[0]));
      return;
    }
    $stdout .= $_[0];
    while ($stdout =~ s/^([^\x0A]*[^\x0D\x0A])\x0D?\x0A//) {
      my ($name, $value) = split /:/, $1, 2;
      $name =~ tr/A-Z/a-z/;
      if ($name eq 'status') {
        $value =~ s/^\s+//;
        my ($code, $reason) = split /\s+/, $value, 2;
        $app->http->set_status ($code, reason_phrase => $reason);
      } else {
        $app->http->set_response_header ($name => $value);
      }
    }
    if ($stdout =~ s/^\x0D?\x0A//) {
      $out_mode = 'body';
      $app->http->send_response_body_as_ref (\$stdout);
    }
  });
  return $cmd->run->then (sub {
    return $cmd->wait;
  })->then (sub {
    $app->http->close_response_body;
    die $_[0] unless $_[0]->exit_code == 0;
  });
} # run_cgi

return sub {
  delete $SIG{CHLD} if defined $SIG{CHLD} and not ref $SIG{CHLD}; # XXX

  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);

  $http->set_response_header
      ('Strict-Transport-Security' => 'max-age=2592000; includeSubDomains; preload');

  return $app->execute_by_promise (sub {
    my $path = $app->path_segments;
    if (@$path == 1 and $path->[0] eq 'chat1') {
      return run_cgi ($app, '/chat1', $RootPath->child ('ssmchat/chat1.cgi'));
    } elsif (@$path == 1 and $path->[0] eq 'chat.css') {
      return send_file ($app, $RootPath->child ('ssmchat/chat.css'), 'text/css; charset=utf-8');
    } elsif (@$path == 1 and $path->[0] eq '') {
      return $app->send_redirect ('/chat1');
    } else {
      return $app->send_error (404);
    }
  });
};

=head1 LICENSE

Copyright 2015 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
