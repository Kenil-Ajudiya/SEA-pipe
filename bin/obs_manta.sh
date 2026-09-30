#! /bin/bash

usage() {
echo "This script submits a SLURM job to download MWA data from the All Sky Virtual Observatory (ASVO) using the manta-ray-client.

Useful links:
    MWA ASVO - https://asvo.mwatelescope.org/
    manta-ray-client - https://github.com/MWATelescope/manta-ray-client

Usage: $(basename $0) [OPTIONS] obsinp

Options:
    -d jobid        : SLURM JobID of the job whose successful completion is required before this job starts. Default is no dependency.
    -p project      : (Required) Basename of the project directory.
    -s timeres      : Time resolution in sec. Default = 4 s.
    -k freqres      : Frequency resolution in KHz. Default = 40 kHz.
    -r              : Enables --allow-resubmit option while calling the manta-ray-client (using the mwa_client copmmand). Disabled by default.
    -f edgeflag     : Number of band edge channels to flag. Default = 80.
    -t              : Test mode. Don't submit job, just make the batch file and then return the submission command.
    -h              : Print this help message and exit.
    obsinp          : (Required) The ObsID(s) to process, or a text file of obsids (newline separated). If specifying multiple obsids, they should be separated by spaces.

Examples:
    $(basename $0) -p myproject obsids.txt
    $(basename $0) -p myproject -r 1234567890
    $(basename $0) -p myproject -s 8 -k 80 1234567890 1234568790
    $(basename $0) -p myproject -t obsids.txt

Author: Kenil Ajudiya (k.ajudiya@postgrad.curtin.edu.au)"
}

def_colors() {
    # Bright foreground colors
    BRED='\033[91m'           # Bright Red
    BGRN='\033[92m'           # Bright Green
    BYLW='\033[93m'           # Bright Yellow
    BBLU='\033[94m'           # Bright Blue
    BMAG='\033[95m'           # Bright Magenta
    BCYN='\033[96m'           # Bright Cyan
    BWHT='\033[97m'           # Bright White

    # Bold
    BLD='\033[1m'

    # Reset formatting
    RST='\033[0m'
}

