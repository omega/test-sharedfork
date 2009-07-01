package Test::SharedFork;
use strict;
use warnings;
use base 'Test::Builder::Module';
our $VERSION = '0.05';
use Test::Builder;
use Test::SharedFork::Scalar;
use Test::SharedFork::Array;
use Test::SharedFork::Store;
use Storable ();
use File::Temp ();
use Fcntl ':flock';

my $tmpnam;
my $STORE;
our $MODE = 'DEFAULT';
BEGIN {
    $tmpnam ||= File::Temp::tmpnam();

    my $store = Test::SharedFork::Store->new($tmpnam);
    $store->lock_cb(sub {
        $store->initialize();
    }, LOCK_EX);
    undef $store;

    no strict 'refs';
    no warnings 'redefine';
    for my $name (qw/ok skip todo_skip current_test/) {
        my $cur = *{"Test::Builder::${name}"}{CODE};
        *{"Test::Builder::${name}"} = sub {
            my @args = @_;
            if ($STORE) {
                $STORE->lock_cb(sub {
                    $cur->(@args);
                });
            } else {
                $cur->(@args);
            }
        };
    };
}

my @CLEANUPME;
sub parent {
    my $store = _setup();
    $STORE = $store;
    push @CLEANUPME, $tmpnam;
    $MODE = 'PARENT';
}

sub child {
    # And musuka said: 'ラピュタは滅びぬ！何度でもよみがえるさ！'
    # (Quote from 'LAPUTA: Castle in he Sky')
    __PACKAGE__->builder->no_ending(1);

    $MODE = 'CHILD';
    $STORE = _setup();
}

sub _setup {
    my $store = Test::SharedFork::Store->new($tmpnam);
    tie __PACKAGE__->builder->{Curr_Test}, 'Test::SharedFork::Scalar', 0, $store;
    tie @{__PACKAGE__->builder->{Test_Results}}, 'Test::SharedFork::Array', $store;

    return $store;
}

sub fork {
    my $self = shift;

    my $pid = fork();
    if ($pid == 0) {
        child();
        return $pid;
    } elsif ($pid > 0) {
        parent();
        return $pid;
    } else {
        return $pid; # error
    }
}

END {
    undef $STORE;
    if ($MODE eq 'PARENT') {
        unlink $_ for @CLEANUPME;
    }
}

1;
__END__

=head1 NAME

Test::SharedFork - fork test

=head1 SYNOPSIS

    use Test::More tests => 200;
    use Test::SharedFork;

    my $pid = fork();
    if ($pid == 0) {
        # child
        Test::SharedFork->child;
        ok 1, "child $_" for 1..100;
    } elsif ($pid) {
        # parent
        Test::SharedFork->parent;
        ok 1, "parent $_" for 1..100;
        waitpid($pid, 0);
    } else {
        die $!;
    }

=head1 DESCRIPTION

Test::SharedFork is utility module for Test::Builder.
This module makes forking test!

This module merges test count with parent process & child process.

=head1 METHODS

=over 4

=item parent

call this class method, if you are parent

=item child

call this class method, if you are child.

you can call this method many times(maybe the number of your children).

=item fork

This method calls fork(2), and call child() or parent() automatically.
Return value is pass through from fork(2).

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom  slkjfd gmail.comE<gt>

yappo

=head1 SEE ALSO

L<Test::TCP>, L<Test::Fork>, L<Test::MultipleFork>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
