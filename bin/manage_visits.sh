#!/bin/bash
#
# Purpose: manage transfer of imSim "visit" directories from production site
# to NCSA.
#
# Usage: <program_name> -f config_file
#
# where: config_file contains all the definitions that are unique to the site
#        running the script
#
# Summary:  Collect *.tar or *.fits.gz files, build visit directories, and
#           when ready, transport visits to NCSA
#
# Method:
#   1. scan a holding directory for *.tar files, unpack
#   2. scan a holding directory for *.fits.gz files and if found
#      call python script to populate visit directories
#   3. when a visit directory is finished, transport to NCSA
#
# Requirements:
#
#   - script runs under a user that has ability to ssh to RHOST using the 
#     "-i identity_file" option to ssh/scp
#   - local site has a java implementation capable of running FDT
#   - local site has a working copy of FDT: http://monalisa.cern.ch/FDT/
#   - local site has Simon's python script fits.gz --> visit dir
#
# To run, edit a local configuration file with all the variables defined below
# filled out to working local values.
#--------------------------------------------------------------------------
#---------- CONFIGURATION is set in cfgfile ---------------------------------
##-- Define variables used below
##SITE_ID=slac
## contact for email that is sent on error conditions (not used yet)
##CONTACT=marshall@slac.stanford.edu 
## directory to hold log files
##LOGDIR=/nfs/slac/g/ki/ki05/marshall/imsim/log
## python script that populates canonical visit directories
##PDIRPY=/nfs/slac/g/ki/ki03/jgj/code/slac_code/vdist_pt1_1.py
## holding directory with initial .tar or .gz files
##HDIR=/nfs/slac/g/ki/ki05/marshall/imsim/holding
## top level dir to hold visit dirs ($TDIR/imSim/raw/v*)
##TDIR=/nfs/slac/g/ki/ki05/marshall/imsim/TOP
## lockfile -- exists while this script is running
##LOCKDIR=/nfs/slac/g/ki/ki05/marshall/imsim
## root name for tmp files
##TMPBASE=/nfs/slac/g/ki/ki05/marshall/imsim/tmp
## minimum age in minutes for files/directories to be processed
##minage=1
## number of image files in a visit directory for eimage/raw
##ecnt=378
##rcnt=6048

##-- fdt xfer local variables
## location of java program
##JRE_LOC=/u1/ki/marshall/java/jre1.6.0_11/bin/java
## location of fdt jar file
##FDTLJAR=/u/ki/marshall/src/fdt-0.9.14/fdt.jar
## root of log file for local fdt
##FDTLLOGBASE=${LOGDIR}/fdtlog_"$SITE_ID"
## local site host where this will run
##LHOST=ki-rh12.slac.stanford.edu
## maximum number of visits to transfer in one run
##MAX_VCNT=2

##-- fdt xfer remote variables
## location of java program
##JRE_REMOTE=/lsst/DC3/opt/java/1.6.0_20-32b/bin/java
## location of fdt jar file
##FDTRJAR=/home/marshall/fdt/fdt.jar
## location of endpoint of fdt based transfers
##DESTDIR=/usr/lsst/ImSimData-Vault/ImSimData/imSim/incoming
## final loc of verified visit, should be same filesystem as DESTDIR
##FINALDIR=/usr/lsst/ImSimData-Vault/ImSimData/imSim
## remote host
##RHOST=lsst2.ncsa.uiuc.edu
## root of log file for remote fdt
##FDTRLOGBASE=${DESTDIR}/ftdlog_"$SITE_ID"
##RUSER=lsstread 

##-- Define programs used below
##RM=/bin/rm
##MV=/bin/mv
##ECHO=/bin/echo
##DATE=/bin/date
##STAT=/usr/bin/stat
##GREP=/bin/grep
##GAWK=/usr/bin/gawk
##FIND=/usr/bin/find
##TAR=/bin/tar
##EMAIL=/bin/mail
##PYTHON=/usr/local/bin/python
##WC=/usr/bin/wc
##SSH=/usr/bin/ssh
##SCP=/usr/bin/scp
##SSHCMD="$SSH -i /u/ki/marshall/.ssh/lsstkey"
##SCPCMD="$SCP -i /u/ki/marshall/.ssh/lsstkey"
##-------------------- END CONFIGURATION ------------------------------------

#---------------------------------------------------------------------------
#- define some functions
#---------------------------------------------------------------------------
# usage: email "message text"
function email {
${EMAIL} -s "${PROG} error" "$CONTACT" <<EOF
$1
Time: $(date)
EOF
}

