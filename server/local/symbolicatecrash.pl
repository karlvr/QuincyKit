#!/usr/bin/perl -w
#
# This script parses a crashdump file and attempts to resolve addresses into function names.
#
# It finds symbol-rich binaries by:
#   a) searching in Spotlight to find .dSYM files by UUID, then finding the executable from there.
#       That finds the symbols for binaries that a developer has built with "DWARF with dSYM File".
#   b) searching in various SDK directories.
#
# Copyright (c) 2008-2015 Apple Inc. All Rights Reserved.
#
#

use strict;
use warnings;
use Getopt::Long;
use Cwd qw(realpath);
use List::MoreUtils qw(uniq);
use File::Basename qw(basename);
use File::Glob ':glob';
use Env qw(DEVELOPER_DIR);
use Config;
no warnings "portable";

require bigint;
if($Config{ivsize} < 8) {
    bigint->import(qw(hex));
}

#############################

# Forward definitons
sub usage();

#############################

# read and parse command line
my $opt_help = 0;
my $opt_verbose = 0;
my $opt_output = "-";
my @opt_dsyms = ();
my $opt_spotlight = 1;

Getopt::Long::Configure ("bundling");
GetOptions ("help|h"      => \$opt_help,
            "verbose|v"   => \$opt_verbose,
            "output|o=s"  => \$opt_output,
            "dsym|d=s"    => \@opt_dsyms,
            "spotlight!"  => \$opt_spotlight)
or die("Error in command line arguments\n");

usage() if $opt_help;

#############################

# have this thing to de-HTMLize Leopard-era plists
my %entity2char = (
    # Some normal chars that have special meaning in SGML context
    amp    => '&',  # ampersand 
    'gt'    => '>',  # greater than
    'lt'    => '<',  # less than
    quot   => '"',  # double quote
    apos   => "'",  # single quote
    );

#############################

if(!defined($DEVELOPER_DIR)) {
    die "Error: \"DEVELOPER_DIR\" is not defined";
}


# We will find these tools once we can guess the right SDK
my $otool = undef;
my $atos  = undef;
my $symbolstool = undef;
my $size  = undef;


#############################
# run the script

symbolicate_log(@ARGV);

exit 0;

#############################

# begin subroutines

sub HELP_MESSAGE() {
    usage();
}

sub usage() {
print STDERR <<EOF;
usage: 
    $0 [--help] [--dsym=DSYM] [--output OUTPUT_FILE] <LOGFILE> [SYMBOL_PATH ...]
    
    <LOGFILE>                   The crash log to be symbolicated. If "-", then the log will be read from stdin
    <SYMBOL_PATH>               Additional search paths in which to search for symbol rich binaries
    -o | --output <OUTPUT_FILE> The symbolicated log will be written to OUTPUT_FILE. Defaults to "-" (i.e. stdout) if not specified
    -d | --dsym <DSYM_BUNDLE>   Adds additional dSYM that will be consulted if and when a binary's UUID matches (may be specified more than once)
    -h | --help                 Display this help message
    -v | --verbose              Enables additional output
EOF
exit 1;
}

##############

sub getToolPath {
    my ($toolName, $sdkGuess) = @_;
    
    if (!defined($sdkGuess)) {
        $sdkGuess = "macosx";
    }
    
    my $toolPath = `'/usr/bin/xcrun' -sdk $sdkGuess -find $toolName`;
    if (!defined($toolPath) || $? != 0) {
        if ($sdkGuess eq "macosx") {
            die "Error: can't find tool named '$toolName' in the $sdkGuess SDK or any fallback SDKs";
        } elsif ($sdkGuess eq "iphoneos") {
            print STDERR "## Warning: can't find tool named '$toolName' in iOS SDK, falling back to searching the Mac OS X SDK\n";
            return getToolPath($toolName, "macosx");
        } else {
            print STDERR "## Warning: can't find tool named '$toolName' in the $sdkGuess SDK, falling back to searching the iOS SDK\n";
            return getToolPath($toolName, "iphoneos");
        }
    }
    
    chomp $toolPath;
    print STDERR "$toolName path is '$toolPath'\n" if $opt_verbose;
    
    return $toolPath;
}

##############

sub getSymbolDirPaths {
    my ($hwModel, $osVersion, $osBuild) = @_;
    
    print STDERR "(\$hwModel, \$osVersion, \$osBuild) = ($hwModel, $osVersion, $osBuild)\n" if $opt_verbose;
    
    my $versionPattern = "{$hwModel $osVersion ($osBuild),$osVersion ($osBuild),$osVersion,$osBuild}";
    #my $versionPattern  = '*';
    print STDERR "\$versionPattern = $versionPattern\n" if $opt_verbose;
    
    my @result = grep { -e && -d } bsd_glob('{/System,,~}/Library/Developer/Xcode/*DeviceSupport/'.$versionPattern.'/Symbols*', GLOB_BRACE | GLOB_TILDE);
    
    foreach my $foundPath (`mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode' || kMDItemCFBundleIdentifier == 'com.apple.Xcode'"`) {
        chomp $foundPath;
        my @pathResults = grep { -e && -d && !/Simulator/ }  bsd_glob($foundPath.'/Contents/Developer/Platforms/*.platform/DeviceSupport/'.$versionPattern.'/Symbols*/');
        push(@result, @pathResults);
    }
    
    print STDERR "Symbol directory paths:  @result\n" if $opt_verbose;
    return @result;
}

sub getSymbolPathAndArchFor_searchpaths {
    my ($bin,$path,$build,$uuid,@extra_search_paths) = @_;
    my @results;
    
    if (! (defined $bin && length($bin)) && !(defined $path && length($path)) ) {
        return undef;
    }
    
    for my $item (@extra_search_paths) {
        my $glob = "$item" . "{";
        if (defined $bin && length($bin)) {
            $glob .= "$bin,*/$bin,";
        }
        if (defined $path && length($path)) {
            $glob .= "$path,";
        }
        $glob .= "}*";
        #print STDERR "\nSearching pattern: [$glob]...\n" if $opt_verbose;
        push(@results, grep { -e && (! -d) } bsd_glob ($glob, GLOB_BRACE));
    }
    
    for my $out_path (@results) {
        my $arch = archForUUID($out_path, $uuid);
        if (defined($arch) && length($arch)) {
            return ($out_path, $arch);
        }
    }
    
    return undef;
}

sub getSymbolPathFor_uuid{
    my ($uuid, $uuidsPath) = @_;
    $uuid or return undef;
    $uuid =~ /(.{4})(.{4})(.{4})(.{4})(.{4})(.{4})(.{8})/;
    return Cwd::realpath("$uuidsPath/$1/$2/$3/$4/$5/$6/$7");
}

