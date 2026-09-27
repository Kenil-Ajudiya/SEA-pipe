#! /bin/bash

echo "Loading SEA-pipe profile..."

# Any system module file should be loaded here. Aside from singularity and slurm there are no additional modules that are expected to be needed.
module load singularity/4.1.0-slurm

# Before running obs_*.sh scripts ensure the completed configuration file has been sourced.
# As a convention when specifying paths below, please ensure that they do not end with a trailing '/', as this assists in readability when combining paths.

# Basic configuration
export GXUSER=$(whoami)         # User name of the operator running the pipeline. This is here to generate user-specific filenames and paths.
                                # It is recommend to use the login account name, although in principal this is not critical and other approaches could be adopted.
export GXVERSION='4.0.0'        # Version number of the pipeline. This should not be changed. Currently it is defined here but not used.
export GXACCOUNT="pawsey0272"   # The SLURM account jobs will be run under. e.g. 'pawsey0272'. Empty will not pass through a
                                # corresponding --account=${GXACCOUNT} to the slurm submission. Only relevant if SLURM is tracking time usage.
export SOFTBASE="/software/projects/pawsey0272"         # Path to the base of the software installation. This is where the GLEAM-X singularity container and data dependencies are stored.
export GXBASE="${SOFTBASE}/${GXUSER}/SEA-pipe"          # Path to the base of SEA-Pipe, where the repository was git cloned into, including the name of the repository foldername, e.g. "${SOFTBASE}/${GXUSER}/SEA-pipe".
export GXPROFILE="${GXBASE}/SEA-pipe-setonix.profile"   # Path to the profile file, e.g. "${GXBASE}/SEA-pipe-setonix.profile".
export GXSCRATCH="/scratch/pawsey0272/${GXUSER}"        # Path to your scratch space used for processing on the HPC environment, e.g. /scratch/pawsey0272/${GXUSER}.
export GXHOME="${GXSCRATCH}"    # HOME space for some tasks. In some system configurations singularity can not mount $HOME, but applications (e.g. CASA, python) would like
                                # one to be available to cache folders. This does not have to be an actual $HOME directory, just a folder with read and write access.
                                # Suggestion is the same path as the scratch space, e.g. $GXSCRATCH. Although if the HPC is configured correctly it could be set to HOME.
                                # This variable is not used in any tasks -- but it used in the creation of the SINGULARITY_BINDPATH variable.
export GXCONTAINER="${SOFTBASE}/containers/gleamx_container_21Mar25.img"  # Absolute path to the GLEAM-X singularity container, including the file name, e.g. "${SOFTBASE}/containers/gleamx_container_21Mar25.img".
# This container is still being evaluated and available upon request from Kenil Ajudiya. In a future update, the container will be automatically downloaded alongside other data dependencies.

# SLURM compute schedular information
export GXCLUSTER="setonix"      # System-wide name of cluster, e.g. "setonix". This should match the name of the cluster, which can be checked with 'scontrol show config' under ClusterName.
                                # This is used when submitting tasks 'sbatch --clusters=${GXCLUSTER}', and in track_task.py as a component of the composite key.
export GXSTANDARDQ="work"       # Slurm queue/partition to submit tasks to, e.g. "work". Available queues can be inspected using 'sinfo' on a system where the slurm schedular is available

# GXNCPUS and GXBASEMEMORY are ignored by the pipeline components that require very less compute resources, e.g., obs_manta.sh, obs_autoflag.sh, etc.
export GXNCPUS=128              # Number of CPUs of each machine, e.g. 48. For tasks that have a 'core' like option this value is passed.
export GXBASEMEMORY=200         # Absolute memory a machine should be considered to have in GB, e.g. 60. This value is submitted to slurm via "--mem=${GXBASEMEMORY}"
export GXMEMORY=180             # Memory limit (in GB) for programs like 'wsclean' to fit within the memory allocation alongside other overheads.
# It is recommended that this be ~10G smaller than GXABSMEMORY, although there is no technical reason - it could be set otherwise.
# If you are loading the entire measurement set into memory, then this value should be set to GXBASEMEMORY - (the size of the measurement set, ~10-15G).

# Restrict to a single node and single task for now, as none of the components of the pipeline are parallelised across nodes, and each node has enough CPUs to handle the workload.
# There is a known issue with the Slingshot netowrk on Setonix resulting in MPI failures when MPI spreads its ranks across multiple nodes.
# This is documented at https://pawsey.atlassian.net/wiki/spaces/US/pages/51929082/Known+Issues+on+Setonix#Issues-with-Slingshot-network.
# Pawsey also suggests setting the environment variable FI_CXI_DEFAULT_VNI to a random value before the execution of each srun command to avoid MPI rank collisions across jobs, 
# in case a task ends up spanning multiple nodes.
# See https://pawsey.atlassian.net/wiki/spaces/US/pages/51927426/Example+Slurm+Batch+Scripts+for+Setonix+on+CPU+Compute+Nodes for more details on FI_CXI_DEFAULT_VNI usage.
export GXTASKLINE="--nodes=1 --ntasks=1"        # This is passed to all SLURM sbatch calls.

export GXLOG="${GXBASE}/log_${GXCLUSTER}"       # Path to output task logs, e.g. ${GXBASE}/queue/log_${GXCLUSTER}. It is recommended that this is cluster specific. 
export GXSCRIPT="${GXBASE}/script_${GXCLUSTER}" # Path to place generated execution scripts. e.g. "${GXBASE}/script_${GXCLUSTER}". It is recommended that this is cluster specific.
export GXTRACK='no-track'                       # Directive to inform task tracking for meta-database. 'track' will track task progression. Anything else will disable tracking. 

