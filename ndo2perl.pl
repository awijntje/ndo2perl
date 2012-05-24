#! /usr/bin/perl 
#
#
# SYNTAX:
#       ndo2perl.pl
#
# DESCRIPTION:
#       Imports NDO logs into database
#	Program is a stand-in replacement for ndo2db and as such need NDOUtils to be loaded.
#
#	ndo2perl can run in two modes.
#	1. as log rotate option (see ndomod.cfg) be aware of time needed to proces a single file!!
#	2. as part of a dir-watch setup (like import_ndologs from Opsview).
#
# AUTHORS:
#       Alan Wijntje 2012
#
#    ndo2perl is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    ndo2perl is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#

use strict;
use warnings;
use Data::Dumper;
use DBI;
use DBD::mysql;
use DBD::Pg;
use Config::File;
use Date::Format;
use File::Copy;
use Time::HiRes;

# my variables
my $start_time = [Time::HiRes::gettimeofday()];
my $file = $ARGV[0];
my $hashref;
my $key;
my $k;
my $v;
my @results;
my $nthash;
my $id;
my $ids;
my $dbconfig;
my $config = "/home/alan/Opsview/perl2db/perl2db.conf";
my $dsn;
my $conn;
my $dbh;
my $sth;
my $a;
my $w;
my $ndo;
my %ndo;
my @instance_id;
my $instance_id;
my $object_id;
my $objecttype_id;
my $name1;
my $name2;
my $objects;
my $objecttype;
my $notifications;
my $contactnotifications;
my $conninfo_id;
my $linecount = 0;
my $entrycount = 0;
my $bytecount = -s $file;
my $running;
my $arraycount=0;
my $keycount = 0;
my $process_count = 0;
my @prepares;
my $insert_id;
my $object_config_type = 0;

# db statement handles.
my $process_event_sth;
my $process_shutdown_sth;
my $notification_start_sth;
my $notification_end_sth;
my $contactnotification_start_sth;
my $contactnotification_end_sth;
my $contactnotificationmethod_start_sth;
my $contactnotificationmethod_end_sth;
my $servicecheck_processed_sth;
my $hostcheck_processed_sth;
my $comment_add_sth;
my $comment_history_sth;
my $comment_delete_sth;
my $comment_delete_history_sth;
my $flapping_start_sth;
my $flapping_end_sth;
my $downtime_add_sth;
my $downtime_history_insert_sth;
my $downtime_delete_sth;
my $downtime_history_update_sth;
my $downtime_start_sth;
my $downtime_history_start_sth;
my $downtime_stop_sth;
my $downtime_history_stop_sth;
my $programstatus_update_sth;
my $hoststatus_update_sth;
my $servicestatus_update_sth;
my $contactstatus_update_sth;
my $acknowledgement_add_sth;
my $statechange_sth;
my $timedevent_add_sth;
my $timedevent_remove_sth;
my $timedevent_execute_sth;
my $timedeventqueue_add_sth;
my $timedeventqueue_remove_sth;
my $nagios_objects_activate_sth;
my $configfiles_sth;
my $configfilevariables_sth;
my $runtimevariables_sth;
my $hostdefinition_host_sth;
my $hostdefinition_contactgroups_sth;
my $hostdefinition_contact_sth;
my $hostdefinition_parenthost_sth;
my $hostgroupdefinition_hostgroup_sth;
my $hostgroupdefinition_members_sth;
my $servicedefinition_service_sth;
my $servicedefinition_contactgroups_sth;
my $servicedefinition_contacts_sth;
my $servicegroupdefinition_servicegroup_sth;
my $servicegroupdefinition_members_sth;
my $hostdependencydefinition_host_sth;
my $servicedependencydefinition_service_sth;
my $commanddefinition_command_sth;
my $timeperioddefinition_timeperiod_sth;
my $timeperioddefinition_timeranges_sth;
my $contactdefinition_contact_sth;
my $contactdefinition_contactaddresses_sth;
my $contactdefinition_notificationcommands_sth;
my $contactgroupdefinition_contactgroup_sth;
my $contactgroupdefinition_members_sth;
my $hostescalation_host_sth;
my $hostescalation_contacts_sth;
my $hostescalation_contactgroups_sth;
my $serviceescalation_service_sth;
my $serviceescalation_contacts_sth;
my $serviceescalation_contactgroups_sth;
my $log_data_sth;
my $system_command_start_sth;
my $system_command_end_sth;
my $eventhandler_start_sth;
my $eventhandler_end_sth;
my $externalcommand_start_sth;
my $externalcommand_end_sth;
my $nagios_objects_insert_sth;
my $customvariables_sth;
my $customvariable_status_sth;

# my global lists.
my %ndo_id_list = (
	'211'	=> \&programstatus_update,
	'212'	=> \&hoststatus_update,
	'213'	=> \&servicestatus_update,
	'222'	=> \&acknowledgement_add,
	'224'	=> \&contactstatus_update,
	'303'   => \&runtimevariables,
	'400'   => \&hostdefinition,
	'401'   => \&hostgroupdefinition,
	'402'   => \&servicedefinition,
	'405'   => \&servicedependencydefinition,
	'406'	=> \&hostescalationdefinition,
	'407'	=> \&serviceescalationdefinition,
	'408'   => \&commanddefinition,
	'409'   => \&timeperioddefinition,
	'410'   => \&contactdefinition,
	'411'   => \&contactgroupdefinition,
	'900'   => \&startconfigdump,
	'901'   => \&endconfigdump,
);
my %eventlist = (
	'100'   => \&process_event,
	'101'   => \&process_event,
	'102'   => \&process_event,
	'103'   => \&process_shutdown,
	'104'   => \&process_prelaunch,
	'105'   => \&process_event,
	'106'   => \&process_event,
	'200'	=> \&timedevent_add,
	'201'	=> \&timedevent_remove,
	'202'	=> \&timedevent_execute,
	'205'	=> \&timedevent_sleep,
	'300'	=> \&log_data,
	'400'	=> \&system_command_start,
	'401'	=> \&system_command_end,
	'500'	=> \&eventhandler_start,
	'501'	=> \&eventhandler_end,
	'600'	=> \&notification_start,
	'601'	=> \&notification_end,
	'602'	=> \&contactnotification_start,
	'603'	=> \&contactnotification_end,
	'604'	=> \&contactnotificationmethod_start,
	'605'	=> \&contactnotificationmethod_end,
	'701'   => \&servicecheck_processed,
	'801'   => \&hostcheck_processed,
	'900'   => \&comment_add,
	'901'   => \&comment_delete,
	'902'   => \&comment_load,
	'1000'  => \&flapping_start,
	'1001'  => \&flapping_end,
	'1100'  => \&downtime_add,
	'1101'  => \&downtime_delete,
	'1102'  => \&downtime_load,
	'1103'  => \&downtime_start,
	'1104'  => \&downtime_stop,
	'1300'  => \&not_implemented,
	'1301'  => \&not_implemented,
	'1302'  => \&not_implemented,
	'1303'  => \&not_implemented,
	'1400'	=> \&externalcommand_start,
	'1401'	=> \&externalcommand_end,
	'1500'  => \&not_implemented,
	'1501'  => \&not_implemented,
	'1600'  => \&not_implemented,
	'1601'  => \&not_implemented,
	'1602'  => \&not_implemented,
	'1603'  => \&not_implemented,
	'1800'  => \&not_implemented,
	'1801'  => \&statechange,
);
# general lists we need we starting up to populate some tables.
my $contact_group_list_ref = {};

# subroutines we need to define straigth away.
sub mkhashkey ();

if ((!defined($file))||($file =~ /core/)) {
	print "Usage: $0 <ndolog-file>\n";
	exit;
}