# called on trap triggered exit
function cleanexit {
${RM} -f tmp.$PID.*
#- don't leave any java fdt's behind
set +u
if [ $JRE_PID ] ; then 
    ${ECHO} kill any left over FDT/JAVA process
    kill -TERM $JRE_PID; 
fi
${RM} -f $LOCKFILE
${RM} -f $TMPBASE*
${ECHO} -n "cleanexit(): "
${DATE} --utc '+%Y/%m/%d %H:%M:%S %Z'
exit $?
}

# find age of a file in seconds
function fileage {
now=`${DATE} +%s`
mt=`${STAT} -c %Y $1`
age=$(($now - $mt))
${ECHO} $age
return
}

# usage message
function usage {
   ${ECHO} "Usage: ${0##*/} -f config_file"
   exit 1
}
#---------------------------------------------------------------------------
#- initialization
#- read configuration file
#- create lockfile with our PID
#- trap exit to remove the lockfile
#---------------------------------------------------------------------------
PROGPATH=$0
PROG=${0##*/}
PID=$$
dir0=$PWD
set -u

# check for config file on command line
cfgfile=
while getopts "hf:" Option
do
    case $Option in
        f     ) cfgfile=$OPTARG; /bin/echo " "using config file \"${OPTARG}\";;
        h     ) usage;;
        *     ) /bin/echo "Unimplemented option chosen.";;   # Default.
    esac
done
shift $(($OPTIND - 1))

# read in and process the config file
if [ "XXX"$cfgfile != "XXX" ] && [ -s $cfgfile ]; then
    . $cfgfile
else
    usage
fi

#-- check that certain directories exist and we can write in
if [ ! -d ${LOGDIR} ] || [ ! -w ${LOGDIR} ]; then 
    ${ECHO} "${LOGDIR} dir does not exist or is not writable"
    exit 1
fi

if [ ! -d ${HDIR} ] || [ ! -w ${HDIR} ]; then 
    ${ECHO} "${HDIR} dir does not exist or is not writable"
    exit 1
fi

if [ ! -d ${TDIR} ] || [ ! -w ${TDIR} ]; then 
    ${ECHO} "${TDIR} dir does not exist or is not writable"
    exit 1
fi

if [ ! -d ${LOCKDIR} ] || [ ! -w ${LOCKDIR} ]; then 
    ${ECHO} "${LOCKDIR} dir does not exist or is not writable"
    exit 1
fi

LOCKFILE=${LOCKDIR}/${PROG}.lock
if ( set -o noclobber ; ${ECHO} "$PID" > "$LOCKFILE") 2> /dev/null; 
then
    trap cleanexit INT TERM EXIT
else
    ${ECHO} "Failed to acquire lockfile: $LOCKFILE." 
    ${ECHO} "Held by PID $(< $LOCKFILE)"
    ${ECHO} "exiting"
    exit 1
fi

${ECHO} start at: $(${DATE}  --utc '+%Y/%m/%d %H:%M:%S %Z')
#---------------------------------------------------------------------------
#- extract any *.fits.gz files from tarfiles in the holding dir
#- note that tarfiles are deleted after extraction
#---------------------------------------------------------------------------
cd $HDIR;
tarlist=${TMPBASE}.tarfiles.$$
${FIND} . -maxdepth 1 -name '*.tar' -mmin +${minage} > $tarlist
tarcnt=$(${WC} -l $tarlist| ${GAWK} '{print $1}')
if [ $tarcnt -gt 0 ] ; then
    ${ECHO} -n "found $tarcnt tar files (age>"$minage"m): unpacking"
    declare -i nf=0
    while read tf
    do
        filelist=${TMPBASE}.files.$$
        ${TAR} t --file $tf | ${GREP} -E '\./.*\.fits.gz$' > $filelist
        nf+=$(${WC} -l $filelist | ${GAWK} '{print $1}')
        if [ -s $filelist ]; then
            ${TAR} xm --file $tf --unlink-first --files-from $filelist
            if [ $? -ne 0 ]; then
                ${ECHO} "Error: ${TAR} failed, exiting"
                exit 1
            else
                ${RM} -f $tf
                ${ECHO} -n "."
            fi
        fi
        ${RM} -f $filelist
    done < $tarlist
    ${ECHO} ""
    ${ECHO} "extracted $nf fits.gz files"
    unset nf
    ${ECHO} done at: $(${DATE}  --utc '+%Y/%m/%d %H:%M:%S %Z')
else
    ${ECHO} found $tarcnt tar files
