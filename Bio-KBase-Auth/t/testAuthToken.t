#!/usr/bin/env perl
#
# Test the Authentication Token code
#
# sychan@lbl.gov
# 8/13/2012

use lib "../lib/";
use lib "lib";
use HTTP::Request;
use LWP::UserAgent;
use JSON;
use Digest::MD5 qw( md5_base64);
use Test::More tests => 18;
#use Time::HiRes qw( gettimeofday tv_interval);

BEGIN {
    use_ok( Bio::KBase::AuthToken);
}

my @users = ();

sub testServer {
    my $d = shift;
    my $res = new HTTP::Response;
    my $msg = new HTTP::Message;
    my $at = new Bio::KBase::AuthToken;

    while (my $c = $d->accept()) {
	while (my $r = $c->get_request) {
	    note( sprintf "Server: Recieved a connection: %s %s\n\t%s\n", $r->method, $r->url->path, $r->content);
	    note( sprintf "        Authorization header: %s\n", $r->header('Authorization'));
	    my $body = sprintf("You sent a %s for %s.\n\n",$r->method(), $r->url->path);
	    my ($token) = $r->header('Authorization') =~ /OAuth (.+)/;
	    
	    if ($token) {
		$at->token( $token);
	    } else {
		$at->{'token'} = undef;
	    }
	    note( "Server received request with token: ". ($token ? $token : "NULL"));
	    note( sprintf("Validation result on server side: %s", $at->validate() ? $at->validate() : 0 ));
	    if ($at->validate()) {
		$res->code(200);
		$body .= sprintf( "Successfully logged in as user %s\n",
				  $at->user_id);
	    } else {
		$res->code(401);
		$body .= sprintf("You failed to login: %s.\n", $at->error_message);
	    }
	    $res->content( $body);
	    $c->send_response($res);
	}
	$c->close;
	undef($c);
    }
}

sub testClient {
    my $server = shift;

    my $ua = LWP::UserAgent->new();

    ok( $at = Bio::KBase::AuthToken->new('user_id' => 'kbasetest', 'password' => '@Suite525'), "Logging in using papa account using username/password");
    ok($at->validate(), "Valid client token for user kbasetest");
    $ua->default_header( "Authorization" => "OAuth " . $at->token);

    ok( $res = $ua->get( $server."someurl"), "Submitting authenticated request to server");
    ok( ($res->code >= 200) && ($res->code < 300), "Querying server with token in Authorization header");
    note( sprintf "Client: Recieved a response: %d %s\n", $res->code, $res->content);

    # As a sanity check, trash the oauth_secret and make sure that
    # we get a negative result
    $ua->default_header( "Authorization" => "BogoToken ");

    note( "Client: Sending bad request (expecting failure)\n");
    ok( $res = $ua->get( $server."someurl"), "Submitting improperly authenticated request to server");
    ok( ($res->code < 200) || ($res->code >= 300), "Querying server with bad oauth creds, expected 401 error");
    note( sprintf "Client: Recieved a response: %d %s\n", $res->code, $res->content);

}

if ( defined $ENV{ $Bio::KBase::AuthToken::TokenEnv }) {
    undef $ENV{ $Bio::KBase::AuthToken::TokenEnv };
}

my %old_config = map { $_ =~ s/authentication\.//; $_ => $Bio::KBase::Auth::Conf{'authentication.' . $_ } } keys %Bio::KBase::Auth::AuthConf;

if ( -e $Bio::KBase::Auth::ConfPath) {
    # clear all the authentication fields that we may care about during testing
    %new = %old_config;
    foreach $key ( 'user_id','password','keyfile','keyfile_passphrase','client_secret','token') {
	$new{$key} = undef;
    }
    Bio::KBase::Auth::SetConfigs( %new);

}

ok( $at = Bio::KBase::AuthToken->new(), "Creating empty token");
ok( (not defined($at->error_message())), "Making sure empty token doesn't generate error");
ok( $at = Bio::KBase::AuthToken->new('user_id' => 'papa', 'password' => 'papapa'), "Logging in using papa account");
ok($at->validate(), "Validating token for papa user using username/password");

ok( $at = Bio::KBase::AuthToken->new('user_id' => 'papa', 'password' => 'poopa'), "Logging in using papa account and bad password");
ok(!($at->validate()), "Testing that bad password fails");

ok( $at = Bio::KBase::AuthToken->new('user_id' => 'papa_blah', 'password' => ''), "Logging in using bad account and bad password");
ok(!($at->validate()), "Testing that bad account/password fails");

ok( $at = Bio::KBase::AuthToken->new('user_id' => undef, ), "Logging in using undef user_id");
ok(!($at->validate()), "Testing that undef user_id fails");

ok( $at = Bio::KBase::AuthToken->new('user_id' => 'kbasetest', 'password' => '@Suite525'), "Logging in using kbasetest account using username/password");
ok($at->validate(), "Validating token from kbasetest username/password");

$badtoken = <<EOT2;
un=papa|clientid=papa|expiry=2376607863|SigningSubject=https://graph.not.api.test.globuscs.info/goauth/keys/861eb8e0-e634-11e1-ac2c-1231381a5994|sig=321ca03d17d984b70822e7414f20a73709f87ba4ed427ad7f41671dc58eae15911322a71787bdaece3885187da1158daf37f21eadd10ea2e75274ca0d8e3fc1f70ca7588078c2a4a96d1340f5ac26ccea89b406399486ba592be9f1d8ffe6273b7acdba8a0edf4154cb3da6caa6522f363d2f6f4d04e080d682e15b35f0bbc36
EOT2

#ok( $at = Bio::KBase::AuthToken->new('token' => $badtoken), "Creating token with bad SigningSubject");
#ok(!($at->validate()), "Validating that bad SigningSubject fails");
#ok(($at->error_message() =~ /Token signed by unrecognized source/), "Checking for 'unrecognized source' error message");

note( "Creating settings for testing kbase_config");
Bio::KBase::Auth::SetConfigs("password" =>'@Suite525',"user_id" => "kbasetest");

ok( $at = Bio::KBase::AuthToken->new(), "Creating a new token object for testing kbase_config with password");
ok( $at->user_id() eq "kbasetest", "Verifying that kbasetest user was read from kbase_config");
ok( $at->validate(), "Verifying that kbasetest user token was acquired properly with userid and password");

ok( $at = Bio::KBase::AuthToken->new( ignore_kbase_config => 1), "Creating a blank object by ignoring the kbase_config file");
ok( ! defined($at->user_id()), "Verifying that kbase_config was ignored");

if ( -e $Bio::KBase::Auth::ConfPath) {
    # restore old config
    Bio::KBase::Auth::SetConfigs( %old_config);
}


done_testing();