# Convert a uuid from the canonical format, like "C42A118D-722D-2625-F235-7463535854FD",
# to crash log format like "c42a118d722d2625f2357463535854fd".
sub getCrashLogUUIDForCanonicalUUID{
    my ($uuid) = @_;

    $uuid = lc($uuid);
    $uuid =~ s/\-//g;

    return $uuid;
}

# Convert a uuid from the crash log, like "c42a118d722d2625f2357463535854fd",
# to canonical format like "C42A118D-722D-2625-F235-7463535854FD".
sub getCanonicalUUIDForCrashLogUUID{
    my ($uuid) = @_;
    
    my $cononical_uuid = uc($uuid);    # uuid's in Spotlight database and from other tools are all uppercase
    $cononical_uuid =~ /(.{8})(.{4})(.{4})(.{4})(.{12})/;
    $cononical_uuid = "$1-$2-$3-$4-$5";
    
    return $cononical_uuid;
}


# Look up a dsym file by UUID in Spotlight, then find the executable from the dsym.
sub getSymbolPathAndArchFor_dsymUuid{
    my ($uuid) = @_;
    $uuid or return undef;
    
    # Convert a uuid from the crash log, like "c42a118d722d2625f2357463535854fd",
    # to canonical format like "C42A118D-722D-2625-F235-7463535854FD".
    my $canonical_uuid = getCanonicalUUIDForCrashLogUUID($uuid);
    
    # Do the search in Spotlight.
    my $cmd = "mdfind \"com_apple_xcode_dsym_uuids == $canonical_uuid\"";
    print STDERR "Running $cmd\n" if $opt_verbose;
    
    my @dsym_paths    = ();
    my @archive_paths = ();
    
    foreach my $dsymdir (split(/\n/, `$cmd`)) {
        $cmd = "mdls -name com_apple_xcode_dsym_paths ".quotemeta($dsymdir);
        print STDERR "Running $cmd\n" if $opt_verbose;
        
        my $com_apple_xcode_dsym_paths = `$cmd`;
        $com_apple_xcode_dsym_paths =~ s/^com_apple_xcode_dsym_paths\ \= \(\n//;
        $com_apple_xcode_dsym_paths =~ s/\n\)//;
        
        my @subpaths = split(/,\n/, $com_apple_xcode_dsym_paths);
        map(s/^[[:space:]]*\"//, @subpaths);
        map(s/\"[[:space:]]*$//, @subpaths);
        
        push(@dsym_paths, map($dsymdir."/".$_, @subpaths));
        
        if($dsymdir =~ m/\.xcarchive$/) {
            push(@archive_paths, $dsymdir);
        }
    }
    
    @dsym_paths = uniq(@dsym_paths);
    
    if ( @dsym_paths >= 1 ) {
        foreach my $dsym_path (@dsym_paths) {
            my $arch = archForUUID($dsym_path, $uuid);
            if (defined($arch) && length($arch)) {
                print STDERR "Found dSYM $dsym_path ($arch)\n" if $opt_verbose;
                return ($dsym_path, $arch);
            }
        }
    }
    
    print STDERR "Did not find dsym for $uuid\n" if $opt_verbose;
    return undef;
}

#########

sub archForUUID {  
    my ($path, $uuid) = @_;
    
    if ( ! -f $path ) {
        print STDERR "## $path doesn't exist \n" if $opt_verbose;
        return undef;
    }
    
    my $cmd;
    
    
    $cmd = "/usr/bin/file '$path'";
    print STDERR "Running $cmd\n" if $opt_verbose;
    my $file_result = `$cmd`;
    my $is_dsym = index($file_result, "dSYM companion file") >= 0;
    
    my $canonical_uuid = getCanonicalUUIDForCrashLogUUID($uuid);
    my $architectures = "armv[4-8][tfsk]?|arm64|i386|x86_64\\S?";
    my $arch;

    $cmd = "'$symbolstool' -uuid '$path'";
    print STDERR "Running $cmd\n" if $opt_verbose;
    
    my $symbols_result = `$cmd`;
    if($symbols_result =~ /$canonical_uuid\s+($architectures)/) {
        $arch = $1;
        print STDERR "## $path contains $uuid ($arch)\n" if $opt_verbose;
    } else {
        print STDERR "## $path doesn't contain $uuid\n" if $opt_verbose;
        return undef;
    }
    
    $cmd = "'$otool' -arch $arch -l '$path'";
    
    print STDERR "Running $cmd\n" if $opt_verbose;
    
    my $TEST_uuid = `$cmd`;
    if ( $TEST_uuid =~ /uuid ((0x[0-9A-Fa-f]{2}\s+?){16})/ || $TEST_uuid =~ /uuid ([^\s]+)\s/ ) {
        my $test = $1;
        
        if ( $test =~ /^0x/ ) {
            # old style 0xnn 0xnn 0xnn ... on two lines
            $test =  join("", split /\s*0x/, $test);
            
            $test =~ s/0x//g;     ## remove 0x
            $test =~ s/\s//g;     ## remove spaces
        } else {
            # new style XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
            $test =~ s/-//g;     ## remove -
            $test = lc($test);
        }
        
        if ( $test eq $uuid ) {
            
            if ( $is_dsym ) {
                return $arch;
            } else {
                ## See that it isn't stripped.  Even fully stripped apps have one symbol, so ensure that there is more than one.
                my ($nlocalsym) = $TEST_uuid =~ /nlocalsym\s+([0-9A-Fa-f]+)/;
                my ($nextdefsym) = $TEST_uuid =~ /nextdefsym\s+([0-9A-Fa-f]+)/;
                my $totalsym = $nextdefsym + $nlocalsym;
                print STDERR "\nNumber of symbols in $path: $nextdefsym + $nlocalsym = $totalsym\n" if $opt_verbose;
                return $arch if ( $totalsym > 1 );
                    
                print STDERR "## $path appears to be stripped, skipping.\n" if $opt_verbose;
            }
        } else {
            print STDERR "Given UUID $uuid for '$path' is really UUID $test\n" if $opt_verbose;
        }
    } else {
        print STDERR "Can't understand the output from otool ($TEST_uuid -> $cmd)\n";
        return undef;
    }

    return undef;
}

sub getSymbolPathAndArchFor_manualDSYM {
    my ($uuid) = @_;
    my @dsym_machos = ();
    
    for my $dsym_path (@opt_dsyms) {
        if( -d $dsym_path ) {
            #test_path is a directory, assume it's a dSYM bundle and find the mach-o file(s) within
            push @dsym_machos, bsd_glob("$dsym_path/Contents/Resources/DWARF/*");
            next;
        }
        
        if ( -f $dsym_path ) {
            #test_path is a file, assume it's a dSYM macho file
            push @dsym_machos, $dsym_path;
            next;
        }
    }
    
    #Check the uuid's of each of the found files
    for my $macho_path (@dsym_machos) {
        
        print STDERR "Checking “$macho_path”\n";
        
        my $arch = archForUUID($macho_path, $uuid);
        if (defined($arch) && length($arch)) {
            print STDERR "$macho_path matches $uuid ($arch)\n";
            return ($macho_path, $arch);
        } else {
            print STDERR "$macho_path does not match $uuid\n";
        }
    }
    
    return undef;
}

sub getSymbolPathAndArchFor {
    my ($path,$build,$uuid,@extra_search_paths) = @_;
    
    # derive a few more parameters...
    my $bin = ($path =~ /^.*?([^\/]+)$/)[0]; # basename
    
    # Look in any of the manually-passed dSYMs
    if( @opt_dsyms ) {
        print STDERR "-- [$uuid] CHECK (manual)\n"  if $opt_verbose;
        my ($out_path, $arch) = getSymbolPathAndArchFor_manualDSYM($uuid);
        if(defined($out_path) && length($out_path) && defined($arch) && length($arch)) {
            print STDERR "-- [$uuid] MATCH (manual): $out_path ($arch)\n"  if $opt_verbose;
            return ($out_path, $arch);
        }
        print STDERR "-- [$uuid] NO MATCH (manual)\n\n"  if $opt_verbose;
    }
    
    # Look for a UUID match in the cache directory
    my $uuidsPath = "/Volumes/Build/UUIDToSymbolMap";
    if ( -d $uuidsPath ) {
        print STDERR "-- [$uuid] CHECK (uuid cache)\n"  if $opt_verbose;
        my $out_path = getSymbolPathFor_uuid($uuid, $uuidsPath);
        if(defined($out_path) && length($out_path)) {
            my $arch = archForUUID($out_path, $uuid);
            if (defined($arch) && length($arch)) {
                print STDERR "-- [$uuid] MATCH (uuid cache): $out_path ($arch)\n"  if $opt_verbose;
                return ($out_path, $arch);
            }
        }
        print STDERR "-- [$uuid] NO MATCH (uuid cache)\n\n"  if $opt_verbose;
    }
    
    # Look in the search paths (e.g. the device support directories)
    print STDERR "-- [$uuid] CHECK (device support)\n"  if $opt_verbose;
    for my $func ( \&getSymbolPathAndArchFor_searchpaths, ) {
        my ($out_path, $arch) = &$func($bin,$path,$build,$uuid,@extra_search_paths);
        if ( defined($out_path) && length($out_path) && defined($arch) && length($arch) ) {
            print STDERR "-- [$uuid] MATCH (device support): $out_path ($arch)\n"  if $opt_verbose;
            return ($out_path, $arch);
        }
    }
    print STDERR "-- [$uuid] NO MATCH (device support)\n\n"  if $opt_verbose;
    
    # Ask spotlight
    if( $opt_spotlight ) {
        print STDERR "-- [$uuid] CHECK (spotlight)\n"  if $opt_verbose;
        my ($out_path, $arch) = getSymbolPathAndArchFor_dsymUuid($uuid);
        
        if(defined($out_path) && length($out_path) && defined($arch) && length($arch)) {
            print STDERR "-- [$uuid] MATCH (spotlight): $out_path ($arch)\n"  if $opt_verbose;
            return ($out_path, $arch);
        }
        print STDERR "-- [$uuid] NO MATCH (spotlight)\n\n"  if $opt_verbose;
    }
    
    print STDERR "-- [$uuid] NO MATCH\n\n"  if $opt_verbose;
    
    print STDERR "## Warning: Can't find any unstripped binary that matches version of $path\n" if $opt_verbose;
    print STDERR "\n" if $opt_verbose;
    
    return undef;
}

###########################
# crashlog parsing
###########################

# options:
#  - regex: don't escape regex metas in name
#  - continuous: don't reset pos when done.
#  - multiline: expect content to be on many lines following name
#  - nocolon: when multiline, the header line does not contain a colon
sub parse_section {
    my ($log_ref, $name, %arg ) = @_;
    my $content;
    
    $name = quotemeta($name) 
    unless $arg{regex};
    
    my $colon = ':';
    if ($arg{nocolon}) {
        $colon = ''
    }
    
    # content is thing from name to end of line...
    if( $$log_ref =~ m{ ^($name)$colon [[:blank:]]* (.*?) $ }mgx ) {
        $content = $2;
        $name = $1;
        $name =~ s/^\s+//;
        
        # or thing after that line.
        if($arg{multiline}) {
            $content = $1 if( $$log_ref =~ m{ 
                \G\n    # from end of last thing...
                (.*?) 
                (?:\n\s*\n|$) # until next blank line or the end
            }sgx ); 
        }
    } 
    
    pos($$log_ref) = 0 
    unless $arg{continuous}; 
    
    return ($name,$content) if wantarray;
    return $content;
}

# convenience method over above
sub parse_sections {
    my ($log_ref,$re,%arg) = @_;
    
    my ($name,$content);
    my %sections = ();
    
    while(1) {
        ($name,$content) = parse_section($log_ref,$re, regex=>1,continuous=>1,%arg);
        last unless defined $content;
        $sections{$name} = $content;
    } 
    
    pos($$log_ref) = 0;
    return \%sections;
}

sub parse_threads {
    my ($log_ref,%arg) = @_;
    
    my $nocolon = 0;
    my $stack_delimeter = 'Thread\s+\d+\s?(Highlighted|Crashed)?'; # Crash reports
    
    if ($arg{event_type}) {
        # Spindump reports
        if ($arg{event_type} eq "cpu usage" ||
            $arg{event_type} eq "wakeups" ||
            $arg{event_type} eq "disk writes" ||
            $arg{event_type} eq "powerstats") {
            
            # Microstackshots report
            $stack_delimeter = 'Powerstats\sfor:.*';
            $nocolon = 1;
        } else {
            # Regular spindump
            $stack_delimeter = '\s+Thread\s+\S+(\s+DispatchQueue\s+\S+)?';
            $nocolon = 1;
        }
    }
    
    return parse_sections($log_ref,$stack_delimeter,multiline=>1,nocolon=>$nocolon)
}

sub parse_processes {
    my ($log_ref, $is_spindump_report, $event_type) = @_;
    
    if (! $is_spindump_report) {
        # Crash Reports only have one process
        return ($log_ref);
    }
    
    my $process_delimeter;
    
    if ($event_type eq "cpu usage" ||
        $event_type eq "wakeups" ||
        $event_type eq "disk writes" ||
        $event_type eq "powerstats") {
        
        # Microstackshots report
        $process_delimeter = '^Powerstats\s+for';
    } else {
        # Regular spindump
        $process_delimeter = '^Process';
    }
    
    return \split(/(?=$process_delimeter)/m, $$log_ref);
}

sub parse_images {
    my ($log_ref, $report_version, $is_spindump_report) = @_;
    
    my $section = parse_section($log_ref,'Binary Images Description',multiline=>1);
    if (!defined($section)) {
        $section = parse_section($log_ref,'\\s*Binary\\s*Images',multiline=>1,regex=>1); # new format
    }
    if (!defined($section)) {
        die "Error: Can't find \"Binary Images\" section in log file";
    }
    
    my @lines = split /\n/, $section;
    scalar @lines or die "Can't find binary images list: $$log_ref" if !$is_spindump_report;
    
    my %images = ();
    my ($pat, $app, %captures);
    
    #To get all the architectures for string matching.
    my $architectures = "armv[4-8][tfsk]?|arm64|i386|x86_64\\S?";
    
    # Once Perl 5.10 becomes the default in Mac OS X, named regexp 
    # capture buffers of the style (?<name>pattern) would make this 
    # code much more sane.
    if(! $is_spindump_report) {
        if($report_version == 102 || $report_version == 103) { # Leopard GM
            $pat = '
                ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )
                (\+)?                               (?# the application may have a + in front of the name [3] )
                (.+)                                (?# bundle name [4] )
                \s+ .+ \(.+\) \s*                   (?# the versions--generally "??? [???]" )
                \<?([[:xdigit:]]{32})?\>?           (?# possible UUID [5] )
                \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [6] )
                ';
            %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
            'bundlename' => \$4, 'uuid' => \$5, 'path' => \$6);
        }
        elsif($report_version == 104 || $report_version == 105) { # Kirkwood
            # 0x182155000 - 0x1824c6fff CoreFoundation arm64  <f0d21c6db8d83cf3a0c4712fd6e69a8e> /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
            $pat = '
            ^\s* (\w+) \s* \- \s* (\w+) \s*     (?# the range base and extent [1,2] )
            (\+)?                               (?# the application may have a + in front of the name [3] )
            (.+)                                (?# bundle name [4] )
            \s+ ('.$architectures.') \s+        (?# the image arch [5] )
            \<?([[:xdigit:]]{32})?\>?           (?# possible UUID [6] )
            \s* (\/.*)\s*$                      (?# first fwdslash to end we hope is path [7] )
            ';
            %captures = ( 'base' => \$1, 'extent' => \$2, 'plus' => \$3,
            'bundlename' => \$4, 'arch' => \$5, 'uuid' => \$6,
            'path' => \$7);
        }
        else {
            die "Unsupported crash log version: $report_version";
        }
    }
    else { # Spindump reports
        #       0x7fffa5f55000 -     0x7fffa63ddff7  com.apple.CoreFoundation 6.9 (1333.19) <08238AC4-4618-39AC-878B-B1562CD6B235> /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
        $pat = '
        ^                                   (?# Beginning of the line )
        \s* \*?                             (?# indent and kernel dot)
        (\S+) \s* \- \s* (\S+)              (?# the range base and extent [1,2] )
        \s+ (.+?)                           (?# bundle name [3] )
        (?: \s+ (\S+) )?                    (?# optional short version [4] )
        (?: \s+ \( (\S+) \) )?              (?# optional version [5] )
        \s+ \< ( .* ) \>                    (?# UUID [6] )
        (?: \s+ (\/.*) )?                   (?# optional path [7] )
        \s*$                                (?# End of the line )
        ';
        %captures = ( 'base' => \$1, 'extent' => \$2, 'bundleid' => \$3,
        'shortversion' => \$4, 'version' => \$5, 'uuid' => \$6,
        'path' => \$7);
    }
    
    for my $line (@lines) {
        next if $line =~ /PEF binary:/; # ignore these
        
        $line =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;
        
        if ($line =~ /$pat/ox) {
            
            # Dereference references
            my %image;
            while((my $key, my $val) = each(%captures)) {
                $image{$key} = ${$captures{$key}} || '';
                #print STDERR "image{$key} = $image{$key}\n";
            }
            
            if (defined $image{bundleid} && $image{bundleid} eq "???") {
                delete $image{bundleid};
            }
            
            if (! defined $image{bundlename}) {
                # (Only occurs in spindump)
                # Match what string frames will use as the binary's identifier
                if (defined $image{path} && $image{path} ne '') {
                    $image{bundlename} = ($image{path} =~ /^.*?([^\/]+)$/)[0]; # basename of path
                } elsif (defined $image{bundleid} && $image{bundleid} ne '') {
                    $image{bundlename} = $image{bundleid};
                } else {
                    $image{bundlename} = "<$image{uuid}>";
                }
            }
            
            if ($image{extent} eq "???") {
                $image{extent} = '';
            }
            
            # Spindump uses canonical UUID, but the rest of the code here expects CrashLog style UUIDs
            $image{uuid} = getCrashLogUUIDForCanonicalUUID($image{uuid});
            
            # Just take the first instance.  That tends to be the app.
            my $bundlename = $image{bundlename};
            $app = $bundlename if (!defined $app && defined $image{plus} && length $image{plus});
            
            # frameworks and apps (and whatever) may share the same name, so disambiguate
            if ( defined($images{$bundlename}) ) {
                # follow the chain of hash items until the end
                my $nextIDKey = $bundlename;
                while ( length($nextIDKey) ) {
                    last if ( !length($images{$nextIDKey}{nextID}) );
                    $nextIDKey = $images{$nextIDKey}{nextID};
                }
                
                # add ourselves to that chain
                $images{$nextIDKey}{nextID} = $image{base};
                
                # and store under the key we just recorded
                $bundlename = $bundlename . $image{base};
            }
            
            # we are the end of the nextID chain
            $image{nextID} = "";
            
            $images{$bundlename} = \%image;
        }
    }
    
    return (\%images, $app);
}

# if this is actually a partial binary identifier we know about, then
# return the full name. else return undef.
my %_partial_cache = ();
sub resolve_partial_id {
    my ($bundle,$images) = @_;
    # is this partial? note: also stripping elipsis here
    return undef unless $bundle =~ s/^\.\.\.//;
    return $_partial_cache{$bundle} if exists $_partial_cache{$bundle};
    
    my $re = qr/\Q$bundle\E$/;
    for (keys %$images) { 
        if( /$re/ ) { 
            $_partial_cache{$bundle} = $_;
            return $_;
        }
    }
    return undef;
}

sub fixup_last_exception_backtrace {
    my ($log_ref,$exception,$images) = @_;
    my $repl = $exception;
    if ($exception =~ m/^.0x/) {
        my @lines = split / /, substr($exception, 1, length($exception)-2);
        my $counter = 0;
        $repl = "";
        for my $line (@lines) {
            my ($image,$image_base) = findImageByAddress($images, $line);
            my $offset = hex($line) - hex($image_base);
            my $formattedTrace = sprintf("%-3d %-30s\t0x%08x %s + %d", $counter, $image, hex($line), $image_base, $offset);
            $repl .= $formattedTrace . "\n";
            ++$counter;
        }
        $log_ref = replace_chunk($log_ref, $exception, $repl);
        # may need to do this a second time since there could be First throw call stack too
        $log_ref = replace_chunk($log_ref, $exception, $repl);
    }
    return ($log_ref, $repl);
}

#sub parse_last_exception_backtrace {
#    print STDERR "Parsing last exception backtrace\n" if $opt_verbose;
#    my ($backtrace,$images, $inHex) = @_;
#    my @lines = split /\n/,$backtrace;
#    
#    my %frames = ();
#    
#    # these two have to be parallel; we'll lookup by hex, and replace decimal if needed
#    my @hexAddr;
#    my @replAddr;
#    
#    for my $line (@lines) {
#        # end once we're done with the frames
#        last if $line =~ /\)/;
#        last if !length($line);
#        
#        if ($inHex && $line =~ /0x([[:xdigit:]]+)/) {
#            push @hexAddr, sprintf("0x%08s", $1);
#            push @replAddr, "0x".$1;
#        }
#        elsif ($line =~ /(\d+)/) {
#            push @hexAddr, sprintf("0x%08x", $1);
#            push @replAddr, $1;
#        }
#    }
#    
#    # we don't have a hint as to the binary assignment of these frames
#    # map_addresses will do it for us
#    return map_addresses(\@hexAddr,$images,\@replAddr);
#}

# returns an oddly-constructed hash:
#  'string-to-replace' => { bundle=>..., address=>... }
sub parse_backtrace {
    my ($backtrace,$images,$decrement,$is_spindump_report) = @_;
    my @lines = split /\n/,$backtrace;
    
    my %frames = ();
    
    if ( ! $is_spindump_report ) {
        # Crash report
        
        my $is_first = 1;
        
        for my $line (@lines) {
            if( $line =~ m{
                ^\d+ \s+                   # stack frame number
                (\S.*?) \s+                # bundle [1]
                (                          # description to replace [2]
                    (0x\w+) \s+            # address [3]
                    0x\w+ \s+              # library address
                    (?: \+ \s+ (\d+))?     # offset [4], optional
                    .*                     # remainder of description
                )                          # end of capture
                \s*                        # new line
                $                          # end of line
            }x ) {
                my($bundle,$replace,$address,$offset) = ($1,$2,$3,$4);
                #print STDERR "Parse_bt: $bundle,$replace,$address\n" if ($opt_verbose);
                
                # disambiguate within our hash of binaries
                $bundle = findImageByNameAndAddress($images, $bundle, $address);
                
                # skip unless we know about the image of this frame
                next unless
                $$images{$bundle} or
                $bundle = resolve_partial_id($bundle,$images);
                
                my $raw_address = $address;
                if($decrement && !$is_first) {
                    $address = sprintf("0x%X", (hex($address) & ~1) - 1);
                }
                
                $frames{$replace} = {
                    'address' => $address,
                    'raw_address' => $raw_address,
                    'bundle'  => $bundle,
                };
                
                if (defined $offset) {
                    $frames{$replace}{offset} = $offset
                }
                
                $is_first   = 0;
            }
            #        else { print STDERR "unable to parse backtrace line $line\n" }
        }
        
    } else {
        # Spindump report

        my $previousFrame;
        my $previousIndentLength;
        
        for my $line (@lines) {
            #       *138  unix_syscall64 + 675 (systemcalls.c:376,10 in kernel.development + 6211555) [0xffffff80007ec7e3] 1-138
            if( $line =~ m{
                ^                               # Start of line
                ( \s* \*? )                     # indent and kernel dot [1]
                ( \d+ ) \s+                     # count [2]
                (                               # Start of string to replace (symbol, binary, address) [3]
                    ( .+? )                       # symbol [4]
                    (?: \s* \+ \s* (\d+) )?       # offset from symbol [5], optional
                    (?: \s+ \(                    # Start of binary info, entire section optional
                        (?: ( .*? ) \s+ in \s+ )?   # source info [6], optional
                        (.+?)                       # Binary name (or UUID, if no name) [7]
                        (?: \s* \+ \s* (\d+) )?     # Offset in binary [8], optional
                    \) )?                         # End of binary info, entire section optional
                    \s* \[ (.+) \]                # address [9]
                )                               # End of string to replace
                (?: \s+ \(.*\) )?               # state [10], optional
                (?: \s+                         # Start of timeline info, entire section optional
                    (\d+)                         # Start time index [11]
                    (?: \s* \- \s* (\d+))?        # End time index [12], optional
                )?                              # End of timeline info, entire section optional
                $                               # End of line
            }x ) {
                my($indent,$count,$replace,$symbol,$offsetInSymbol,$sourceInfo,$binaryName,$offsetInBinary,$address,$state,$timeIndexStart,$timeIndexEnd) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);
                # print STDERR "Parse_bt $line:\n$indent,$count,$symbol,$offsetInSymbol,$sourceInfo,$binaryName,$offsetInBinary,$address,$timeIndexStart,$timeIndexEnd\n" if ($opt_verbose);
                
                next if defined $sourceInfo; # Don't bother trying to sybolicate frames that already have source info
                
                next unless defined $binaryName;
                
                # disambiguate within our hash of binaries
                my $binaryKey = findImageByNameAndAddress($images, $binaryName, $address);
                
                # skip unless we know about the image of this frame
                next unless
                $$images{$binaryName};
                
                $frames{$replace} = {
                    'address' => $address, # To be fixed up for non-leaf frames in the next loop
                    'raw_address' => $address,
                    'bundle'  => $binaryKey,
                };
                
                # Fixed up symbolication address the non-leaf previous frame
                if (defined $previousFrame && defined $previousIndentLength &&
                    length $indent > $previousIndentLength) {
                        
                        $$previousFrame{'address'} = sprintf("0x%X", (hex($$previousFrame{'address'}) & ~1) - 1);
                        
                        # print STDERR "Updated symbolication address: $$previousFrame{'raw_address'} -> $$previousFrame{'address'}\n";
                    }
                $previousIndentLength = length $indent;
                $previousFrame = $frames{$replace};
            }
            # else { print STDERR "unable to parse backtrace line $line\n" }
        }
        
        
    }
    
    return \%frames;
}

sub slurp_file {
    my ($file) = @_;
    my $data;
    my $fh;
    my $readingFromStdin = 0;
    
    local $/ = undef;
    
    # - or "" mean read from stdin, otherwise use the given filename
    if($file && $file ne '-') {
        open $fh,"<",$file or die "while reading $file, $! : ";
    } else {
        open $fh,"<&STDIN" or die "while readin STDIN, $! : ";
        $readingFromStdin = 1;
    }
    
    $data = <$fh>;
    
    
    # Replace DOS-style line endings
    $data =~ s/\r\n/\n/g;
    
    # Replace Mac-style line endings
    $data =~ s/\r/\n/g;
    
    # Replace "NO-BREAK SPACE" (these often get inserted when copying from Safari)
    # \xC2\xA0 == U+00A0
    $data =~ s/\xc2\xa0/ /g;
    
    close $fh or die $!;
    return \$data;
}

sub parse_OSVersion {
    my ($log_ref) = @_;
    my $section = parse_section($log_ref,'OS Version');
    if ( $section =~ /\s([0-9\.]+)\s+\(Build (\w+)/ ) {
        return ($1, $2)
    }
    if ( $section =~ /\s([0-9\.]+)\s+\((\w+)/ ) {
        return ($1, $2)
    }
    if ( $section =~ /\s([0-9\.]+)/ ) {
        return ($1, "")
    }
    die "Error: can't parse OS Version string $section";
}

sub parse_HardwareModel {
    my ($log_ref) = @_;
    my $model = parse_section($log_ref, 'Hardware Model');
    if (!defined($model)) {
        $model = parse_section($log_ref, 'Hardware model'); # spindump format
    }
    
    $model or return undef;
    # HACK: replace the comma in model names because bsd_glob can't handle commas (even escaped ones) in
    # the {} groups
    $model =~ s/,/\?/g;
    $model =~ /(\S+)/;
    return $1;
}

sub parse_SDKGuess {
    my ($log_ref) = @_;
    
    # It turns out that most SDKs are named "lowercased(HardwareModelWithoutNumbers) + os",
    # so attempt to form a valid SDK name from that. Any code that uses this must NOT rely
    # on this guess being accurate and should fallback to whatever logic makes sense for the situation
    my $model = parse_HardwareModel($log_ref);
    $model or return undef;
    
    $model =~ /(\D+)\d/;
    $1 or return undef;
    
    my $sdk = lc($1) . "os";
    if($sdk eq "ipodos" || $sdk eq "ipados") {
        $sdk = "iphoneos";
    }
    if ( $sdk =~ /mac/) {
        $sdk = "macosx";
    }
    
    return $sdk;
}

sub parse_event_type {
    my ($log_ref) = @_;
    my $event = parse_section($log_ref,'Event');
    return $event;
}

sub parse_steps {
    my ($log_ref) = @_;
    my $steps = parse_section($log_ref,'Steps');
    $steps or return undef;
    $steps =~ /(\d+)/;
    return $1;
}

sub parse_report_version {
    my ($log_ref) = @_;
    my $version = parse_section($log_ref,'Report Version');
    $version or return undef;
    $version =~ /(\d+)/;
    return $1;
}
sub findImageByAddress {
    my ($images,$address) = @_;
    my $image;
    
    for $image (values %$images) {
        if ( hex($address) >= hex($$image{base}) && hex($address) <= hex($$image{extent}) )
        {
            return ($$image{bundlename},$$image{base});
        }
    }
    
    print STDERR "Unable to map $address\n" if $opt_verbose;
    
    return undef;
}

sub findImageByNameAndAddress {
    my ($images,$bundle,$address) = @_;
    my $key = $bundle;
    
    #print STDERR "findImageByNameAndAddress($bundle,$address) ... ";
    
    my $binary = $$images{$bundle};
    
    while($$binary{nextID} && length($$binary{nextID}) ) {
        last if ( hex($address) >= hex($$binary{base}) && hex($address) <= hex($$binary{extent}) );
        
        $key = $key . $$binary{nextID};
        $binary = $$images{$key};
    }
    
    #print STDERR "$key\n";
    return $key;
}

sub prune_used_images {
    my ($images,$bt) = @_;
    
    # make a list of images actually used in backtrace
    my $images_used = {};
    for(values %$bt) {
        #print STDERR "Pruning: $images, $$_{bundle}, $$_{address}\n" if ($opt_verbose);
        my $imagename = findImageByNameAndAddress($images, $$_{bundle}, $$_{address});
        $$images_used{$imagename} = $$images{$imagename};
    }
    
    # overwrite the incoming image list with that;
    %$images = %$images_used; 
}

# fetch symbolled binaries
#   array of binary image ranges and names
#   the OS build
#   the name of the crashed program
#    undef
#   array of possible directories to locate symboled files in
sub fetch_symbolled_binaries {
    our %uuid_cache; # Global cache of UUIDs we've already searched for

    print STDERR "Finding Symbols:\n" if $opt_verbose;
    
    my ($images,$build,$bundle,@extra_search_paths) = @_;
    
    # fetch paths to symbolled binaries. or ignore that lib if we can't
    # find it
    for my $b (keys %$images) {
        my $lib = $$images{$b};
        my $symbol;
        my $arch;
        
        if (defined $uuid_cache{$$lib{uuid}}) {
            ($symbol, $arch) = @{$uuid_cache{$$lib{uuid}}};
            if ( $symbol ) {
                $$lib{symbol} = $symbol;
                if ( ! (defined $$lib{arch} && length $$lib{arch}) ) {
                    if (defined $arch && length($arch)) {
                        print STDERR "Already found $b: @{$uuid_cache{$$lib{uuid}}}\n" if $opt_verbose;
                        $$lib{arch} = $arch;
                    } else {
                        print STDERR "Already checked and failed to find $b (found $symbol, nob can't determine arch)\n" if $opt_verbose;
                        delete $$images{$b};
                        next;
                    }
                } else {
                    print STDERR "Already found $b: @{$uuid_cache{$$lib{uuid}}}\n" if $opt_verbose;
                }
            } else {
                print STDERR "Already checked and failed to find $b\n" if $opt_verbose;
                delete $$images{$b};
                next;
            }
        } else {
            
            
            print STDERR "-- [$$lib{uuid}] fetching symbol file for $b\n" if $opt_verbose;
            
            $symbol = $$lib{symbol};
            if ($symbol) {
                print STDERR "-- [$$lib{uuid}] found in cache\n" if $opt_verbose;
            } else {
                ($symbol, $arch) = getSymbolPathAndArchFor($$lib{path},$build,$$lib{uuid},@extra_search_paths);
                @{$uuid_cache{$$lib{uuid}}} = ($symbol, $arch);
                if ( $symbol ) {
                    $$lib{symbol} = $symbol;
                    if ( ! (defined $$lib{arch} && length $$lib{arch}) ) {
                        if (defined $arch && length($arch)) {
                            print STDERR "Set $$lib{uuid} to $arch\n" if $opt_verbose;
                            $$lib{arch} = $arch;
                        } else {
                            delete $$images{$b};
                            next;
                        }
                    }
                } else {
                    delete $$images{$b};
                    next;
                }
            }
        }
        
        # check for sliding. set slide offset if so
        open my($ph),"-|", "'$size' -m -l -x '$symbol'" or die $!;
        my $real_base = (
        grep { $_ }
        map { (/_TEXT.*vmaddr\s+(\w+)/)[0] } <$ph>
        )[0];
        close $ph;
        if ($?) {
            
            # <rdar://problem/21493669> 13T5280f: My crash logs aren't symbolicating
            # System libraries were not being symbolicated because /usr/bin/size is always failing.
            # That's <rdar://problem/21604022> /usr/bin/size doesn't like LC_SEGMENT_SPLIT_INFO command 12
            #
            # Until that's fixed, just hope for the best and assume no sliding. I've been informed that since
            # this scripts always deals with post-mortem crash files instead of running processes, sliding shouldn't
            # happen in practice. Nevertheless, we should probably add this sanity check back in once we 21604022
            # gets resolved.
            $real_base = $$lib{base}
            
            # call to size failed.  Don't use this image in symbolication; don't die
            # delete $$images{$b};
            #print STDERR "Error in symbol file for $symbol\n"; # and log it
            # next;
        }
        
        if($$lib{base} ne $real_base) {
            $$lib{slide} =  hex($real_base) - hex($$lib{base});
        }
    }
    
    print STDERR keys(%$images) . " binary images were found.\n" if $opt_verbose;
}

# run atos
sub symbolize_frames {
    my ($images,$bt,$is_spindump_report) = @_;
    
    # create mapping of framework => address => bt frame (adjust for slid)
    # and for framework => arch
    my %frames_to_lookup = ();
    my %arch_map = ();
    my %base_map = ();
    my %image_map = ();
    
    for my $k (keys %$bt) {
        my $frame = $$bt{$k};
        my $lib = $$images{$$frame{bundle}};
        unless($lib) {
            # don't know about it, can't symbol
            # should have already been warned about this!
            # print STDERR "Skipping unknown $$frame{bundle}\n";
            delete $$bt{$k};
            next;
        }
        
        # list of address to lookup, mapped to the frame object, for
        # each library
        $frames_to_lookup{$$lib{symbol}}{$$frame{address}} = $frame;
        $arch_map{$$lib{symbol}} = $$lib{arch};
        $base_map{$$lib{symbol}} = $$lib{base};
        $image_map{$$lib{symbol}} = $lib;
    }
    
    # run atos for each library
    while(my($symbol,$frames) = each(%frames_to_lookup)) {
        # escape the symbol path if it contains single quotes
        my $escapedSymbol = $symbol;
        $escapedSymbol =~ s/\'/\'\\'\'/g;
        
        # run atos with the addresses and binary files we just gathered
        my $arch = $arch_map{$symbol};
        my $base = $base_map{$symbol};
        my $lib = $image_map{$symbol};
        my $cmd = "'$atos' -arch $arch -l $base -o '$escapedSymbol' @{[ keys %$frames ]} | ";
        
        print STDERR "Running $cmd\n" if $opt_verbose;
        
        open my($ph),$cmd or die $!;
        my @symbolled_frames = map { chomp; $_ } <$ph>;
        close $ph or die $!;
        
        my $references = 0;
        
        foreach my $symbolled_frame (@symbolled_frames) {
            
            my ($library, $source) = ($symbolled_frame =~ /\s*\(in (.*?)\)(?:\s*\((.*?)\))?/);
            $symbolled_frame =~ s/\s*\(in .*?\)//; # clean up -- don't need to repeat the lib here
            
            if ($is_spindump_report) {
                # Source is formatted differently for spindump
                $symbolled_frame =~ s/\s*\(.*?\)//; # remove source info from symbol string
                
                # Spindump may not have had library names, pick them up here
                if (defined $library && !(defined $$lib{path} && length($$lib{path})) && !(defined $$lib{new_path} && length($$lib{new_path})) ) {
                    $$lib{new_path} = $library;
                    print STDERR "Found new name for $$lib{uuid}: $$lib{new_path}\n" if ( $opt_verbose );
                }
            }
            
            
            # find the correct frame -- the order should match since we got the address list with keys
            my ($k,$frame) = each(%$frames);
            
            if ( $symbolled_frame !~ /^\d/ ) {
                # only symbolicate if we fetched something other than an address
                
                my $offset = $$frame{offset};
                if (defined $offset) {
                    # add offset from unsymbolicated frame after symbolicated name
                    $symbolled_frame =~ s|(.+)\(|$1."+ ".$offset." ("|e;
                }
                
                if ($is_spindump_report) {
                    # Spindump formatting
                    if (defined $library) {
                        $symbolled_frame .= " (";
                        if (defined $source) {
                            $symbolled_frame .= "$source in ";
                        }
                        $symbolled_frame .= "$library + " . (hex($$frame{raw_address}) - hex($base)) . ")";
                    }
                    $symbolled_frame .= " [$$frame{raw_address}]";
                }
                
                $$frame{symbolled} = $symbolled_frame;
                $references++;
            }
            
        }
        
        if ( $references == 0 ) {
            if ( ! $is_spindump_report) { # Bad addresses aren't uncommon in microstackshots and stackshots
                print STDERR "## Warning: Unable to symbolicate from required binary: $symbol\n";
            }
        }
    }
    
    # just run through and remove elements for which we didn't find a
    # new mapping:
    while(my($k,$v) = each(%$bt)) {
        delete $$bt{$k} unless defined $$v{symbolled};
    }
}

# run the final regex to symbolize the log
sub replace_symbolized_frames {
    my ($log_ref,$bt,$images,$is_spindump_report)  = @_;
    my $re = join "|" , map { quotemeta } keys %$bt;
    
    # spindump's symbolled string already includes the raw address
    my $log = $$log_ref;
    $log =~ s#$re#
    my $frame = $$bt{$&};
    (! $is_spindump_report ? $$frame{raw_address} . " " : "") . $$frame{symbolled};
    #esg;
    
    $log =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;
    
    
    if ($is_spindump_report) {
        # Spindump may not have image names, so add any names we found
        
        my @images_to_replace_keys = grep { defined $$images{$_}{new_path} } keys %$images;
        
        if (scalar(@images_to_replace_keys)) {
            
            print STDERR "" . scalar(@images_to_replace_keys) . " images with new names:\n" if ( $opt_verbose );
            if ( $opt_verbose ) { print STDERR "$_\n" for @images_to_replace_keys; }
            
            # First, replace in frames that we couldn't symbolicate
            # 2  ??? (<C1C37AEF-7DA2-38E5-88BA-664E2625478F> + 196600) [0x1051e3ff8]
            # becomes
            # 2  ??? (BackBoard + 196600) [0x1051e3ff8]
            my $image_re = join "|" , map { quotemeta } @images_to_replace_keys;
            $image_re = "\\(($image_re)"; # Open paren precedes UUID in frames

            $log =~ s#$image_re#
            "(" . $$images{$1}{new_path}
            #esg;
            
            $log =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;

            # Second, replace in image infos
            # 0x1051b4000 -                ???  ??? <C1C37AEF-7DA2-38E5-88BA-664E2625478F>
            # becomes
            # 0x1051b4000 -                ???  ??? <C1C37AEF-7DA2-38E5-88BA-664E2625478F>  BackBoard
            $image_re = join "|" , map { quotemeta } @images_to_replace_keys;
            $image_re = "\\s($image_re)"; # Whitespace precedes image infos
            
            $log =~ s#$image_re#
            "$&  " . $$images{$1}{new_path}
            #esg;
            
            $log =~ s/(&(\w+);?)/$entity2char{$2} || $1/eg;
            
        }
    }
    
    
    return \$log;
}

sub replace_chunk {
    my ($log_ref,$old,$new) = @_;
    my $log = $$log_ref;
    my $re = quotemeta $old;
    $log =~ s/$re/$new/;
    return \$log;
}

#############

sub output_log($) {
  my ($log_ref)  = @_;
  
  if($opt_output && $opt_output ne "-") {
    close STDOUT;
    open STDOUT, '>', $opt_output;
  }
  
  print $$log_ref;
}

#############

sub symbolicate_log {
    my ($file,@extra_search_paths) = @_;
    
    print STDERR "Symbolicating $file ...\n" if ( $opt_verbose && defined $file);
    print STDERR "Symbolicating stdin ...\n" if ( $opt_verbose && ! defined $file);
    
    my $log_ref = slurp_file($file);
    
    print STDERR length($$log_ref)." characters read.\n" if ( $opt_verbose );
    
    # get the version number
    my $report_version = parse_report_version($log_ref);
    $report_version or die "No crash report version in $file";
    
    # setup the tool paths we will need
    my $sdkGuess = parse_SDKGuess($log_ref);
    print STDERR "SDK guess for tool search is '$sdkGuess'\n" if $opt_verbose;
    $otool = getToolPath("otool", $sdkGuess);
    $atos  = getToolPath("atos", $sdkGuess);
    $symbolstool = getToolPath("symbols", $sdkGuess);
    $size  = getToolPath("size", $sdkGuess);
    
    # spindump-based reports will have an "Steps:" line.
    # ReportCrash-based reports will not
    my $steps = parse_steps($log_ref);
    my $is_spindump_report = defined $steps;
    
    my $event_type;
    if ($is_spindump_report) {
        
        # Spindump's format changes depending on the event (microstackshots vs regular spindump)
        $event_type = parse_event_type($log_ref);
        $event_type = $event_type || "manual";
        
        # Cut off spindump's binary format
        $$log_ref =~ s/Spindump binary format.*$//s;
    }
    
    # extract hardware model
    my $model = parse_HardwareModel($log_ref);
    print STDERR "Hardware Model $model\n" if $opt_verbose;
    
    # extract build
    my ($version, $build) = parse_OSVersion($log_ref);
    print STDERR "OS Version $version Build $build\n" if $opt_verbose;
    
    my @process_sections = parse_processes($log_ref, $is_spindump_report, $event_type);
    
    my $header;
    my $multiple_processes = 0;
    if (scalar(@process_sections) > 1) {
        # If we found multiple process sections, the first section is just the report's header
        $header = shift @process_sections;
        
        print STDERR "Found " . scalar(@process_sections) . " process sections\n" if $opt_verbose;
        $multiple_processes = 1;
    }
    
    my $symbolicated_something = 0;
    
    for my $process_section (@process_sections) {
        if ($multiple_processes) {
            print STDERR "Processing " . ($$process_section =~ /^.*:\s+(.*)/)[0] . "\n";
        }
        
        
        # read the binary images
        my ($images,$first_bundle) = parse_images($process_section, $report_version, $is_spindump_report);
        
        if ( $opt_verbose ) {
            print STDERR keys(%$images) . " binary images referenced:\n";
            foreach (keys(%$images)) {
                print STDERR $_;
                print STDERR "\t\t(";
                print STDERR $$images{$_}{path};
                print STDERR ")\n";
            }
            print STDERR "\n";
        }
        
        my $bt = {};
        my $threads = parse_threads($process_section,event_type=>$event_type);
        print STDERR "Num stacks found: " . scalar(keys %$threads) . "\n" if $opt_verbose;
        for my $thread (values %$threads) {
            # merge all of the frames from all backtraces into one
            # collection
            my $b = parse_backtrace($thread,$images,0,$is_spindump_report);
            @$bt{keys %$b} = values %$b;
        }
        
        my $exception = parse_section($process_section,'Last Exception Backtrace', multiline=>1);
        if (defined $exception) {
            ($process_section, $exception) = fixup_last_exception_backtrace($process_section, $exception, $images);
            #my $e = parse_last_exception_backtrace($exception, $images, 1);
            my $e = parse_backtrace($exception, $images,1,$is_spindump_report);
            
            # treat these frames in the same was as any thread
            @$bt{keys %$e} = values %$e;
        }
        
        # sort out just the images needed for this backtrace
        prune_used_images($images,$bt);
        if ( $opt_verbose ) {
            print STDERR keys(%$images) . " binary images remain after pruning:\n";
            foreach my $junk (keys(%$images)) {
                print STDERR $junk;
                print STDERR ", ";
            }
            print STDERR "\n";
        }
        
        @extra_search_paths = (@extra_search_paths, getSymbolDirPaths($model, $version, $build));
        fetch_symbolled_binaries($images,$build,$first_bundle,@extra_search_paths);
        
        # If we didn't get *any* symbolled binaries, just print out the original crash log.
        my $imageCount = keys(%$images);
        if ($imageCount == 0) {
            next;
        }
        
        # run atos
        symbolize_frames($images,$bt,$is_spindump_report);
        
        if(keys %$bt) {
            # run our fancy regex
            $process_section = replace_symbolized_frames($process_section,$bt,$images,$is_spindump_report);
            
            $symbolicated_something = 1;
        } else {
            # There were no symbols found, don't change the section
        }
    }
    
    if ($symbolicated_something) {
        if (defined $header) {
            output_log($header);
        }
        
        output_log($_) for @process_sections;
    } else {
        #There were no symbols found
        print STDERR "No symbolic information found\n";
        output_log($log_ref);
    }

}
