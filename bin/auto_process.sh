#! /bin/bash

usage()
{
echo "$0 [-e profile] [-d jobid] [-p project] [-b batchsize] [-c calid] [-g] [-f] [-r] [-z] [-u] [-m] [-n] [-i] [-s] [-t] [-v] [-h] obsinp
    -e profile  : The profile to use for the processing. Default is SEA-pipe-setonix.profile in GXBASE.
    -d jobid    : JobID for dependency (afterok).
    -p project  : project, (must be specified, no default)
    -b batchsize: The size of the batch to process. Default is 100. This is to avoid SLURM job submission limits.
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
    obsinp      : the obsid(s) to process, or a text file of obsids (newline separated).
                  If specifying multiple obsids, they should be separated by spaces." 1>&2;
exit 1;
}

# initial variables
profile=
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
batchsize=100
# parse args and set options
while getopts 'e:d:p:b:c:gfrzumnistvh' OPTION; do
    case "$OPTION" in
    e)
        profile=${OPTARG}
        ;;
    d)
	    jobid="${OPTARG}"
        depend="-d ${jobid}"
	    ;;
    p)
        project="${OPTARG}"
        ;;
    b)
        batchsize="${OPTARG}"
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
obsinp=$@

if [[ -z "${obsinp}" ]] || [[ -z "${project}" ]]; then
    usage
fi

if [[ -z "${profile}" ]] && [[ -n "${GXPROFILE}" ]] && [[ -f "${GXPROFILE}" ]]; then
    profile="${GXPROFILE}"
else
    echo "Profile not specified and default profile not found." 1>&2;
    echo "Please specify a profile using the -e option or set the GXPROFILE environment variable to source the default SEA-pipe-setonix.profile." 1>&2;
    exit 1;
fi
source "${profile}" # The command-line argument (-e) overrides the default profile.
export GXPROFILE="${profile}" # The job scripts will source this profile to get the correct environment variables for the processing.

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
    calid="${obsinp}"
fi

# start the real program
cd "${base}" || exit 1

if [[ -f "${obsinp}" ]]; then
    mapfile -t obsid_array < "${obsinp}"
else
    obsid_array=(${obsinp})
