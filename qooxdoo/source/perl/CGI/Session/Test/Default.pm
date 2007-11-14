package CGI::Session::Test::Default;

use strict;
use Carp;
use Test::More ();
use Data::Dumper;
use Scalar::Util "refaddr";

our $AUTOLOAD;
our $CURRENT;
sub ok_later (&;$);
    

$CGI::Session::Test::Default::VERSION = '4.20';

=head1 CGI::Session::Test::Default

Run a suite of tests for a given CGI::Session::Driver

=head2 new()

    my $t = CGI::Session::Test::Default->new(
        # These are all optional, with default as follows
        dsn   => "driver:file",
        args  => undef,
        tests => 77,
    );

Create a new test object, possibly overriding some defaults.

=cut

sub new {
    my $class   = shift;
    my $self    = bless {
            dsn     => "driver:file",
            args    => undef,
            tests   => 101,
            test_number =>  0,
            @_
    }, $class;
    
    if($self->{skip}) {
        $self->{_skip} = { map { $_ => $_ } @{$self->{skip}} };
    } else {
        $self->{_skip} = {};
    }

    return $self;
}

=head2 number_of_tests()

    my $new_num = $t->number_of_tests($new_num);

A setter/accessor method to affect the number of tests to run,
after C<new()> has been called and before C<run()>.

=cut

sub number_of_tests {
    my $self = shift;

    if ( @_ ) {
        $self->{tests} = $_[0];
    }

    return $self->{tests};
}

=head2 run()

    $t->run();

Run the test suite. See C<new()> for setting related options.

=cut