# first we read in our file before we start the main program.
chomp($file);
open(FH, '<', $file) or die "can't open file: $!\n";
while(<FH>) {
	chomp($_);
	$linecount++;
	# no nice way of doing this lets just get it working and figure out a nice solution later on.
	next if ($_ =~ /^999$/); # skip 999 as it just end a block of info.
	next if ($_ =~ /^\s*$/); # skip empty lines.
	if ($_ =~ /AGENT:/) { 
		($a,$w) = split(":",$_);
		$w =~ s/^\s+|\s+$//g;
		$ndo{$a} = $w;
		next;
	} elsif ($_ =~ /AGENTVERSION:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /STARTTIME:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /DISPOSITION:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /CONNECTION:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /CONNECTTYPE:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /INSTANCENAME:/) {
                ($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	} elsif ($_ =~ /ENDTIME:/) {
		($a,$w) = split(":",$_);
                $w =~ s/^\s+|\s+$//g;
                $ndo{$a} = $w;
		next;
	}
	if (($_ =~ /^([0-9]{3,4}):$/)||($_ =~ /^1000$/)) {
		if (defined($key)) {
			$entrycount++;
			undef $key;
		}
		if ($_ =~ /^([0-9]{3,4}):$/) {
			$key = mkhashkey();
			$k = "ndo_id";
			chop($_);
			$hashref->{$key}->{$k} = $_;
			next;
		}
	}
	if ($_ =~ /=/ ) {
		($k,$v) = split ('=',$_,2);
		# need some logic in case we have multiple $k with different $v.
		if ((defined($hashref->{$key}->{$k})) && ($arraycount==0)) { # we already have this key
			# turn it into an array.
			# first save our old values and delete the key.
			my $old_v = $hashref->{$key}->{$k};
			delete $hashref->{$key}->{$k};
			push @{ $hashref->{$key}->{$k} }, $old_v;
			push @{ $hashref->{$key}->{$k} },$v;
			$arraycount++;
		} elsif ((defined($hashref->{$key}->{$k})) && ($arraycount!=0)) { # already have an array.
			push @{ $hashref->{$key}->{$k} },$v;
		} else {
			$hashref->{$key}->{$k} = $v;
			$arraycount = 0;
		}
	}
}
close FH;
my $diff = Time::HiRes::tv_interval($start_time);
my $mesg = "reading $file size: $bytecount lines: $linecount took: $diff seconds";

## MAIN program.
my $prog_start_time = [Time::HiRes::gettimeofday()];
while(1) {
	# make a db connection in a subroutine so we can setup dbhandles per thread later on.
	&dbconnect();

	# retrieve our instance ID
	$sth = $dbh->prepare("SELECT instance_id FROM nagios_instances WHERE instance_name='$ndo{INSTANCENAME}'");
	$sth->execute();
	@instance_id = $sth->fetchrow_array();
	$instance_id = $instance_id[0];
	# update conninfo on current import.
	&initialize_nagios_conninfo();
	# retrieve a series of timestamps (still not sure what they are used for though).
	&retrieve_timestamps();
	# retrieve object_id and objecttype_id which we need to have to insert results.
	&retrieve_object_ids();
	# setup all needed DB statements and handlers (only load what we need).
	&prepare_statements();
	# start going through our events in order (the order is important).
	while ($entrycount > $process_count) {
		$process_count++;
		&determine_event(\%{ $hashref->{$process_count} } );
	}
        # send final info to nagios_conninfo.
        &finalize_nagios_conninfo();
	$dbh->disconnect();
	my $prog_diff = Time::HiRes::tv_interval($prog_start_time);
	print $mesg." processing $entrycount entries took: $prog_diff seconds\n";
	last;
}

sub mkhashkey () {
	$keycount++;
	return $keycount;
}

sub dbconnect () {
	# here we handle setting up a DB connection and handle.
        $dbconfig = Config::File::read_config_file($config);
	if ($dbconfig->{driver} eq "mysql") {
        	$dsn = "dbi:$dbconfig->{driver}:$dbconfig->{database}:$dbconfig->{db_host}";
        	$dbh =  DBI->connect($dsn, $dbconfig->{db_user}, $dbconfig->{db_password}, { AutoCommit => 1}) or die "Can't connect to DB: $DBI::errstr";
	} elsif ($dbconfig->{driver} eq "Pg") {
		$dsn = "dbi:$dbconfig->{driver}:dbname=$dbconfig->{database}i;host=$dbconfig->{db_host}";
		$dbh = DBI->connect($dsn, $dbconfig->{db_user}, $dbconfig->{db_password}, { AutoCommit => 1}) or die "Can't connect to DB: $DBI::errstr";
	}
	# make sure our timezone is set to UTC. not sure how this works in other timezones probably stays what it is.
        $sth = $dbh->prepare("SET time_zone = '+00:00'");
        $sth->execute();
	return;
}

sub initialize_nagios_conninfo () {
	# things we need to do before inserting our results.
	my $connquery = "INSERT INTO nagios_conninfo 
		(instance_id, connect_time, last_checkin_time, bytes_processed, lines_processed, 
		entries_processed, agent_name, agent_version, disposition, connect_source, connect_type, data_start_time) 
		VALUES 
		(?,NOW(),NOW(),?,?,?,?,?,?,?,?,FROM_UNIXTIME(?))";
	$sth = $dbh->prepare($connquery);
	$sth->execute($instance_id,0,0,0,$ndo{'AGENT'},$ndo{'AGENTVERSION'},$ndo{'DISPOSITION'},$ndo{'CONNECTION'},$ndo{'CONNECTTYPE'},$ndo{'STARTTIME'});
	$conninfo_id = &determine_insert_id($sth);
	return $conninfo_id;
}

sub finalize_nagios_conninfo () {
	# final stats for conninfo.
	my $fconquery = "UPDATE nagios_conninfo SET disconnect_time=NOW(), last_checkin_time=NOW(), data_end_time=FROM_UNIXTIME($ndo{'ENDTIME'}), bytes_processed=$bytecount, lines_processed=$linecount, entries_processed=$entrycount WHERE conninfo_id = '$conninfo_id'";
	$sth = $dbh->prepare($fconquery);
	$sth->execute();
	$dbh->disconnect();
}

sub retrieve_timestamps () {
	# these timestamps are used for various updates to various tabels.
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(status_update_time) AS latest_time FROM nagios_programstatus 
		WHERE instance_id=$instance_id ORDER BY status_update_time DESC LIMIT 0,1");
	$sth->execute();
	my @progstatusupdatetime = $sth->fetchrow_array();
	my $progstatus_update_time = $progstatusupdatetime[0];
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(status_update_time) AS latest_time FROM nagios_hoststatus 
		WHERE instance_id=$instance_id ORDER BY status_update_time DESC LIMIT 0,1");
	$sth->execute();
	my @hoststatusupdatetime = $sth->fetchrow_array();
	my $hoststatus_update_time = $hoststatusupdatetime[0];
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(status_update_time) AS latest_time FROM nagios_servicestatus 
		WHERE instance_id=$instance_id ORDER BY status_update_time DESC LIMIT 0,1");
	$sth->execute();
	my @srvstatusupdatetime = $sth->fetchrow_array();
	my $srvstatus_update_time = $srvstatusupdatetime[0];
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(status_update_time) AS latest_time FROM nagios_contactstatus 
		WHERE instance_id=$instance_id	ORDER BY status_update_time DESC LIMIT 0,1");
	$sth->execute();
	my @constatusupdatetime = $sth->fetchrow_array();
	my $constatus_update_time = $constatusupdatetime[0];
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(queued_time) AS latest_time FROM nagios_timedeventqueue 
		WHERE instance_id=$instance_id ORDER BY queued_time DESC LIMIT 0,1");
	$sth->execute();
	my @timequeued = $sth->fetchrow_array();
	my $queued_time = $timequeued[0];
	$sth = $dbh->prepare("SELECT UNIX_TIMESTAMP(entry_time) AS latest_time FROM nagios_comments 
		WHERE instance_id=$instance_id ORDER BY entry_time DESC LIMIT 0,1");
	$sth->execute();
	my @commentrytime = $sth->fetchrow_array();
	my $comm_entry_time = $commentrytime[0];
	return ($progstatus_update_time,$hoststatus_update_time,$srvstatus_update_time,$constatus_update_time,$queued_time,$comm_entry_time);
}

sub retrieve_object_ids () {
	my $obiquery ="SELECT object_id, objecttype_id, name1, name2 FROM nagios_objects WHERE instance_id='$instance_id'";
	$sth = $dbh->prepare($obiquery);
	$sth->execute();
	while (my @row = $sth->fetchrow_array) {
		if (not defined ($row[3])) { $row[3] = "NULL"; }
		$objects->{$row[2]}->{$row[3]} = $row[0];
		$objecttype->{$row[2]}->{$row[3]} = $row[1];
	}
	return ($objects, $objecttype);
}

sub determine_object_id () {
	# determine the object_id for our event
	$id = $_[0];
	$ids = $_[1];
	if (defined($id)) {
		$object_id = $objects->{$id}->{$ids};
	}
	if ((not defined($object_id)) && (defined($id))) {
		my ($name1,$name2,$called_from);
		if (defined($_[2])) {
			$called_from = $_[2];
		}
		$name1 = $id;
		if ($ids eq "NULL") {
			$name2 = undef; # so mysql get's set to NULL correclty (not as a string)
		} else {
			$name2 = $ids;
		}
		my $objecttype_id = &objecttypes($called_from);
		# object does not exist so add it.
		# example for service: INSERT INTO nagios_objects SET instance_id='1', objecttype_id='2' , name1='localhost' , name2='Connectivity - LAN'
		# example for host: INSERT INTO nagios_objects SET instance_id='1', objecttype_id='1' , name1='localhost'
		$nagios_objects_insert_sth->execute($instance_id,$objecttype_id,$name1,$name2);
		$object_id = &determine_insert_id($nagios_objects_insert_sth);
		# add to our objects hash we need them not only in this call.
		if (not defined($name2)) {$name2 = "NULL"; }
		$objects->{$name1}->{$name2} = $object_id;
		$objecttype->{$name1}->{$name2} = $objecttype_id;
	}
	return($object_id);
}

sub determine_objecttype_id () {
	# determine the objecttype id.
	$id = $_[0];
	if (defined $_[1]) {
		$ids = $_[1];
	} else {
		$ids = "NULL";
	}
	$objecttype_id = $objecttype->{$id}->{$ids};
	return($objecttype_id);
}

sub objecttypes () {
	my $type = shift;
	# table containing the various objecttype_ids found in nagios.
	# based on Nagios DB model documentation
	my %objecttypes = (
		'host'			=> 1,
		'service'		=> 2,
		'hostgroup'		=> 3,
		'servicegroup'		=> 4,
		'hostescalation'	=> 5,
		'serviceescalation'	=> 6,
		'hostdependency'	=> 7,
		'servicedependency'	=> 8,
		'timeperiod'		=> 9,
		'contact'		=> 10,
		'contactgroup'		=> 11,
		'command'		=> 12,
		'extendedhostinfo'	=> 13,
		'extendedserviceinfo'	=> 14,
	);
	return ($objecttypes{ $type });
}

sub determine_event () {
	my $eventhash_ref = shift;
	if (defined($eventhash_ref->{'ndo_id'}) && defined($ndo_id_list{ $eventhash_ref->{'ndo_id'} } ) ) {
		&{ $ndo_id_list{ $eventhash_ref->{'ndo_id'} } }($eventhash_ref);
	} elsif (defined($eventhash_ref->{1}) && defined($eventlist{ $eventhash_ref->{1} } ) ) {
		&{ $eventlist{ $eventhash_ref->{1} } }($eventhash_ref);
	} elsif (defined($eventhash_ref->{1}) && not defined($eventlist{ $eventhash_ref->{1} } )) {
		&unknown_event_type($eventhash_ref);
	} else {
		&unknown_ndo_id($eventhash_ref);
	}
	return;
}

sub determine_insert_id () {
	my $dbhandler = shift;
	if ($dbconfig->{driver} eq "mysql") {
		$insert_id = $dbhandler->{mysql_insertid};
	} elsif ($dbconfig->{driver} eq "Pg") {
		# code to retrieve last insert id for postgres, need to know which table was updated though.
		#$insert_id = $dbh->last_insert_id(undef,undef,"table",undef);
	}
	return($insert_id);
}

#########################################################################################################################
#
# DB prepared statements.
#
# Because a lot of events happen multiple times it makes more sense to prepare them once and execute them many.
# It also makes it easier to maintain the queries as they all reside here.

sub prepare_statements () {
	my $nagios_objects_insert_query = "INSERT INTO nagios_objects (instance_id,objecttype_id,name1,name2) VALUES (?,?,?,?)";
	$nagios_objects_insert_sth = $dbh->prepare($nagios_objects_insert_query);
	my $process_event_query = "INSERT INTO nagios_processevents 
		(instance_id,event_type,event_time,event_time_usec,process_id,program_name,program_version,program_date)
		VALUES
		(?,?,FROM_UNIXTIME(?),?,?,?,?,?)";
	$process_event_sth = $dbh->prepare($process_event_query);
	my $process_shutdown_query = "UPDATE nagios_programstatus SET program_end_time=FROM_UNIXTIME(?),is_currently_running=?
		WHERE instance_id=?";
	$process_shutdown_sth = $dbh->prepare($process_shutdown_query);
	my $notification_start_query = "INSERT INTO nagios_notifications (instance_id,notification_type,notification_reason,notification_number,
		start_time,start_time_usec,end_time,end_time_usec,object_id,state,output,escalated,contacts_notified) VALUES
		(?,?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,notification_type=?,
		notification_reason=?,notification_number=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),
		end_time_usec=?,object_id=?,state=?,output=?,escalated=?,contacts_notified=?";
	$notification_start_sth = $dbh->prepare($notification_start_query);
	my $notification_end_query = "INSERT INTO nagios_notifications (instance_id,notification_type,notification_reason,notification_number,
		start_time,start_time_usec,end_time,end_time_usec,object_id,state,output,escalated,contacts_notified) VALUES
		(?,?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,notification_type=?,
		notification_reason=?,notification_number=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),
		end_time_usec=?,object_id=?,state=?,output=?,escalated=?,contacts_notified=?";
	$notification_end_sth = $dbh->prepare($notification_end_query);
	my $contactnotification_start_query = "INSERT INTO nagios_contactnotifications (instance_id,notification_id,contact_object_id,start_time,
		start_time_usec,end_time,end_time_usec) VALUES (?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?) ON DUPLICATE KEY UPDATE instance_id=?,
		notification_id=?,contact_object_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?";
	$contactnotification_start_sth = $dbh->prepare($contactnotification_start_query);
	my $contactnotification_end_query = "INSERT INTO nagios_contactnotifications (instance_id,notification_id,contact_object_id,start_time,
		start_time_usec,end_time,end_time_usec) VALUES (?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?) ON DUPLICATE KEY UPDATE instance_id=?,
		notification_id=?,contact_object_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?";
	$contactnotification_end_sth = $dbh->prepare($contactnotification_end_query);
	my $contactnotificationmethod_start_query = "INSERT INTO nagios_contactnotificationmethods (instance_id,contactnotification_id,start_time,
		start_time_usec,end_time,end_time_usec,command_object_id,command_args) VALUES (?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,contactnotification_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,
		end_time=FROM_UNIXTIME(?),end_time_usec=?,command_object_id=?,command_args=?";
	$contactnotificationmethod_start_sth = $dbh->prepare($contactnotificationmethod_start_query);
	my $contactnotificationmethod_end_query = "INSERT INTO nagios_contactnotificationmethods (instance_id,contactnotification_id,start_time,
		start_time_usec,end_time,end_time_usec,command_object_id,command_args) VALUES (?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,contactnotification_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,
		end_time=FROM_UNIXTIME(?),end_time_usec=?,command_object_id=?,command_args=?";
	$contactnotificationmethod_end_sth = $dbh->prepare($contactnotificationmethod_end_query);
	my $servicecheck_processed_query = "INSERT INTO nagios_servicechecks (instance_id,service_object_id,check_type,current_check_attempt,
		max_check_attempts,state,state_type,start_time,start_time_usec,end_time,end_time_usec,timeout,early_timeout,execution_time,
		latency,return_code,output,perfdata,command_object_id,command_args,command_line) VALUES
		(?,?,?,?,?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,?)";
	$servicecheck_processed_sth = $dbh->prepare($servicecheck_processed_query);
	my $hostcheck_processed_query = "INSERT INTO nagios_hostchecks (instance_id,host_object_id,check_type,is_raw_check,current_check_attempt,
		max_check_attempts,state,state_type,start_time,start_time_usec,end_time,end_time_usec,timeout,early_timeout,execution_time,
		latency,return_code,output,perfdata,command_object_id,command_args,command_line) VALUES
		(?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,?)";
	$hostcheck_processed_sth = $dbh->prepare($hostcheck_processed_query);
	my $comment_add_query = "INSERT INTO nagios_comments (instance_id,comment_type,entry_type,object_id,comment_time,internal_comment_id,
		author_name,comment_data,is_persistent,comment_source,expires,expiration_time,entry_time,entry_time_usec) VALUES
		(?,?,?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?) ON DUPLICATE KEY UPDATE
		instance_id=?,comment_type=?,entry_type=?,object_id=?,comment_time=FROM_UNIXTIME(?),internal_comment_id=?,author_name=?,comment_data=?,
		is_persistent=?,comment_source=?,expires=?,expiration_time=?";
	$comment_add_sth = $dbh->prepare($comment_add_query);
	my $comment_history_query = "INSERT INTO nagios_commenthistory (instance_id,comment_type,entry_type,object_id,comment_time,internal_comment_id,
		author_name,comment_data,is_persistent,comment_source,expires,expiration_time,entry_time,entry_time_usec) VALUES
		(?,?,?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?) ON DUPLICATE KEY UPDATE
		instance_id=?,comment_type=?,entry_type=?,object_id=?,comment_time=FROM_UNIXTIME(?),internal_comment_id=?,author_name=?,comment_data=?,
		is_persistent=?,comment_source=?,expires=?,expiration_time=?";
	$comment_history_sth = $dbh->prepare($comment_history_query);
	my $comment_delete_query = "DELETE FROM nagios_comments WHERE instance_id=? AND comment_time=? AND internal_comment_id=?";
	$comment_delete_sth = $dbh->prepare($comment_delete_query);
	my $comment_delete_history_query = "UPDATE nagios_commenthistory SET deletion_time=?,deletion_time_usec=?
		 WHERE instance_id=? AND comment_time=? AND internal_comment_id=?";
	$comment_delete_history_sth = $dbh->prepare($comment_delete_history_query);
	my $flapping_start_query = "INSERT INTO nagios_flappinghistory (instance_id,event_time,event_time_usec,event_type,reason_type,flapping_type,object_id,
		percent_state_change,low_threshold,high_threshold,comment_time,internal_comment_id) VALUES
		(?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),?)";
	$flapping_start_sth = $dbh->prepare($flapping_start_query);
	my $flapping_end_query = "INSERT INTO nagios_flappinghistory (instance_id,event_time,event_time_usec,event_type,reason_type,flapping_type,object_id,
		percent_state_change,low_threshold,high_threshold,comment_time,internal_comment_id) VALUES
		(?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),?)";
	$flapping_end_sth = $dbh->prepare($flapping_end_query);
	my $downtime_add_query = "INSERT INTO nagios_scheduleddowntime (instance_id,downtime_type,object_id,entry_time,author_name,comment_data,
		internal_downtime_id,triggered_by_id,is_fixed,duration,scheduled_start_time,scheduled_end_time) VALUES
		(?,?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?)) ON DUPLICATE KEY UPDATE
		instance_id=?,downtime_type=?,object_id=?,entry_time=FROM_UNIXTIME(?),author_name=?,comment_data=?,internal_downtime_id=?,
		triggered_by_id=?,is_fixed=?,duration=?,scheduled_start_time=FROM_UNIXTIME(?),scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_add_sth = $dbh->prepare($downtime_add_query);
	my $downtime_history_insert_query = "INSERT INTO nagios_downtimehistory (instance_id,downtime_type,object_id,entry_time,author_name,comment_data,
		internal_downtime_id,triggered_by_id,is_fixed,duration,scheduled_start_time,scheduled_end_time) VALUES
		(?,?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?)) ON DUPLICATE KEY UPDATE
		instance_id=?,downtime_type=?,object_id=?,entry_time=FROM_UNIXTIME(?),author_name=?,comment_data=?,internal_downtime_id=?,
		triggered_by_id=?,is_fixed=?,duration=?,scheduled_start_time=FROM_UNIXTIME(?),scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_history_insert_sth = $dbh->prepare($downtime_history_insert_query);
	my $downtime_delete_query = "DELETE FROM nagios_scheduleddowntime WHERE instance_id=? AND downtime_type=? AND object_id=?
		AND entry_time=FROM_UNIXTIME(?) AND scheduled_start_time=FROM_UNIXTIME(?) AND scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_delete_sth = $dbh->prepare($downtime_delete_query);
	my $downtime_history_update_query = "UPDATE nagios_downtimehistory SET actual_end_time=FROM_UNIXTIME(?),actual_end_time_usec=?,was_cancelled=1
		WHERE instance_id=? AND downtime_type=? AND object_id=? AND entry_time=FROM_UNIXTIME(?) AND scheduled_start_time=FROM_UNIXTIME(?)
		AND scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_history_update_sth = $dbh->prepare($downtime_history_update_query);
	my $downtime_start_query = "UPDATE nagios_scheduleddowntime SET actual_start_time=FROM_UNIXTIME(?),actual_start_time_usec=?,was_started=?
		WHERE instance_id=? AND downtime_type=? AND object_id=? AND entry_time=FROM_UNIXTIME(?) AND scheduled_start_time=FROM_UNIXTIME(?)
		AND scheduled_end_time=FROM_UNIXTIME(?) AND was_started=?";
	$downtime_start_sth = $dbh->prepare($downtime_start_query);
	my $downtime_history_start_query = "UPDATE nagios_downtimehistory SET actual_start_time=FROM_UNIXTIME(?),actual_start_time_usec=?,was_started=?
		 WHERE instance_id=? AND downtime_type=? AND object_id=? AND entry_time=FROM_UNIXTIME(?) AND scheduled_start_time=FROM_UNIXTIME(?)
		 AND scheduled_end_time=FROM_UNIXTIME(?) AND was_started=?";
	$downtime_history_start_sth = $dbh->prepare($downtime_history_start_query);
	my $downtime_stop_query = "DELETE FROM nagios_scheduleddowntime WHERE instance_id=? AND downtime_type=? AND object_id=? AND entry_time=FROM_UNIXTIME(?)
		AND scheduled_start_time=FROM_UNIXTIME(?) AND scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_stop_sth = $dbh->prepare($downtime_stop_query);
	my $downtime_history_stop_query = "UPDATE nagios_downtimehistory SET actual_end_time=FROM_UNIXTIME(?),actual_end_time_usec=?,was_cancelled=?
		WHERE instance_id=? AND downtime_type=? AND object_id=? AND entry_time=FROM_UNIXTIME(?) AND scheduled_start_time=FROM_UNIXTIME(?)
		AND scheduled_end_time=FROM_UNIXTIME(?)";
	$downtime_history_stop_query = $dbh->prepare($downtime_history_stop_query);
	my $programstatus_update_query = "INSERT INTO nagios_programstatus (instance_id,status_update_time,program_start_time,is_currently_running,process_id,
		daemon_mode,last_command_check,last_log_rotation,notifications_enabled,active_service_checks_enabled,passive_service_checks_enabled,
		active_host_checks_enabled,passive_host_checks_enabled,event_handlers_enabled,flap_detection_enabled,failure_prediction_enabled,
		process_performance_data,obsess_over_hosts,obsess_over_services,modified_host_attributes,modified_service_attributes,
		global_host_event_handler,global_service_event_handler) VALUES
		(?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,status_update_time=FROM_UNIXTIME(?),program_start_time=FROM_UNIXTIME(?),is_currently_running=?,process_id=?,daemon_mode=?,
		last_command_check=FROM_UNIXTIME(?),last_log_rotation=FROM_UNIXTIME(?),notifications_enabled=?,active_service_checks_enabled=?,
		passive_service_checks_enabled=?,active_host_checks_enabled=?,passive_host_checks_enabled=?,event_handlers_enabled=?,
		flap_detection_enabled=?,failure_prediction_enabled=?,process_performance_data=?,obsess_over_hosts=?,obsess_over_services=?,
		modified_host_attributes=?,modified_service_attributes=?,global_host_event_handler=?,global_service_event_handler=?";
	$programstatus_update_sth = $dbh->prepare($programstatus_update_query);
	my $hoststatus_update_query = "INSERT INTO nagios_hoststatus (instance_id,host_object_id,status_update_time,output,perfdata,current_state,
		has_been_checked,should_be_scheduled,current_check_attempt,max_check_attempts,last_check,next_check,check_type,last_state_change,
		last_hard_state_change,last_hard_state,last_time_up,last_time_down,last_time_unreachable,state_type,last_notification,
		next_notification,no_more_notifications,notifications_enabled,problem_has_been_acknowledged,acknowledgement_type,current_notification_number,
		passive_checks_enabled,active_checks_enabled,event_handler_enabled,flap_detection_enabled,is_flapping,percent_state_change,latency,execution_time,
		failure_prediction_enabled,process_performance_data,obsess_over_host,modified_host_attributes,event_handler,check_command,
		normal_check_interval,retry_check_interval,check_timeperiod_object_id,scheduled_downtime_depth) VALUES
		(?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),
		FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,host_object_id=?,status_update_time=FROM_UNIXTIME(?),output=?,perfdata=?,current_state=?,
		has_been_checked=?,should_be_scheduled=?,current_check_attempt=?,max_check_attempts=?,last_check=FROM_UNIXTIME(?),
		next_check=FROM_UNIXTIME(?),check_type=?,last_state_change=FROM_UNIXTIME(?),last_hard_state_change=FROM_UNIXTIME(?),last_hard_state=?,
		last_time_up=FROM_UNIXTIME(?),last_time_down=FROM_UNIXTIME(?),last_time_unreachable=FROM_UNIXTIME(?),state_type=?,
		last_notification=FROM_UNIXTIME(?),next_notification=FROM_UNIXTIME(?),no_more_notifications=?,notifications_enabled=?,
		problem_has_been_acknowledged=?,acknowledgement_type=?,current_notification_number=?,passive_checks_enabled=?,active_checks_enabled=?,
		event_handler_enabled=?,flap_detection_enabled=?,is_flapping=?,percent_state_change=?,latency=?,execution_time=?,failure_prediction_enabled=?,
		process_performance_data=?,obsess_over_host=?,modified_host_attributes=?,event_handler=?,check_command=?,normal_check_interval=?,
		retry_check_interval=?,check_timeperiod_object_id=?,scheduled_downtime_depth=?";
	$hoststatus_update_sth = $dbh->prepare($hoststatus_update_query);
	my $servicestatus_update_query = "INSERT INTO nagios_servicestatus (instance_id,service_object_id,status_update_time,output,perfdata,current_state,
		has_been_checked,should_be_scheduled,current_check_attempt,max_check_attempts,last_check,next_check,check_type,last_state_change,
		last_hard_state_change,last_hard_state,last_time_ok,last_time_warning,last_time_unknown,last_time_critical,state_type,last_notification,
		next_notification,no_more_notifications,notifications_enabled,problem_Has_been_acknowledged,acknowledgement_type,
		current_notification_number,passive_checks_enabled,active_checks_enabled,event_handler_enabled,flap_detection_enabled,
		is_flapping,percent_state_change,latency,execution_time,failure_prediction_enabled,process_performance_data,obsess_over_service,
		modified_service_attributes,event_handler,check_command,normal_check_interval,retry_check_interval,check_timeperiod_object_id,
		scheduled_downtime_depth) VALUES
		(?,?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,
		FROM_UNIXTIME(?),FROM_UNIXTIME(?),FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),
		?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,service_object_id=?,status_update_time=FROM_UNIXTIME(?),output=?,perfdata=?,current_state=?,has_been_checked=?,
		should_be_scheduled=?,current_check_attempt=?,max_check_attempts=?,last_check=FROM_UNIXTIME(?),next_check=FROM_UNIXTIME(?),check_type=?,
		last_state_change=FROM_UNIXTIME(?),last_hard_state_change=FROM_UNIXTIME(?),last_hard_state=?,last_time_ok=FROM_UNIXTIME(?),
		last_time_warning=FROM_UNIXTIME(?),last_time_unknown=FROM_UNIXTIME(?),last_time_critical=FROM_UNIXTIME(?),state_type=?,
		last_notification=FROM_UNIXTIME(?),next_notification=FROM_UNIXTIME(?),no_more_notifications=?,notifications_enabled=?,
		problem_Has_been_acknowledged=?,acknowledgement_type=?,current_notification_number=?,passive_checks_enabled=?,active_checks_enabled=?,
		event_handler_enabled=?,flap_detection_enabled=?,is_flapping=?,percent_state_change=?,latency=?,execution_time=?,
		failure_prediction_enabled=?,process_performance_data=?,obsess_over_service=?,modified_service_attributes=?,event_handler=?,check_command=?,
		normal_check_interval=?,retry_check_interval=?,check_timeperiod_object_id=?,scheduled_downtime_depth=?";
	$servicestatus_update_sth = $dbh->prepare($servicestatus_update_query);
	my $contactstatus_update_query = "INSERT INTO nagios_contactstatus (instance_id,contact_object_id,status_update_time,host_notifications_enabled,
		service_notifications_enabled,last_host_notification,last_service_notification,modified_attributes,modified_host_attributes,
		modified_service_attributes) VALUES (?,?,FROM_UNIXTIME(?),?,?,FROM_UNIXTIME(?),FROM_UNIXTIME(?),?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,contact_object_id=?,status_update_time=FROM_UNIXTIME(?),host_notifications_enabled=?,
		service_notifications_enabled=?,last_host_notification=FROM_UNIXTIME(?),last_service_notification=FROM_UNIXTIME(?),modified_attributes=?,
		modified_host_attributes=?,modified_service_attributes=?";
	$contactstatus_update_sth = $dbh->prepare($contactstatus_update_query);
	my $acknowledgement_add_query = "INSERT INTO nagios_acknowledgements (instance_id,entry_time,entry_time_usec,acknowledgement_type,object_id,
		state,author_name,comment_data,is_sticky,persistent_comment,notify_contacts) VALUES
		(?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,entry_time=FROM_UNIXTIME(?),entry_time_usec=?,acknowledgement_type=?,object_id=?,state=?,author_name=?,comment_data=?,
		is_sticky=?,persistent_comment=?,notify_contacts=?";
	$acknowledgement_add_sth = $dbh->prepare($acknowledgement_add_query);
	my $statechange_query = "INSERT INTO nagios_statehistory (instance_id,state_time,state_time_usec,object_id,state_change,state,state_type,
		current_check_attempt,max_check_attempts,last_state,last_hard_state,output) VALUES (?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?)";
	$statechange_sth = $dbh->prepare($statechange_query);
	my $nagios_objects_activate_query = "UPDATE nagios_objects SET is_active='1' WHERE instance_id=? AND objecttype_id=? AND object_id=?";
	$nagios_objects_activate_sth = $dbh->prepare($nagios_objects_activate_query);
	my $timedevent_add_query = "INSERT INTO nagios_timedevents (instance_id,event_type,queued_time,queued_time_usec,scheduled_time,
		recurring_event,object_id) VALUES (?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?) ON DUPLICATE KEY UPDATE instance_id=?,
		event_type=?,queued_time=FROM_UNIXTIME(?),queued_time_usec=?,scheduled_time=FROM_UNIXTIME(?),recurring_event=?,object_id=?";
	$timedevent_add_sth = $dbh->prepare($timedevent_add_query);
	my $timedevent_remove_query = "UPDATE nagios_timedevents SET deletion_time=?,deletion_time_usec=? WHERE instance_id=? AND event_type=?
		AND scheduled_time=? AND recurring_event=? AND object_id=?";
	$timedevent_remove_sth = $dbh->prepare($timedevent_remove_query);
	my $timedevent_execute_query = "UPDATE nagios_timedevents SET event_time=?,event_time_usec=? WHERE instance_id=? AND object_id=? AND
		event_type=? AND scheduled_time=?";
	$timedevent_execute_sth = $dbh->prepare($timedevent_execute_query);
	my $timedeventqueue_add_query = "INSERT INTO nagios_timedeventqueue (instance_id,event_type,queued_time,queued_time_usec,scheduled_time,
		recurring_event,object_id) VALUES (?,?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?) ON DUPLICATE KEY UPDATE instance_id=?,
		event_type=?,queued_time=FROM_UNIXTIME(?),queued_time_usec=?,scheduled_time=FROM_UNIXTIME(?),recurring_event=?,object_id=?";
	$timedeventqueue_add_sth = $dbh->prepare($timedeventqueue_add_query);
	my $timedeventqueue_remove_query = "DELETE FROM nagios_timedeventqueue WHERE instance_id=? AND event_type=? AND scheduled_time=?
		AND recurring_event=? AND object_id=?";
	$timedeventqueue_remove_sth = $dbh->prepare($timedeventqueue_remove_query);
	my $configfiles_query = "INSERT INTO nagios_configfiles (instance_id,configfile_type,configfile_path) VALUES (?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,configfile_type=?,configfile_path=?";
	$configfiles_sth = $dbh->prepare($configfiles_query);
	my $configfilevariables_query = "INSERT INTO nagios_configfilevariables (instance_id,configfile_id,varname,varvalue) VALUES (?,?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,configfile_id=?,varname=?,varvalue=?";
	$configfilevariables_sth = $dbh->prepare($configfilevariables_query);
	my $runtimevariables_query = "INSERT INTO nagios_runtimevariables (instance_id,varname,varvalue) VALUES (?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,varname=?,varvalue=?";
	$runtimevariables_sth = $dbh->prepare($runtimevariables_query);
	my $hostdefinition_host_query = "INSERT INTO nagios_hosts (instance_id,config_type,host_object_id,alias,display_name,address,check_command_object_id,
		check_command_args,eventhandler_command_object_id,eventhandler_command_args,check_timeperiod_object_id,notification_timeperiod_object_id,
		failure_prediction_options,check_interval,retry_interval,max_check_attempts,first_notification_delay,notification_interval,notify_on_down,
		notify_on_unreachable,notify_on_recovery,notify_on_flapping,notify_on_downtime,stalk_on_up,stalk_on_down,stalk_on_unreachable,
		flap_detection_enabled,flap_detection_on_up,flap_detection_on_down,flap_detection_on_unreachable,low_flap_threshold,high_flap_threshold,
		process_performance_data,freshness_checks_enabled,freshness_threshold,passive_checks_enabled,event_handler_enabled,active_checks_enabled,
		retain_status_information,retain_nonstatus_information,notifications_enabled,obsess_over_host,failure_prediction_enabled,notes,notes_url,
		action_url,icon_image,icon_image_alt,vrml_image,statusmap_image,have_2d_coords,x_2d,y_2d,have_3d_coords,x_3d,y_3d,z_3d) VALUES
		(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,config_type=?,host_object_id=?,alias=?,display_name=?,address=?,check_command_object_id=?,check_command_args=?,
		eventhandler_command_object_id=?,eventhandler_command_args=?,check_timeperiod_object_id=?,notification_timeperiod_object_id=?,
		failure_prediction_options=?,check_interval=?,retry_interval=?,max_check_attempts=?,first_notification_delay=?,notification_interval=?,
		notify_on_down=?,notify_on_unreachable=?,notify_on_recovery=?,notify_on_flapping=?,notify_on_downtime=?,stalk_on_up=?,stalk_on_down=?,
		stalk_on_unreachable=?,flap_detection_enabled=?,flap_detection_on_up=?,flap_detection_on_down=?,flap_detection_on_unreachable=?,
		low_flap_threshold=?,high_flap_threshold=?,process_performance_data=?,freshness_checks_enabled=?,freshness_threshold=?,passive_checks_enabled=?,
		event_handler_enabled=?,active_checks_enabled=?,retain_status_information=?,retain_nonstatus_information=?,notifications_enabled=?,
		obsess_over_host=?,failure_prediction_enabled=?,notes=?,notes_url=?,action_url=?,icon_image=?,icon_image_alt=?,vrml_image=?,statusmap_image=?,
		have_2d_coords=?,x_2d=?,y_2d=?,have_3d_coords=?,x_3d=?,y_3d=?,z_3d=?";
	$hostdefinition_host_sth = $dbh->prepare($hostdefinition_host_query);
	my $hostdefinition_contactgroups_query = "INSERT INTO nagios_host_contactgroups (instance_id,host_id,contactgroup_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,host_id=?,contactgroup_object_id=?";
	$hostdefinition_contactgroups_sth = $dbh->prepare($hostdefinition_contactgroups_query);
	my $hostdefinition_contact_query = "INSERT INTO nagios_host_contacts (instance_id,host_id,contact_object_id) VALUES (?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,host_id=?,contact_object_id=?";
	$hostdefinition_contact_sth = $dbh->prepare($hostdefinition_contact_query);
	my $hostdefinition_parenthost_query = "INSERT INTO nagios_host_parenthosts (instance_id,host_id,parent_host_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,host_id=?,parent_host_object_id=?";
	$hostdefinition_parenthost_sth = $dbh->prepare($hostdefinition_parenthost_query);
	my $hostgroupdefinition_hostgroup_query = "INSERT INTO nagios_hostgroups (instance_id,config_type,hostgroup_object_id,alias)
		VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,hostgroup_object_id=?,alias=?";
	$hostgroupdefinition_hostgroup_sth = $dbh->prepare($hostgroupdefinition_hostgroup_query);
	my $hostgroupdefinition_members_query = "INSERT INTO nagios_hostgroup_members (instance_id,hostgroup_id,host_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,hostgroup_id=?,host_object_id=?";
	$hostgroupdefinition_members_sth = $dbh->prepare($hostgroupdefinition_members_query);
	my $servicedefinition_service_query = "INSERT INTO nagios_services (instance_id,config_type,host_object_id,service_object_id,display_name,
		check_command_object_id,check_command_args,eventhandler_command_object_id,eventhandler_command_args,check_timeperiod_object_id,
		notification_timeperiod_object_id,failure_prediction_options,check_interval,retry_interval,max_check_attempts,first_notification_delay,
		notification_interval,notify_on_warning,notify_on_unknown,notify_on_critical,notify_on_recovery,notify_on_flapping,notify_on_downtime,
		stalk_on_ok,stalk_on_warning,stalk_on_unknown,stalk_on_critical,is_volatile,flap_detection_enabled,flap_detection_on_ok,flap_detection_on_warning,
		flap_detection_on_unknown,flap_detection_on_critical,low_flap_threshold,high_flap_threshold,process_performance_data,freshness_checks_enabled,
		freshness_threshold,passive_checks_enabled,event_handler_enabled,active_checks_enabled,retain_status_information,retain_nonstatus_information,
		notifications_enabled,obsess_over_service,failure_prediction_enabled,notes,notes_url,action_url,icon_image,icon_image_alt) VALUES
		(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE
		instance_id=?,config_type=?,host_object_id=?,service_object_id=?,display_name=?,check_command_object_id=?,check_command_args=?,
		eventhandler_command_object_id=?,eventhandler_command_args=?,check_timeperiod_object_id=?,notification_timeperiod_object_id=?,
		failure_prediction_options=?,check_interval=?,retry_interval=?,max_check_attempts=?,first_notification_delay=?,notification_interval=?,
		notify_on_warning=?,notify_on_unknown=?,notify_on_critical=?,notify_on_recovery=?,notify_on_flapping=?,notify_on_downtime=?,stalk_on_ok=?,
		stalk_on_warning=?,stalk_on_unknown=?,stalk_on_critical=?,is_volatile=?,flap_detection_enabled=?,flap_detection_on_ok=?,flap_detection_on_warning=?,
		flap_detection_on_unknown=?,flap_detection_on_critical=?,low_flap_threshold=?,high_flap_threshold=?,process_performance_data=?,
		freshness_checks_enabled=?,freshness_threshold=?,passive_checks_enabled=?,event_handler_enabled=?,active_checks_enabled=?,
		retain_status_information=?,retain_nonstatus_information=?,notifications_enabled=?,obsess_over_service=?,failure_prediction_enabled=?,notes=?,
		notes_url=?,action_url=?,icon_image=?,icon_image_alt=?";
	$servicedefinition_service_sth = $dbh->prepare($servicedefinition_service_query);
	my $servicedefinition_contactgroups_query = "INSERT INTO nagios_service_contactgroups (instance_id,service_id,contactgroup_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,service_id=?,contactgroup_object_id=?";
	$servicedefinition_contactgroups_sth = $dbh->prepare($servicedefinition_contactgroups_query);
	my $servicedefinition_contacts_query = "INSERT INTO nagios_service_contacts (instance_id,service_id,contact_object_id) VALUES (?,?,?) 
		ON DUPLICATE KEY UPDATE instance_id=?,service_id=?,contact_object_id=?";
	$servicedefinition_contacts_sth = $dbh->prepare($servicedefinition_contacts_query);
	my $servicegroupdefinition_servicegroup_query = "INSERT INTO nagios_servicegroups (instance_id,config_type,servicegroup_object_id,alias) VALUES
		(?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,servicegroup_object_id=?,alias=?";
	$servicegroupdefinition_servicegroup_sth = $dbh->prepare($servicegroupdefinition_servicegroup_query);
	my $servicegroupdefinition_members_query = "INSERT INTO nagios_servicegroup_members (instance_id,servicegroup_id,service_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,servicegroup_id=?,service_object_id=?";
	$servicegroupdefinition_members_sth = $dbh->prepare($servicegroupdefinition_members_query);
	my $hostdependencydefinition_host_query = "INSERT INTO nagios_hostdependencies (instance_id,config_type,host_object_id,dependent_host_object_id,
		dependency_type,inherits_parent,timeperiod_object_id,fail_on_up,fail_on_down,fail_on_unreachable) VALUES (?,?,?,?,?,?,?,?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,host_object_id=?,dependent_host_object_id=?,dependency_type=?,inherits_parent=?,
		timeperiod_object_id=?,fail_on_up=?,fail_on_down=?,fail_on_unreachable=?";
	$hostdependencydefinition_host_sth = $dbh->prepare($hostdependencydefinition_host_query);
	my $servicedependencydefinition_service_query = "INSERT INTO nagios_servicedependencies (instance_id,config_type,service_object_id,
		dependent_service_object_id,dependency_type,inherits_parent,timeperiod_object_id,fail_on_ok,fail_on_warning,fail_on_unknown,fail_on_critical)
		VALUES (?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,service_object_id=?,dependent_service_object_id=?,
		dependency_type=?,inherits_parent=?,timeperiod_object_id=?,fail_on_ok=?,fail_on_warning=?,fail_on_unknown=?,fail_on_critical=?";
	$servicedependencydefinition_service_sth = $dbh->prepare($servicedependencydefinition_service_query);
	my $commanddefinition_command_query = "INSERT INTO nagios_commands (instance_id,config_type,object_id,command_line) VALUES (?,?,?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,object_id=?,command_line=?";
	$commanddefinition_command_sth = $dbh->prepare($commanddefinition_command_query);
	my $timeperioddefinition_timeperiod_query = "INSERT INTO nagios_timeperiods (instance_id,config_type,timeperiod_object_id,alias) VALUES
		(?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,timeperiod_object_Id=?,alias=?";
	$timeperioddefinition_timeperiod_sth = $dbh->prepare($timeperioddefinition_timeperiod_query);
	my $timeperioddefinition_timeranges_query = "INSERT INTO nagios_timeperiod_timeranges (instance_id,timeperiod_id,day,start_sec,end_sec)
		VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,timeperiod_id=?,day=?,start_sec=?,end_sec=?";
	$timeperioddefinition_timeranges_sth = $dbh->prepare($timeperioddefinition_timeranges_query);
	my $contactdefinition_contact_query = "INSERT INTO nagios_contacts (instance_id,config_type,contact_object_id,alias,email_address,pager_address,
		host_timeperiod_object_id,service_timeperiod_object_id,host_notifications_enabled,service_notifications_enabled,can_submit_commands,
		notify_service_recovery,notify_service_warning,notify_service_unknown,notify_service_critical,notify_service_flapping,notify_service_downtime,
		notify_host_recovery,notify_host_down,notify_host_unreachable,notify_host_flapping,notify_host_downtime) VALUES
		(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,contact_object_id=?,alias=?,email_address=?,
		pager_address=?,host_timeperiod_object_id=?,service_timeperiod_object_id=?,host_notifications_enabled=?,service_notifications_enabled=?,
		can_submit_commands=?,notify_service_recovery=?,notify_service_warning=?,notify_service_unknown=?,notify_service_critical=?,
		notify_service_flapping=?,notify_service_downtime=?,notify_host_recovery=?,notify_host_down=?,notify_host_unreachable=?,
		notify_host_flapping=?,notify_host_downtime=?";
	$contactdefinition_contact_sth = $dbh->prepare($contactdefinition_contact_query);
	my $contactdefinition_contactaddresses_query = "INSERT INTO nagios_contact_addresses (instance_id,contact_id,address_number,address) VALUES
		(?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,contact_id=?,address_number=?,address=?";
	$contactdefinition_contactaddresses_sth = $dbh->prepare($contactdefinition_contactaddresses_query);
	my $contactdefinition_notificationcommands_query = "INSERT INTO nagios_contact_notificationcommands (instance_id,contact_id,notification_type,
		command_object_id,command_args) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,contact_id=?,notification_type=?,
		command_object_id=?,command_args=?";
	$contactdefinition_notificationcommands_sth = $dbh->prepare($contactdefinition_notificationcommands_query);
	my $contactgroupdefinition_contactgroup_query = "INSERT INTO nagios_contactgroups (instance_id,config_type,contactgroup_object_id,alias)
		VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,contactgroup_object_id=?,alias=?";
	$contactgroupdefinition_contactgroup_sth = $dbh->prepare($contactgroupdefinition_contactgroup_query);
	my $contactgroupdefinition_members_query = "INSERT INTO nagios_contactgroup_members (instance_id,contactgroup_id,contact_object_id) VALUES
		(?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,contactgroup_id=?,contact_object_id=?";
	$contactgroupdefinition_members_sth = $dbh->prepare($contactgroupdefinition_members_query);
	my $hostescalation_host_query = "INSERT INTO nagios_hostescalations (instance_id,config_type,host_object_id,timeperiod_object_id,
		first_notification,last_notification,notification_interval,escalate_on_recovery,escalate_on_down,escalate_on_unreachable)
		VALUES (?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,host_object_id=?,timeperiod_object_id=?,
		first_notification=?,last_notification=?,notification_interval=?,escalate_on_recovery=?,escalate_on_down=?,
		escalate_on_unreachable=?";
	$hostescalation_host_sth = $dbh->prepare($hostescalation_host_query);
	my $hostescalation_contacts_query = "INSERT INTO nagios_hostescalation_contacts (instance_id,hostescalation_id,contact_object_id)
		VALUES (?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,hostescalation_id=?,contact_object_id=?";
	$hostescalation_contacts_sth = $dbh->prepare($hostescalation_contacts_query);
	my $hostescalation_contactgroups_query = "INSERT INTO nagios_hostescalation_contactgroups (instance_id,hostescalation_id,contactgroup_object_id)
		VALUES (?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,hostescalation_id=?,contactgroup_object_id=?";
	$hostescalation_contactgroups_sth = $dbh->prepare($hostescalation_contactgroups_query);
	my $serviceescalation_service_query = "INSERT INTO nagios_serviceescalations (instance_id,config_type,service_object_id,timeperiod_object_id,
		first_notification,last_notification,notification_interval,escalate_on_recovery,escalate_on_warning,escalate_on_unknown,
		escalate_on_critical) VALUES (?,?,?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,config_type=?,service_object_id=?,
		timeperiod_object_id=?,first_notification=?,last_notification=?,notification_interval=?,escalate_on_recovery=?,escalate_on_warning=?,
		escalate_on_unknown=?,escalate_on_critical=?";
	$serviceescalation_service_sth = $dbh->prepare($serviceescalation_service_query);
	my $serviceescalation_contacts_query = "INSERT INTO nagios_serviceescalation_contacts (instance_id,serviceescalation_id,contact_object_id)
		VALUES (?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,serviceescalation_id=?,contact_object_id=?";
	$serviceescalation_contacts_sth = $dbh->prepare($serviceescalation_contacts_query);
	my $serviceescalation_contactgroups_query = "INSERT INTO nagios_serviceescalation_contactgroups (instance_id,serviceescalation_id,contactgroup_object_id)
		VALUES (?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,serviceescalation_id=?,contactgroup_object_id=?";
	$serviceescalation_contactgroups_sth = $dbh->prepare($serviceescalation_contactgroups_query);
	my $log_data_query = "INSERT INTO nagios_logentries (instance_id,logentry_time,entry_time,entry_time_usec,logentry_type,logentry_data,realtime_data,
		inferred_data_extracted) VALUES (?,?,?,?,?,?,?,?)";
	$log_data_sth = $dbh->prepare($log_data_query);
	my $system_command_start_query = "INSERT INTO nagios_systemcommands (instance_id,start_time,start_time_usec,end_time,end_time_usec,command_line,
		timeout,early_timeout,execution_time,return_code,output) VALUES (?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,FROM_UNIXTIME(?),?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?,
		command_line=?,timeout=?,early_timeout=?,execution_time=FROM_UNIXTIME(?),return_code=?,output=?";
	$system_command_start_sth = $dbh->prepare($system_command_start_query);
	my $system_command_end_query = "INSERT INTO nagios_systemcommands (instance_id,start_time,start_time_usec,end_time,end_time_usec,command_line,
		timeout,early_timeout,execution_time,return_code,output) VALUES (?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,FROM_UNIXTIME(?),?,?)
		ON DUPLICATE KEY UPDATE instance_id=?,start_time=FROM_UNIXTIME(?),start_time_usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?,
		command_line=?,timeout=?,early_timeout=?,execution_time=FROM_UNIXTIME(?),return_code=?,output=?";
	$system_command_end_sth = $dbh->prepare($system_command_end_query);
	my $eventhandler_start_query = "INSERT INTO nagios_eventhandlers (instance_id,eventhandler_type,object_id,state,state_type,start_time,start_time_usec,
		end_time,end_time_usec,command_object_id,command_args,command_line,timeout,early_timeout,execution_time,return_code,output) VALUES
		(?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),?,?) ON DUPLICATE KEY UPDATE instance_id=?,
		start_time=FROM_UNIXTIME(?),start_time-usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?,command_object_id=?,command_args=?,
		command_line=?,timeout=?,early_timeout=?,execution_time=FROM_UNIXTIME(?),return_code=?,output=?";
	$eventhandler_start_sth = $dbh->prepare($eventhandler_start_query);
	my $eventhandler_end_query = "INSERT INTO nagios_eventhandlers (instance_id,eventhandler_type,object_id,state,state_type,start_time,start_time_usec,
		end_time,end_time_usec,command_object_id,command_args,command_line,timeout,early_timeout,execution_time,return_code,output) VALUES
		(?,FROM_UNIXTIME(?),?,FROM_UNIXTIME(?),?,?,?,?,?,?,?,?,?,?,FROM_UNIXTIME(?),?,?) ON DUPLICATE KEY UPDATE instance_id=?,
		start_time=FROM_UNIXTIME(?),start_time-usec=?,end_time=FROM_UNIXTIME(?),end_time_usec=?,command_object_id=?,command_args=?,
		command_line=?,timeout=?,early_timeout=?,execution_time=FROM_UNIXTIME(?),return_code=?,output=?";
	$eventhandler_end_sth = $dbh->prepare($eventhandler_end_query);
	my $externalcommand_start_query = "INSERT INTO nagios_externalcommands (instance_id,entry_time,command_type,command_name,command_args) VALUES
		(?,FROM_UNIXTIME(?),?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,entry_time=FROM_UNIXTIME(?),command_type=?,command_name=?,command_args=?";
	$externalcommand_start_sth = $dbh->prepare($externalcommand_start_query);
	my $externalcommand_end_query = "INSERT INTO nagios_externalcommands (instance_id,entry_time,command_type,command_name,command_args) VALUES
		(?,FROM_UNIXTIME(?),?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,entry_time=FROM_UNIXTIME(?),command_type=?,command_name=?,command_args=?";
	$externalcommand_end_sth = $dbh->prepare($externalcommand_end_query);
	my $customvariable_status_query = "INSERT INTO nagios_customvariablestatus (instance_id,object_id,status_update_time,has_been_modified,varname,varvalue)
		VALUES (?,?,FROM_UNIXTIME(?),?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,object_id=?,status_update_time=FROM_UNIXTIME(?),
		has_been_modified=?,varname=?,varvalue=?";
	$customvariable_status_sth = $dbh->prepare($customvariable_status_query);
	my $customvariables_query = "INSERT INTO nagios_customvariables (instance_id,object_id,config_type,has_been_modified,varname,varvalue)
		VALUES (?,?,?,?,?,?) ON DUPLICATE KEY UPDATE instance_id=?,object_id=?,config_type=?,
		has_been_modified=?,varname=?,varvalue=?";
	$customvariables_sth = $dbh->prepare($customvariables_query);
	return;
}

#########################################################################################################################
#
# Event subroutines.
#
# Event_types as described by the NDOUtils source code.
#
# 100: process_start
# 101: process_daemonize
# 102: process_restart
# 103: process_shutdown
# 104: process_prelaunch
# 105: process_eventloopstart
# 106: process_eventloopend
#
##########
# notes:
#	after a 104 the db is cleaned out.
#	after a 101 a number of tables are populated.
#		these should be populate based on ndo_id so no specific code is needed here.
#	after a 105 another set of tables are populated.

# types 10X series
sub process_event () {
	$nthash = shift;
	# update nagios_processevents.
	# split event time into normal and usec part.
	my ($event_time,$event_time_usec) = split(/\./, $nthash->{4});
	$process_event_sth->execute($instance_id,$nthash->{1},$event_time,$event_time_usec,$nthash->{102},$nthash->{105},$nthash->{107},$nthash->{104});
	return;
}

sub process_shutdown () {
	$nthash = shift;
	# first update processevents table.
	&process_event($nthash); # not sure this will work.....
	# next update programstatus to include our shutdown/end time.
	my ($event_time,$event_time_usec) = split(/\./, $nthash->{4});
	$process_shutdown_sth->execute($event_time,'0',$instance_id);
	return;
}

sub process_prelaunch () {
	$nthash = shift;
	# first update nagios_processevents table.
	&process_event($nthash); # not sure this will work.
	# next clean out he dbtables.
	my @dbtables = ("nagios_programstatus","nagios_contactstatus","nagios_timedeventqueue",
		"nagios_comments","nagios_runtimevariables","nagios_customvariablestatus","nagios_configfiles",
		"nagios_configfilevariables","nagios_customvariables","nagios_commands","nagios_timeperiods",
		"nagios_timeperiod_timeranges","nagios_contactgroups","nagios_contactgroup_members","nagios_hostgroups",
		"nagios_hostgroup_members","nagios_servicegroups","nagios_servicegroup_members","nagios_hostescalations",
		"nagios_hostescalation_contacts","nagios_serviceescalations","nagios_serviceescalation_contacts",
		"nagios_hostdependencies","nagios_servicedependencies","nagios_contacts","nagios_contact_addresses",
		"nagios_contact_notificationcommands","nagios_hosts","nagios_host_parenthosts","nagios_host_contacts",
		"nagios_services","nagios_service_contacts","nagios_service_contactgroups","nagios_host_contactgroups",
		"nagios_hostescalation_contactgroups","nagios_serviceescalation_contactgroups");
	# delete all entries in dbtables for our instance_id.
	foreach my $dbtable (@dbtables) {
		my $delete_objects_query = "DELETE FROM $dbtable WHERE instance_id=$instance_id";
		my $delete_objects_sth = $dbh->prepare($delete_objects_query);
		$delete_objects_sth->execute();
	}
	# update nagios_objects tables so everything is de-activated.
	my $deacquery = "UPDATE nagios_objects SET is_active='0' WHERE instance_id=$instance_id";
	$sth = $dbh->prepare($deacquery);
	$sth->execute();
	return;
}
# End of 10X series

############################################################################################################
#
# 200: timedevent_add
# 201: timedevent_remove
# 202: timedevent_execute
# 203: timedevent_delay (not implemented)
# 204: timedevent_skip (not implemented)
# 205: timedevent_sleep
#
###########
# notes:
#	None of these events have been seen yet.

# types 20X series
sub timedevent_add () {
	$nthash = shift;
	my ($queued_time,$queued_time_usec) = split(/\./,$nthash->{4});
	my $event_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$event_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} elsif (defined($nthash->{53})) {
		$event_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	} else {
		$event_object_id = '';
	}
	$timedevent_add_sth->execute($instance_id,$nthash->{41},$queued_time,$queued_time_usec,$nthash->{111},
		$nthash->{108},$event_object_id,$instance_id,$nthash->{41},$queued_time,$queued_time_usec,$nthash->{111},
		$nthash->{108},$event_object_id);
	$timedeventqueue_add_sth->execute($instance_id,$nthash->{41},$queued_time,$queued_time_usec,$nthash->{111},
		$nthash->{108},$event_object_id,$instance_id,$nthash->{41},$queued_time,$queued_time_usec,$nthash->{111},
		$nthash->{108},$event_object_id);
	return;
}

sub timedevent_remove () {
	$nthash = shift;
	my ($deletion_time,$deletion_time_usec) = split(/\./,$nthash->{4});
	my $event_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$event_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} elsif (defined($nthash->{53})) {
		$event_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	} else {
		$event_object_id = '';
	}
	$timedevent_remove_sth->execute($deletion_time,$deletion_time_usec,$instance_id,$nthash->{41},$nthash->{111},$nthash->{108},$event_object_id);
	$timedeventqueue_remove_sth->execute($instance_id,$nthash->{41},$nthash->{111},$nthash->{108},$event_object_id);
	return;
}

sub timedevent_execute () {
	$nthash = shift;
	my ($event_time,$event_time_usec) = split(/\./,$nthash->{4});
	my $event_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$event_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} elsif (defined($nthash->{53})) {
		$event_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	} else {
		$event_object_id = '';
	}
	$timedevent_execute_sth->execute($event_time,$event_time_usec,$instance_id,$event_object_id,$nthash->{41},$nthash->{111});
	$timedeventqueue_remove_sth->execute($instance_id,$nthash->{41},$nthash->{111},$nthash->{108},$event_object_id);
	return;
}

sub timedevent_sleep () {
	# according to DBHandler nothing is done here.
	return;
}

# End of 20X series

###############################################################################################################
#
# 300: log_data
# 301: log_rotation
#
###########
# notes:

# types 30X series
sub log_data () {
	$nthash = shift;
	my ($entry_time,$entry_time_usec) = split (/\./,$nthash->{4});
	my $realtime = 1;
	my $infered = 1;
	$log_data_sth->execute($instance_id,$nthash->{73},$entry_time,$entry_time_usec,$nthash->{74},"$nthash->{72}",$realtime,$infered);
	return;
}

# End of 30X series

#################################################################################################################
#
# 400: system_command_start
# 401: system_command_end
#
###########
# notes:

# types 40X series
sub system_commandi_start () {
	$nthash = shift;
	my ($start_time,$start_time_usec) = split(/\./,$nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./,$nthash->{33});
	$system_command_start_sth->execute($instance_id,$start_time,$start_time_usec,$end_time,$end_time_usec,"$nthash->{14}",$nthash->{123},
		$nthash->{32},$nthash->{42},$nthash->{110},"$nthash->{95}",$instance_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		"$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},$nthash->{110},"$nthash->{95}");
	return;
}

sub system_command_end () {
	$nthash = shift;
	my ($start_time,$start_time_usec) = split(/\./,$nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./,$nthash->{33});
	$system_command_end_sth->execute($instance_id,$start_time,$start_time_usec,$end_time,$end_time_usec,"$nthash->{14}",$nthash->{123},
		$nthash->{32},$nthash->{42},$nthash->{110},"$nthash->{95}",$instance_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		"$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},$nthash->{110},"$nthash->{95}");
	return;
}

# End of 40X series

#################################################################################################################
#
# 500: eventhandler_start
# 501: eventhandler_end
#
###########
# notes:
#       None of these events have been seen yet.

# types 50X series
sub eventhandler_start () {
	$nthash = shift;
	my ($start_time,$start_time_usec) = split(/\./,$nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./,$nthash->{33});
	my $handler_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$handler_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$handler_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	$eventhandler_start_sth->execute($instance_id,$nthash->{40},$handler_object_id,$nthash->{118},$nthash->{121},$start_time,$start_time_usec,
		$end_time,$end_time_usec,$command_object_id,"$nthash->{13}","$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},
		$nthash->{110},"$nthash->{95}",$instance_id,$nthash->{40},$handler_object_id,$nthash->{118},$nthash->{121},$start_time,$start_time_usec,
		$end_time,$end_time_usec,$command_object_id,"$nthash->{13}","$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},
		$nthash->{110},"$nthash->{95}");
	return;
}

sub eventhandler_end () {
	$nthash = shift;
	my ($start_time,$start_time_usec) = split(/\./,$nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./,$nthash->{33});
	my $handler_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$handler_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$handler_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	$eventhandler_end_sth->execute($instance_id,$nthash->{40},$object_id,$nthash->{118},$nthash->{121},$start_time,$start_time_usec,
		$end_time,$end_time_usec,$command_object_id,"$nthash->{13}","$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},
		$nthash->{110},"$nthash->{95}",$instance_id,$nthash->{40},$object_id,$nthash->{118},$nthash->{121},$start_time,$start_time_usec,
		$end_time,$end_time_usec,$command_object_id,"$nthash->{13}","$nthash->{14}",$nthash->{123},$nthash->{32},$nthash->{42},
		$nthash->{110},"$nthash->{95}");
	return;
}
# End of 50X series

#################################################################################################################
#
# 600: notification_start
# 601: notification_end
# 602: contactnotification_start
# 603: contactnotification_end
# 604: contactnotificationmethod_start
# 605: contactnotificationmethod_end
#
############
# notes:

# types 60X series
sub notification_start () {
	$nthash = shift;
	my $notif_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notif_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$notif_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
        my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
        my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$notification_start_sth->execute($instance_id,$nthash->{89},$nthash->{87},$nthash->{26},$start_time,$start_time_usec,$end_time,$end_time_usec,
		$notif_object_id,$nthash->{118},"$nthash->{95}",$nthash->{36},$nthash->{24},
		$instance_id,$nthash->{89},$nthash->{87},$nthash->{26},$start_time,$start_time_usec,$end_time,$end_time_usec,$notif_object_id,
		$nthash->{118},"$nthash->{95}",$nthash->{36},$nthash->{24});
	my $notification_id = &determine_insert_id($notification_start_sth);
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notifications->{ $nthash->{53} }->{ $nthash->{114} } = $notification_id;
	} else {
		my $notif_service = "NULL";
		$notifications->{ $nthash->{53} }->{ $notif_service } = $notification_id;
	}
	return;
}

sub notification_end () {
	$nthash = shift;
	my $notif_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notif_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$notif_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
        my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
        my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$notification_end_sth->execute($instance_id,$nthash->{89},$nthash->{87},$nthash->{26},$start_time,$start_time_usec,$end_time,$end_time_usec,
		$notif_object_id,$nthash->{118},"$nthash->{95}",$nthash->{36},$nthash->{24},
		$instance_id,$nthash->{89},$nthash->{87},$nthash->{26},$start_time,$start_time_usec,$end_time,$end_time_usec,$notif_object_id,
		$nthash->{118},"$nthash->{95}",$nthash->{36},$nthash->{24});
	my $notification_id = &determine_insert_id($notification_end_sth);
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notifications->{ $nthash->{53} }->{ $nthash->{114} } = $notification_id;
	} else {
		my $notif_service = "NULL";
		$notifications->{ $nthash->{53} }->{ $notif_service } = $notification_id;
	}
	return;
}

sub contactnotification_start () {
	$nthash = shift;
	my $contact_object_id = &determine_object_id($nthash->{134},"NULL",'contact');
	my $notification_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notification_id = $notifications->{ $nthash->{53} }->{ $nthash->{114} };
	} else {
		my $notif_service = "NULL";
		$notification_id = $notifications->{ $nthash->{53} }->{ $notif_service };
	}
	my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$contactnotification_start_sth->execute($instance_id,$notification_id,$contact_object_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$instance_id,$notification_id,$contact_object_id,$start_time,$start_time_usec,$end_time,$end_time_usec);
	my $contactnotification_id = &determine_insert_id($contactnotification_start_sth);
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$contactnotifications->{ $nthash->{53} }->{ $nthash->{114} }->{ $nthash->{134} } = $contactnotification_id;
	} else {
		my $notif_service = "NULL";
		$contactnotifications->{ $nthash->{53} }->{ $notif_service }->{ $nthash->{134} } = $contactnotification_id;
	}
	return;
}

