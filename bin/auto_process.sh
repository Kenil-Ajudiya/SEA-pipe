#! /bin/bash

usage() {
echo "This script is used to process a list of obsids in a project directory. It will submit jobs to the SLURM scheduler to process the obsids in batches,
with each batch containing a specified number of obsids. The processing steps include getting the data from ASVO, flagging the data, applying calibration,
imaging, and post-imaging corrections. The script can also perform transient detection on the processed data.

Usage: $(basename $0) [OPTIONS] obsinp

Options:
    -e profile      : The profile to use for the processing. Default is SEA-pipe-setonix.profile in GXBASE.
    -d jobid        : SLURM JobID of the job whose successful completion is required before the first processing step starts. Default is no dependency.
    -p project      : (Required) Basename of the project directory.
    -b batchsize    : The size of the batch to process. Default is 100. This is to avoid SLURM job submission limits of 1000 submitted jobs.
                      Since there are at least 4 mandatory processing steps (autocal, apply_cal, uvflag, image), the batch size must be at less than 250.
    -c calid        : The ObsID(s) of the calibration observation(s) to use. If a single ObsID is specified, solutions from project/calid/calid_*_solutions.bin
                      will be applied. If obsinp is a text file, then calid can be a one-to-one map to the ObsIDs to be processed. Default is obsinp.
    -g              : Get the data from ASVO. If not specified, the data is assumed to be already present in the project directory.
    -f              : Flag the data using the obs_autoflag.sh script, which flags only the tiles known to be bad in specific obsids.
                      This is deprecated and will be superseded by a calibration solution flagging tool in a future version.
                      Currently, uvflag.sh attempts to flag bad visibilities (those having large amplitudes).
    -r              : Copy the mesaurement set to RAM, avoiding a significant disk I/O.
                      Faster, but needs ~3x as much RAM as the size of the measurement set. Disabled by default.
    -z              : Debugging mode: create and use a new CORRECTED_DATA column to store the calibrated data and then image that column instead of the DATA column.
                      This will almost double the size of the measurement set, so use this option only if you have enough disk space. This is useful for debugging and testing.
    -u              : Subtract out known bright sources using obs_uvsub.sh. This is especially useful to avoid contamination in the transient snapshot cubes.
    -m              : Do sidelobe subtraction using obs_sidelobe_sub.sh to avoid contamination from sidelobes. This is useful mostly at low
                      elevations and at higher frequencies where the sidelobes are above the horizon and as (or more) sensitive than the main lobe.
    -n              : Do (infield) self-calibration using obs_selfcal.sh, especially useful after subtracting the sidelobes, and apply the derived selfcal solutions.
    -i              : Do post-imaging corrections and processing using obs_postimage.sh.
    -s              : Subtract the sky model from the observed visibilities, produce a data cube of snapshot images from the residual visibilities
                      (using the obs_transient.sh script) and run the transient detection filters (using the obs_tfilter.sh script).
    -t              : Test mode. Don't submit job, just make the batch file and then return the submission command.
    -h              : Print this help message and exit.
    obsinp          : (Required) The ObsID(s) to process, or a text file of obsids (newline separated). If specifying multiple obsids, they should be separated by spaces.

Examples:
    $(basename $0) -p myproject -r obsids.txt
    $(basename $0) -p myproject -e SEA-pipe-setonix.profile -b 250 -r -s obsids.txt
    $(basename $0) -p myproject -g -f -r -u -m -n -i -s 1234567890 1234567980 1234568790
    $(basename $0) -p myproject -g -f -r -z -u -m -n -i -s 1234567890
    $(basename $0) -p myproject -t -v 1234567890

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

print_art() {
    echo -e "${BLD}${BYLW}                                      |                                       ${RST}"
    echo -e "${BLD}${BYLW}                                    \ . /                                     ${RST}"
    echo -e "${BLD}${BYLW}                                 -- . o . --                                  ${RST}"
    echo -e "${BLD}${BYLW}                                    / ' \                                     ${RST}"
    echo -e "${BLD}${BYLW}                                      |                                       ${RST}"
    echo -e ""
    echo -e "${BLD}${BBLU}______________________________________________________________________________${RST}"
    echo -e "${BLD}${BCYN}      .           .           .           .           .          .           .${RST}"
    echo -e "${BLD}${BCYN}   .  .  .     .  .  .     .  .  .     .  .  .     .  .  .    .  .  .     .  .${RST}"
    echo -e "${BLD}${BCYN}.  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  . .  .  .  .  .  .${RST}"
    echo -e "${BLD}${BCYN}.  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  . .  .  .  .  .  .${RST}"
    echo -e "${BLD}${BCYN}.  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  .  . .  .  .  .  .  .${RST}"
    echo -e ""
    echo -e "${BLD}${BCYN}          ███████╗ ███████╗  █████╗   ██████╗  ██╗ ██████╗  ███████╗          ${RST}"
    echo -e "${BLD}${BCYN}          ██╔════╝ ██╔════╝ ██╔══██╗  ██╔══██╗ ██║ ██╔══██╗ ██╔════╝          ${RST}"
    echo -e "${BLD}${BCYN}          ███████╗ █████╗   ███████║  ██████╔╝ ██║ ██████╔╝ █████╗            ${RST}"
    echo -e "${BLD}${BCYN}          ╚════██║ ██╔══╝   ██╔══██║  ██╔═══╝  ██║ ██╔═══╝  ██╔══╝            ${RST}"
    echo -e "${BLD}${BCYN}          ███████║ ███████╗ ██║  ██║  ██║      ██║ ██║      ███████╗          ${RST}"
    echo -e "${BLD}${BCYN}          ╚══════╝ ╚══════╝ ╚═╝  ╚═╝  ╚═╝      ╚═╝ ╚═╝      ╚══════╝          ${RST}"
    echo -e ""
    echo -e "${BLD}${BCYN}                   A Pipeline to Search for Exotic Activity                   ${RST}"
    echo -e ""
    echo -e "${BLD}${BGRN}              Code at https://github.com/Kenil-Ajudiya/SEA-pipe               ${RST}"
    echo -e "${BLD}${BGRN}    Report any issues at https://github.com/Kenil-Ajudiya/SEA-pipe/issues     ${RST}"
    echo -e ""
    echo -e ""
}

sanity_checks() {
    if [[ -z "${obsinp}" ]] || [[ -z "${project}" ]]; then
        echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # At least tell me your project directory name and what obsids to process.${RST}" 1>&2
        usage
        exit 1
    fi

    if [[ -n "${profile}" ]]; then # Custom profile specified on the command line, so use that.
        if [[ -f "${profile}" ]]; then
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Using profile ${profile}. GXPROFILE environment variable will be set to this profile for the job scripts."
        else
            echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # The specified profile ${profile} does not exist.${RST}" 1>&2
            echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # Do not specify the -e option if you want to use the default profile.${RST}"
            exit 1
        fi
    else # No custom profile specified, so use the default profile if it exists.
        if [[ -n "${GXPROFILE}" ]] && [[ -f "${GXPROFILE}" ]]; then
            profile="${GXPROFILE}"
        else
            echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # Profile not specified and default profile not found.${RST}" 1>&2
            echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # Please specify a profile using the -e option or set the GXPROFILE environment variable to source the default SEA-pipe-setonix.profile.${RST}"
            exit 1
        fi
    fi
    source "${profile}" # The command-line argument (-e) overrides the default profile.
    export GXPROFILE="${profile}" # The job scripts will source this profile to get the correct environment variables for the processing.

    std_logs="${GXLOG}/submission_logs/auto_process_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Logs will be stored in ${std_logs}."
    export TEMP_LOG_FILE="${std_logs//'auto_process'/'tmp'}" # The job scripts will use this log file to write their logs.
    if [[ ! -d "$(dirname '${std_logs}')" ]]; then
        mkdir -p "$(dirname '${std_logs}')"
    fi
    # Redirect stdout and stderr to both the log and the terminal
    exec > >(tee -a "${std_logs}") 2> >(tee -a "${std_logs}" >&2)

    project_dir="${GXSCRATCH}/${project}"

    if  [[ ! -d "${project_dir}" ]]; then
        if [[ -n "${getdata}" ]]; then
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Creating project directory ${project_dir}."
            mkdir "${project_dir}"
        else
            echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # Project directory ${project_dir} does not exist.${RST}" 1>&2
            echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # If you want me to get the data from ASVO, use the -g option, and I will make the project directory for you.${RST}"
            return 1
        fi
    fi
    cd "${project_dir}" || return 1

    if [[ -f "${obsinp}" ]]; then
        mapfile -t obsid_array < "${obsinp}"
    else
        obsid_array=(${obsinp})
    fi

    for obsid in "${obsid_array[@]}"; do # Validate that all the obsids are integers
        if ! [[ "${obsid}" =~ ^[0-9]+$ ]]; then
            echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # All ObsIDs must be valid integers Found: ${obsid}.${RST}" 1>&2
            return 1
        fi
    done

    if [[ "${batchsize}" -gt 250 ]]; then
        echo -e "${BLD}${BYLW}$(date '+%Y-%m-%d %H:%M:%S') # WARNING # There are 4 mandatory processing steps (autocal, apply_cal, uvflag, image), and SLURM will allow a maximum of 1000 submitted jobs.${RST}" 1>&2
        echo -e "${BLD}${BYLW}$(date '+%Y-%m-%d %H:%M:%S') # WARNING # So, batch size must be less than 250. The specified batch size is ${batchsize}>250. Setting batch size to 250.${RST}" 1>&2
        batchsize=250
    fi

    if [[ "${#obsid_array[@]}" -gt "${batchsize}" ]]; then
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} The number of obsids (${#obsid_array[@]}) exceeds the batch size (${batchsize}). Splitting the obsids into smaller batches."
        batch_mode=1
        num_batches=$(( (${#obsid_array[@]} + ${batchsize} - 1) / ${batchsize} ))
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Number of batches: ${num_batches}."
    else
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} The number of obsids (${#obsid_array[@]}) does not exceed the batch size (${batchsize}). Processing all obsids in a single batch."
        batch_mode=
    fi
    if [[ -z "${calid}" ]]; then
        calid_specified=
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} No calibration ObsID specified. Using the same ObsIDs as the input ObsIDs for calibration."
    else
        calid_specified=yes
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Calibration ObsID(s) specified: ${calid}."
    fi
}

call_submission_script() {
    local script="$1"
    local other_args="${@:2}" # Capture all arguments after the first one

    mapfile -t stdout < <(${script} ${test} ${depend} -p ${project} ${other_args} ${batch_file}; echo "$?") # Capture the exit code of obs_manta.sh and append it to the stdout array.
    printf '%s\n' "${stdout[@]:0:${#stdout[@]}-1}" # Print each line of the stdout captured in the stdout array to a new line, except the last one.
    exit_code="${stdout[-1]}" # Extract the last line of the stdout captured above, which is the exit code of obs_manta.sh.
    if [[ -z "${test}" ]]; then
        jobid="${stdout[-2]}" # Extract the second-to-last line of the stdout captured above.
        jobid="${jobid##* }" # Extract the last word from the second-to-last line, which is the job ID.
        all_submitted_jobs+=("${jobid}")
        depend="-d ${jobid}"
        echo -e "${BLD}${BGRN}$(date '+%Y-%m-%d %H:%M:%S') # LOG # JobID for ${script}: ${jobid}.${RST}"
    fi
    if [[ "${exit_code}" -ne 0 ]]; then
        echo -e "${BLD}${BRED}$(date '+%Y-%m-%d %H:%M:%S') # ERROR # ${script} failed with exit code ${exit_code}. Aborting further processing.${RST}" 1>&2
        return ${exit_code}
    fi
    sleep 1 # Sleep for a second to avoid overwhelming the SLURM scheduler with too many job submissions in a short time.
}

# This function processes the obsids in batches, submitting jobs to SLURM for each batch using the obs_*.sh scripts.
# It handles dependencies between jobs and waits for each batch to finish before starting the next one if in batch mode.
process_obsids() {
    all_submitted_jobs=() # Array to keep track of all submitted job IDs
    for ((i=0; i<${#obsid_array[@]}; i+=${batchsize})); do
        batch_obsids=("${obsid_array[@]:i:${batchsize}}")

        if [[ -z "${batch_mode}" ]]; then # We are not in batch mode, but do not overwrite any existing batch files.
            batch_file="${obsid_array[0]}.tmp"
        else
            batch_num="$(( (${i} / ${batchsize}) + 1))"
            batch_file="${project}_obsid_batch_${batch_num}.txt"
        fi
        printf '%s\n' "${batch_obsids[@]}" > "${batch_file}" # Write the batch obsids to a text file with obsids separated by newlines
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Created ObsID list file: ${batch_file} with ${#batch_obsids[@]} obsids."
        if [[ -z "${calid_specified}" ]]; then
            calid="${batch_file}"
        fi

        if [[ -n "${getdata}" ]]; then
            call_submission_script "obs_manta.sh" || return $?
        fi

        if [[ -n "${autoflag}" ]]; then
            call_submission_script "obs_autoflag.sh" || return $?
        fi

        call_submission_script "obs_autocal.sh" "${ramcopy}" || return $?

        call_submission_script "obs_apply_cal.sh" -c ${calid} ${debug} || return $?

        call_submission_script "obs_uvflag.sh" ${debug} || return $?

        if [[ -n "${uvsub}" ]]; then
            call_submission_script "obs_uvsub.sh" "${debug}" || return $?
        fi

        if [[ -n "${sidelobe}" ]]; then
            call_submission_script "obs_sidelobe_sub.sh" "${debug}" || return $?
        fi

        if [[ -n "${selfcal}" ]]; then
            call_submission_script "obs_selfcal.sh" "${debug}" || return $?

            call_submission_script "obs_apply_cal.sh" -s -c "${calid}" "${debug}" || return $?
        fi

        call_submission_script "obs_image.sh" "${ramcopy}" "${debug}" || return $?

        if [[ -n "${postimage}" ]]; then
            call_submission_script "obs_postimage.sh" || return $?
        fi

        if [[ -n "${transient}" ]]; then
            call_submission_script "obs_transient.sh" "${ramcopy}" "${debug}" || return $?

            call_submission_script "obs_tfilter.sh" || return $?
        fi

        if [[ -n "${test}" ]] || ! [[ "${jobid}" =~ ^[0-9]+$ ]]; then
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} It's either test mode or I am debugging. Did not get a numeric job ID, and probably did not submit any jobs either."
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} I am not going to wait for no reason."
        else
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Waiting for all jobs in batch ${batch_num} of ${num_batches} to finish before starting the next batch..."
            echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Meanwhile, you can watch the status of your jobs using 'squeue --me' or 'squeue -u ${USER}' in another terminal."
            # Here, squeue displays only the jobs which are either waiting for resources or still running.
            while squeue --me -h -o "%i" | grep -q ${jobid}; do # If I am able to grep the jobid, then it is still running. If not, then it has finished.
                sleep 10
            done
        fi
        depend="" # Reset the dependency for the next batch of jobs.
    done

    echo -e "${BLD}${BGRN}$(date '+%Y-%m-%d %H:%M:%S') # LOG # Completed processing all batches. Below is the accounting information for all submitted jobs:${RST}"
    echo "" # Just making some space here for a beautiful sacct table header.
    # We need to parse a comma-separated list of job IDs to the sacct command.
    sacct --jobs "$(IFS=,; echo "${all_submitted_jobs[*]}")" --units=G --format=JobID%25,JobName%50,State,ExitCode,MaxRSS,ReqMem,Elapsed,AllocCPUS,UserCPU,SystemCPU,TotalCPU
}

# Remove the ANSI color codes from the std_logs file to make them easier to read and parse.
tidy-up_log_files() {
    if [[ -f "${std_logs}" ]]; then
        sed -i 's/\x1b\[[0-9;]*m//g' "${std_logs}"
        echo -e "${BLD}${BCYN}$(date '+%Y-%m-%d %H:%M:%S') # INFO #${RST} Logs are stored in ${std_logs}."
    fi
    if [[ -f "${TEMP_LOG_FILE}" ]]; then
        rm -f "${TEMP_LOG_FILE}" > /dev/null 2>&1
    fi
}

main() {
    # Initialize variables for the flags and the parameters
    profile=
    depend=
    test=
    batchsize=100
    getdata=
    autoflag=
    ramcopy=
    debug=
    calid=
    uvsub=
    sidelobe=
    selfcal=
    postimage=
    transient=

    # Parse command-line arguments
    if [[ "$#" -eq 0 ]]; then
        echo -e "${BLD}${BMAG}$(date '+%Y-%m-%d %H:%M:%S') # HELP # I think you need some help...${RST}"
        usage
        exit 0
    fi
    while getopts 'e:d:p:b:c:gfrzumnisth' OPTION; do
        case "$OPTION" in
            e)
                profile=${OPTARG}
                ;;
            d)
                depend="-d ${OPTARG}"
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
                test=-t
                ;;
            ? | : | h)
            usage
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
    echo -e "${BLD}${BGRN}$(date '+%Y-%m-%d %H:%M:%S') # LOG # All sanity checks in auto_process.sh passed.${RST}"

    process_obsids
    exit_code=$?
    tidy-up_log_files # Tidy up the log files regardless of the exit code.
    if [[ "${exit_code}" -ne 0 ]]; then
        exit "${exit_code}"
    fi
}

def_colors

print_art

main "$@"