sanity_checks() {
    if [[ -z "${obsinp}" ]] || [[ -z "${project}" ]]; then
        echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # At least tell me your project directory name and what obsids to process.${RST}" 1>&2
        usage
        exit 1
    fi

    if [[ -n "${TEMP_LOG_FILE}" ]]; then
        std_logs="${TEMP_LOG_FILE}"
    else
        std_logs="${GXLOG}/submission_logs/obs_manta_$(date +%Y%m%d_%H%M%S).log"
    fi
    if [[ ! -d "$(dirname '${std_logs}')" ]]; then
        mkdir -p "$(dirname '${std_logs}')"
    fi
    # Redirect stdout and stderr to both the log and the terminal
    exec > >(tee -a "${std_logs}") 2> >(tee -a "${std_logs}" >&2)

    project_dir="${GXSCRATCH}/${project}"
    if [[ ! -d "${project_dir}" ]]; then
        mkdir "${project_dir}" || { echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # Failed to create project directory ${project_dir}.${RST}" 1>&2;  return 1; }
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Created project directory ${project_dir}."
    fi
    cd "${project_dir}" || return 1

    if [[ -f "${obsinp}" ]]; then
        mapfile -t obsid_array < "${obsinp}"
    else
        obsid_array=(${obsinp})
        if [[ "${#obsid_array[@]}" -gt 1 ]]; then
            obsinp="${obsid_array[0]}_and_$((${#obsid_array[@]}-1))_more"
        fi
    fi

    temp_obsid_array=()
    for obsid in "${obsid_array[@]}"; do # Validate that all the obsids are integers
        if ! [[ "${obsid}" =~ ^[0-9]+$ ]]; then
            echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # All ObsIDs must be valid integers Found: ${obsid}.${RST}" 1>&2
            return 1
        fi

        if [[ -d "${obsid}/${obsid}.ms" ]]; then
            echo -e "${BLD}${BYLW}$(date '+%Y-%m-%d %H:%M:%S') # WARNING # ${obsid}/${obsid}.ms already exists. I will not download it again.${RST}" 1>&2
            echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # If you want to re-download it, please delete the directory ${obsid} first.${RST}" 1>&2
        else
            temp_obsid_array+=("${obsid}") 
        fi
    done
    obsid_array=("${temp_obsid_array[@]}")
    if [[ "${#obsid_array[@]}" -eq 0 ]]; then
        echo -e "${BLD}${BYLW}$(date '+%Y-%m-%d %H:%M:%S') # WARNING # All obsids already exist. Nothing to download.${RST}" 1>&2
        return 0
    fi
}

submit_job() {
    rm -f "${obsinp}_manta.tmp" > /dev/null 2>&1
    for obsid in "${obsid_array[@]}"; do # Prepare the CSV file with the obsids and their parameters for the MWA client
        echo "obs_id=${obsid}, preprocessor=birli, delivery=scratch, job_type=c, avg_time_res=${timeres}, avg_freq_res=${freqres}, flag_edge_width=${edgeflag}, output=ms" >>  "${obsinp}_manta.tmp"
    done

    if [[ -n "${dep_jobid}" ]]; then
        depend="--dependency=afterok:${dep_jobid}"
    else
        depend=
    fi

    script="${GXSCRIPT}/manta_${obsinp}.sh"

    cat "${GXBASE}/templates/manta.tmpl" | sed -e "s:OBSINP:${obsinp}:g" \
                                            -e "s:RESUBMIT:${allow_resubmit}:g" \
                                            -e "s:PROJECT_DIR:${project_dir}:g" > "${script}"

    chmod 755 "${script}"

    output="${GXLOG}/slurm_logs/manta_${obsinp}.o%A"
    error="${GXLOG}/slurm_logs/manta_${obsinp}.e%A"

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
    echo "export FI_CXI_DEFAULT_VNI=$(od -vAn -N4 -tu < /dev/urandom | tr -d ' ')" >> "${script}_job.sh"
    echo "srun singularity run ${GXCONTAINER} ${script}" >> "${script}_job.sh"

    # This is the only task that should reasonably be expected to run on another cluster. It is possible that accounting is not performed by SLURM.
    if [[ -n "${GXCOPYA}" ]]; then
        account="--account=${GXCOPYA}"
    else
        account="--account=${GXACCOUNT}"
    fi

    # Export the MWA_ASVO_API_KEY to ensure that ASVO authentication works correctly.
    sub="sbatch --begin=now+2minutes --time=2-00:00:00 --mem=10G --cpus-per-task=1 ${GXTASKLINE} --clusters=${GXCOPYM} ${account} --partition=${GXCOPYQ} --job-name=manta_${obsinp} --export=MWA_ASVO_API_KEY --output=${output} --error=${error} ${depend} ${script}_job.sh"

    if [[ -n "${test}" ]]; then
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # TEST #${RST} The SLURM batch script is ${script}"
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # TEST #${RST} In the production mode, I would have printed:"
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # TEST #${RST} Submitted ${script} as JOBID"
        return 0
    fi

    # Submit the SLURM job and capture the job ID.
    jobid=($(${sub})) # This prints "Submitted batch job JOBID on cluster setonix" to stdout, which is captured in the array jobid.
    jobid="${jobid[3]}" # The JOBID is the 4th element of the array (index 3).
    echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Submission command: ${sub}"

    # Record the submission in the processing database.
    if [[ "${GXTRACK}" == "track" ]]; then
        # Rename the error and output shell variables as we now know the jobid.
        error="${error//%A/${jobid}}"
        output="${output//%A/${jobid}}"

        for i in $(seq "${#obsid_array[@]}"); do
            track_task.py queue --jobid=${jobid} --taskid=0 --task='download' --submission_time=$(date +%s) \
                --batch_file=${script}_job.sh --obs_id=${obsid_array[$((i-1))]} --stderr=${error} --stdout=${output}
        done
    fi

    # Do not echo anything after the jobid - it has to be the last word printed to stdout, without a full-stop.
    # Do not redirect the stdout to stderr.
    # This is used to capture the jobid in the auto_process.sh script.
    echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Submitted ${script} as ${jobid}"
}

tidy-up_log_files() {
    if [[ -f "${std_logs}" ]]; then
        sed -i 's/\x1b\[[0-9;]*m//g' "${std_logs}"
        # The auto_process.sh script sets the TEMP_LOG_FILE environment variable to the log file name.
        # It also captures all the stdout and stderr of this script to its own log file and deletes this file after the script finishes.
        if [[ -z "${TEMP_LOG_FILE}" ]]; then # Print the log file location if TEMP_LOG_FILE is not set.
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Logs are stored in ${std_logs}."
        fi
    fi
}

main() {
    # Initialize variables for the flags and the parameters
    dep_jobid=
    test=
    timeres=
    freqres=
    allow_resubmit=
    edgeflag=80

    # Parse command-line arguments
    if [[ "$#" -eq 0 ]]; then
        echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # I think you need some help...${RST}"
        usage
        exit 0
    fi
    while getopts 'd:p:s:k:f:rth' OPTION; do
        case "$OPTION" in
            d)
                dep_jobid="${OPTARG}"
                ;;
            p)
                project="${OPTARG}"
                ;;
            s)
                timeres="${OPTARG}"
                ;;
            k)
                freqres="${OPTARG}"
                ;;
            f)
                edgeflag="${OPTARG}"
                ;;
            r)
                allow_resubmit=yes
                ;;
            t)
                test=yes
                ;;
            ? | : | h)
                usage
                exit 1
                ;;
        esac
    done
    shift  "$((${OPTIND} - 1))"
    obsinp="$@"

    sanity_checks
    exit_code=$?
    if [[ "${exit_code}" -ne 0 ]]; then # If sanity_checks failed, tidy up the log files and exit with the same exit code.
        tidy-up_log_files
        exit "${exit_code}"
    fi
    echo -e "${BLD}${BGRN}$(date '+%Y-%m-%d %H:%M:%S') # LOG # All sanity checks in obs_manta.sh passed.${RST}"

    submit_job
    exit_code=$?
    tidy-up_log_files # Tidy up the log files regardless of the exit code.
    if [[ "${exit_code}" -ne 0 ]]; then
        exit "${exit_code}"
    fi
}

def_colors

main "$@"
