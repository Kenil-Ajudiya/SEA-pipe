#! /bin/bash

usage()
{
echo "$0 [-d jobid] [-p project] [-c calid] [-g] [-f] [-r] [-z] [-u] [-m] [-n] [-i] [-s] [-t] [-v] [-h] obsnum
    -d jobid    : JobID for dependency (afterok).
    -p project  : project, (must be specified, no default)
    -c calid    : The ID of the calibration to use.
    -g          : Get the data from ASVO. If not specified, the data is assumed to be 
                  already present in the project directory
    -f          : Flag the data using the obs_autoflag.sh script, which flags only the tiles known to be bad in specific obsids.
                  This is not very useful because obs_uvflag.sh is quite good at flagging bad visibilities (having large amplitudes).
    -r          : Copy the mesaurement set to RAM instead of reordering on disk
                  (Faster, but needs ~3x as much RAM as the size of the measurement set)
    -z          : Debugging mode: create and use a new CORRECTED_DATA column to store the
                  calibrated data and then image that column instead of the DATA column
    -u          : Subtract out known bright sources using obs_uvsub.sh to avoid contamination from sidelobes.
    -m          : Do sidelobe subtraction using obs_sidelobe_sub.sh to avoid contamination from sidelobes. This is useful mostly at low
                  elevations and at higher frequencies where the sidelobes are above the horizon and as (or more) sensitive than the main lobe.
    -n          : Do (infield) self-calibration using obs_selfcal.sh to improve the calibration solutions, especially after subtracting the sidelobes.
    -i          : Do post-imaging corrections using obs_postimage.sh.
    -s          : Subtract the sky model from the observed visibilities, produce a data cube of snapshot images from the residual visibilities
                  (using the obs_transient.sh script) and run the transient detection filters (using the obs_tfilter.sh script).
    -t          : Test. Don't submit job, just make the batch file and then return the submission command.
    -v          : Verbose. Print out the commands that are being run.
    -h          : Print this help message and exit.
    obsnum      : the obsid to process, or a text file of obsids (newline separated)." 1>&2;
exit 1;
}

pipeuser="${GXUSER}"

# initial variables
jobid=
depend=
tst=
debug=
ramcopy=
getdata=
autoflag=
uvsub=
sidelobe=
selfcal=
postimage=
transient=
calid=
verbose=
# parse args and set options
while getopts 'd:p:c:gfrzumnistvh' OPTION; do
    case "$OPTION" in
    d)
	    jobid="${OPTARG}"
        depend="-d ${jobid}"
	    ;;
    p)
        project="${OPTARG}"
        ;;
	c)
        calid="${OPTARG}"
        ;;
    g)
        getdata=1
        ;;
    f)
        autoflag=1
        ;;
    r)
        ramcopy=-r
        ;;
    z)
        debug=-z
        ;;
    u)
        uvsub=1
        ;;
    m)
        sidelobe=1
        ;;
    n)
        selfcal=1
        ;;
    i)
        postimage=1
        ;;
    s)
        transient=1
        ;;
	t)
	    tst=-t
	    ;;
	v)
	    verbose=1
	    ;;
	? | : | h)
	    usage
	    ;;
  esac
done

shift  "$(($OPTIND -1))"
obsnum=$1

if [[ -z "${obsnum}" ]] || [[ -z "${project}" ]]; then
    usage
fi

base="${GXSCRATCH}/${project}"

if  [[ ! -d "${base}" ]]; then
    if [[ -z "${getdata}" ]]; then
        echo "Project directory ${base} does not exist." 1>&2;
        echo "If you want me to get the data from ASVO, use the -g option, and I will make the project directory for you." 1>&2;
        exit 1;
    else
        mkdir "${base}"
    fi
fi

if [[ -z "${calid}" ]]; then
    calid="${obsnum}"
fi

# start the real program
cd "${base}" || exit 1

if [[ -n "${getdata}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_manta.sh ${tst} ${depend} -p ${project} ${obsnum}"
    fi
    jobid=($(obs_manta.sh ${tst} ${depend} -p ${project} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_manta.sh: ${jobid}."
    fi
fi

if [[ -n "${autoflag}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_autoflag.sh ${tst} ${depend} -p ${project} ${obsnum}"
    fi
    jobid=($(obs_autoflag.sh ${tst} ${depend} -p ${project} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_autoflag.sh: ${jobid}."
    fi
fi

if [[ -n "${verbose}" ]]; then
    echo "Submitting obs_autocal.sh ${tst} ${depend} -p ${project} -i ${ramcopy} ${obsnum}"
fi
jobid=($(obs_autocal.sh ${tst} ${depend} -p ${project} -i ${ramcopy} ${obsnum}))
if [[ -n ${tst} ]]; then
    echo "${jobid[@]}."
else
    jobid=${jobid[3]}
    depend="-d ${jobid}"
    echo "JobID for obs_autocal.sh: ${jobid}."
fi

if [[ -n "${verbose}" ]]; then
    echo "Submitting obs_apply_cal.sh ${tst} ${depend} -p ${project} -c ${calid} ${debug} ${obsnum}"
fi
jobid=($(obs_apply_cal.sh ${tst} ${depend} -p ${project} -c ${calid} ${debug} ${obsnum}))
if [[ -n ${tst} ]]; then
    echo "${jobid[@]}."
else
    jobid=${jobid[3]}
    depend="-d ${jobid}"
    echo "JobID for obs_apply_cal.sh: ${jobid}."
fi

if [[ -n "${verbose}" ]]; then
    echo "Submitting obs_uvflag.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}"
fi
jobid=($(obs_uvflag.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}))
if [[ -n ${tst} ]]; then
    echo "${jobid[@]}."
else
    jobid=${jobid[3]}
    depend="-d ${jobid}"
    echo "JobID for obs_uvflag.sh: ${jobid}."
fi

if [[ -n "${uvsub}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_uvsub.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}"
    fi
    jobid=($(obs_uvsub.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_uvsub.sh: ${jobid}."
    fi
fi

if [[ -n "${sidelobe}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_sidelobe_sub.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}"
    fi
    jobid=($(obs_sidelobe_sub.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_sidelobe_sub.sh: ${jobid}."
    fi
fi

if [[ -n "${selfcal}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_selfcal.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}"
    fi
    jobid=($(obs_selfcal.sh ${tst} ${depend} -p ${project} ${debug} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_selfcal.sh: ${jobid}."
    fi
fi

if [[ -n "${verbose}" ]]; then
    echo "Submitting obs_image.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${obsnum}"
fi
jobid=($(obs_image.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${obsnum}))
if [[ -n ${tst} ]]; then
    echo "${jobid[@]}."
else
    jobid=${jobid[3]}
    depend="-d ${jobid}"
    echo "JobID for obs_image.sh: ${jobid}."
fi

if [[ -n "${postimage}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_postimage.sh ${tst} ${depend} -p ${project} ${obsnum}"
    fi
    jobid=($(obs_postimage.sh ${tst} ${depend} -p ${project} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_postimage.sh: ${jobid}."
    fi
fi

if [[ -n "${transient}" ]]; then
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_transient.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${obsnum}"
    fi
    jobid=($(obs_transient.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_transient.sh: ${jobid}."
    fi

    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_tfilter.sh ${tst} ${depend} -p ${project} ${obsnum}"
    fi
    jobid=($(obs_tfilter.sh ${tst} ${depend} -p ${project} ${obsnum}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_tfilter.sh: ${jobid}."
    fi
fi
