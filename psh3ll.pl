#!/usr/bin/env perl
use strict;
use warnings;
use Net::Amazon::S3;
use Term::ReadLine;
use Encode;
use ExtUtils::MakeMaker ();
use File::HomeDir;
use File::Spec;
use YAML;
use Data::Dumper;
use File::HomeDir;
use Perl6::Say;
use Data::Dumper;

our $conf = File::Spec->catfile( File::HomeDir->my_home, ".psh3ll" );
our %config = ();
our $changed;
our $api;
our %commands;
our $bucket_name;

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

sub _show_banner {
    say;
    say "Welcome to pSh3ll (Amazon S3 command shell for Perl) (c) 2008 Dann.";
    say "Type 'help' for command list.";
    say;
}

sub _input_loop {
    my $term   = Term::ReadLine->new('pSh3ll');
    my $prompt = 'psh3ll> ';

    while ( defined( my $input = eval { $term->readline($prompt) } ) ) {
        my @tokens = split( /\s/, $input );
        return unless ( @tokens >= 1 );

        my $command = shift @tokens;
        if ( $command eq 'quit' || $command eq 'exit' ) {
            quit();
            return;
        }
        _dispatch_on_input( $command, \@tokens );

        $term->addhistory($input);
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

}

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

sub _setup_commands {
    %commands = (
        bucket       => \&bucket,
        count        => \&count,
        createbucket => \&createbucket,
        delete       => \&delete,
        deleteall    => \&deleteall,
        deletebucket => \&deletebucket,
        exit         => \&exit,
        get          => \&get,
        getacl       => \&getacl,
        getfile      => \&getfile,
        gettorrent   => \&gettorrent,
        head         => \&head,
        host         => \&host,
        help         => \&help,
        list         => \&list,
        listbuckets  => \&listbuckets,
        listatom     => \&listatom,
        listrss      => \&listrss,
        pass         => \&pass,
        put          => \&put,
        putfile      => \&putfile,
        putfilewacl  => \&putfilewacl,
        quit         => \&quit,
        setacl       => \&setacl,
        user         => \&user,
    );
}

sub get_bucket {
    my $bucket = $api->bucket($bucket_name);
    $bucket;
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
    say 'not implemented yet';
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
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }

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
    say 'not implemented yet';
}

sub exit {
}

sub get {
    my $args = shift;
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }

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
    say 'not implemented yet';
}

sub getfile {
    say 'not implemented yet';
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
        "setacl ['bucket'|'item'] ¥<id¥> ['private'|'public-read'|'public-read-write'|'authenticated-read']";
    say "user [username]";
}

sub head {
    say 'not implemented yet';
}

sub host {
    say 'not implemented yet';
}

sub list {
    unless ($bucket_name) {
        say "error: bucket is not set";
        return;
    }

    my $bucket   = $api->bucket($bucket_name);
    my $response = $bucket->list_all
        or die $api->err . ": " . $api->errstr;
    foreach my $key ( @{ $response->{keys} } ) {
        my $key_name = $key->{key};
        my $key_size = $key->{size};
        say "Bucket contains key '$key_name' of size $key_size";
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
    say 'not implemented yet';
}

sub put {
    say 'not implemented yet';
}

sub puffilewacl {
    say 'not implemented yet';
}

sub quit {
    say 'Goodbye...';
}

sub setacl {
    say 'not implemented yet';
}

sub user {
    say 'not implemented yet';
}

__END__