fi
if [[ ${#obsid_array[@]} -gt ${batchsize} ]]; then
    echo "The number of obsids (${#obsid_array[@]}) exceeds the batch size (${batchsize}). Splitting the obsids into smaller batches.";
    batch_mode=1
    num_batches=$(( (${#obsid_array[@]} + ${batchsize} - 1) / ${batchsize} ))
    echo "Number of batches: ${num_batches}."
else
    batch_mode=
fi
# Split the obsid_array into smaller batches
for ((i=0; i<${#obsid_array[@]}; i+=${batchsize})); do
    batch_obsids=("${obsid_array[@]:i:${batchsize}}")

    if [[ -z "${batch_mode}" ]]; then # We are not in batch mode, but do not overwrite any existing batch files.
        batch_file="${obsid_array[0]}.tmp"
    else
        batch_num=$((i / batchsize + 1))
        batch_file="${project}_obsid_batch_${batch_num}.txt"
    fi
    printf '%s\n' "${batch_obsids[@]}" > "${batch_file}" # Write the batch obsids to a text file with obsids separated by newlines
    echo "Created ObsID list file: ${batch_file} with ${#batch_obsids[@]} obsids."

    # obs_manta.sh
    if [[ -n "${getdata}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_manta.sh ${tst} ${depend} -p ${project} ${batch_file}"
        fi
        jobid=($(obs_manta.sh ${tst} ${depend} -p ${project} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_manta.sh: ${jobid}."
        fi
    fi

    # obs_autoflag.sh
    if [[ -n "${autoflag}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_autoflag.sh ${tst} ${depend} -p ${project} ${batch_file}"
        fi
        jobid=($(obs_autoflag.sh ${tst} ${depend} -p ${project} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_autoflag.sh: ${jobid}."
        fi
    fi

    # # obs_autocal.sh
    # if [[ -n "${verbose}" ]]; then
    #     echo "Submitting obs_autocal.sh ${tst} ${depend} -p ${project} -i ${ramcopy} ${batch_file}"
    # fi
    # jobid=($(obs_autocal.sh ${tst} ${depend} -p ${project} -i ${ramcopy} ${batch_file}))
    # if [[ -n ${tst} ]]; then
    #     echo "${jobid[@]}."
    # else
    #     jobid=${jobid[3]}
    #     depend="-d ${jobid}"
    #     echo "JobID for obs_autocal.sh: ${jobid}."
    # fi

    # # obs_apply_cal.sh
    # if [[ -n "${verbose}" ]]; then
    #     echo "Submitting obs_apply_cal.sh ${tst} ${depend} -p ${project} -c ${calid} ${debug} ${batch_file}"
    # fi
    # jobid=($(obs_apply_cal.sh ${tst} ${depend} -p ${project} -c ${calid} ${debug} ${batch_file}))
    # if [[ -n ${tst} ]]; then
    #     echo "${jobid[@]}."
    # else
    #     jobid=${jobid[3]}
    #     depend="-d ${jobid}"
    #     echo "JobID for obs_apply_cal.sh: ${jobid}."
    # fi

    # # obs_uvflag.sh
    # if [[ -n "${verbose}" ]]; then
    #     echo "Submitting obs_uvflag.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}"
    # fi
    # jobid=($(obs_uvflag.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}))
    # if [[ -n ${tst} ]]; then
    #     echo "${jobid[@]}."
    # else
    #     jobid=${jobid[3]}
    #     depend="-d ${jobid}"
    #     echo "JobID for obs_uvflag.sh: ${jobid}."
    # fi

    # obs_uvsub.sh
    if [[ -n "${uvsub}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_uvsub.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}"
        fi
        jobid=($(obs_uvsub.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_uvsub.sh: ${jobid}."
        fi
    fi

    # obs_sidelobe_sub.sh
    if [[ -n "${sidelobe}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_sidelobe_sub.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}"
        fi
        jobid=($(obs_sidelobe_sub.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_sidelobe_sub.sh: ${jobid}."
        fi
    fi

    # obs_selfcal.sh
    if [[ -n "${selfcal}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_selfcal.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}"
        fi
        jobid=($(obs_selfcal.sh ${tst} ${depend} -p ${project} ${debug} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_selfcal.sh: ${jobid}."
        fi

        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_apply_cal.sh ${tst} ${depend} -p ${project} -s -c ${calid} ${debug} ${batch_file}"
        fi
        jobid=($(obs_apply_cal.sh ${tst} ${depend} -p ${project} -s -c ${calid} ${debug} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_apply_cal.sh: ${jobid}."
        fi

    fi

    # obs_image.sh
    if [[ -n "${verbose}" ]]; then
        echo "Submitting obs_image.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${batch_file}"
    fi
    jobid=($(obs_image.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${batch_file}))
    if [[ -n ${tst} ]]; then
        echo "${jobid[@]}."
    else
        jobid=${jobid[3]}
        depend="-d ${jobid}"
        echo "JobID for obs_image.sh: ${jobid}."
    fi

    # obs_postimage.sh
    if [[ -n "${postimage}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_postimage.sh ${tst} ${depend} -p ${project} ${batch_file}"
        fi
        jobid=($(obs_postimage.sh ${tst} ${depend} -p ${project} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_postimage.sh: ${jobid}."
        fi
    fi

    # obs_transient.sh and obs_tfilter.sh
    if [[ -n "${transient}" ]]; then
        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_transient.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${batch_file}"
        fi
        jobid=($(obs_transient.sh ${tst} ${depend} -p ${project} ${ramcopy} ${debug} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_transient.sh: ${jobid}."
        fi

        if [[ -n "${verbose}" ]]; then
            echo "Submitting obs_tfilter.sh ${tst} ${depend} -p ${project} ${batch_file}"
        fi
        jobid=($(obs_tfilter.sh ${tst} ${depend} -p ${project} ${batch_file}))
        if [[ -n ${tst} ]]; then
            echo "${jobid[@]}."
        else
            jobid=${jobid[3]}
            depend="-d ${jobid}"
            echo "JobID for obs_tfilter.sh: ${jobid}."
        fi
    fi

    # If we are in batch mode and this is not the last batch, wait for all jobs in the current batch to finish before starting the next batch.
    if [[ -n "${batch_mode}" ]] && [[ "${batch_num}" -lt "${num_batches}" ]]; then
        # All jobs submitted, now wait for them to finish before starting the next batch.
        if [[ -n "${tst}" || ! "${jobid}" =~ ^[0-9]+$ ]]; then
            echo "It's either test mode or I am debugging. Did not get a numeric job ID, and probably did not submit any jobs either. Not waiting for any job to finish."
        else
            echo "Waiting for all jobs in batch ${batch_num} of ${num_batches} to finish before starting the next batch..."
            echo "Meanwhile, you can watch the status of your jobs using 'squeue --me' or 'squeue -u ${USER}' in another terminal."
            # Here, squeue displays only the jobs which are either waiting for resources or still running.
            while squeue --me -h -o "%i" | grep -q ${jobid}; do # If I am able to grep the jobid, then it is still running. If not, then it has finished.
                sleep 10
            done
        fi
        depend="" # Reset the dependency for the next batch of jobs.
    fi
done