sub contactnotification_end () {
	$nthash = shift;
	my $contact_object_id = &determine_object_id($nthash->{134},"NULL",'contact');
	my $notification_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$notification_id = $notifications->{ $nthash->{53} }->{ $nthash->{114} };
	} else {
		my $notif_service = "NULL";
		$notification_id = $notifications->{ $nthash->{53} }->{ $notif_service };
	}
	my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$contactnotification_end_sth->execute($instance_id,$notification_id,$contact_object_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$instance_id,$notification_id,$contact_object_id,$start_time,$start_time_usec,$end_time,$end_time_usec);
	my $contactnotification_id = &determine_insert_id($contactnotification_start_sth);
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$contactnotifications->{ $nthash->{53} }->{ $nthash->{114} }->{ $nthash->{134} } = $contactnotification_id;
	} else {
		my $notif_service = "NULL";
		$contactnotifications->{ $nthash->{53} }->{ $notif_service }->{ $nthash->{134} } = $contactnotification_id;
	}
	return;
}

sub contactnotificationmethod_start () {
	$nthash = shift;
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	my $contactnotification_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$contactnotification_id = $contactnotifications->{ $nthash->{53} }->{ $nthash->{114} }->{ $nthash->{134} };
	} else {
		my $notif_service = "NULL";
		$contactnotification_id = $contactnotifications->{ $nthash->{53} }->{ $notif_service }->{ $nthash->{134} };
	}
	my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$contactnotificationmethod_start_sth->execute($instance_id,$contactnotification_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$command_object_id,"$nthash->{13}",$instance_id,$contactnotification_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$command_object_id,"$nthash->{13}");
	return;
}

