#!/usr/bin/env perl
use strict;
use warnings;

=head1 DESCRIPTION

The pSh3ll is a perl based command shell for managing your Amazon S3 objects.
It is built upon the Amazon S3 REST perl library.

=cut

use Net::Amazon::S3;
use Encode;
use Term::ReadLine;
use ExtUtils::MakeMaker ();
use File::HomeDir;
use Path::Class qw(dir file);
use File::Slurp;
use YAML;
use Perl6::Say;

our $conf = file( File::HomeDir->my_home, ".psh3ll" );
our %config = ();
our $changed;
our $api;
our %commands;
our $bucket_name;
our $term_;
our @command_list = qw(
    bucket count createbucket delete deleteall deletebucket
    exit get getfile getacl gettorrent head host help list listbuckets listatom
    listrss pass put putfile putfilewacl quit setacl user
);

main();

sub main {
    setup_api();
    shell();
}

END {
    save_config() if $changed;
}

sub setup_api {
    setup_config();
    $api = Net::Amazon::S3->new(
        {   aws_access_key_id     => $config{aws_access_key_id},
            aws_secret_access_key => $config{aws_secret_access_key},
        }
    );
}

sub shell {
    _show_banner();
    _setup_commands();
    _input_loop() && say;
    _quit();
}

### main routine related methods
sub _show_banner {
    say;
    say "Welcome to pSh3ll (Amazon S3 command shell for Perl) (c) 2008 Dann.";
    say "Type 'help' for command list.";
    say;
}

sub _setup_commands {
    %commands = map { $_ => \&$_ } @command_list;
}

sub _input_loop {
    $term_ = term('pSh3ll');
    my $prompt = 'psh3ll> ';

    while ( defined( my $input = eval { $term_->readline($prompt) } ) ) {
        my @tokens = split( /\s/, $input );
        next unless @tokens >= 1;

        my $command = shift @tokens;
        if ( $command eq 'quit' || $command eq 'exit' ) {
            quit();
            return;
        }
        _dispatch_on_input( $command, \@tokens );

        $term_->addhistory($input);
    }

    return 1;
}

sub _dispatch_on_input {
    my $command = shift;
    my $args    = shift;

    if ( exists $commands{$command} ) {
        $commands{$command}($args);
    }
    else {
        say 'Unknown command:' . $command;
    }
}

sub _quit {
    _write_history($term_);
}

### configuration related methods
sub prompt {
    my $value = ExtUtils::MakeMaker::prompt( $_[0] );
    $changed++;
    return $value;
}

sub setup_config {
    my $config = eval { YAML::LoadFile($conf) } || {};
    %config = %$config;
    $config{aws_access_key_id}     ||= prompt("AWS access key:");
    $config{aws_secret_access_key} ||= prompt("AWS secret access key:");
}

sub save_config {
    YAML::DumpFile( $conf, \%config );
    chmod 0600, $conf;
}

### term related methods

sub term {
    my $name     = shift;
    my $new_term = Term::ReadLine->new($name);

    my $attribs = $new_term->Attribs;
    $attribs->{completion_function} = sub {
        my ( $text, $line, $start ) = @_;
        my @matched = grep { $_ =~ /^$text/ } @command_list;
        return @matched;
    };

    _read_history($new_term);
    return $new_term;
}

sub _history_file {
    return file( File::HomeDir->my_home, '.psh3ll_history' )->stringify;
}

sub _read_history {
    my $term = shift;
    my $h    = _history_file;

    if ( $term->Features->{readHistory} ) {
        $term->ReadHistory($h);
    }
    elsif ( $term->Features->{setHistory} ) {
        if ( -e $h ) {
            my @h = File::Slurp::read_file($h);
            chomp @h;
            $term->SetHistory(@h);
        }
    }
    else {

        # warn "Your ReadLine doesn't support setHistory\n";
    }

}

sub _write_history {
    my $term = shift;
    my $h    = _history_file;

    if ( $term->Features->{writeHistory} ) {
        $term->WriteHistory($h);
    }
    elsif ( $term->Features->{getHistory} ) {
        require File::Slurp;
        my @h = map {"$_\n"} $term->GetHistory;
        File::Slurp::write_file( $h, @h );
    }
    else {

        # warn "Your ReadLine doesn't support getHistory\n";
    }
}

### command utility methods
sub get_bucket {
    my $bucket = $api->bucket($bucket_name);
    $bucket;
}

sub is_valid_acl {
    my $acl = shift;
    unless ( $acl eq 'private'
        || $acl eq 'public-read'
        || $acl eq 'public-read-write'
        || $acl eq 'authenticated-read' )
    {
        say
            "acl must be ['private'|'public-read'|'public-read-write'|'authenticated-read']";
        return 0;
    }
    return 1;
}

sub is_bucket_set {
    unless ($bucket_name) {
        say "error: bucket is not set";
        return 0;
    }
    return 1;
}

