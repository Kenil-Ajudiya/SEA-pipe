#! /bin/bash

usage()
{
echo "obs_image.sh [-d dep] [-p project] [-z] [-t] obsnum
  -d dep     : job number for dependency (afterok)
  -p project : project, (must be specified, no default)
  -z         : Debugging mode: different to others! Calibrate doesn't like
               using the CORRECTED_DATA column, so if this is selected it assumes you've been using the corrected to this point and OVERWRITES THE DATA COLUMN with the corrected! USE WITH CAUTION!
  -t         : test. Don't submit job, just make the batch file
               and then return the submission command
  obsnum     : the obsid to process, or a text file of obsids (newline separated). 
               A job-array task will be submitted to process the collection of obsids. " 1>&2;
exit 1;
}

#initial variables
dep=
tst=
debug=
# parse args and set options
while getopts ':tzd:a:p:' OPTION; do
    case "$OPTION" in
	d)
	    dep=${OPTARG}
	    ;;
    p)
        project=${OPTARG}
        ;;
    z)
        debug=1
        ;;
	t)
	    tst=1
	    ;;
	? | : | h)
	    usage
	    ;;
  esac
done
# set the obsid to be the first non option
shift  "$(($OPTIND -1))"
obsnum=$1

base="${GXSCRATCH}/$project"
code="${GXBASE}"

# if obsid is empty then just print help

if [[ -z ${obsnum} ]] || [[ -z $project ]] || [[ ! -d ${base} ]]; then
    usage
fi

if [[ -n ${dep} ]]; then
    if [[ -f ${obsnum} ]]; then
        depend="--dependency=aftercorr:${dep}"
    else
        depend="--dependency=afterok:${dep}"
    fi
fi

# Establish job array options
if [[ -f ${obsnum} ]]; then
    numfiles=$(wc -l "${obsnum}" | awk '{print $1}')
    jobarray="--array=1-${numfiles}"
else
    numfiles=1
    jobarray=''
fi

# start the real program

script="${GXSCRIPT}/selfcal_${obsnum}.sh"
cat "${GXBASE}/templates/selfcal.tmpl" | sed -e "s:OBSNUM:${obsnum}:g" \
                                 -e "s:BASEDIR:${base}:g" \
                                 -e "s:DEBUG:${debug}:g" > "${script}"

output="${GXLOG}/selfcal_${obsnum}.o%A"
error="${GXLOG}/selfcal_${obsnum}.e%A"

if [[ -f ${obsnum} ]]; then
   output="${output}_%a"
   error="${error}_%a"
fi

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

sub="sbatch --begin=now+5minutes --time=12:00:00 --mem=${GXBASEMEMORY}G --cpus-per-task=${GXNCPUS} ${GXTASKLINE} --clusters=${GXCLUSTER} --account=${GXACCOUNT} --partition=${GXSTANDARDQ} --job-name=selfcal_${obsnum} ${jobarray} --output=${output} --error=${error} ${depend} ${script}_job.sh"

if [[ -n ${tst} ]]; then
    echo "script is ${script}"
    echo "submit via:"
    echo "${sub}"
    exit 0
fi
    
# submit job
jobid=($(${sub}))
jobid=${jobid[3]}

echo "Submitted ${script} as ${jobid} . Follow progress here:"

for taskid in $(seq ${numfiles}); do
    # rename the err/output files as we now know the jobid
    obserror=$(echo "${error}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")
    obsoutput=$(echo "${output}" | sed -e "s/%A/${jobid}/" -e "s/%a/${taskid}/")

    if [[ -f ${obsnum} ]]; then
        obs=$(sed -n -e "${taskid}"p "${obsnum}")
    else
        obs=$obsnum
    fi

    if [[ "${GXTRACK}" = "track" ]]; then
        # record submission
        ${GXCONTAINER} track_task.py queue --jobid="${jobid}" --taskid="${taskid}" --task='image' --submission_time="$(date +%s)" \
                            --batch_file="${script}" --obs_id="${obs}" --stderr="${obserror}" --stdout="${obsoutput}"
    fi

    echo "$obsoutput"
    echo "$obserror"
done
