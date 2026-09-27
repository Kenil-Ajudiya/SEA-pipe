#! /bin/bash

usage() {
echo "obs_manta.sh [-p project] [-d dep] [-s timeave] [-k freqav] [-t] obsnum
  -d dep      : job number for dependency (afterok)
  -p project  : project, (must be specified, no default)
  -s timeres  : time resolution in sec. default = 2 s
  -k freqres  : freq resolution in KHz. default = 40 kHz
  -r          : enables --allow-resubmit in the mwa_client command
  -f edgeflag : number of edge band channels flagged. default = 80
  -g          : download gpubox fits files instead of measurement sets
  -t          : test. Don't submit job, just make the batch file
                and then return the submission command
  obsnum      : the obsid to process, or a text file of obsids (newline separated)." 1>&2;
exit 1;
}

# initial variables
dep=
tst=
gpubox=
timeres=
freqres=
allow_resubmit=0
edgeflag=80

# parse args and set options
while getopts 'tgd:p:s:k:f:rh' OPTION; do
    case "$OPTION" in
    d)
        dep=${OPTARG} ;;
    p)
        project=${OPTARG} ;;
	s)
	    timeres=${OPTARG} ;;
	k)
	    freqres=${OPTARG} ;;
    t)
        tst=1 ;;
    g)
        gpubox=1 ;;
    f)
        edgeflag=${OPTARG} ;;
    r)
        allow_resubmit=1 ;;
    ? | : | h)
        usage ;;
    esac
done
shift  "$(($OPTIND -1))"
obsnum=$@

# If obsnum is not specified or is an empty file or project directory is not specified then just print help.
if [[ -z ${obsnum} ]] || ([[ -f ${obsnum} ]] && [[ ! -s ${obsnum} ]]) || [[ -z $project ]]; then
    usage
fi

if [[ -n ${dep} ]]; then
    depend="--dependency=afterok:${dep}"
fi

# Add the metadata to the observations table in the database
# import_observations_from_db.py --obsid "${obsnum}"

base="${GXSCRATCH}/${project}"
cd "${base}" || exit 1

dllist=""
if [[ ! -f "${obsnum}" ]]; then
    list=${obsnum}
    for item in $list; do # Validate that the list contains only integers
        if ! [[ $item =~ ^[0-9]+$ ]]; then
            echo "Error: The provided ObsID input is neither an accessible file nor a valid list of integer values."
            exit 1
        fi
    done
else
    list=$(cat "${obsnum}")
fi

rm -f "${obsnum}_manta.tmp"

# Set up telescope-configuration-dependent options
# Might use these later to get different metafits files etc
for obsid in $list; do
    # Note this implicitly 
    if [[ $obsid -lt 1151402936 ]]; then
        telescope="MWA128T"
        basescale=1.1
        if [[ -z $freqres ]]; then freqres=40; fi
        if [[ -z $timeres ]]; then timeres=4; fi
    elif [[ $obsid -ge 1151402936 ]] && [[ $obsid -lt 1191580576 ]]; then
        telescope="MWAHEX"
        basescale=2.0
        if [[ -z $freqres ]]; then freqres=40; fi
        if [[ -z $timeres ]]; then timeres=8; fi
    elif [[ $obsid -ge 1191580576 ]]; then
        telescope="MWALB"
        basescale=0.5
        if [[ -z $freqres ]]; then freqres=40; fi
        if [[ -z $timeres ]]; then timeres=4; fi
    fi

    if [[ -d "${obsid}/${obsid}.ms" ]]; then
        echo "${obsid}/${obsid}.ms already exists. I will not download it again."
    else
        if [[ -z ${gpubox} ]]; then
            echo "obs_id=${obsid}, preprocessor=birli, delivery=scratch, job_type=c, avg_time_res=${timeres}, avg_freq_res=${freqres}, flag_edge_width=${edgeflag}, output=ms" >>  "${obsnum}_manta.tmp"
            stem="ms"
        else
            echo "obs_id=${obsid}, delivery=acacia, job_type=d, download_type=vis" >>  "${obsnum}_manta.tmp"
            stem="vis"
        fi
        dllist=$dllist"$obsid "
    fi