### commands
sub bucket {
    my $args = shift;
    if ( !@{$args} == 1 ) {
        say "error: bucket [bucketname]";
        return;
    }

    $bucket_name = $args->[0];
    say "--- bucket set to '" . $bucket_name . "' ---";

}

sub createbucket {
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }

    my $bucket = $api->add_bucket( { bucket => $bucket_name } );

    if ( $api->err ) {
        say "--- could not create bucket '" . $bucket_name + "' ---";
        say $api->err . ": " . $api->errstr;
    }
    else {
        say "--- created bucket '" . $bucket_name . "' ---";
    }
}

sub count {
    my $args = shift;
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }
    my $bucket = get_bucket();

    # TODO
    my $response = $bucket->list_all
        or die $bucket->err . ": " . $bucket->errstr;
    say scalar( @{ $response->{keys} } );
}

sub deletebucket {
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }

    my $bucket = $api->bucket($bucket_name);
    $bucket->delete_bucket;
    if ( $api->err ) {
        say "--- could not delete bucket '" . $bucket_name + "' ---";
        say $api->err . ": " . $api->errstr;
    }
    else {
        say "--- deleted bucket '" . $bucket_name . "' ---";
        $bucket_name = undef;
    }
}

sub delete {
    my $args = shift;
    return unless is_bucket_set();
    if ( !@{$args} == 1 ) {
        say "error: delete <id>";
        return;
    }

    my $key        = $args->[0];
    my $bucket     = get_bucket();
    my $is_success = $bucket->delete_key($key);
    if ($is_success) {
        say "--- deleted item '" . $bucket_name . "/" . $key . "' ---";
    }
    else {
        say "--- could not delete item '"
            . $bucket_name . "/"
            . $key . "' ---";
        say $bucket->errstr if $bucket->err;
    }

}

sub deleteall {
    return unless is_bucket_set();

    my $bucket = $api->bucket($bucket_name);

    # TODO: error handling
    my $response = $bucket->list_all
        or die $bucket->err . ": " . $bucket->errstr;
    foreach my $key ( @{ $response->{keys} } ) {
        my $key_name   = $key->{key};
        my $is_success = $bucket->delete_key($key_name);
        if ($is_success) {
            say "--- deleted item '"
                . $bucket_name . "/"
                . $key_name . "' ---";
        }
        else {
            say "--- could not delete item '"
                . $bucket_name . "/"
                . $key_name . "' ---";
            say $bucket->errstr if $bucket->err;
        }
    }
}

sub exit {
}

sub get {
    my $args = shift;
    return unless is_bucket_set();

    if ( !@{$args} == 1 ) {
        say "error: get <id>";
        return;
    }

    my $key    = $args->[0];
    my $bucket = get_bucket();
    my $value  = $bucket->get_key($key);
    if ($value) {
        say $value->{value};
    }
    else {
        say "couldn't get $key";
        say $bucket->errstr;
    }
}

sub getacl {
    my $args = shift;
    if ( !@{$args} == 2 ) {
        say "getacl [bucket|item] <id>";
        return;
    }

    my $object_type = $args->[0];
    unless ( $object_type eq 'bucket'
        || $object_type eq 'item' )
    {
        say "object type must be ['bucket'|'item'] ";
        return;
    }
    my $key = $args->[1];
    my $acl;
    if ( $object_type eq 'bucket' ) {
        my $bucket = $api->bucket($key);
        $acl = $bucket->get_acl;

    }
    elsif ( $object_type eq 'item' ) {
        unless ($bucket_name) {
            say "error: bucket is not set";
            return;
        }
        my $bucket = get_bucket();
        $acl = $bucket->get_acl($key);
    }
    say $acl;
}

sub getfile {
    my $args = shift;
    return unless is_bucket_set();

    if ( !@{$args} == 2 ) {
        say "error: getfile <id> <file>";
        return;
    }

    my $key    = $args->[0];
    my $bucket = get_bucket();
    my $value  = $bucket->get_key($key);

    if ($value) {
        my $filename = $args->[1];
        my $fh       = file($filename)->openw;
        $fh->print( $value->{value} );
        $fh->close;
        say "Got item '$key' as '$filename'";
    }
    else {
        say "Couldn't get $key";
        say $bucket->errstr;
    }
}

sub gettorrent {
    say 'not implemented yet';
}

sub help {
    say "bucket [bucketname]";
    say "count [prefix]";
    say "createbucket";
    say "delete <id>";
    say "deleteall [prefix]";
    say "deletebucket";
    say "exit";
    say "get <id>";
    say "getacl ['bucket'|'item'] <id>";
    say "getfile <id> <file>";
    say "gettorrent <id>";
    say "head ['bucket'|'item'] <id>";
    say "host [hostname]";
    say "list [prefix] [max]";
    say "listatom [prefix] [max]";
    say "listrss [prefix] [max]";
    say "listbuckets";
    say "pass [password]";
    say "put <id> <data>";
    say "putfile <id> <file>";
    say
        "putfilewacl <id> <file> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
    say "quit";
    say
        "setacl ['bucket'|'item'] <id> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
    say "user [username]";
}