sub contactnotificationmethod_end () {
	$nthash = shift;
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	my $contactnotification_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$contactnotification_id = $contactnotifications->{ $nthash->{53} }->{ $nthash->{114} }->{ $nthash->{134} };
	} else {
		my $notif_service = "NULL";
		$contactnotification_id = $contactnotifications->{ $nthash->{53} }->{ $notif_service }->{ $nthash->{134} };
	}
	my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$contactnotificationmethod_end_sth->execute($instance_id,$contactnotification_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$command_object_id,"$nthash->{13}",$instance_id,$contactnotification_id,$start_time,$start_time_usec,$end_time,$end_time_usec,
		$command_object_id,"$nthash->{13}");
	return;
}
# End of 60X series

#################################################################################################################
#
# 700: servicecheck_initate
# 701: servicecheck_processed
# 702: servicecheck_raw_start (not implemented)
# 703: servicecheck_raw_end (not implemented)
# 704: servicecheck_async_precheck (skipped in dbhandler.c).
#
################
# notes:
#	only 701 has been seen.

# types 70X-series
sub servicecheck_processed () {
	$nthash = shift;
	# update nagios_servicechecks.
	my $service_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	# split start and end time into timestamp and usec.
	my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	if (not defined($nthash->{95})) { $nthash->{95} = ''; }
	$servicecheck_processed_sth->execute($instance_id,$service_object_id,$nthash->{12},$nthash->{25},$nthash->{76},$nthash->{118},$nthash->{121},
		$start_time,$start_time_usec,$end_time,$end_time_usec,$nthash->{123},$nthash->{32},$nthash->{42},$nthash->{71},$nthash->{110},$nthash->{95},
		$nthash->{99},$command_object_id,$nthash->{13},$nthash->{14});
	return;
}
# End of 70X series