# Details for obs_manta
export GXCOPYA='pawsey0272'     # Account to submit obs_manta.sh job under, if time accounting is being performed by SLURM.
                                # Leave this empty if the job is to be submitted as the user and there is no time accounting.
export GXCOPYQ='copy'           # A required parameter directing the job to a particular queue on $GXCOPYM. Set as just the queue name, e.g. 'copyq'
export GXCOPYM='setonix'        # A required parameter directing the job to be submitted to a particular machine. Set as just the machine name, e.g. 'zeus'

# Data dependencies
# Data dependencies are downloaded into the directories below if the directories do not exist. 
export GXMWAPB="${SOFTBASE}/data/mwa_pb"    # The calibrate program requires the FEE model of the MWA primary beam.
                                            # This describes the path that containers the file mwa_full_embedded_element_pattern.h5
                                            # and can be downloaded from http://ws.mwatelescope.org/static/mwa_full_embedded_element_pattern.h5
                                            # If this folder does not exist, it is created. 
export GXMWALOOKUP="${SOFTBASE}/data/pb"    # The path to the folder containing the MWA PB lookup HDF5's used by lookup_beam.py and lookup_jones.py. 
                                            # If this folder does not exist, it is created. 

# Singularity bind paths
# This describes a set of paths that need to be available within the container for all processing tasks. Depending on the system
# and pipeline configuration it is best to have these explicitly set across all tasks. For each 'singularity run' command this
# SINGULARITY_BINDPATHS will be used to mount against. These GX variables should be all that is needed on a typical deployed 
# pipeline, but can be used to further expose/enhance functionality if desired. 
export SINGULARITY_BINDPATH="${GXHOME}:${HOME},${GXSCRIPT},${SOFTBASE},${GXBASE},${GXSCRATCH},${GXMWALOOKUP}:/pb_lookup,${GXMWAPB},${GXSTAGE},/scratch/mwasci/asvo"

export PATH="${PATH}:${GXBASE}/bin" # Adds the obs_* script to the searchable path. 

# Force matplotlib to write configuration to a location with write access. Attempting to fix issues on pawsey 
export MPLCONFIGDIR="${GXSCRATCH}"
# Redirect astropy cache and home location. Attempting to fix issue on pawsey.
export XDG_CONFIG_HOME="${GXSCRATCH}"
export XDG_CACHE_HOME="${GXSCRATCH}"

# Loads a file that contains secrets used throughout the pipeline. These include
# - MWA_ASVO_API_KEY
# - GXDBHOST
# - GXDBPORT
# - GXDBUSER
# - GXDBPASS
# This GXSECRETS file is expected to export each of the variables above. 
# This file SHOULD NOT be git tracked! 
GXSECRETS="${GXBASE}/secrets/SEA_secrets.profile"
if [[ -f ${GXSECRETS} ]]; then
    source "${GXSECRETS}"
fi

# Check that required variables have a value. This perfoms a simple 'is empty' check
for var in GXCLUSTER GXSTANDARDQ GXBASEMEMORY GXMEMORY GXNCPUS GXUSER GXCOPYQ GXCOPYM GXLOG GXSCRIPT; do
    if [[ -z ${!var} ]]; then
        echo "${var} is currently not configured, please ensure it was a valid value"
        return 1
    fi
done

# Check that the following values that point to a path actually exist. These are ones that (reasonably) should not
# automatically be created
for var in GXBASE GXSCRATCH GXHOME; do
    if [[ ! -d ${!var} ]]; then
        echo "The ${var} configurable has the path ${!var}, which appears to not exist. Please ensure it is a valid path."
        return 1
    fi
done

# Creates directories as needed below for the mandatory paths if they do not exist
if [[ ! -d "${GXLOG}" ]]; then
    mkdir -p "${GXLOG}"
fi

if [[ ! -d "${GXSCRIPT}" ]]; then
    mkdir -p "${GXSCRIPT}"
fi

# Go fourth and download the data dependencies
if [[ -d ${GXBASE} ]]; then
    if [[ ! -d ${GXMWAPB} ]]; then
        echo "Creating ${GXMWAPB} and caching FEE hdf5 file"
        mkdir -p ${GXMWAPB} \
            && wget -P ${GXMWAPB} http://ws.mwatelescope.org/static/mwa_full_embedded_element_pattern.h5
    fi

    if [[ ! -d ${GXMWALOOKUP} ]]; then
        echo "You don't have the MWA PB lookup files. These are required to do a quick primary beam correction in the image.tmpl script. You can ask WSCLEAN to calculate the primary beam on the fly, but it is much slower."
        echo "Feel free to contact Kenil Ajudiya to get the files and point the GXMWALOOKUP variable to the correct location."
        # echo "Creating ${GXMWALOOKUP} and caching hdf5 lookup files"
        # mkdir -p ${GXMWALOOKUP} \
        #     && wget -O pb_lookup.tar.gz -P ${GXMWALOOKUP} https://cloudstor.aarnet.edu.au/plus/s/77FRhCpXFqiTq1H/download \
        #     && tar -xzvf pb_lookup.tar.gz -C ${GXMWALOOKUP} \
        #     && rm pb_lookup.tar.gz

    fi
fi
