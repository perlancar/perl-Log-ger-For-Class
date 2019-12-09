package Log::ger::For::Class;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Scalar::Util qw(blessed);
use Log::ger::For::Package qw(add_logging_to_package);
use Perinci::Sub::Util qw(gen_modified_sub);

our %SPEC;

sub import {
    my $class = shift;

    my $hook;
    while (@_) {
        my $arg = shift;
        if ($arg eq '-hook') {
            $hook = shift;
        } elsif ($arg eq 'add_logging_to_class') {
            no strict 'refs';
            my @c = caller(0);
            *{"$c[0]::$arg"} = \&$arg;
        } else {
            add_logging_to_class(classes => [$arg], import_hook=>$hook);
        }
    }
}

sub _default_precall_logger {
    my $args  = shift;
    my $margs = $args->{args};

    # exclude $self or package
    $margs->[0] = '$self' if blessed($margs->[0]);

    Log::ger::For::Package::_default_precall_logger($args);
}

sub _default_postcall_logger {
    my $args = shift;

    Log::get::For::Package::_default_postcall_logger($args);
}

gen_modified_sub(
    output_name => 'add_logging_to_class',
    base_name => 'Log::ger::For::Package::add_logging_to_package',
    summary => 'Add logging to class',
    description => <<'_',

Logging will be done using Log::ger.

Currently this function adds logging around method calls, e.g.:

    -> Class::method(...)
    <- Class::method() = RESULT
    ...

_
    remove_args => ['packages', 'filter_subs'],
    add_args    => {
        classes => {
            summary => 'Classes to add logging to',
            schema => ['array*' => {of=>'str*'}],
            req => 1,
            pos => 0,
        },
        filter_methods => {
            summary => 'Filter methods to add logging to',
            schema => ['array*' => {of=>'str*'}],
            description => <<'_',

The default is to add logging to all non-private methods. Private methods are
those prefixed by `_`.

_
        },
    },
    output_code => sub {
        my %args = @_;

        my $classes = $args{classes} or die "Please specify 'classes'";
        $classes = [$classes] unless ref($classes) eq 'ARRAY';
        delete $args{classes};

        my $filter_methods = $args{filter_methods};
        delete $args{filter_methods};

        if (!$args{precall_logger}) {
            $args{precall_logger} = \&_default_precall_logger;
            $args{logger_args}{precall_wrapper_depth} = 3;
        }
        if (!$args{postcall_logger}) {
            $args{postcall_logger} = \&_default_postcall_logger;
            $args{logger_args}{postcall_wrapper_depth} = 3;
        }
        add_logging_to_package(
            %args,
            packages => $classes,
            filter_subs => $filter_methods,
        );
    },
);

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Log::ger::For::Class qw(add_logging_to_class);
 add_logging_to_class(classes => [qw/My::Class My::SubClass/]);
 # now method calls to your classes are logged, by default at level 'trace'


=head1 DESCRIPTION

Most of the things that apply to L<Log::ger::For::Package> also applies to this
module, since this module uses add_logging_to_package() as its backend.


=head1 SEE ALSO

L<Log::ger::For::Package>

L<Log::ger::For::DBI>, an application of this module.

=cut