fi
${RM} $tarlist
unset ffiles
#---------------------------------------------------------------------------
#- run the python script that moves *.fits.gz files in the holding dir into
#- the canonical visit hierarchy, only include files >5 minutes age
#---------------------------------------------------------------------------
cd $HDIR;
flist=${TMPBASE}.fitslist.$$
${FIND} . -maxdepth 1 -name '*.fits.gz' -mmin +${minage} > $flist
fcnt=$(${WC} -l $flist|${GAWK} '{print $1}')
if [ $fcnt -gt 0 ] ; then
    ${ECHO} -n "found $fcnt image files (age>"$minage"m): distributing-"
    declare -i cnt=0
    declare -i tcnt=0
    while read fz
    do
        #- only do 100 files per python call
        ffiles[$cnt]=$fz
        cnt+=1
        rem=$(($cnt % 100))
        #- do 100 files in call to python
        if [ $rem -eq 0 ] ; then
            ${PYTHON} ${PDIRPY} ${TDIR} ${ffiles[@]} > /dev/null
            if [ $? -ne 0 ]; then
                ${ECHO}  "${PDIRPY} returned an error"
                exit 1
            fi
            tcnt+=$cnt
            cnt=0
            unset ffiles
            ${ECHO} -n "-"
        fi
    done < $flist
    #- get the remainder
    if [ $cnt -gt 0 ]; then
        ${PYTHON} ${PDIRPY} ${TDIR} ${ffiles[@]} > /dev/null
        if [ $? -ne 0 ]; then
            ${ECHO}  "${PDIRPY} returned an error"
            exit 1
        fi
        unset ffiles
            tcnt+=$cnt
    fi
    ${ECHO} "->"$tcnt
    unset cnt
    unset tcnt
    ${ECHO} done at: $(${DATE}  --utc '+%Y/%m/%d %H:%M:%S %Z')
else
    ${ECHO} found $fcnt image files
fi
unset ffiles
#---------------------------------------------------------------------------
#- in the visit top dir, find and rename completed visits
#---------------------------------------------------------------------------
${ECHO} Searching for completed visits...
cd $TDIR
vdirs=($(${FIND} imSim -maxdepth 3 -type d\
      -name 'v[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-f?'))
