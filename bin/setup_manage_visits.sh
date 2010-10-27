#!/bin/bash
#
# Purpose: to set up the local directories needed to transfer data to NCSA
#
# Usage: <program_name> -f config_file
#

# usage message
function usage {
   $ECHO "Usage: $PROG [-r] -f config_file"
   exit 1
}

function makedir {
   $ECHO "Making directory $1..."
   mkdir -p $1
}

function ensuredir {
   [ -d "$1" ] || makedir $1 || { errmsg "Failed to create $1"; exit 3; }
}

function errmsg {
   $ECHO ${PROG}: ${*} 1>&2
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
while getopts "hf:r" Option
do
    case $Option in
        f     ) cfgfile=$OPTARG;;
        r     ) doremdir=1;;
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

# make sure the parent of MANAGE_VISITS_VAR exists and is write-able
if [ -n "$MANAGE_VISITS_VAR" ]; then
  if [ ! -e "$MANAGE_VISITS_VAR" ]; then
    parent=`dirname $MANAGE_VISITS_VAR`
    if [ ! -d "$parent" -o ! -w "$parent" ]; then
        errmsg "Warning: Parent of \$MANAGE_VISITS_VAR, $MANAGE_VISITS_VAR," \
               "not a writable directory"
    fi
  elif [ ! -d "$MANAGE_VISITS_VAR" ]; then
    errmsg ${MANAGE_VISITS_VAR}: Warning: MANAGE_VISITS_VAR is not a directory
  elif [ ! -w "$MANAGE_VISITS_VAR" ]; then
    errmsg Warning: MANAGE_VISITS_VAR, ${MANAGE_VISITS_VAR}, is not writable \
           by $USER
  fi
fi

# create the local directories for transfering data
ensuredir $LOGDIR
ensuredir $LOCKDIR
ensuredir $TMPBASE
ensuredir $HDIR
ensuredir $TDIR

if [ -n "$doremdir" ]; then
    if [ -n "$REMOTE_MANAGE_VISITS_VAR" ]; then 
        if [ ! -e "$REMOTE_MANAGE_VISITS_VAR" ]; then 
            parent=`dirname $REMOTE_MANAGE_VISITS_VAR`
            if [ ! -d "$parent" -o ! -w "$parent" ]; then
                errmsg "Warning: Parent of \$REMOTE_MANAGE_VISITS_VAR," \
                       $REMOTE_MANAGE_VISITS_VAR, "not a writable directory"
            fi
        elif [ ! -d "$REMOTE_MANAGE_VISITS_VAR" ]; then 
            errmsg ${MANAGE_VISITS_VAR}: Warning: REMOTE_MANAGE_VISITS_VAR \
                   is not a directory
        elif [ ! -w "$REMOTE_MANAGE_VISITS_VAR" ]; then
            errmsg Warning: REMOTE_MANAGE_VISITS_VAR, \
                   ${REMOTE_MANAGE_VISITS_VAR}, is not writable by $USER
        fi
    fi

    ensuredir $REMOTE_LOGDIR
    ensuredir $DESTDIR
    ensuredir $FINALDIR
    ensuredir $FINALDIR/raw
    ensuredir $FINALDIR/eimage
fi

echo All directories are ready


