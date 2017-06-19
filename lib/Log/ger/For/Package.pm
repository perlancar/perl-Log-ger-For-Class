package Log::ger::For::Package;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;
use experimental 'smartmatch';
use Log::ger;

use Data::Clean::JSON;
use Package::MoreUtil qw(package_exists list_package_contents
                         list_subpackages);
use Sub::Uplevel;

our %SPEC;

my $cleanser = Data::Clean::JSON->new(-ref => ['stringify']);
my $import_hook_installed;

sub import {
    my $class = shift;

    my $hook;
    while (@_) {
        my $arg = shift;
        if ($arg eq '-hook') {
            $hook = shift;
        } elsif ($arg eq 'add_logging_to_package') {
            no strict 'refs';
            my @c = caller(0);
            *{"$c[0]::$arg"} = \&$arg;
        } else {
            add_logging_to_package(packages=>[$arg], import_hook=>1);
        }
    }
}

my $nest_level = 0;
my $default_indent    = 1;
my $default_max_depth = -1;

sub _default_precall_logger {
    my $args  = shift;

    if (log_is_trace()) {

        my $largs  = $args->{logger_args} // {};

        # TODO: replace this with its equivalent for Log::ger.

        # # there is no equivalent of caller_depth in Log::Any, so we do this only
        # # for Log4perl
        # my $wd = $largs->{precall_wrapper_depth} // 2;
        # local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth +
        #     $wd + $nest_level if defined $Log::Log4perl::caller_depth;

        my $md     = $largs->{max_depth} // $default_max_depth;

        if ($md == -1 || $nest_level < $md) {
            my $indent = " "x($nest_level*($largs->{indent}//$default_indent));
            my $cargs;
            if ($largs->{log_sub_args} // $ENV{LOG_SUB_ARGS} // 1) {
                $cargs = $cleanser->clone_and_clean($args->{args});
            } else {
                $cargs = "...";
            }
            log_tracef("%s---> %s(%s)", $indent, $args->{name}, $cargs);
        }

    }
    $nest_level++;
}

sub _default_postcall_logger {
    my $args = shift;

    $nest_level--;
    if (log_is_trace()) {

        my $largs  = $args->{logger_args} // {};

        # TODO: replace with its Log::ger equivalent

        # # there is no equivalent of caller_depth in Log::Any, so we do this only
        # # for Log4perl
        # my $wd = $largs->{postcall_wrapper_depth} // 2;
        # local $Log::Log4perl::caller_depth = $Log::Log4perl::caller_depth +
        #     $wd + $nest_level if defined $Log::Log4perl::caller_depth;

        my $md     = $largs->{max_depth} // $default_max_depth;
        if ($md == -1 || $nest_level < $md) {
            my $indent = " "x($nest_level*($largs->{indent}//$default_indent));
            if (@{$args->{result}}) {
                my $cres;
                if ($largs->{log_sub_result} // $ENV{LOG_SUB_RESULT} // 1) {
                    $cres = $cleanser->clone_and_clean($args->{result});
                } else {
                    $cres = "...";
                }
                log_trace("%s<--- %s() = %s", $indent, $args->{name}, $cres);
            } else {
                log_trace("%s<--- %s()", $indent, $args->{name});
            }
        }

    }
}

$SPEC{add_logging_to_package} = {
    v => 1.1,
    summary => 'Add logging to package',
    description => <<'_',

Logging will be done using Log::ger.

Currently this function adds logging around function calls, e.g.:

    ---> Package::func(ARGS)
    <--- Package::func() = RESULT
    ...

_
    args => {
        packages => {
            summary => 'Packages to add logging to',
            schema => ['array*' => {of=>'str*'}],
            req => 1,
            pos => 0,
            description => <<'_',

Each element can be the name of a package or a regex pattern (any non-valid
package name will be regarded as a regex). If the package is (comes from) a
module, the module must already be loaded. This function will not load modules
for you.

_
        },
        import_hook => {
            summary => 'Whether to install import (@INC) hook instead',
            schema  => ['bool' => default => 0],
            description => <<'_',

If this setting is true, then instead of installing logging to all existing
packages, an @INC import hook will be installed instead so that subsequent
modules that are loaded and that match `packages` will be logged. So to log all
subsequent loaded modules, you can set `packages` to `['.*']`.

_
        },
        precall_logger => {
            summary => 'Supply custom precall logger',
            schema  => 'code*',
            description => <<'_',

Code will be called when logging subroutine/method call. Code will be given a
hashref argument \%args containing these keys: `args` (arrayref, a shallow copy
of the original @_), `orig` (coderef, the original subroutine/method), `name`
(string, the fully-qualified subroutine/method name), `logger_args` (arguments
given when adding logging).

You can use this mechanism to customize logging.

The default logger accepts these arguments (can be supplied via `logger_args`):

* `indent` => INT (default: 0)

Indent according to nesting level.

* `max_depth` => INT (default: -1)

Only log to this nesting level. -1 means unlimited.

* `log_sub_args` => BOOL (default: 1)

Whether to display subroutine arguments when logging subroutine entry. The default can also
be supplied via environment `LOG_SUB_ARGS`.

* `log_sub_result` => BOOL (default: 1)

Whether to display subroutine result when logging subroutine exit. The default
can also be set via environment `LOG_SUB_RESULT`.

_
        },
        postcall_logger => {
            summary => 'Supply custom postcall logger',
            schema  => 'code*',
            description => <<'_',

Just like `precall_logger`, but code will be called after subroutine/method is
called. Code will be given a hashref argument \%args containing these keys:
`args` (arrayref, a shallow copy of the original @_), `orig` (coderef, the
original subroutine/method), `name` (string, the fully-qualified
subroutine/method name), `result` (arrayref, the subroutine/method result),
`logger_args` (arguments given when adding logging).

You can use this mechanism to customize logging.

_
        },
        logger_args => {
            summary => 'Pass arguments to logger',
            schema  => 'any*',
            description => <<'_',

This allows passing arguments to logger routine.

_
        },
        filter_subs => {
            summary => 'Filter subroutines to add logging to',
            schema => ['any*' => {of=>['re*', 'code*']}],
            description => <<'_',

The default is to read from environment `LOG_PACKAGE_INCLUDE_SUB_RE` and
`LOG_PACKAGE_EXCLUDE_SUB_RE` (these should contain regex that will be matched
against fully-qualified subroutine/method name), or, if those environment are
undefined, add logging to all non-private subroutines (private subroutines are
those prefixed by `_`). For example.

_
        },
    },
    result_naked => 1,
};
sub add_logging_to_package {
    my %args = @_;

    my $packages = $args{packages} or die "Please specify 'packages'";
    my $hook     = $args{import_hook};
    $packages = [$packages] unless ref($packages) eq 'ARRAY';

    my $filter = $args{filter_subs};
    my $envincre = $ENV{LOG_PACKAGE_INCLUDE_SUB_RE};
    my $envexcre = $ENV{LOG_PACKAGE_EXCLUDE_SUB_RE};
    if (!defined($filter) && (defined($envincre) || defined($envexcre))) {
        $filter = sub {
            local $_ = shift;
            if (defined $envexcre) {
                return 0 if /$envexcre/;
                return 1 unless defined($envincre);
            }
            if (defined $envincre) {
                return 1 if /$envincre/;
                return 0;
            }
        };
    }
    $filter //= qr/::[^_]\w+$/;

    my $_add = sub {
        my ($package) = @_;

        my %contents = list_package_contents($package);
        my @syms;
        for my $sym (keys %contents) {
            my $sub = $contents{$sym};
            next unless ref($sub) eq 'CODE';

            my $name = "${package}::$sym";
            if (ref($filter) eq 'CODE') {
                next unless $filter->($name);
            } else {
                next unless $name =~ $filter;
            }

            no strict 'refs';
            no warnings; # redefine sub

            # replace the sub in the source
            push @syms, $sym;
            *{"$package\::$sym"} = sub {
                my $logger;
                my %largs = (
                    orig   => $sub,
                    name   => $name,
                    args   => [@_],
                    logger_args => $args{logger_args},
                );

                $logger = $args{precall_logger} // \&_default_precall_logger;
                $logger->(\%largs);

                my $wa = wantarray;
                my @res;
                if ($wa) {
                    @res = uplevel 1, $sub, @_;
                } elsif (defined $wa) {
                    $res[0] = uplevel 1, $sub, @_;
                } else {
                    uplevel 1, $sub, @_;
                }

                $logger = $args{postcall_logger} // \&_default_postcall_logger;
                $largs{result} = \@res;
                $logger->(\%largs);

                if ($wa) {
                    return @res;
                } elsif (defined $wa) {
                    return $res[0];
                } else {
                    return;
                }
            };

        } # for $sym
        log_trace("Added logging to package %s (subs %s)",
                  $package, [sort @syms]);
    };

    if ($hook) {
        if ($import_hook_installed++) {
            warn "Only the first add_logging_to_package(import_hook=>1, ...) ".
                "will be in effect";
        } else {
            unshift @INC, sub {
                my ($self, $module) = @_;

                # load the module first
                local @INC = grep { !ref($_) || $_ != $self } @INC;
                require $module;

                my $package = $module;
                $package =~ s/\.pm$//;
                $package =~ s!/!::!g;

                $_add->($package) if $package ~~ @$packages;

                # ignore this hook
                my $line = 0;
                return sub {
                    unless ($line++) {
                        $_ = "1;\n";
                        return 1;
                    }
                    return 0;
                }
            };
        }
    } else {
        my $all_packages;
        my %processed;
        for my $package (@$packages) {
            if ($package =~ /\A\w+(::\w+)*\z/) {
                next if $processed{$package};
                $_add->($package);
                $processed{$package}++;
            } else {
                $all_packages //= [list_subpackages("", 1)];
                for (@$all_packages) {
                    next unless /$package/;
                    next if $processed{$_};
                    $_add->($_);
                    $processed{$_}++;
                }
            }
        } # for $package
    }

    1;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

Add log to some existing packages (in other words, modules that are already
loaded):

 use Foo;
 use Bar;
 use Log::ger::For::Package qw(Foo Bar);
 ...

Now calls to your module functions are logged, by default at level 'trace'. To
see the logs, use e.g. Log::ger::Output::Screen in command-line:

 % TRACE=1 perl -MLog::ger::Output=Screen -MFoo -MBar -MLog::ger::For::Package=Foo,Bar \
     -e'Foo::func(1, 2, 3)'
 ---> Foo::func([1, 2, 3])
  ---> Bar::nested()
  <--- Bar::nested()
 <--- Foo::func() = 'result'

Use C<add_logging_to_package()> which gives more options, e.g. to add log to
multiple packages specified by regex:

 use Log::ger::For::Package qw(add_logging_to_package);
 add_logging_to_package(packages => [qw/Foo::.*/]);

To install an import (C<@INC>) hook so that subsequent modules loaded will be
logged:

 add_logging_to_package(packages => [...], import_hook=>1);

or, via import:

 % TRACE=1 perl -MLog::ger::Output=Screen -MLog::ger::For::Package=-hook,1,.* ...


=head1 FAQ

=head2 How do I know that logging has been added to a package?

Log::ger::For::Package logs a trace statement like this after it added logging
to a package:

 Added logging to package Foo (subs ["sub1","sub2",...])


=head1 ENVIRONMENT

=head2 LOG_PACKAGE_INCLUDE_SUB_RE (str)

=head2 LOG_PACKAGE_EXCLUDE_SUB_RE (str)

=head2 LOG_SUB_ARGS (bool)

=head2 LOG_SUB_RESULT (bool)


=head1 CREDITS

Some code portion taken from L<Devel::TraceMethods>.


=head1 SEE ALSO

L<Log::ger::For::Class>

For some modules, use the appropriate Log::ger::For::*, for example:
L<Log::ger::For::DBI>, L<Log::ger::For::LWP>.

=cut