if [ ${#vdirs[@]} -gt 0 ] ; then
    for vdir in ${vdirs[@]} ; do
        ${ECHO} -n checking $vdir
        if [ ! -d $vdir ] ; then
            ${ECHO} not a directory, skipping
            continue
        fi
        declare -x nf=`find $vdir -type f | wc -l`
        key=${vdir#*/}      #-- pull off the first level (imSim)
        key=${key#*/}      #-- pull off the first level (imSim)
        key=${key%/v*}    #-- pull off the /v*-f?
        if [ $key == raw ]; then
            vcnt=$rcnt
        elif [ $key == eimage ]; then
            vcnt=$ecnt
        else
            ${ECHO} warning: key= $key is not raw|eimage
        fi

        if [ $nf -eq $vcnt ] ; then
            ${MV} "$vdir" "$vdir".fin
            ${ECHO} ":" finished, found all $vcnt files
        elif [ $nf -gt $vcnt ] ; then
            ${ECHO} ":" warning, found $nf">"$vcnt files, check $vdir
        else
            ${ECHO} ":" not ready, found $nf of $vcnt files
        fi
        unset nf
    done
    ${ECHO} done at: $(${DATE}  --utc '+%Y/%m/%d %H:%M:%S %Z')
fi
#---------------------------------------------------------------------------
#- in the visit top dir, find, transfer and rename the completed visits
#---------------------------------------------------------------------------
cd $TDIR
vdirs=($(find imSim -maxdepth 3\
      -name 'v[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-f?.fin'))
if [ ${#vdirs[@]} -gt 0 ] ; then
    declare -i nvisits=0
    ${ECHO} "processing ${#vdirs[@]} visit directories"
    for vdir in ${vdirs[@]} ; do
        if [ $nvisits -ge $MAX_VCNT ]; then
            ${ECHO} "Maximimum visits/run count reached, breaking out"
            ${ECHO} $nvisits of ${#vdirs[@]} visit dirs processed
            break
        fi
        ${ECHO} processing $vdir
        if [ ! -d $vdir ] ; then
            ${ECHO} $vdir not a directory, skipping
            continue
        fi
        tdir=${vdir##*/}      #-- pull off the leading path
        ttdir=${tdir%.fin}    #-- pull off the .fin
        #- set key (has value raw or eimage)
        key=${vdir#*/}      #-- pull off the first level (imSim)
        key=${key#*/}      #-- pull off the first level (imSim)
        key=${key%/v*}    #-- pull off the /v*-f?
        if [ $key == raw ]; then
            vcnt=$rcnt
        elif [ $key == eimage ]; then
            vcnt=$ecnt
        else
            ${ECHO} error: key= $key is not raw|eimage
            ${ECHO} exiting...
            exit 1
        fi
        #- set log file names
        FDTLLOG=$FDTLLOGBASE.$key.$ttdir
        FDTRLOG=$FDTRLOGBASE.$key.$ttdir
        #-----------------------------------------------------------
        #- check to see if the vdir is already there
        #- (can't really check success easily)
        #- ignored if -f used
        #-----------------------------------------------------------
        rval=`${SSHCMD} $RUSER@$RHOST \
        "if [ -d $FINALDIR/$key/$ttdir ]; then ${ECHO} $ttdir; fi"`

        if [ $rval"XXX" == $ttdir"XXX" ] ; then
            ${ECHO} $key/$ttdir exists on remote side
            if (( !$force )) ; then
                ${ECHO} Skipping $ttdir
                continue #--- skip to next dir
            else
                ${ECHO} force option set, will copy 
            fi
        fi
        #-----------------------------------------------------------
        #- invoke local FDT as a server
        #-----------------------------------------------------------
        ${ECHO} Begin transfer of $key/$ttdir....
        sleep 5
        $JRE_LOC -jar $FDTLJAR -p 1234 -noupdates -md5 -f $RHOST -S > $FDTLLOG 2>&1 &
        JRE_PID=$!
        sleep 5  #- give time to set up socket
        #-----------------------------------------------------------
        #- rm -rf the remote:incoming/$key/$tdir if it is there
        #- since existence means something went wrong before
        #-----------------------------------------------------------
        ${SSHCMD} $RUSER@$RHOST "if [ -d $DESTDIR/$key/$tdir ]; then\
        /bin/echo \"$DESTDIR/$key/$tdir already exists, clearing it\" ;\
        /bin/rm -rf $DESTDIR/$key/$tdir; fi"
        #-----------------------------------------------------------
        #- invoke remote FDT as client in pull mode
        #-----------------------------------------------------------
        retval=1
        COUNTER=0
        while [ $retval -ne 0 -a $COUNTER -lt 10 ]; do
            ${SSHCMD} $RUSER@$RHOST $JRE_REMOTE -jar $FDTRJAR -p 1234 -noupdates -md5 \
            -pull -c $LHOST -r -d $DESTDIR/$key $vdir \> $FDTRLOG 2\>\&1
            retval=$?
            echo RETVAL is $retval retrying for the $COUNTER time.
            let COUNTER=COUNTER+1
            sleep 5
        done
        if [ $retval -ne 0 ] ; then
            ${ECHO} remote FDT client failed, killing local FDT server
            kill -TERM $JRE_PID
        else
            ${ECHO} remote FDT client success, wait for local FDT server
            wait #- for the local server to finish, flush logfile etc.
        fi
        #-----------------------------------------------------------
        #- copy remote logfile to local; count # of files transferred;
        #- chksums verify;mv vdir to final
        #- need to decide whether to use known val 6426 or count #files
        #-----------------------------------------------------------
        ${SCPCMD} $RUSER@$RHOST:$FDTRLOG $FDTLLOG.remote
        # TBD, remove kruft at remote end?

        # TBD whether to count #files transfered instead
        #NSUMS=`${GAWK} 'BEGIN{cnt=first=0};\
        #/MD5/ {first == 0 ? first = 1 : first = 0};\
        #{if(first) cnt++;}END{printf("%d\n",cnt-1);}' $FDTLLOG.remote`
        NSUMS=$vcnt
        NOK=`${SSHCMD} $RUSER@$RHOST "md5sum --check ${FDTRLOG} | grep OK | wc -l"`
        if (( $NOK == $NSUMS )) ; then
            ${ECHO} done
            ${ECHO} All $NOK files transferred successfully.
            ${SSHCMD} $RUSER@$RHOST /bin/mv $DESTDIR/$key/$tdir $FINALDIR/$key/$ttdir
            ${SSHCMD} $RUSER@$RHOST /bin/rm $FDTRLOG
        else
            ${ECHO} ERROR: fdt file transfer failure
            ${ECHO} Checksums returned only $NOK out of $NSUMS expected
            ${ECHO} removing remote partial/corrupt $DESTDIR/$key/$tdir
            ${SSHCMD} $RUSER@$RHOST /bin/rm -r $DESTDIR/$key/$tdir
            ${ECHO} exiting...
            exit 1
        fi
        ${ECHO} done
        ${MV} "$vdir" "${vdir%.fin}".xfr
        nvisits+=1
    done
    ${ECHO} done at: $(${DATE} --utc '+%Y/%m/%d %H:%M:%S %Z') 
else
    ${ECHO} found ${#vdirs[@]} visits to transfer
fi
#---------------------------------------------------------------------------
#- end of script, remove trap
#---------------------------------------------------------------------------
trap - INT TERM EXIT
${RM} -f $LOCKFILE
${RM} -f $TMPBASE/*
cd $dir0
${ECHO} exit at: $(${DATE} --utc '+%Y/%m/%d %H:%M:%S %Z') 
exit 0