#################################################################################################################
#
# 800: hostcheck_initiate (not used according to dbhandler.c)
# 801: hostcheck_processed
# 802: hostcheck_raw_start
# 803: hostcheck_raw_end
# 804: hostcheck_async_precheck (not used according to dbhandler.c)
# 805: hostcheck_sync_precheck (not used according to dbhandler.c)
#
################
# notes:
#	dbhandler code is a bit unclear, at first it suggest only handling hostcheck_processed,
#	but later on it shows setting the is_raw value based on hostcheck_raw_start/end.

# types 80X series
sub hostcheck_processed () {
	$nthash = shift;
	# update nagios_hostchecks.
        my $host_object_id = &determine_object_id($nthash->{53},"NULL",'host');
        my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
        # split start and end time into timestamp and usec.
        my ($start_time,$start_time_usec) = split(/\./, $nthash->{117});
        my ($end_time,$end_time_usec) = split(/\./, $nthash->{33});
	$hostcheck_processed_sth->execute($instance_id,$host_object_id,$nthash->{12},'0',$nthash->{25},$nthash->{76},$nthash->{118},$nthash->{121},$start_time,
		$start_time_usec,$end_time,$end_time_usec,$nthash->{123},$nthash->{32},$nthash->{42},$nthash->{71},$nthash->{110},$nthash->{95},
		$nthash->{99},$command_object_id,$nthash->{13},$nthash->{14});
	return;
}
# End of 80X series.

#################################################################################################################
#
# 900: comment_add
# 901: comment_delete
# 902: comment_load
#
###############
# notes:

# types 90X series
sub comment_add () {
	$nthash = shift;
	my $com_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$com_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$com_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
	my ($entry_time,$entry_time_usec) = split(/\./, $nthash->{4});
	$comment_add_sth->execute($instance_id,$nthash->{20},$nthash->{35},$com_object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43},$entry_time,$entry_time_usec,
		$instance_id,$nthash->{20},$nthash->{35},$com_object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43});
        $comment_history_sth->execute($instance_id,$nthash->{20},$nthash->{35},$com_object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
                $nthash->{116},$nthash->{44},$nthash->{43},$entry_time,$entry_time_usec,
		$instance_id,$nthash->{20},$nthash->{35},$com_object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43});
	return;
}

sub comment_delete () {
	$nthash = shift;
	# delete comment
	my ($deletion_time,$deletion_time_usec) = split(/\./, $nthash->{4});
	$comment_delete_sth->execute($instance_id,$nthash->{34},$nthash->{18});
	$comment_delete_history_sth->execute($deletion_time,$deletion_time_usec,$instance_id,$nthash->{34},$nthash->{18});
	return;
}

sub comment_load () {
	$nthash = shift;
	my $com_object_id;
	if (defined($nthash->{53}) && (defined($nthash->{114})) ) {
		$com_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$com_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
        my ($entry_time,$entry_time_usec) = split(/\./, $nthash->{4});
	$comment_add_sth->execute($instance_id,$nthash->{20},$nthash->{35},$object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43},$entry_time,$entry_time_usec,
		$instance_id,$nthash->{20},$nthash->{35},$object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43});
	$comment_history_sth->execute($instance_id,$nthash->{20},$nthash->{35},$object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43},$entry_time,$entry_time_usec,
		$instance_id,$nthash->{20},$nthash->{35},$object_id,$nthash->{34},$nthash->{18},"$nthash->{10}","$nthash->{17}",$nthash->{100},
		$nthash->{116},$nthash->{44},$nthash->{43});
        return;
}
# End of 90X series

#################################################################################################################
#
# 1000: flapping_start
# 1001: flapping_stop
#
#################
# notes:
#	both types seem to use the same SQL.
#
# example SQL: INSERT INTO nagios_flappinghistory 
#	SET instance_id='1', event_time=FROM_UNIXTIME(1332078404), event_time_usec='156019', event_type='1000', reason_type='0', flapping_type='1', 
#	object_id='212', percent_state_change='34.473680', low_threshold='20.000000', high_threshold='30.000000', 
#	comment_time=FROM_UNIXTIME(1332078404), internal_comment_id='235'
#

# types 100X series
sub flapping_start () {
	$nthash = shift;
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my ($event_time,$event_time_usec) = split(/\./, $nthash->{4});
	$flapping_start_sth->execute($instance_id,$event_time,$event_time_usec,$nthash->{1},$nthash->{3},$nthash->{48},$object_id,$nthash->{98},$nthash->{75},
		$nthash->{52},$nthash->{19},$nthash->{18});
	return;
}