done

script="${GXSCRIPT}/manta_${obsnum}.sh"

cat "${GXBASE}/templates/manta.tmpl" | sed -e "s:OBSLIST:${obsnum}:g" \
                                 -e "s:STEM:${stem}:g"  \
                                 -e "s:TRES:${timeres}:g" \
                                 -e "s:FRES:${freqres}:g" \
                                 -e "s:RESUBMIT:${allow_resubmit}:g" \
                                 -e "s:BASEDIR:${base}:g" > "${script}"

output="${GXLOG}/manta_${obsnum}.o%A"
error="${GXLOG}/manta_${obsnum}.e%A"

chmod 755 "${script}"

# DEVELOPER's NOTES:
# In the SLURM job script, start with a fresh login shell and source the profile to ensure that the environment is set up correctly.
# From the perspective of SLURM, this is a very simple job script with a single task.
# If there are multiple obsids to process, the job script will be submitted as a job array (with the --array option), with one task for each obsid.
# In a job array, each task is equivalent to a single job submission, and has a unique SLURM_JOB_ID. Only one of the array tasks will have SLURM_JOB_ID the same as SLURM_ARRAY_JOB_ID.
# If it is not a job array, SLURM_ARRAY_* environment variables will be unset (i.e. empty).
# In any case, the sbatch command need only specify the resources required for a single task (or a single obsid) since each obsid will be processed as a SLURM job.
# Moreover, the SLURM environment variables will be set automatically by SLURM in the job script for each task, and the resources allocated to that task need not be specified explicitly to the srun command.
# Precedence order for resource allocation requests (using the sbatch command) is: command line options > SLURM environment variables > SLURM directives in the header of the job script.
echo '#!/bin/bash --login' > "${script}_job.sh"
echo "source ${GXPROFILE}" >> "${script}_job.sh"
echo "export FI_CXI_DEFAULT_VNI=$(od -vAn -N4 -tu < /dev/urandom)" >> "${script}_job.sh"
echo "srun singularity run ${GXCONTAINER} ${script}" >> "${script}_job.sh"

# This is the only task that should reasonably be expected to run on another cluster. It is possible that accounting is not performed by SLURM.
if [[ -n ${GXCOPYA} ]]; then
    account="--account=${GXCOPYA}"
else
    account=""
fi

# Export the MWA_ASVO_API_KEY to ensure that ASVO authentication works correctly.
sub="sbatch --begin=now+2minutes --time=2-00:00:00 --mem=10G --cpus-per-task=1 ${GXTASKLINE} --clusters=${GXCOPYM} ${account} --partition=${GXCOPYQ} --job-name=manta_${obsnum} --export=MWA_ASVO_API_KEY --output=${output} --error=${error} ${depend} ${script}_job.sh"

if [[ -n ${tst} ]]; then
    echo "script is ${script}"
    echo "submit via:"
    echo "${sub}"
    exit 0
fi

# submit job
jobid=($(${sub}))
jobid=${jobid[3]}

# rename the err/output files as we now know the jobid
error="${error//%A/${jobid[0]}}"
output="${output//%A/${jobid[0]}}"

# record submission
n=1
if [[ "${GXTRACK}" == "track" ]]; then
    for obsid in $dllist; do
        ${GXCONTAINER} track_task.py queue \
                        --jobid="${jobid[0]}" \
                        --taskid="${n}" \
                        --task='download' \
                        --submission_time="$(date +%s)" \
                        --batch_file="${script}" \
                        --obs_id="${obsid}" \
                        --stderr="${error}" \
                        --stdout="${output}"
    done
    ((n+=1))
fi

echo "Submitted ${script} as ${jobid} . Follow progress here:"
echo "${output}"
echo "${error}"
