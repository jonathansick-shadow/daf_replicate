#! /bin/bash
#
# set -x
trxroot=/lsst3/transfer/pt1_2
logdir=$trxroot/logs
# logdir=/tmp
transfered=$trxroot/transfered
archived=$trxroot/archived
max=10
logfile=pt12archive.log
lockfile=pt12archive.lock
lssthome=/lsst/DC3/stacks/32bit/default
archivescript=archiveColl.py
buildregscript=~rplante/pt12buildreg.sh
conf=$trxroot/lsstobs_pt1_2.conf

prog=`basename $0`
log=$logdir/$logfile
lock=$logdir/$lockfile
regbldlaunched=

[ -w $logdir ] || {
    echo ${prog}: Unable to write to log directory: $logdir
    exit 1
}
[ ! -e $log -o \( -w $log -a -f $log \) ] || {
    echo ${prog}: Unable to write to log file: $log
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

function movecals {
    declare -a vs
    declare -a ds
    declare -a types
    types=(bias dark flat flat flat flat flat flat)
    t=0
    while [ $t -lt ${#types[*]} ]; do
        vs=(`ls -rd --sort=time $transfered/raw/v9999$t* 2>/dev/null`)
        [ ${#vs[*]} -gt 0 ] && {
            log moving ${#vs[*]} 9999$t visits from raw to ${types[$t]}
            mv ${vs[*]} $transfered/${types[$t]} >> $log 2>&1 || {
                complain Failed to move ${types[$t]} visits
                exit 3
            }
        }
        (( t += 1 ))
    done
}

function archiveColls {
    n=$3
    # echo regbldlaunched=$regbldlaunched 1>&2

    declare -a visits
    declare -a colls
    lim=$((max-n))

    visits=(`ls -r --sort=time $transfered/$1`)
    count=${#visits[*]}
    [ $count -eq 0 ] && {
        log No $1 visits available 
        echo $n
        return 0
    }
    [ $count -gt $lim ] && count=$lim
    if [ $count -gt 0 ]; then
        log archiving $count/${#visits[*]} visits available from $1
    else
        log archiving visit limit reached
        echo $n
        return 0
    fi

    for visit in "${visits[@]}"; do
        # echo [ $n -lt $max ] 1>&2
        [ $n -lt $max ] || break

        colls=$1/$visit
        [ -d "$transfered/$2/$visit" ] && colls[1]=$2/$visit
        (( n += 1 ))
        # echo $n 1>&2

        echo $archivescript -q -c $conf -m update -l $log -L 2 ${colls[*]} >> $log
        $archivescript -q -c $conf -m update -l $log -L 2 ${colls[*]} >> $log 2>&1 || {
            log Problem archiving visit $visit
            continue
        }

        # move collections
        for coll in "${colls[@]}"; do
            # echo mv $transfered/$coll $archived/`dirname $coll` 1>&2
            mv $transfered/$coll $archived/`dirname $coll` >> $log 2>&1
        done

        # launch registry builder
        if [ -z "$regbldlaunched" ]; then 
            log launching $buildregscript in background
            $buildregscript &
            regbldlaunched=1
        fi

    done

    echo $n
}

function setuplsst {
    [ -f "$lssthome/loadLSST.sh" ] || {
        complain Unable to load LSST env from $lssthome
        exit 3
    }
    . "$lssthome/loadLSST.sh" 
    setup sciarch
}

#============ MAIN ===========================================

lockapp || {
    log already running with pid=$pid\; exiting.
    exit 2
}
trap unlockapp EXIT
log Starting with command-line: $0 $@

setuplsst 
[ -x "$SCIARCH_HOME/bin/archiveColl.py" ] || {
    complain archiveColl.py script not 'found!': "$SCIARCH_HOME/bin/archiveColl.py"
    exit 3
}

movecals

ndone=`archiveColls raw eimage 0`
[ $ndone -gt 0 ] && regbldlaunched=1
ndone=`archiveColls bias eimage $ndone`
[ $ndone -gt 0 ] && regbldlaunched=1
ndone=`archiveColls dark eimage $ndone`
[ $ndone -gt 0 ] && regbldlaunched=1
ndone=`archiveColls flat eimage $ndone`
[ $ndone -gt 0 ] && regbldlaunched=1
ndone=`archiveColls eimage raw $ndone`

log No. done = $ndone