sub flapping_end () {
	$nthash = shift;
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my ($event_time,$event_time_usec) = split(/\./, $nthash->{4});
	$flapping_end_sth->execute($instance_id,$event_time,$event_time_usec,$nthash->{1},$nthash->{3},$nthash->{48},$object_id,$nthash->{98},$nthash->{75},
		$nthash->{52},$nthash->{19},$nthash->{18});
	return;
}
# End of 100X series

#################################################################################################################
#
# 1100: downtime_add
# 1101: downtime_delete
# 1102: downtime_load
# 1103: downtime_start
# 1104: downtime_stop
#
####################
# notes:
#	All types except 1102 have been implemented.

# types 110X series.
sub downtime_add () {
	$nthash = shift;
	# update nagios_scheduleddowntime and downtimehistory (add downtime).
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	$downtime_add_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33},
		$instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33});
	$downtime_history_insert_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33},
		$instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33});
	return;
}

sub downtime_delete () {
	$nthash = shift;
	# update nagios_schedulddowntime (remove downtime user has cancelled the downtime).
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my ($end_time,$end_time_usec) = split(/\./, $nthash->{4});
	$downtime_delete_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33});
	$downtime_history_update_sth->execute($end_time,$end_time_usec,$instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33});
	return;
}

sub downtime_load () {
	$nthash = shift;
	# probably only used in reloads ro repopulate scheduleddowntime table.
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	$downtime_add_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33},
		$instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33});
	$downtime_history_insert_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33},
		$instance_id,$nthash->{30},$object_id,$nthash->{34},"$nthash->{10}","$nthash->{17}",$nthash->{29},$nthash->{124},
		$nthash->{46},$nthash->{31},$nthash->{117},$nthash->{33});
        return;
}

sub downtime_start () {
	$nthash = shift;
	# update nagios_scheduleddowntime and downtimehistory (planned downtime has started).
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my ($start_time,$start_time_usec) = split(/\,/, $nthash->{4});
	$downtime_start_sth->execute($start_time,$start_time_usec,'1',$instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33},'0');
	$downtime_history_start_sth->execute($start_time,$start_time_usec,'1',$instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33},'0');
	return;
}

sub downtime_stop () {
	$nthash = shift;
	# update nagios_scheduleddowntime and downtimehistory (downtime period has passed).
        my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
        my ($end_time,$end_time_usec) = split(/\./, $nthash->{4});
        $downtime_stop_sth->execute($instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33});
        $downtime_history_stop_sth->execute($end_time,$end_time_usec,'0',$instance_id,$nthash->{30},$object_id,$nthash->{34},$nthash->{117},$nthash->{33});
        return;
}
# End of 110X series.

#################################################################################################################
#
# 1200: programstatus_update
# 1201: hoststatus_update
# 1202: servicestatus_update
# 1203: contactstatus_update
#
################
# notes:
#	All types have been implemented

# types 120X seriers
sub programstatus_update () {
        $nthash = shift;
        # update nagios_programstatus
	if (defined $nthash->{102}) {
		$running = 1;
	}
	$programstatus_update_sth->execute($instance_id,$nthash->{4},$nthash->{106},$running,$nthash->{102},$nthash->{28},$nthash->{55},
		$nthash->{60},$nthash->{88},$nthash->{9},$nthash->{97},$nthash->{8},$nthash->{96},$nthash->{39},$nthash->{47},$nthash->{45},
		$nthash->{103},$nthash->{92},$nthash->{94},$nthash->{78},$nthash->{80},"$nthash->{49}","$nthash->{50}",
		$instance_id,$nthash->{4},$nthash->{106},$running,$nthash->{102},$nthash->{28},$nthash->{55},$nthash->{60},
		$nthash->{88},$nthash->{9},$nthash->{97},$nthash->{8},$nthash->{96},$nthash->{39},$nthash->{47},$nthash->{45},
		$nthash->{103},$nthash->{92},$nthash->{94},$nthash->{78},$nthash->{80},"$nthash->{49}","$nthash->{50}");
	return;
}

sub hoststatus_update () {
	$nthash = shift;
	# update nagios_hoststatus
	my $host_object_id = &determine_object_id($nthash->{53},"NULL",'host');
	my $timeperiod_object_id = &determine_object_id($nthash->{162},"NULL",'timeperiod');
	$hoststatus_update_sth->execute($instance_id,$host_object_id,$nthash->{4},"$nthash->{95}","$nthash->{99}",$nthash->{27},$nthash->{51},$nthash->{115},
                $nthash->{25},$nthash->{76},$nthash->{58},$nthash->{81},$nthash->{12},$nthash->{63},$nthash->{57},$nthash->{56},$nthash->{69},
                $nthash->{65},$nthash->{68},$nthash->{121},$nthash->{59},$nthash->{82},$nthash->{85},$nthash->{88},$nthash->{101},
                $nthash->{7},$nthash->{26},$nthash->{96},$nthash->{8},$nthash->{38},$nthash->{47},$nthash->{54},$nthash->{98},$nthash->{71},
                $nthash->{42},$nthash->{45},$nthash->{103},$nthash->{91},$nthash->{78},"$nthash->{37}",$nthash->{11},$nthash->{86},$nthash->{109},
                $timeperiod_object_id,$nthash->{113},
		$instance_id,$host_object_id,$nthash->{4},"$nthash->{95}","$nthash->{99}",$nthash->{27},$nthash->{51},$nthash->{115},$nthash->{25},
		,$nthash->{76},$nthash->{58},$nthash->{81},$nthash->{12},$nthash->{63},$nthash->{57},$nthash->{56},$nthash->{69},$nthash->{65},
		$nthash->{68},$nthash->{121},$nthash->{59},$nthash->{82},$nthash->{85},$nthash->{88},$nthash->{101},$nthash->{7},$nthash->{26},
		$nthash->{96},$nthash->{8},$nthash->{38},$nthash->{47},$nthash->{54},$nthash->{98},$nthash->{71},$nthash->{42},$nthash->{45},
		$nthash->{103},$nthash->{91},$nthash->{78},"$nthash->{37}",$nthash->{11},$nthash->{86},$nthash->{109},$timeperiod_object_id,$nthash->{113});
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariable_status_sth->execute($instance_id,$host_object_id,$nthash->{4},$modified,$varname,$varvalue,
					$instance_id,$host_object_id,$nthash->{4},$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariable_status_sth->execute($instance_id,$host_object_id,$nthash->{4},$modified,$varname,$varvalue,
				$instance_id,$host_object_id,$nthash->{4},$modified,$varname,$varvalue);
		}
	}
	return;
}

sub servicestatus_update () {
        $nthash = shift;
        # map values to variables.
        my $service_object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	my ($comm,$rest) = split(/\!/, $nthash->{11});
        my $command_object_id = &determine_object_id($comm,"NULL",'command');
	my $timeperiod_object_id = &determine_object_id($nthash->{209},"NULL",'timeperiod');
	if (not defined($nthash->{37})) { $nthash->{37} = ''; }
	if (not defined($nthash->{95})) { $nthash->{95} = ''; }
	$servicestatus_update_sth->execute($instance_id,$service_object_id,$nthash->{4},"$nthash->{95}","$nthash->{99}",$nthash->{27},$nthash->{51},
		$nthash->{115},$nthash->{25},$nthash->{76},$nthash->{61},$nthash->{83},$nthash->{12},$nthash->{63},$nthash->{57},$nthash->{56},$nthash->{66},
		$nthash->{70},$nthash->{67},$nthash->{64},$nthash->{121},$nthash->{62},$nthash->{84},$nthash->{85},$nthash->{88},$nthash->{101},
		$nthash->{7},$nthash->{26},$nthash->{97},$nthash->{9},$nthash->{38},$nthash->{47},$nthash->{54},$nthash->{98},$nthash->{71},
		$nthash->{42},$nthash->{45},$nthash->{103},$nthash->{93},$nthash->{80},"$nthash->{37}",$nthash->{11},$nthash->{86},$nthash->{109},
		$timeperiod_object_id,$nthash->{113},
		$instance_id,$service_object_id,$nthash->{4},"$nthash->{95}","$nthash->{99}",$nthash->{27},$nthash->{51},$nthash->{115},
		$nthash->{25},$nthash->{76},$nthash->{61},$nthash->{83},$nthash->{12},$nthash->{63},$nthash->{57},$nthash->{56},$nthash->{66},
		$nthash->{70},$nthash->{67},$nthash->{64},$nthash->{121},$nthash->{62},$nthash->{84},$nthash->{85},$nthash->{88},$nthash->{101},
		$nthash->{7},$nthash->{26},$nthash->{97},$nthash->{9},$nthash->{38},$nthash->{47},$nthash->{54},$nthash->{98},$nthash->{71},
		$nthash->{42},$nthash->{45},$nthash->{103},$nthash->{93},$nthash->{80},"$nthash->{37}",$nthash->{11},$nthash->{86},$nthash->{109},
		$timeperiod_object_id,$nthash->{113});
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariable_status_sth->execute($instance_id,$service_object_id,$nthash->{4},$modified,$varname,$varvalue,
					$instance_id,$service_object_id,$nthash->{4},$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariable_status_sth->execute($instance_id,$service_object_id,$nthash->{4},$modified,$varname,$varvalue,
				$instance_id,$service_object_id,$nthash->{4},$modified,$varname,$varvalue);
		}
	}
	return;
}

sub contactstatus_update () {
	$nthash = shift;
	# update nagios_contactstatus.
	my $contact_object_id = &determine_object_id($nthash->{134},"NULL",'contact');
	$contactstatus_update_sth->execute($instance_id,$contact_object_id,$nthash->{4},$nthash->{178},$nthash->{225},$nthash->{59},$nthash->{62},
		$nthash->{261},$nthash->{78},$nthash->{80},
		$instance_id,$contact_object_id,$nthash->{4},$nthash->{178},$nthash->{225},$nthash->{59},$nthash->{62},$nthash->{261},$nthash->{78},$nthash->{80});
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariable_status_sth->execute($instance_id,$contact_object_id,$nthash->{4},$modified,$varname,$varvalue,
					$instance_id,$contact_object_id,$nthash->{4},$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariable_status_sth->execute($instance_id,$contact_object_id,$nthash->{4},$modified,$varname,$varvalue,
				$instance_id,$contact_object_id,$nthash->{4},$modified,$varname,$varvalue);
		}
	}
	return;
}
# End of 120X series

#################################################################################################################
#
# 1300: adaptiveprogram_update
# 1301: adaptivehost_update
# 1302: adaptiveservice_update
# 1303: adaptivecontact_update
#
######################
# notes:
#	According to the dbhandler.h from NDO these types are not used.

# types 130X series
# End of 130X series

#################################################################################################################
#
# 1400: externalcommand_start
# 1401: externalcommand_end
#
####################
# notes:
#	None of these types has been seen yet.

# types 140X series
sub externalcommand_start () {
	$nthash = shift;
	$externalcommand_start_sth->execute($instance_id,$nthash->{34},$nthash->{16},"$nthash->{127}","$nthash->{13}",
		$instance_id,$nthash->{34},$nthash->{16},"$nthash->{127}","$nthash->{13}");
	return;
}

sub externalcommand_end () {
	$nthash = shift;
	$externalcommand_end_sth->execute($instance_id,$nthash->{34},$nthash->{16},"$nthash->{127}","$nthash->{13}",
		$instance_id,$nthash->{34},$nthash->{16},"$nthash->{127}","$nthash->{13}");
	return;
}
# End of 140X series

#################################################################################################################
#
# 1500: aggregatedstatus_startdump
# 1501: aggregatedstatus_enddump
#
####################
# notes:
#	According to the dbhandler.h from NDO these types are not used.

# types 150X series
# End of 150X series

#################################################################################################################
#
# 1600: retentiondata_startload
# 1601: retentiondata_endload
# 1602: retentiondata_startsave
# 1603: retentiondata_endsave
#
####################
# notes:
#	According to the dbhanlder.h from NDO these types are not used.

# types 160X series
# End of 160X series

#################################################################################################################
#
# 1700: acknowledgement_add
# 1701: acknowledgement_remove (not implemented)
# 1702: acknowledgement_load (not implemented)
#
###################
# notes:
#	1700 type implemented

# types 170X seriers
sub acknowledgement_add () {
	$nthash = shift;
	# update nagios_acknowledgement.
	my $object_id;
	if ($nthash->{7} == 1 ) {
		$object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
	} else {
		$object_id = &determine_object_id($nthash->{53},"NULL",'host');
	}
	my ($entry_time,$entry_time_usec) = split(/\./, $nthash->{4});
	$acknowledgement_add_sth->execute($instance_id,$entry_time,$entry_time_usec,$nthash->{7},$object_id,$nthash->{118},"$nthash->{10}",
		"$nthash->{17}",$nthash->{122},$nthash->{100},$nthash->{90},
		$instance_id,$entry_time,$entry_time_usec,$nthash->{7},$object_id,$nthash->{118},"$nthash->{10}","$nthash->{17}",
		$nthash->{122},$nthash->{100},$nthash->{90});
	return;
}
# End of 170X series

#################################################################################################################
#
# 1800: statechange_start (not implemented)
# 1801: statechange_end
#
###################
# notes:
#	1801 type implemented

# types 180X series
sub statechange () {
	$nthash = shift;
	my $object_id = &determine_object_id($nthash->{53},$nthash->{114},'service');
        # split time into timestamp and usec.
        my ($state_time,$state_time_usec) = split(/\./, $nthash->{4});
	$statechange_sth->execute($instance_id,$state_time,$state_time_usec,$object_id,$nthash->{119},$nthash->{118},$nthash->{121},$nthash->{25},
		$nthash->{76},$nthash->{265},$nthash->{56},$nthash->{95});
	return;
}
# End of 180X series

#################################################################################################################
#
# NDO events.
#
# these events are needed to populate and add objects to the DB.
# for now we have seen a small segment of NDO events.
#
# ID	primary DB table		| secondary DB table.
# 300	nagios_configfiles		| nagios_configfilevariables
# 303   nagios_runtimevariables		|
# 400	nagios_hosts			|
# 401	nagios_hostgroups		|
# 402	nagios_services			|
# 405	nagios_servicedependencies	|
# 408	nagios_commands			| nagios_objects
# 409	nagios_timeperiods		|
# 410	nagios_contacts			|
# 411	nagios_contactgroups		|
#
#################################################################################################################

#################################################################################################################
# 
# ndo_id:
# 300: mainconfigfilevariables.
# 301: resourceconfigfilevariables.
# 302: configvariables. according to dbhandler.c nothing is done here.
# 303: runtimevariables.
#
#################################################################################################################
# notes:
# 	have only seen the 303 so far, more research needed here.
#	duplicat key-values prevent use from processing this call at the moment.
#
# EXAMPLE SQL 303: INSERT INTO nagios_runtimevariables SET instance_id='1', varname='config_file', varvalue='/usr/local/nagios/etc/nagios\.cfg' 
#	ON DUPLICATE KEY UPDATE instance_id='1', varname='config_file', varvalue='/usr/local/nagios/etc/nagios\.cfg'

# Start of ndo_id 30X series.
sub mainconfigfilevariables () {
	$nthash = shift;
	return;
}

sub runtimevariables () {
	$nthash = shift;
	if(defined($nthash->{112})) {
		my @runtimevariables = @{ $nthash->{112} };
		foreach my $runtimevariable (@runtimevariables) {
			my ($varname,$varvalue) = split(/=/, $runtimevariable);
			$runtimevariables_sth->execute($instance_id,"$varname","$varvalue",$instance_id,"$varname","$varvalue");
		}
	}
	return;
}
# End of nod_id 30X series.

#################################################################################################################
#
# ndo_id
# 400: hostdefinition.
# 401: hostgroupdefinition.
# 402: servicedefinition.
# 403: servicegroupdefinition.
# 404: hostdependencydefinition.
# 405: servicedependencydefinition.
# 406: hostescalationdefinition.
# 407: serviceescalationdefinition.
# 408: commanddefinition.
# 409: timeperioddefinition.
# 410: contactdefinition.
# 411: contactgroupdefinition.
# 412: hostextinfodefinition (not implemented anymore).
# 413: serviceectinfodefionition (not implemented anymore).

