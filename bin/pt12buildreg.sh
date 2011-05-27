#! /bin/bash
#
# set -x
trxroot=/lsst3/transfer/pt1_2
logdir=$trxroot/logs
# logdir=/tmp
archived=$trxroot/archived
ingested=$trxroot/ingested
max=20
maxiter=100
logfile=pt12buildreg.log
lockfile=pt12buildreg.lock
ingestfile=pt12buildreg-ingested.log
lssthome=/lsst/DC3/stacks/32bit/default
genreg=genInputRegistry.py

prog=`basename $0`
log=$logdir/$logfile
lock=$logdir/$lockfile
ingestlog=$logdir/$ingestfile
rotateconf=$logdir/$prog.rotate
rotated=

[ -w $logdir ] || {
    echo ${prog}: Unable to write to log directory: $logdir 1>&2
    exit 1
}
[ ! -e $log -o \( -w $log -a -f $log \) ] || {
    echo ${prog}: Unable to write to log file: $log 1>&2
    exit 1
}

function log {
    echo `date '+%Y-%m-%d %T'` ${prog}: $* >> $log
}

function complain {
    log $@
    echo $@ 1>&2
}

function lockapp {
    [ -e "$lock" ] && {
        [ ! -f "$lock" ] && {
            complain Lock file not a file: $lock
            exit 3
        }
        pid=`cat $lock | awk '{print $1}'`
        if { ps -ww $pid | tail -n +1 | grep -q $prog; }; then
            return 1
        else
            log Removing stale lock file 
            rm -f $lock
        fi
    }
    [ -f "$lock" ] || {
        echo $$ > "$lock"
    }
    return 0
}

function unlockapp {
    [ -f "$lock" ] && rm -f "$lock"
}

function setuplsst {
    [ -f "$lssthome/loadLSST.sh" ] || {
        complain Unable to load LSST env from $lssthome
        exit 3
    }
    . "$lssthome/loadLSST.sh" 
    setup obs_lsstSim
    PATH=${OBS_LSSTSIM_DIR}/bin:$PATH
}

function movereg {
    [ -z "$rotated" ] && {
        [ -f "$rotateconf" ] || cat > $rotateconf <<EOF
$ingested/registry.sqlite3 {
   rotate 5
   missingok
   nocompress
}
EOF

        /usr/sbin/logrotate -s $logdir/logrotate.status -f "$rotateconf"
        rotated=1
        # rm "$rotateconf"
    }
    log mv -f $archived/registry.sqlite3 $ingested/registry.sqlite3
    mv -f $archived/registry.sqlite3 $ingested/registry.sqlite3
}

function cleanfail {
    code=$1
    [ -z "$code" ] && code=1
    [ -e "$archived/registry.sqlite3" ] && {
        mv -f $archived/registry.sqlite3 $archived/registry.sqlite3.failed > $log 2>&1
    }
    exit $code
}

#============ MAIN ===========================================

lockapp || {
    log already running with pid=$pid\; exiting.
    exit 2
}
trap unlockapp EXIT
log Starting with command-line: $0 $@

[ -d "$trxroot" -a ! -d "$ingested" ] && mkdir -p $ingested/raw $ingested/eimage

[ -e "$ingested/registry.sqlite3" -a ! -f "$ingested/registry.sqlite3" ] && {
    complain Existing registry not a file: $ingested/registry.sqlite3
    exit 3
}

setuplsst
[ -x "$OBS_LSSTSIM_DIR/bin/$genreg" ] || {
    complain $genreg script not 'found!': "$OBS_LSSTSIM_DIR/bin/$genreg"
    exit 3
}

declare -a visits
declare -a dirs

# trivially handled non-raw visits
for coll in bias dark flat eimage; do
    i=0
    visits=(`ls -r --sort=time $archived/$coll | head -$max`)
    while [ $i -lt $maxiter -a ${#visits[*]} -ne 0 ]; do 
        log moving ${#visits[*]} $coll visits to ingested
        log ${visits[*]}
        dirs=()
        for visit in "${visits[@]}"; do
            dirs[${#dirs[@]}]="$archived/$coll/$visit"
        done
        mv ${dirs[@]} $ingested/$coll

        visits=(`ls -r --sort=time $archived/$coll | head -$max`)
        (( i += 1 ))
    done
    
done


# get a list of raw visits to ingest
visits=(`ls -r --sort=time $archived/raw | head -$max`)
[ ${#visits[*]} -eq 0 ] && {
    log No visits available for ingesting\; exiting.
    exit 0
}

i=0
while [ $i -lt $maxiter -a ${#visits[*]} -ne 0 ]; do 
    dirs=()
    for visit in "${visits[@]}"; do
        dirs[${#dirs[@]}]="$archived/raw/$visit"
    done
    
    inputregistry=
    [ -e "$ingested/registry.sqlite3" ] && {
        inputregistry="-i $ingested/registry.sqlite3"
    }

    log $genreg $inputregistry -o $archived/registry.sqlite3 ${dirs[@]}
    # echo $genreg $inputregistry -o $archived/registry.sqlite3 ${dirs[@]} && touch $archived/registry.sqlite3
    $genreg $inputregistry -o $archived/registry.sqlite3 ${dirs[@]} > $logdir/.$prog.$$ 2>&1 || {
        [ -f "$logdir/.$prog.$$" ] && { 
            cat $logdir/.$prog.$$ >> $log
            cat $logdir/.$prog.$$ >> $ingestlog
        }
        complain Trouble processing visits\; see log for details
        cleanfail 1
    }
    [ -f "$logdir/.$prog.$$" ] && {
        cat $logdir/.$prog.$$ >> $ingestlog
        grep completed $logdir/.$prog.$$ >> $log
    }

    movereg && {
        mv $dirs $ingested/raw 
        # echo mv $dirs $ingested/raw 2>&1
    }

    visits=(`ls -r --sort=time $archived/raw | head -$max`)
    (( i += 1 ))
done

if [ $i -lt $maxiter ]; then
    log No more visits available to ingest
else
    log Maximum interations reached\; exiting.
fi