sub head {
    say 'not implemented yet';
}

sub host {
    say 'not implemented yet';
}

sub list {
    return unless is_bucket_set();

    my $bucket   = $api->bucket($bucket_name);
    my $response = $bucket->list_all
        or die $api->err . ": " . $api->errstr;
    foreach my $key ( @{ $response->{keys} } ) {
        my $key_name  = $key->{key};
        my $key_size  = $key->{size};
        my $key_owner = $key->{owner};
        say "key='$key_name', size=$key_size";
    }
}

sub listbuckets {
    my $response = $api->buckets;
    foreach my $bucket ( @{ $response->{buckets} } ) {
        say $bucket->bucket;
    }
}

sub listatom {
    say 'not implemented yet';
}

sub listrss {
    say 'not implemented yet';
}

sub pass {
    my $args = shift;
    $config{aws_secret_access_key} = $args->[0];
    save_config();
    setup_api();
    say 'set pass';
}

sub put {
    my $args = shift;
    return unless is_bucket_set();
    if ( !@{$args} == 2 ) {
        say "put <id> <data>";
        return;
    }

    my $key    = $args->[0];
    my $data   = $args->[1];
    my $bucket = get_bucket();
    my $status = $bucket->add_key( $key, $data );
    say "Uploaded: $key";
}

sub putfilewacl {
    my $args = shift;
    return unless is_bucket_set();
    if ( !@{$args} == 3 ) {
        say
            "error: putfilewacl <id> <file> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
        return;
    }

    my $key      = $args->[0];
    my $filename = $args->[1];
    my $file     = file($filename);
    my $data     = $file->slurp;
    my $bucket   = get_bucket();

    my $status = $bucket->add_key( $key, $data );

    my $acl = $args->[2];
    return unless is_valid_acl($acl);

    my $is_success = $bucket->set_acl( { acl_short => $acl, key => $key, } );
    say "Uploaded: $key";
}

sub quit {
    say 'Goodbye...';
}

sub setacl {
    my $args = shift;
    if ( !@{$args} == 3 ) {
        say
            "setacl ['bucket'|'item'] <id> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
        return;
    }

    my $object_type = $args->[0];
    unless ( $object_type eq 'bucket'
        || $object_type eq 'item' )
    {
        say "object type must be ['bucket'|'item'] ";
        return;
    }

    my $key = $args->[1];

    my $acl = $args->[2];
    return unless is_valid_acl($acl);

    if ( $object_type eq 'bucket' ) {
        my $is_succeeded = _set_acl_for_bucket( $key, $acl );
        return unless $is_succeeded;
    }
    elsif ( $object_type eq 'item' ) {
        return unless is_bucket_set();

        my $is_succeeded = _set_acl_for_item( $key, $acl );
        return unless $is_succeeded;
    }
    else {
        say
            "error: setacl ['bucket'|'item'] ¥<id¥> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
    }
}

sub _set_acl_for_bucket {
    my $bucket_name = shift;
    my $acl         = shift;
    my $bucket      = $api->bucket($bucket_name);
    my $is_success  = $bucket->set_acl( { acl_short => $acl } );
    if ($is_success) {
        say 'success';
        return 1;
    }
    else {
        say $bucket->err . ": " . $bucket->errstr;
        return 0;
    }
}

sub _set_acl_for_item {
    my $key        = shift;
    my $acl        = shift;
    my $bucket     = get_bucket();
    my $is_success = $bucket->set_acl( { acl_short => $acl, key => $key, } );
    if ($is_success) {
        say 'success';
        return 1;
    }
    else {
        say $bucket->err . ": " . $bucket->errstr;
        return 0;
    }

}

sub user {
    my $args = shift;
    $config{aws_access_key_id} = $args->[0];
    save_config();
    setup_api();
    say 'set user';
}

__END__

=head1 NAME

psh3ll.pl - Amazon S3 command shell for Perl

=head1 SYNOPSIS

  bucket [bucketname]
  count [prefix]
  createbucket
  delete <id>
  deleteall [prefix]
  deletebucket
  exit
  get
  getacl ['bucket'|'item'] <id>
  getfile <id> <file>
  gettorrent <id>
  head ['bucket'|'item'] <id>
  host [hostname]
  list [prefix] [max]
  listatom [prefix] [max]
  listrss [prefix] [max]
  listbuckets
  pass [password]
  put <id> <data>
  putfile <id> <file>
  putfilewacl <id> <file> ['private'|'public-read'|'public-read-write'|'authenticated-read']
  quit
  setacl ['bucket'|'item'] <id> ['private'|'public-read'|'public-read-write'|'authenticated-read']
  user [username]

=head1 AUTHOR

Dann E<lt>techmemo (at) gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<http://rubyforge.org/projects/rsh3ll/>

=cut

