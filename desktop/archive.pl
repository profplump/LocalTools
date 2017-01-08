#!/usr/bin/perl 
use strict;
use warnings;

#------------------------------------------------------------
## @file archive.pl
#  @brief Archive email messages to keep mailbox sizes down
#  Puts the emails into folders by month

#-------------------------------------------------------------------------------
# Includes
#-------------------------------------------------------------------------------
use File::Basename;
use Mail::IMAPClient;
use Date::Parse;

# Runtime
my ($folder, $DAYS) = @ARGV;
if (!defined($folder) || length($folder) < 1) {
	$folder = 'INBOX';
}
if (!defined($DAYS) || length($DAYS) < 1) {
	$DAYS = 3;
}

# Select mode
my $ALL    = 0;
my $DEDUP  = 0;
my $DELETE = 0;
if (basename($0) =~ /DELETE/i) {
	$DELETE = 1;
}
if (basename($0) =~ /ALL/i) {
	$ALL = 1;
}
if (basename($0) =~ /DEDUP/i) {
	$ALL   = 1;
	$DEDUP = 1;
}

#-----------------------------------------------------------------------------------
# Globals
#-----------------------------------------------------------------------------------
my $USERNAME  = 'nope';
my $PASSWD    = 'nope';
my $SERVER    = 'nope.com';
my $PORT      = 993;
my $SSL       = 1;
my $DELIMITER = '/';
my $MINAGE    = $DAYS * 86400;
my $MAX_UIDS  = 100;
my $TIMEOUT   = 75;

# Debug
my $DEBUG = 0;
if ($ENV{'DEBUG'}) {
	$DEBUG = 1;
}

# Overrides
if ($ENV{'TIMEOUT'}) {
	$TIMEOUT = $ENV{'TIMEOUT'};
}
if ($ENV{'SERVER'}) {
	$SERVER = $ENV{'SERVER'};
}
if ($ENV{'USERNAME'}) {
	$USERNAME = $ENV{'USERNAME'};
}
if ($ENV{'PASSWD'}) {
	$PASSWD = $ENV{'PASSWD'};
}
if ($ENV{'PORT'}) {
	$PORT = $ENV{'PORT'};
}
if ($ENV{'DELIMITER'}) {
	$DELIMITER = $ENV{'DELIMITER'};
}
if ($ENV{'MAX_UIDS'}) {
	$MAX_UIDS = $ENV{'MAX_UIDS'};
}

# Construct search dates
my $date = time() - $MINAGE;

#---------------------------------------------------------------------
# Create the IMAP object and connect
#---------------------------------------------------------------------

# Basic IMAP client object
my $imap = Mail::IMAPClient->new()
  or die("Unable to create Mail::IMAPClient object\n");
$imap->Timeout($TIMEOUT);
$imap->Uid(1);
$imap->Debug($DEBUG);

# Configure all our runtime parameters
$imap->Server($SERVER);
$imap->Port($PORT);
$imap->User($USERNAME);
$imap->Password($PASSWD);
$imap->Ssl($SSL);

# Connect
$imap->connect()
  or die('Unable to connect: ' . $@ . "\n");

#---------------------------------------------------------------------
# Work
#---------------------------------------------------------------------

# We only want to peek
$imap->Peek(1);

# Select the inbox and clean it up
$imap->select($folder)
  or die("Unable to select folder: ${@}\n");
$imap->expunge();

# Get the list of all messages
my @uids = ();
if ($ALL) {
	@uids = $imap->messages();
} else {
	@uids = $imap->before($date);
}
if ($@) {
	die("Unable to fetch message list: ${@}\n");
}

#-----------------------------------------------------------------------------------
# Delete in groups
#-----------------------------------------------------------------------------------
if ($DELETE) {

	my $numIDs = scalar(@uids);
	for (my $i = 0 ; $i < $numIDs ; $i += $MAX_UIDS) {
		my $end = $i + $MAX_UIDS - 1;
		if ($end > $numIDs) {
			$end = $numIDs - 1;
		}
		my @subset = @uids[ $i .. $end ];
		$imap->delete_message(@subset)
		  or die("Could not set flag: ${@}\n");
		$imap->expunge();
	}

	#-----------------------------------------------------------------------------------
	# Dedup the whole set, but query individually
	#-----------------------------------------------------------------------------------
} elsif ($DEDUP) {

	my $count       = 0;
	my %seen_msgids = ();
	foreach my $uid (@uids) {
		my $msg_id = $imap->get_header($uid, 'Message-Id')
		  or die("Could not get header: ${@}\n");
		if ($seen_msgids{$msg_id}) {
			if ($imap->size($uid) != $imap->size($seen_msgids{$msg_id})) {
				next;
			} elsif ($imap->date($uid) ne $imap->date($seen_msgids{$msg_id})) {
				next;
			} elsif ($imap->get_header($uid, 'Subject') ne $imap->get_header($seen_msgids{$msg_id}, 'Subject')) {
				next;
			}

			$imap->delete_message($uid)
			  or die("Could not set flag: ${@}\n");
			$count++;
			if ($count > $MAX_UIDS) {
				$imap->expunge();
				$count = 0;
			}
		} else {
			$seen_msgids{$msg_id} = $uid;
		}
	}

	#-----------------------------------------------------------------------------------
	# Move individually
	#-----------------------------------------------------------------------------------
} else {
	my $count = 0;
	foreach my $uid (@uids) {

		# Limit each run to a managable number of items
		$count++;
		if ($count > $MAX_UIDS) {
			$imap->expunge();
			$count = 0;
		}

		# Fetch the message date
		my $msg_date = $imap->date($uid)
		  or warn("Unable to retrieve or parse date from message ${uid}: ${@}\n");

		# Assume non-parsable timestamps are "now"
		my $ts = str2time($msg_date);
		if ($ts < 1000000 || $ts > time()) {
			$ts = time();
		}

		# Move to $YEAR/$MONTH
		my (undef(), undef(), undef(), undef(), $month, $year) = localtime($ts);
		$month = sprintf('%02d', $month + 1);
		$year  = sprintf('%04d', $year + 1900);
		my $path = $folder;
		if (!($folder =~ /${DELIMITER}${year}(?:${DELIMITER}.*)?$/)) {
			$path .= $DELIMITER . $year;
		}
		if (!($folder =~ /${DELIMITER}${month}(?:${DELIMITER}.*)?$/)) {
			$path .= $DELIMITER . $month;
		}
		if ($path ne $folder) {
			$imap->move($path, $uid)
			  or die("Unable to move message ${uid}: ${@}\n");
		}
	}
}

# Cleanup
$imap->expunge();
$imap->close();
exit(0);