sub run {
    my $self = shift;

    $CURRENT = $self;
    use_ok("CGI::Session", "CGI::Session loaded successfully!");

    my $sid = undef;
    FIRST: {
        ok(1, "=== 1 ===");
        my $session = CGI::Session->load() or die CGI::Session->errstr;
        ok($session, "empty session should be created");
        ok(!$session->id);
        ok($session->is_empty);
        ok(!$session->is_expired);

        undef $session;

        $session = CGI::Session->new($self->{dsn}, '_DOESN\'T EXIST_', $self->{args}) or die CGI::Session->errstr;
        ok( $session, "Session created successfully!");

        #
        # checking if the driver object created is really the driver requested:
        #
        my $dsn = $session->parse_dsn( $self->{dsn} );
        ok( ref $session->_driver eq "CGI::Session::Driver::" . $dsn->{driver}, ref $dsn->{Driver} );

        ok( $session->ctime && $session->atime, "ctime & atime are set");
        ok( $session->atime == $session->ctime, "ctime == atime");
        ok( !$session->etime, "etime not set yet");

        ok( $session->id, "session id is " . $session->id);

        $session->param('author', "Sherzod Ruzmetov");
        $session->param(-name=>'emails', -value=>['sherzodr@cpan.org', 'sherzodr@handalak.com']);
        $session->param('blogs', {
            './lost+found'              => 'http://author.handalak.com/',
            'Yigitlik sarguzashtlari'   => 'http://author.handalak.com/uz/'
        });

        ok( ($session->param) == 3, "session holds 3 params" . scalar $session->param );
        ok( $session->param('author') eq "Sherzod Ruzmetov", "My name's correct!");

        ok( ref ($session->param('emails')) eq 'ARRAY', "'emails' holds list of values" );
        ok( @{ $session->param('emails') } == 2, "'emails' holds list of two values");
        ok( $session->param('emails')->[0] eq 'sherzodr@cpan.org', "first value of 'emails' is correct!");
        ok( $session->param('emails')->[1] eq 'sherzodr@handalak.com', "second value of 'emails' is correct!");

        ok( ref( $session->param('blogs') ) eq 'HASH', "'blogs' holds a hash");
        ok( $session->param('blogs')->{'./lost+found'} eq 'http://author.handalak.com/', "first blog is correct");
        ok( $session->param('blogs')->{'Yigitlik sarguzashtlari'} eq 'http://author.handalak.com/uz/', "second blog is correct");

        $sid = $session->id;
        $session->flush();
    }

    sleep(1);

    SECOND: {
            SKIP: {
            ok(1, "=== 2 ===");
            my $session;
            eval { $session = CGI::Session->load($self->{dsn}, $sid, $self->{args}) };

            if ($@ || CGI::Session->errstr) {
                Test::More::skip("couldn't load session, bailing out: SQLite/Storable support is TODO", 56);
            }

            is($@.CGI::Session->errstr,'','survived eval without error.');
            ok($session, "Session was retrieved successfully");
            ok(!$session->is_expired, "session isn't expired yet");

            is($session->id,$sid, "session IDs are consistent");
            ok($session->atime > $session->ctime, "ctime should be older than atime");
            ok(!$session->etime, "etime shouldn't be set yet");

            ok( ($session->param) == 3, "session should hold params" );
            ok( $session->param('author') eq "Sherzod Ruzmetov", "my name's correct");

            ok( ref ($session->param('emails')) eq 'ARRAY', "'emails' should hold list of values" );
            ok( @{ $session->param('emails') } == 2, "'emails' should hold list of two values");
            ok( $session->param('emails')->[0] eq 'sherzodr@cpan.org', "first value is correct!");
            ok( $session->param('emails')->[1] eq 'sherzodr@handalak.com', "second value is correct!");

            ok( ref( $session->param('blogs') ) eq 'HASH', "'blogs' holds a hash");
            ok( $session->param('blogs')->{'./lost+found'} eq 'http://author.handalak.com/', "first blog is correct!");
            ok( $session->param('blogs')->{'Yigitlik sarguzashtlari'} eq 'http://author.handalak.com/uz/', "second blog is correct!");

            # TODO: test many any other variations of expire() syntax
            $session->expire('+1s');
            ok($session->etime == 1, "etime set to 1 second");

            $session->expire("+1m");
            ok($session->etime == 60, "etime set to one minute");

            $session->expires("2h");
            ok($session->etime == 7200, "etime set to two hours");

            $session->expires("5d");
            ok($session->etime == 432000, "etime set to 5 days");

            $session->expires("-10s");
            ok($session->etime == -10, "etime set to 10 seconds in the past");

            #
            # Setting the expiration time back to 1s, so that subsequent tests
            # relying on this value pass
            #
            $session->expire("1s");
            ok($session->etime == 1, "etime set back to one second");
            eval { $session->close(); };
            is($@, '', 'calling close method survives eval');
        }
    }

    sleep(1);   # <-- letting the time tick

    my $driver;
    THREE: {
        ok(1, "=== 3 ===");
        my $session = CGI::Session->load($self->{dsn}, $sid, $self->{args}) or die CGI::Session->errstr;
        ok($session, "Session instance loaded ");
        ok(!$session->id, "session doesn't have ID");
        ok($session->is_empty, "session is empty, which is the same as above");
        #print $session->dump;
        ok($session->is_expired, "session was expired");
        ok(!$session->param('author'), "session data cleared");

        sleep(1);

        $session = $session->new() or die CGI::Session->errstr;
        #print $session->dump();
        ok($session, "new session created");
        ok($session->id, "session has id :" . $session->id );
        ok(!$session->is_expired, "session isn't expired");
        ok(!$session->is_empty, "session isn't empty");
        ok($session->atime == $session->ctime, "access and creation times are same");

        ok($session->id ne $sid, "it's a completely different session than above");

        $driver     = $session->_driver();
        $sid        = $session->id;
    }



    FOUR: {
        # We are intentionally removing the session stored in the datastore and will be requesting
        # re-initialization of that id. This test is necessary since I noticed weird behaviors in
        # some of my web applications that kept creating new sessions when the object requested
        # wasn't in the datastore.
        ok(1, "=== 4 ===");

        ok($driver->remove( $sid ), "Session '$sid' removed from datastore successfully");

        my $session = CGI::Session->new($self->{dsn}, $sid, $self->{args} ) or die CGI::Session->errstr;
        ok($session, "session object created successfully");
        ok($session->id ne $sid, "claimed ID ($sid) couldn't be recovered. New ID is: " . $session->id);
        $sid = $session->id;
    }



    FIVE: {
        ok(1, "=== 5 ===");
        my $session = CGI::Session->new($self->{dsn}, $sid, $self->{args}) or die CGI::Session->errstr;
        ok($session, "Session object created successfully");
        ok($session->id eq $sid, "claimed id ($sid) was recovered successfully!");

        # Remove the object, finally!
        $session->delete();
    }


    SIX: {
        ok(1, "=== 6 ===");
        my $session = CGI::Session->new($self->{dsn}, $sid, $self->{args}) or die CGI::Session->errstr;
        ok($session, "Session object created successfully");
        ok($session->id ne $sid, "New object created, because previous object was deleted");
        $sid = $session->id;

        #
        # creating a simple object to be stored into session
        my $simple_class = SimpleObjectClass->new();
        ok($simple_class, "SimpleObjectClass created successfully");

        $simple_class->name("Sherzod Ruzmetov");
        $simple_class->emails(0, 'sherzodr@handalak.com');
        $simple_class->emails(1, 'sherzodr@cpan.org');
        $simple_class->blogs('lost+found', 'http://author.handalak.com/');
        $simple_class->blogs('yigitlik', 'http://author.handalak.com/uz/');
        $session->param('simple_object', $simple_class);

        ok($session->param('simple_object')->name eq "Sherzod Ruzmetov");
        ok($session->param('simple_object')->emails(1) eq 'sherzodr@cpan.org');
        ok($session->param('simple_object')->blogs('yigitlik') eq 'http://author.handalak.com/uz/');
        
        #
        # creating an overloaded object to be stored into session
        my $overloaded_class = OverloadedObjectClass->new("ABCDEFG");
        ok($overloaded_class, "OverloadedObjectClass created successfully");
        ok(overload::Overloaded($overloaded_class) , "OverloadedObjectClass is properly overloaded");
        ok(ref ($overloaded_class) eq "OverloadedObjectClass", "OverloadedObjectClass is an object");
        $session->param("overloaded_object", $overloaded_class);
        
        ok($session->param("overloaded_object") eq "ABCDEFG");
        
        my $simple_class2 = SimpleObjectClass->new();
        ok($simple_class2, "SimpleObjectClass created successfully");

        $simple_class2->name("Sherzod Ruzmetov");
        $simple_class2->emails(0, 'sherzodr@handalak.com');
        $simple_class2->emails(1, 'sherzodr@cpan.org');
        $simple_class2->blogs('lost+found', 'http://author.handalak.com/');
        $simple_class2->blogs('yigitlik', 'http://author.handalak.com/uz/');
        my $embedded = OverloadedObjectClass->new("Embedded");
        $session->param("embedded_simple_and_overloaded",[ undef, $simple_class2, $embedded, $embedded ]);

        ok(!defined($session->param("embedded_simple_and_overloaded")->[0]),"First element of anonymous array undef");

        ok($session->param("embedded_simple_and_overloaded")->[1]->name eq "Sherzod Ruzmetov");
        ok($session->param("embedded_simple_and_overloaded")->[1]->emails(1) eq 'sherzodr@cpan.org');
        ok($session->param("embedded_simple_and_overloaded")->[1]->blogs('yigitlik') eq 'http://author.handalak.com/uz/');
  
        ok($session->param("embedded_simple_and_overloaded")->[2] eq "Embedded");
        
        ok(refaddr($session->param("embedded_simple_and_overloaded")->[2]) == refaddr($session->param("embedded_simple_and_overloaded")->[3] ),
            "Overloaded objects have matching addresses");
    }


    SEVEN: {
        ok(1, "=== 7 ===");
        my $session = CGI::Session->new($self->{dsn}, $sid, $self->{args}) or die CGI::Session->errstr;
        ok($session, "Session object created successfully");
        ok($session->id eq $sid, "Previously stored object loaded successfully");


        my $simple_object = $session->param("simple_object");
        ok(ref $simple_object eq "SimpleObjectClass", "SimpleObjectClass loaded successfully");

        my $dsn = CGI::Session->parse_dsn($self->{dsn});
        ok_later { $simple_object->name eq "Sherzod Ruzmetov" };
        ok_later { $simple_object->emails(1) eq 'sherzodr@cpan.org' };
        ok_later { $simple_object->emails(0) eq 'sherzodr@handalak.com' };
        ok_later { $simple_object->blogs('lost+found') eq 'http://author.handalak.com/' };
        ok(ref $session->param("overloaded_object") );
        ok($session->param("overloaded_object") eq "ABCDEFG", "Object is still overloaded");
        ok(overload::Overloaded($session->param("overloaded_object")), "Object is really overloaded");

        ok(!defined($session->param("embedded_simple_and_overloaded")->[0]),"First element of anonymous array undef");
        
        my $simple_object2 = $session->param("embedded_simple_and_overloaded")->[1];
        ok(ref $simple_object2 eq "SimpleObjectClass", "SimpleObjectClass loaded successfully");

        ok_later { $simple_object2->name eq "Sherzod Ruzmetov" };
        ok_later { $simple_object2->emails(1) eq 'sherzodr@cpan.org' };
        ok_later { $simple_object2->emails(0) eq 'sherzodr@handalak.com' };
        ok_later { $simple_object2->blogs('lost+found') eq 'http://author.handalak.com/' };

        
        ok($session->param("embedded_simple_and_overloaded")->[2] eq "Embedded");
        ok(overload::Overloaded($session->param("embedded_simple_and_overloaded")->[2]), "Object is really overloaded");
        
        ok(refaddr($session->param("embedded_simple_and_overloaded")->[2]) == refaddr($session->param("embedded_simple_and_overloaded")->[3]),
            "Overloaded objects have matching addresses");        
        $session->delete();
    }
    
    $CURRENT = undef;
    $self->{test_number} = 0;
}