# Start of ndo_id 4XX series.

# 400 hostdefinition
sub hostdefinition () {
	$nthash = shift;
	# retrieve our object_id and object-type_id (type id should allways be 1 though)
        my $host_object_id = &determine_object_id($nthash->{174},"NULL",'host');
	my $objecttype_id = &determine_objecttype_id($nthash->{174},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$host_object_id);
	my ($check_command,$command_args);
	if (defined($nthash->{160})) {
		($check_command,$command_args) = split(/\!/,$nthash->{160});
	}
	if (not defined($command_args)) { $command_args = ''; }
	my $check_command_object_id = &determine_object_id($check_command,"NULL",'command');
	if (not defined($check_command_object_id)) { $check_command_object_id = ''; }
	my ($eventhandler_command,$eventhandler_args,$eventhandler_command_object_id,$f_p_options);
	if ($nthash->{164} != '0') {
		($eventhandler_command,$eventhandler_args) = split (/\!/, $nthash->{163});
		$eventhandler_command_object_id = &determine_object_id($eventhandler_command,"NULL",'command');
	} else {
		$eventhandler_command_object_id = '0';
		$eventhandler_args = '';
	}
	my $check_timeperiod_object_id = &determine_object_id($nthash->{162},"NULL",'timeperiod');
	my $notification_timeperiod_object_id = &determine_object_id($nthash->{177},"NULL",'timeperiod');
	if (defined ($nthash->{166})) {
		$f_p_options = $nthash->{166};
	} else {
		$f_p_options = '';
	}
	$hostdefinition_host_sth->execute($instance_id,$object_config_type,$host_object_id,"$nthash->{159}","$nthash->{258}",$nthash->{158},"$check_command_object_id",
		"$command_args",$eventhandler_command_object_id,"$eventhandler_args",$check_timeperiod_object_id,$notification_timeperiod_object_id,"$f_p_options",
		$nthash->{161},$nthash->{247},$nthash->{173},$nthash->{246},$nthash->{176},$nthash->{189},$nthash->{192},$nthash->{191},$nthash->{190},$nthash->{248},
		$nthash->{230},$nthash->{228},$nthash->{229},$nthash->{167},$nthash->{251},$nthash->{252},$nthash->{253},$nthash->{183},$nthash->{156},$nthash->{201},
		$nthash->{168},$nthash->{169},$nthash->{96},$nthash->{164},$nthash->{8},$nthash->{204},$nthash->{203},$nthash->{178},$nthash->{91},$nthash->{165},
		"$nthash->{186}","$nthash->{187}","$nthash->{126}","$nthash->{179}","$nthash->{180}","$nthash->{239}","$nthash->{235}",$nthash->{154},$nthash->{240},
		$nthash->{242},$nthash->{155},$nthash->{241},$nthash->{243},$nthash->{244},
		$instance_id,$object_config_type,$host_object_id,"$nthash->{159}","$nthash->{258}",$nthash->{158},"$check_command_object_id","$command_args",
		$eventhandler_command_object_id,"$eventhandler_args",$check_timeperiod_object_id,$notification_timeperiod_object_id,"$f_p_options",$nthash->{161},
		$nthash->{247},$nthash->{173},$nthash->{246},$nthash->{176},$nthash->{189},$nthash->{192},$nthash->{191},$nthash->{190},$nthash->{248},$nthash->{230},
		$nthash->{228},$nthash->{229},$nthash->{167},$nthash->{251},$nthash->{252},$nthash->{253},$nthash->{183},$nthash->{156},$nthash->{201},$nthash->{168},
		$nthash->{169},$nthash->{96},$nthash->{164},$nthash->{8},$nthash->{204},$nthash->{203},$nthash->{178},$nthash->{91},$nthash->{165},"$nthash->{186}",
		"$nthash->{187}","$nthash->{126}","$nthash->{179}","$nthash->{180}","$nthash->{239}","$nthash->{235}",$nthash->{154},$nthash->{240},$nthash->{242},
		$nthash->{155},$nthash->{241},$nthash->{243},$nthash->{244});
	# iterate over the contactgroups and set the contact info.
	# we need our host_id from our previous insert.
	my $host_id = &determine_insert_id($hostdefinition_host_sth);
	if (defined($nthash->{130})) {
		if (ref ($nthash->{130}) eq "ARRAY") {
			my @contactgroups = @{ $nthash->{130} };
			foreach my $contactgroup (@contactgroups) {
				my $contactgroup_id = &determine_object_id($contactgroup,"NULL",'contactgroup');
				$hostdefinition_contactgroups_sth->execute($instance_id,$host_id,$contactgroup_id,$instance_id,$host_id,$contactgroup_id);
				if (defined ($contact_group_list_ref->{$contactgroup_id})) {
					if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
						my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
						foreach my $contact (@contacts) {
							$hostdefinition_contact_sth->execute($instance_id,$host_id,$contact,$instance_id,$host_id,$contact);
						}
					} else {
						 my $contact = $contact_group_list_ref->{ $contactgroup_id };
						 $hostdefinition_contact_sth->execute($instance_id,$host_id,$contact,$instance_id,$host_id,$contact);
					}
				}
			}
		} else {
			my $contactgroup_id = &determine_object_id($nthash->{130},"NULL",'contactgroup');
			$hostdefinition_contactgroups_sth->execute($instance_id,$host_id,$contactgroup_id,$instance_id,$host_id,$contactgroup_id);
			if (defined ($contact_group_list_ref->{$contactgroup_id})) {
				if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
					my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
					foreach my $contact (@contacts) {
						$hostdefinition_contact_sth->execute($instance_id,$host_id,$contact,$instance_id,$host_id,$contact);
					}
				} else {
					my $contact = $contact_group_list_ref->{ $contactgroup_id };
					$hostdefinition_contact_sth->execute($instance_id,$host_id,$contact,$instance_id,$host_id,$contact);
				}
			}
		}
	}
	if (defined($nthash->{200})) {
		if (ref ($nthash->{200}) eq "ARRAY") {
			my @parents = @{ $nthash->{200} };
			foreach my $parent (@parents) {
				my $parent_object_id = &determine_object_id($parent,"NULL",'host');
				$hostdefinition_parenthost_sth->execute($instance_id,$host_id,$parent_object_id,$instance_id,$host_id,$parent_object_id);
			}
		} else {
			my $parent_object_id = &determine_object_id($nthash->{200},"NULL",'host');
			$hostdefinition_parenthost_sth->execute($instance_id,$host_id,$parent_object_id,$instance_id,$host_id,$parent_object_id);
		}
	}
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariables_sth->execute($instance_id,$host_id,$object_config_type,$modified,$varname,$varvalue,
					$instance_id,$host_id,$object_config_type,$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariables_sth->execute($instance_id,$host_id,$object_config_type,$modified,$varname,$varvalue,
				$instance_id,$host_id,$object_config_type,$modified,$varname,$varvalue);
		}
	}
	return;
}

# 401 hostgroupdefinition
sub hostgroupdefinition () {
	$nthash = shift;
	my $object_id = &determine_object_id($nthash->{172},"NULL",'hostgroup');
	my $objecttype_id = &determine_objecttype_id($nthash->{172},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$object_id);
	$hostgroupdefinition_hostgroup_sth->execute($instance_id,$object_config_type,$object_id,"$nthash->{170}",
		$instance_id,$object_config_type,$object_id,"$nthash->{170}");
	my $hostgroup_id = &determine_insert_id($hostgroupdefinition_hostgroup_sth);
	if(defined($nthash->{171})) {
		if (ref ($nthash->{171}) eq "ARRAY") {
			my @groupmembers = @{ $nthash->{171} };
			foreach my $groupmember (@groupmembers) {
				my $host_object_id = &determine_object_id($groupmember,"NULL",'host');
				$hostgroupdefinition_members_sth->execute($instance_id,$hostgroup_id,$host_object_id,$instance_id,$hostgroup_id,$host_object_id);
			}
		} else {
			my $host_object_id = &determine_object_id($nthash->{171},"NULL",'host');
			$hostgroupdefinition_members_sth->execute($instance_id,$hostgroup_id,$host_object_id,$instance_id,$hostgroup_id,$host_object_id);
		}
	}
	return;
}

# 402 servicedefinition
sub servicedefinition () {
	$nthash = shift;
	# example:  UPDATE nagios_objects SET is_active='1' WHERE instance_id='1' AND objecttype_id='2' AND object_id='136'
	my $object_id = &determine_object_id($nthash->{174},$nthash->{210},'service');
	my $objecttype_id = &determine_objecttype_id($nthash->{174},$nthash->{210});
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$object_id);
	my $host_object_id = &determine_object_id($nthash->{174},"NULL",'host');
	my $service_object_id = &determine_object_id($nthash->{174},$nthash->{210},'service');
	my ($command,$command_args);
	if (defined($nthash->{207})) {
		($command,$command_args) = split(/\!/, $nthash->{207});
	}
	if (not defined($command_args)) { $command_args = ''; }
	my $check_command_object_id = &determine_object_id($command,"NULL",'command');
	if (not defined($check_command_object_id)) { $check_command_object_id = ''; }
	my $check_timeperiod_object_id = &determine_object_id($nthash->{209},"NULL",'timeperiod');
	my $notification_timeperiod_object_id = &determine_object_id($nthash->{224},"NULL",'timeperiod');
	my ($eventhandler,$eventhandler_args,$f_p_options,$eventhandler_command_object_id);
	if (defined($nthash->{211})) {
		($eventhandler,$eventhandler_args) = split(/\!/,$nthash->{211});
	}
	if (not defined($eventhandler_args)) { $eventhandler_args = ''; }
	$eventhandler_command_object_id = &determine_object_id($eventhandler,"NULL",'command');
	if (not defined($eventhandler_command_object_id)) { $eventhandler_command_object_id = ''; }
        if (defined ($nthash->{214})) {
                $f_p_options = $nthash->{214};
        } else {
		$f_p_options = '';
	}
	$servicedefinition_service_sth->execute($instance_id,$object_config_type,$host_object_id,$service_object_id,"$nthash->{258}",$check_command_object_id,"$command_args",
		$eventhandler_command_object_id,"$eventhandler_args",$check_timeperiod_object_id,$notification_timeperiod_object_id,"$f_p_options",$nthash->{208},
		$nthash->{226},$nthash->{185},$nthash->{246},$nthash->{223},$nthash->{197},$nthash->{196},$nthash->{193},$nthash->{195},$nthash->{194},$nthash->{249},
		$nthash->{232},$nthash->{234},$nthash->{233},$nthash->{231},$nthash->{221},$nthash->{215},$nthash->{254},$nthash->{255},$nthash->{256},$nthash->{257},
		$nthash->{184},$nthash->{157},$nthash->{202},$nthash->{216},$nthash->{217},$nthash->{97},$nthash->{212},$nthash->{9},$nthash->{206},
		$nthash->{205},$nthash->{225},$nthash->{93},$nthash->{213},"$nthash->{186}","$nthash->{187}","$nthash->{126}","$nthash->{179}","$nthash->{180}",
		$instance_id,$object_config_type,$host_object_id,$service_object_id,"$nthash->{258}",$check_command_object_id,"$command_args",
		$eventhandler_command_object_id,"$eventhandler_args",$check_timeperiod_object_id,$notification_timeperiod_object_id,"$f_p_options",
		$nthash->{208},$nthash->{226},$nthash->{185},$nthash->{246},$nthash->{223},$nthash->{197},$nthash->{196},$nthash->{193},$nthash->{195},
		$nthash->{194},$nthash->{249},$nthash->{232},$nthash->{234},$nthash->{233},$nthash->{231},$nthash->{221},$nthash->{215},$nthash->{254},
		$nthash->{255},$nthash->{256},$nthash->{257},$nthash->{184},$nthash->{157},$nthash->{202},$nthash->{216},$nthash->{217},$nthash->{97},$nthash->{212},
		$nthash->{9},$nthash->{206},$nthash->{205},$nthash->{225},$nthash->{93},$nthash->{213},"$nthash->{186}","$nthash->{187}","$nthash->{126}",
		"$nthash->{179}","$nthash->{180}");
	my $service_id = &determine_insert_id($servicedefinition_service_sth);
	if(defined($nthash->{130})) {
		if (ref ( $nthash->{130} ) eq "ARRAY" ) {
			my @contactgroups = @{ $nthash->{130} };
			foreach my $contactgroup (@contactgroups) {
				my $contactgroup_id = &determine_object_id($contactgroup,"NULL",'contactgroup');
				$servicedefinition_contactgroups_sth->execute($instance_id,$service_id,$contactgroup_id,$instance_id,$service_id,$contactgroup_id);
				if (defined($contact_group_list_ref->{$contactgroup_id})) {
					if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
						my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
						foreach my $contact (@contacts) {
							$servicedefinition_contacts_sth->execute($instance_id,$service_id,$contact,$instance_id,$service_id,$contact);
						}
					} else {
						my $contact = $contact_group_list_ref->{ $contactgroup_id };
						$servicedefinition_contacts_sth->execute($instance_id,$service_id,$contact,$instance_id,$service_id,$contact);
					}
				}
			}
		} else {
			my $contactgroup_id = &determine_object_id($nthash->{130},"NULL",'contactgroup');
			$servicedefinition_contactgroups_sth->execute($instance_id,$service_id,$contactgroup_id,$instance_id,$service_id,$contactgroup_id);
			if (defined($contact_group_list_ref->{$contactgroup_id})) {
				if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
					my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
					foreach my $contact (@contacts) {
						$servicedefinition_contacts_sth->execute($instance_id,$service_id,$contact,$instance_id,$service_id,$contact);
					}
				} else {
					my $contact = $contact_group_list_ref->{ $contactgroup_id };
					$servicedefinition_contacts_sth->execute($instance_id,$service_id,$contact,$instance_id,$service_id,$contact);
				}
			}
		}
	}
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariables_sth->execute($instance_id,$service_id,$object_config_type,$modified,$varname,$varvalue,
					$instance_id,$service_id,$object_config_type,$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariables_sth->execute($instance_id,$service_id,$object_config_type,$modified,$varname,$varvalue,
				$instance_id,$service_id,$object_config_type,$modified,$varname,$varvalue);
		}
	}
	return;
}

# 403 servicegroupdefinition
sub servicegroupdefinition () {
	$nthash = shift;
	my $servicegroup_object_id = &determine_object_id($nthash->{220},"NULL",'servicegroup');
	$servicegroupdefinition_servicegroup_sth->execute($instance_id,$object_config_type,$servicegroup_object_id,"$nthash->{218}",
		$instance_id,$object_config_type,$servicegroup_object_id,"$nthash->{218}");
	my $servicegroup_id = &determine_insert_id($servicegroupdefinition_servicegroup_sth);
	if (defined($nthash->{219})) {
		if (ref ( $nthash->{219} ) eq "ARRAY" ) {
			my @servicegroupmembers = @{ $nthash->{219} };
			foreach my $servicemember (@servicegroupmembers) {
				my $service_object_id = &determine_object_id($servicemember,"NULL",'service');
				$servicegroupdefinition_members_sth->execute($instance_id,$servicegroup_id,$service_object_id,
					$instance_id,$servicegroup_id,$service_object_id);
			}
		} else {
			my $service_object_id = &determine_object_id($nthash->{219},"NULL",'service');
			$servicegroupdefinition_members_sth->execute($instance_id,$servicegroup_id,$service_object_id,$instance_id,$servicegroup_id,$service_object_id);
		}
	}
	return;
}

# 404 hostdependencydefinition
sub hostdependencydefinition () {
	$nthash = shift;
	my $host_object_id = &determine_object_id($nthash->{174},$nthash->{210},'service');
	my $dephost_object_id = &determine_object_id($nthash->{136},$nthash->{137},'service');
	$hostdependencydefinition_host_sth->execute($instance_id,$object_config_type,$host_object_id,$dephost_object_id,$nthash->{135},$nthash->{181},"$nthash->{258}",
		$nthash->{151},$nthash->{147},$nthash->{150},$instance_id,$object_config_type,$host_object_id,$dephost_object_id,$nthash->{135},$nthash->{181},
		"$nthash->{258}",$nthash->{151},$nthash->{147},$nthash->{150});
	return;
}

