package Smokeping::Traceping;

=head1 NAME

Smokeping::Traceping - Optional traceroute history for SmokePing targets

=head1 DESCRIPTION

This module provides periodic traceroute collection and storage for SmokePing
targets. It stores traceroute results in a SQLite database, allowing users to
view current and historical routing paths for each monitored target.

This feature is entirely optional. When C<traceping_db> is not configured in
the General section, the module is not loaded and SmokePing behaves exactly
as before.

=head1 CONFIGURATION

Add the following to the C<*** General ***> section:

 traceping_db = /var/lib/smokeping/traceping.sqlite
 traceping_interval = 300
 traceping_retention_days = 365

=head1 AUTHOR

Oscar Centelles E<lt>ocentelles@gmail.comE<gt>

=cut

use strict;
use warnings;
use POSIX qw(strftime);

my $dbh;

sub init {
    my ($class, $cfg) = @_;
    my $db_path = $cfg->{General}{traceping_db};
    return unless $db_path;

    eval { require DBI; require DBD::SQLite; };
    if ($@) {
        warn "Traceping: DBI or DBD::SQLite not available, traceroute history disabled: $@\n";
        return;
    }

    $dbh = DBI->connect("dbi:SQLite:dbname=$db_path", '', '', {
        RaiseError => 0,
        PrintError => 0,
        sqlite_unicode => 1,
    });

    unless ($dbh) {
        warn "Traceping: Could not open database $db_path\n";
        return;
    }

    $dbh->do('CREATE TABLE IF NOT EXISTS traceroute_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target TEXT NOT NULL,
        tracert TEXT,
        timestamp TEXT NOT NULL
    )');
    $dbh->do('CREATE INDEX IF NOT EXISTS idx_target_timestamp ON traceroute_history(target, timestamp)');

    return 1;
}

sub is_enabled {
    return defined $dbh;
}

sub collect {
    my ($class, $cfg, $tree, $name) = @_;
    return unless $dbh;

    foreach my $prop (keys %{$tree}) {
        if (ref $tree->{$prop} eq 'HASH') {
            $class->collect($cfg, $tree->{$prop}, $name . "/$prop");
        }
        if ($prop eq 'host' and $tree->{$prop} !~ m|^/|) {
            my $host = $tree->{$prop};
            my $target = $name;
            my $base = $cfg->{General}{datadir};
            $target =~ s|^$base/||;
            $target =~ s|/host$||;
            $target =~ s|/|.|g;

            my $cmd = "/usr/bin/traceroute -I -w 1 -q 1 -m 20 $host 2>&1";
            my $result = `$cmd`;
            my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);

            my $sth = $dbh->prepare('INSERT INTO traceroute_history (target, tracert, timestamp) VALUES (?, ?, ?)');
            $sth->execute($target, $result, $timestamp);
            $sth->finish;
        }
    }
}

sub cleanup {
    my ($class, $retention_days) = @_;
    return unless $dbh;
    $retention_days ||= 365;

    my $cutoff = strftime("%Y-%m-%d %H:%M:%S", localtime(time - ($retention_days * 86400)));
    my $sth = $dbh->prepare('DELETE FROM traceroute_history WHERE timestamp < ?');
    $sth->execute($cutoff);
    $sth->finish;
}

sub get_latest {
    my ($class, $target) = @_;
    return '' unless $dbh;

    my $sth = $dbh->prepare('SELECT tracert FROM traceroute_history WHERE target=? ORDER BY timestamp DESC LIMIT 1');
    $sth->execute($target);
    my ($result) = $sth->fetchrow_array;
    $sth->finish;
    return $result || '';
}

sub get_history {
    my ($class, $target, $limit, $date, $hour) = @_;
    return [] unless $dbh;
    $limit ||= 20;
    $limit = 100 if $limit > 100;
    $limit = 5 if $limit < 5;

    my ($sth, @params);

    if ($date && $date =~ /^\d{4}-\d{2}-\d{2}$/) {
        if ($hour && $hour =~ /^\d{1,2}$/) {
            my $hour_start = sprintf("%02d:00:00", $hour);
            my $hour_end = sprintf("%02d:59:59", $hour);
            $sth = $dbh->prepare("SELECT tracert, timestamp FROM traceroute_history WHERE target=? AND date(timestamp)=? AND time(timestamp) BETWEEN ? AND ? ORDER BY timestamp DESC LIMIT ?");
            @params = ($target, $date, $hour_start, $hour_end, $limit);
        } else {
            $sth = $dbh->prepare("SELECT tracert, timestamp FROM traceroute_history WHERE target=? AND date(timestamp)=? ORDER BY timestamp DESC LIMIT ?");
            @params = ($target, $date, $limit);
        }
    } else {
        $sth = $dbh->prepare('SELECT tracert, timestamp FROM traceroute_history WHERE target=? ORDER BY timestamp DESC LIMIT ?');
        @params = ($target, $limit);
    }

    $sth->execute(@params);
    my @results;
    while (my ($tracert, $timestamp) = $sth->fetchrow_array) {
        push @results, { tracert => $tracert, timestamp => $timestamp };
    }
    $sth->finish;
    return \@results;
}

sub cgi_handler {
    my ($class, $q) = @_;
    my $target = $q->param('traceping_target');
    my $history = $q->param('traceping_history');
    my $date = $q->param('traceping_date');
    my $hour = $q->param('traceping_hour');
    my $limit = $q->param('traceping_limit') || 20;

    return '' unless $target && $target =~ /^[a-zA-Z0-9._-]+$/;

    if ($history) {
        my $records = $class->get_history($target, $limit, $date, $hour);
        my $html = '';
        my $count = 0;
        for my $rec (@$records) {
            $count++;
            my $open = $count == 1 ? 'open' : '';
            $html .= "<details $open style='margin:4px 0;'>";
            $html .= "<summary style='cursor:pointer;padding:8px 12px;background:#f1f3f4;border:1px solid #dadce0;border-radius:4px;font-size:12px;color:#202124;'>";
            $html .= "<strong>$rec->{timestamp}</strong></summary>";
            $html .= "<pre style='margin:8px 0 0 0;background:#1e1e1e;color:#d4d4d4;padding:12px;border-radius:4px;font-size:11px;line-height:1.4;overflow-x:auto;'>$rec->{tracert}</pre>";
            $html .= "</details>";
        }
        if ($count == 0) {
            $html = '<p style="color:#5f6368;font-size:12px;text-align:center;">No history available.</p>';
        }
        return $html;
    } else {
        my $tracert = $class->get_latest($target);
        return $tracert || 'No traceroute data available.';
    }
}

1;