sub skip_or_run {
    my $test = shift;
    
    $CURRENT->{test_number} ++;

    SKIP: {
        if($CURRENT->{_skip}->{$CURRENT->{test_number}}) {
            Test::More::skip("Test does not apply to this setup.", 1);
        }
        
        no strict 'refs';
        &{"Test::More::$test"}(@_);
    }
}

sub ok { skip_or_run("ok", @_); }
sub use_ok { skip_or_run("use_ok", @_); }
sub is { skip_or_run("is", @_); }

sub ok_later (&;$) {
    my($code, $name) = @_;
    
    $CURRENT->{test_number} ++;
    $name = '' unless $name;

    SKIP: {
        if($CURRENT->{_skip}->{$CURRENT->{test_number}}) {
            Test::More::skip("Test does not apply to this setup.", 1);
            fail($name);
        } else {
            Test::More::ok($code->(), $name);
        }
    }
}

sub DESTROY { 1; }


package SimpleObjectClass;
use strict;
use Class::Struct;

struct (
    name    => '$',
    emails  => '@',
    blogs   => '%'
);



package OverloadedObjectClass;

use strict;
use overload (
    '""'    => \&as_string,
    'eq'    => \&equals
);

sub new {
    return bless {
        str_value => $_[1]
    }, $_[0];
}


sub as_string {
    return $_[0]->{str_value};
}

sub equals {
    my ($self, $arg) = @_;

    return ($self->as_string eq $arg);
}

1;