# 405 servicedependencydefinition
sub servicedependencydefinition () {
	$nthash = shift;
	my $service_object_id = &determine_object_id($nthash->{174},$nthash->{210},'service');
	my $dependent_service_object_id = &determine_object_id($nthash->{136},$nthash->{137},'service');
	$servicedependencydefinition_service_sth->execute($instance_id,$object_config_type,$service_object_id,$dependent_service_object_id,$nthash->{135},$nthash->{181},
		"$nthash->{259}",$nthash->{148},$nthash->{152},$nthash->{149},$nthash->{146},$instance_id,$object_config_type,$service_object_id,
		$dependent_service_object_id,$nthash->{135},$nthash->{181},"$nthash->{259}",$nthash->{148},$nthash->{152},$nthash->{149},$nthash->{146});
	return;
}

# 406 hostescalationdefinition
sub hostescalationdefinition () {
	$nthash = shift;
	my $host_object_id = &determine_object_id($nthash->{174},"NULL",'host');
	my $timeperiod_object_id = &determine_object_id($nthash->{145},"NULL",'timeperiod');
	$hostescalation_host_sth->execute($instance_id,$object_config_type,$host_object_id,$timeperiod_object_id,$nthash->{153},$nthash->{182},$nthash->{188},
		$nthash->{141},$nthash->{140},$nthash->{143},$instance_id,$object_config_type,$host_object_id,$timeperiod_object_id,$nthash->{153},
		$nthash->{182},$nthash->{188},$nthash->{141},$nthash->{140},$nthash->{143});
	my $hostescalation_id = &determine_insert_id($hostescalation_host_sth);
        if (defined($nthash->{130})) {
		if (ref ($nthash->{130}) eq "ARRAY") {
			my @contactgroups = @{ $nthash->{130} };
			foreach my $contactgroup (@contactgroups) {
				my $contactgroup_id = &determine_object_id($contactgroup,"NULL",'contactgroup');
				$hostescalation_contactgroups_sth->execute($instance_id,$hostescalation_id,$contactgroup_id,
					$instance_id,$hostescalation_id,$contactgroup_id);
				if (defined ($contact_group_list_ref->{$contactgroup_id})) {
					if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
						my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
						foreach my $contact (@contacts) {
							$hostescalation_contacts_sth->execute($instance_id,$hostescalation_id,$contact,
								$instance_id,$hostescalation_id,$contact);
						}
					} else {
						my $contact = $contact_group_list_ref->{ $contactgroup_id };
						$hostescalation_contacts_sth->execute($instance_id,$hostescalation_id,$contact,
							$instance_id,$hostescalation_id,$contact);
					}
				}
			}
		} else {
			my $contactgroup_id = &determine_object_id($nthash->{130},"NULL",'contactgroup');
			$hostescalation_contactgroups_sth->execute($instance_id,$hostescalation_id,$contactgroup_id,
				$instance_id,$hostescalation_id,$contactgroup_id);
			if (defined ($contact_group_list_ref->{$contactgroup_id})) {
				if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
					my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
					foreach my $contact (@contacts) {
						$hostescalation_contacts_sth->execute($instance_id,$hostescalation_id,$contact,
							$instance_id,$hostescalation_id,$contact);
					}
				} else {
					my $contact = $contact_group_list_ref->{ $contactgroup_id };
					$hostescalation_contacts_sth->execute($instance_id,$hostescalation_id,$contact,
						$instance_id,$hostescalation_id,$contact);
				}
			}
		}
	}
	return;
}

# 407 serviceescalationdefinition
sub serviceescalationdefinition () {
	$nthash = shift;
	my $service_object_id = &determine_object_id($nthash->{174},$nthash->{210},'service');
	my $timeperiod_object_id = &determine_object_id($nthash->{145},"NULL",'timeperiod');
	$serviceescalation_service_sth->execute($instance_id,$object_config_type,$service_object_id,$timeperiod_object_id,$nthash->{153},$nthash->{182},$nthash->{188},
		$nthash->{141},$nthash->{144},$nthash->{142},$nthash->{139},$instance_id,$object_config_type,$service_object_id,$timeperiod_object_id,$nthash->{153},
		$nthash->{182},$nthash->{188},$nthash->{141},$nthash->{144},$nthash->{142},$nthash->{139});
	my $serviceescalation_id = &determine_insert_id($serviceescalation_service_sth);
        if (defined($nthash->{130})) {
		if (ref ($nthash->{130}) eq "ARRAY") {
			my @contactgroups = @{ $nthash->{130} };
			foreach my $contactgroup (@contactgroups) {
				my $contactgroup_id = &determine_object_id($contactgroup,"NULL",'contactgroup');
				$serviceescalation_contactgroups_sth->execute($instance_id,$serviceescalation_id,$contactgroup_id,
					$instance_id,$serviceescalation_id,$contactgroup_id);
				if (defined ($contact_group_list_ref->{$contactgroup_id})) {
					if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
						my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
						foreach my $contact (@contacts) {
							$serviceescalation_contacts_sth->execute($instance_id,$serviceescalation_id,$contact,
								$instance_id,$serviceescalation_id,$contact);
						}
					} else {
						my $contact = $contact_group_list_ref->{ $contactgroup_id };
						$serviceescalation_contacts_sth->execute($instance_id,$serviceescalation_id,$contact,
							$instance_id,$serviceescalation_id,$contact);
					}
				}
			}
		} else {
			my $contactgroup_id = &determine_object_id($nthash->{130},"NULL",'contactgroup');
			$serviceescalation_contactgroups_sth->execute($instance_id,$serviceescalation_id,$contactgroup_id,
				$instance_id,$serviceescalation_id,$contactgroup_id);
			if (defined ($contact_group_list_ref->{$contactgroup_id})) {
				if (ref ( $contact_group_list_ref->{$contactgroup_id} ) eq "ARRAY" ) {
					my @contacts = @{ $contact_group_list_ref->{ $contactgroup_id } };
					foreach my $contact (@contacts) {
						$serviceescalation_contacts_sth->execute($instance_id,$serviceescalation_id,$contact,
							$instance_id,$serviceescalation_id,$contact);
					}
				} else {
					my $contact = $contact_group_list_ref->{ $contactgroup_id };
					$serviceescalation_contacts_sth->execute($instance_id,$serviceescalation_id,$contact,
						$instance_id,$serviceescalation_id,$contact);
				}
			}
		}
	}
	return;
}

# 408 commands table.
sub commanddefinition () {
	$nthash = shift;
	# retrieve our object id and object-type id (type-id should allways be 12 though).
	my $command_object_id = &determine_object_id($nthash->{127},"NULL",'command');
	my $objecttype_id = &determine_objecttype_id($nthash->{127},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$command_object_id);
	$commanddefinition_command_sth->execute($instance_id,$object_config_type,$command_object_id,"$nthash->{14}",
		$instance_id,$object_config_type,$command_object_id,"$nthash->{14}");
	return;
}

# 409: timeperioddefinition
sub timeperioddefinition () {
	$nthash = shift;
	# exmaples: UPDATE nagios_objects SET is_active='1' WHERE instance_id='1' AND objecttype_id='9' AND object_id='113'
        my $time_object_id = &determine_object_id($nthash->{237},"NULL",'timeperiod');
	my $objecttype_id = &determine_objecttype_id($nthash->{237},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$time_object_id);
	$timeperioddefinition_timeperiod_sth->execute($instance_id,$object_config_type,$time_object_id,"$nthash->{236}",
		$instance_id,$object_config_type,$time_object_id,"$nthash->{236}");
	my $timeperiod_id = &determine_insert_id($timeperioddefinition_timeperiod_sth);
	if (defined($nthash->{238})) {
		my @timeperiods = @{ $nthash->{238} };
		foreach my $timeperiod (@timeperiods) {
			my ($day,$seconds) = split(/:/,$timeperiod);
			my ($start_sec,$end_sec) = split(/\-/,$seconds);
			$timeperioddefinition_timeranges_sth->execute($instance_id,$timeperiod_id,$day,$start_sec,$end_sec,
				$instance_id,$timeperiod_id,$day,$start_sec,$end_sec);
		}
			
	}
	return;
}

# 410: contactdefinition
sub contactdefinition () {
	$nthash = shift;
	my $contact_object_id = &determine_object_id($nthash->{134},"NULL",'contact');
	my $host_timeperiod_object_id = &determine_object_id($nthash->{177},"NULL",'timeperiod');
	my $service_timeperiod_object_id = &determine_object_id($nthash->{224},"NULL",'timeperiod');
	my $objecttype_id = &determine_objecttype_id($nthash->{134},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$contact_object_id);
	$contactdefinition_contact_sth->execute($instance_id,$object_config_type,$contact_object_id,"$nthash->{129}","$nthash->{138}","$nthash->{198}",
		$host_timeperiod_object_id,$service_timeperiod_object_id,$nthash->{178},$nthash->{225},$nthash->{250},$nthash->{195},$nthash->{197},$nthash->{196},
		$nthash->{193},$nthash->{194},$nthash->{249},$nthash->{191},$nthash->{189},$nthash->{192},$nthash->{190},$nthash->{248},
		$instance_id,$object_config_type,$contact_object_id,"$nthash->{129}","$nthash->{138}","$nthash->{198}",$host_timeperiod_object_id,
		$service_timeperiod_object_id,$nthash->{178},$nthash->{225},$nthash->{250},$nthash->{195},$nthash->{197},$nthash->{196},$nthash->{193},
		$nthash->{194},$nthash->{249},$nthash->{191},$nthash->{189},$nthash->{192},$nthash->{190},$nthash->{248});
	my $contact_id = &determine_insert_id($contactdefinition_contact_sth);
	if (defined($nthash->{128})) {
		if (ref ($nthash->{128}) eq "ARRAY") {
			my @contactaddresses = @{ $nthash->{128} };
			foreach my $contactaddress (@contactaddresses) {
				my ($address_number,$address) = split(/:/, $contactaddress);
				$contactdefinition_contactaddresses_sth->execute($instance_id,$contact_id,$address_number,$address,
					$instance_id,$contact_id,$address_number,$address);
			}
		} else {
			my ($address_number,$address) = split(/:/,$nthash->{128});
			$contactdefinition_contactaddresses_sth->execute($instance_id,$contact_id,$address_number,$address,
				$instance_id,$contact_id,$address_number,$address);
		}
	}
	# should have something here for host and service notification commands
	if (defined($nthash->{175})) {
		# host notification command;
		my $notification_type = 0; #host notification.
		my $command_id = &determine_object_id($nthash->{175},"NULL",'command');
		my $command_args = '';
		$contactdefinition_notificationcommands_sth->execute($instance_id,$contact_id,$notification_type,$command_id,$command_args,
			$instance_id,$contact_id,$notification_type,$command_id,$command_args);
	}
	if (defined($nthash->{222})) {
		# service notification command;
		my $notification_type = 1; # service notification
		my $command_id = &determine_object_id($nthash->{222},"NULL",'command');
		my $command_args = '';
		$contactdefinition_notificationcommands_sth->execute($instance_id,$contact_id,$notification_type,$command_id,$command_args,
			$instance_id,$contact_id,$notification_type,$command_id,$command_args);
	}
	if (defined($nthash->{262})) {
		my $modified = '';
		if (defined($nthash->{263})) { $modified = $nthash->{263}; }
		if (ref ($nthash->{262}) eq "ARRAY") {
			my @customvariables = @{ $nthash->{262} };
			foreach my $customvariable (@customvariables) {
				my ($varname,$varvalue) = split(/=/,$customvariable);
				$customvariables_sth->execute($instance_id,$contact_id,$object_config_type,$modified,$varname,$varvalue,
					$instance_id,$contact_id,$object_config_type,$modified,$varname,$varvalue);
			}
		} else {
			my ($varname,$varvalue) = split(/=/,$nthash->{262});
			$customvariables_sth->execute($instance_id,$contact_id,$object_config_type,$modified,$varname,$varvalue,
				$instance_id,$contact_id,$object_config_type,$modified,$varname,$varvalue);
		}
	}
	return;
}

# 411 contactgroup definition.
sub contactgroupdefinition () {
	$nthash = shift;
	my $contactgroup_object_id = &determine_object_id($nthash->{133},"NULL",'contactgroup');
	my $objecttype_id = &determine_objecttype_id($nthash->{133},"NULL");
	$nagios_objects_activate_sth->execute($instance_id,$objecttype_id,$contactgroup_object_id);
	$contactgroupdefinition_contactgroup_sth->execute($instance_id,$object_config_type,$contactgroup_object_id,"$nthash->{133}",
		$instance_id,$object_config_type,$contactgroup_object_id,"$nthash->{133}");
	my $contactgroup_id = &determine_insert_id($contactgroupdefinition_contactgroup_sth);
	if (defined($nthash->{132})) {
		if (ref ($nthash->{132}) eq "ARRAY" ) {
			my @contactgroupmembers = @{ $nthash->{132} };
			my @contact_object_ids;
        		foreach my $contactgroupmember (@contactgroupmembers) {
				my $contact_object_id = &determine_object_id($contactgroupmember,"NULL",'contact');
				$contactgroupdefinition_members_sth->execute($instance_id,$contactgroup_id,$contact_object_id,
					$instance_id,$contactgroup_id,$contact_object_id);
				push(@contact_object_ids, $contact_object_id);
			}
			@{ $contact_group_list_ref->{ $contactgroup_object_id } } = @contact_object_ids;
		} else {
			my $contact_object_id = &determine_object_id($nthash->{132},"NULL",'contact');
			$contactgroupdefinition_members_sth->execute($instance_id,$contactgroup_id,$contact_object_id,
				$instance_id,$contactgroup_id,$contact_object_id);
			$contact_group_list_ref->{ $contactgroup_object_id} = $contact_object_id;
		}
	}
	return;
}
# End of ndo_id 4XX series.

#################################################################################################################
#
# ndo_id
#
# 900: startconfigdump
# 901: endconfigdump
#
#################################################################################################################
# notes:
#	According to the dbhandler.h from NDO these are not implemented.
#	Opsview patched the endconfigdump ndo2db code to trigger ndoconfigend to populate some helper tables
#	Seems startconfigdump sets the object_config_type temporarily to 1 so we need to pick this up.
#	Could also use startconfigdump to see if we need INSERT or UPDATE queries (not sure on this though).

# Start of ndo_id 90X series
sub startconfigdump () {
	$object_config_type = 1;
	return($object_config_type);
}

sub endconfigdump () {
	$nthash = shift;
	my $file = "/usr/local/nagios/var/ndoconfigend/".$nthash->{4};
	`touch $file`;
	return;
}
# End of ndo_id 90X series

#################################################################################################################
sub not_implemented () {
	# use this subroutine for any event or ndo_id type that is not implemented in NDO2DB.
	return;
}

#################################################################################################################
#
# some general debugging stuff
# we need to remove this before unleashing the code on the world....

# Something to capture events we have not created routines for.
sub unknown_event_type () {
	$nthash = shift;
	my $event_type = $nthash->{1};
	open(LOG,">/home/alan/Opsview/perl2db/var/$event_type.log") or die "Can't create logfile: $!\n";
	print LOG Dumper (\$nthash);
	#print "Unknown event: $event_type logged for further analyses\n";
	close LOG;
	if (-e "/home/alan/Opsview/perl2db/var/$file") {
		# already saved a copy.
	} else {
		my $newfile = "/home/alan/Opsview/perl2db/var/$file";
		copy($file,$newfile) or die "Can't copy file: $!\n";
	}
	return;
}

sub unknown_ndo_id () {
        $nthash = shift;
        my $ndo_id = $nthash->{'ndo_id'};
	$ndo_id =~ s/\://;
        open(LOG,">/home/alan/Opsview/perl2db/var/$ndo_id.log") or die "Can't create logfile: $!\n";
        print LOG Dumper (\$nthash);
        #print "Unknown ndo_id: $ndo_id logged for further analyses\n";
        close LOG;
        if (-e "/home/alan/Opsview/perl2db/var/$file") {
                # already saved a copy.
        } else {
                my $newfile = "/home/alan/Opsview/perl2db/var/$file";
                copy($file,$newfile) or die "Can't copy file: $!\n";
        }
        return;
}

