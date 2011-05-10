#!/bin/bash
#
# Purpose: to test the configuration of manage_visits.sh
#
# Usage: <program_name> -f config_file
#

# usage message
function usage {
   $ECHO "Usage: $PROG [-r] -f config_file"
   exit 1
}

function errmsg {
   $ECHO ${PROG}: ${*} 1>&2
}

function cancelled {
   errmsg "User cancelled (ssh key setup error?)"
   exit 2
}

function checkdir {
    $ECHO -n "  Checking $1..."
    if [ -d "$1" -a -w "$1" ]; then
        $ECHO OK
    else
        $ECHO FAILED: Not a directory with write access
        /bin/false
    fi
}

function checkremdir {
    $ECHO -n "  Checking remote $1..."
    if $SSHCMD $RUSER@$RHOST test -d "$1" -a -w "$1"; then
        $ECHO OK
    else
        $ECHO FAILED: Not a directory with write access
        /bin/false
    fi
}

ECHO=/bin/echo
PROGPATH=$0
PROG=${0##*/}
PID=$$
dir0=$PWD
set -u

# check for config file on command line
cfgfile=
doremdir=
while getopts "hf:" Option
do
    case $Option in
        f     ) cfgfile=$OPTARG;;
        h     ) usage;;
        *     ) /bin/echo "Unimplemented option chosen.";;   # Default.
    esac
done
shift $(($OPTIND - 1))

# read in and process the config file
if [ "XXX"$cfgfile != "XXX" ] && [ -s $cfgfile ]; then
    . $cfgfile
else
    errmsg "No config file given with -f"
    usage 1>&2
fi

trap cancelled INT

# local directories
$ECHO Checking local directories...
dirprob=
checkdir $LOGDIR  || dirprob=1
checkdir $LOCKDIR || dirprob=1
checkdir $TMPBASE || dirprob=1
checkdir $HDIR    || dirprob=1
checkdir $TDIR    || dirprob=1

# java setup
#
okay=
$ECHO -n Testing Java setup...
out=
if out=`$JRE_LOC -version 2>&1`; then
    $ECHO OK
    $ECHO "  Found" `$JRE_LOC -version 2>&1 | grep version`
    okay=1
else
    $ECHO FAILED
    errmsg "Java setup problem: $out"
fi 

# ssh
# 
$ECHO Testing ssh key setup...
$ECHO "  If" you are asked for a password, type Ctrl-C.
$ECHO -n ssh setup...
if ${SSHCMD} $RUSER@$RHOST /bin/true; then
    $ECHO OK
else
    $ECHO FAILED
    errmsg "Password-less ssh not working (keyfile problem?)"
    exit 3
fi

[ -z "$okay" ] && exit 2

# local FDT
#
okay=
$ECHO -n Testing local FDT...
if out=`${JRE_LOC} -jar $FDTLJAR -V`; then
    $ECHO OK
    okay=1
    $ECHO "  Using" $out
else
    $ECHO FAILED
    errmsg FDT failed: $out
fi

# remote directories
#
$ECHO Checking remote directories...
checkremdir $REMOTE_LOGDIR  || dirprob=1
checkremdir $DESTDIR        || dirprob=1
checkremdir $FINALDIR       || dirprob=1

# remote java
#
$ECHO -n Testing remote Java...
if out=`$SSHCMD $RUSER@$RHOST $JRE_REMOTE -version 2>&1`; then
    $ECHO OK
    $ECHO "  Found remote" `$SSHCMD $RUSER@$RHOST $JRE_REMOTE -version 2>&1 | grep version`
else
    $ECHO FAILED
    errmsg "Remote Java setup problem: $out"
    $ECHO " cmd: $SSHCMD $RUSER@$RHOST $JRE_REMOTE -version" 1>&2
    exit 5
fi 

[ -z "$okay" ] && exit 4

# remote FDT
#
$ECHO -n Testing local FDT...
if out=`$SSHCMD $RUSER@$RHOST $JRE_REMOTE -jar $FDTRJAR -V`; then
    $ECHO OK
    $ECHO "  Using remote" $out
else
    $ECHO FAILED
    errmsg Remote FDT failed: $out
    $ECHO " cmd: $SSHCMD $RUSER@$RHOST $JRE_REMOTE -jar $FDTRJAR -V" 1>&2
fi


[ -n "$dirprob" ] && exit 6

$ECHO
$ECHO All tests pass