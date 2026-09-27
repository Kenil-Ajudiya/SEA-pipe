#! /bin/bash

usage()
{
echo "obs_tfilter.sh [-d dep] [-p project] [-t] obsnum
  -d dep     : job number for dependency (afterok)
  -p project : project, (must be specified, no default)
  -t         : test. Don't submit job, just make the batch file
               and then return the submission command
  obsnum     : the obsid to process, or a text file of obsids (newline separated). 
               A job-array task will be submitted to process the collection of obsids. " 1>&2;
exit 1;
}

#initial variables
dep=
tst=
# parse args and set options
while getopts ':td:a:p:' OPTION; do
    case "$OPTION" in
	d)
	    dep=${OPTARG}
	    ;;
    p)
        project=${OPTARG}
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

# if obsid is empty then just print help

if [[ -z ${obsnum} ]] || [[ -z $project ]] || [[ ! -d ${base} ]]; then
    usage
fi

if [[ -n ${dep} ]]; then
    depend="--dependency=afterok:${dep}"
fi

# start the real program
script="${GPMSCRIPT}/tfilter_${obsnum}.sh"
cat "${GPMBASE}/templates/tfilter.tmpl" | sed -e "s:OBSNUM:${obsnum}:g" \
                                              -e "s:BASEDIR:${base}:g" > "${script}"

output="${GPMLOG}/tfilter_${obsnum}.o%A"
error="${GPMLOG}/tfilter_${obsnum}.e%A"

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

sub="sbatch --begin=now+5minutes --time=03:00:00 --mem=${GXBASEMEMORY}G --cpus-per-task=${GXNCPUS} ${GXTASKLINE} --clusters=${GXCLUSTER} --account=${GXACCOUNT} --partition=${GXSTANDARDQ} --job-name=tfilter_${obsnum} ${jobarray} --output=${output} --error=${error} ${depend} ${script}_job.sh"

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
echo "${output}"
echo "${error}"
