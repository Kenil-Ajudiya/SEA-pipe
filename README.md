# SEA-pipe: A Pipeline to Search for Exotic Activity

SEA-pipe is a transient-search adaptation of the MWA processing workflow originally developed in the GLEAM-X pipeline. The upstream repository is the GLEAM-X pipeline at <https://github.com/GLEAM-X/GLEAM-X-pipeline>. This repository keeps the parts of that workflow that are relevant for searching for transient and variable activity in MWA observations, while dropping the broader survey-production and archive stages that are not required for this use case.

The pipeline is designed for HPC environments and uses a containerised software stack together with SLURM job submission. It follows the same overall structure as the upstream pipeline: named stages are implemented as template scripts and generated job scripts, with the generated work scripts run inside the container context.

## Project scope

This repository is intentionally focused on the transient-search workflow. The retained components cover:

- downloading or preparing MWA measurement sets,
- calibration and self-calibration,
- RFI flagging and source subtraction,
- imaging and post-imaging corrections,
- residual-image transient searches and filtering.

The broader GLEAM-X survey mosaicking, archive-transfer, and database tracking components are not the focus of this branch and are not described here in detail.

## Repository layout

- `bin/`: generated job scripts for each processing stage
- `templates/`: template shell scripts used to build stage-specific batch jobs
- `containers/`: container build scripts
- `sea_src/`: Python utilities used by the processing scripts
- `example_profiles/`: example environment profiles for cluster setup
- `ssh_keys/`: optional SSH key material for pipeline-specific access

## Design

The processing flow is split into stages, each with a template script and a generator script. The generator script adapts the template for a specific observation or project, replacing placeholders with observation-specific values and submitting the job to the scheduler.

This makes it straightforward to run the same workflow repeatedly for many observations while keeping the task logic in a small number of reusable templates.

## Singularity container

SEA-pipe currently uses the same Singularity container as the GLEAM-X pipeline. The container provides the compiled radio-astronomy software and Python environment used by the processing stages, so the workflow does not require those scientific dependencies to be installed on the host system. A SEA-pipe-specific container will replace this shared GLEAM-X container in a future update.

The container is configured with the `GXCONTAINER` variable in the profile. Processing jobs also use `SINGULARITY_BINDPATH` to make the repository, scratch space, generated scripts, calibration data, beam models, and other required paths available inside the container. Singularity and SLURM must be available on the HPC system.

## Pipeline configuration

SEA-pipe is configured through a shell profile. The profile should define the HPC and filesystem settings needed by the generated jobs, including:

- `GXBASE`: the local SEA-pipe checkout and installation base,
- `GXSCRATCH`: scratch space for observation data and intermediate products,
- `GXHOME`: a writable home directory visible inside the container,
- `GXCONTAINER`: the path to the Singularity image,
- `GXCLUSTER`, `GXSTANDARDQ`, `GXACCOUNT`, and copy-job settings for SLURM,
- `GXABSMEMORY`, `GXMEMORY`, and CPU settings for resource requests,
- `GXLOG` and `GXSCRIPT` for task logs and generated scripts,
- `GXMWAPB` and `GXMWALOOKUP` for MWA beam-model data, and
- `SINGULARITY_BINDPATH` for paths exposed inside the container.

The configuration variables retain the `GX` prefix for compatibility with the upstream GLEAM-X workflow. An example profile is provided at `example_profiles/SEA-pipe-setonix.profile`. Profiles are cluster-specific: SLURM queues, resource limits, filesystem paths, and container locations must be changed to match the target HPC system. A completed profile must be sourced before running any `obs_*.sh` script.

## Metadata tracking database

The pipeline can optionally record task state in a MySQL database. Tracking is enabled by setting `GXTRACK=track`; any other value, including the default `no-track`, disables task tracking. When enabled, the templates call `track_task.py` to record task submission, start, completion, and failure states. Database access is configured through a secrets file or environment variables. The required variables are `GXDBHOST`, `GXDBPORT`, `GXDBUSER`, and `GXDBPASS`. These values must not be committed to the repository.

> ⚠️ WARNING
>
> A separate MySQL server needs to be created with an appropriate database schema and user authentication details. The database tables can be created using the `make_db.py` script and must be located in the `sea_src/db` directory before enabling tracking - the `track_task.py` script does not create a database on first use. The GLEAM-X database should not be used with this pipeline.

## Deployment and installation

The following steps provide a practical deployment sequence for an HPC system running SLURM:

1. Clone this repository onto the target HPC system.
2. Copy `example_profiles/SEA-pipe-setonix.profile` to a cluster-specific profile and edit the paths, SLURM queues, resource settings, data locations, and container path.
3. Obtain the current GLEAM-X Singularity container and set `GXCONTAINER` to its absolute path. The container is currently shared with GLEAM-X; a project-specific replacement is planned.
4. Ensure Singularity and SLURM are available, then source the completed profile. Sourcing it creates the configured log and generated-script directories and prepares the required MWA beam-model dependencies where applicable.
5. Install SEA-pipe with Hatch/Hatchling if host-side package access is needed by running `python -m pip install .`. The operational scientific software remains supplied by the Singularity container; a host Python installation is not a substitute for the container.
6. With the profile still loaded, run the relevant `obs_*.sh` scripts or the `auto_process.sh` convenience driver.

The profile should be sourced in each shell before running pipeline commands, or from the login setup used on the target cluster. Do not reuse a profile between HPC systems without checking its cluster name, queues, resource requests, paths, bind mounts, and container location. If task tracking is enabled, configure the `GXDB*` variables separately and verify database access before submitting a full workflow.

## Typical workflow

A standard transient-search workflow is:

1. Download or locate the relevant MWA measurement sets.
2. [Optional] Flag known problematic tiles using `obs_autoflag.sh`.
3. Run `obs_autocal.sh` to derive calibration solutions.
4. Apply the selected calibration using `obs_apply_cal.sh`.
5. Flag bad visibilities by _uv_-distance using `obs_uvflag.sh`.
6. [Optional] Subtract bright sources or sidelobe contamination using `obs_uvsub.sh` and `obs_sidelobe_sub.sh`.
7. [Optional] Run `obs_selfcal.sh` to improve the calibration if bright sources or sidelobes have been subtracted.
8. Image the observation using `obs_image.sh`.
9. [Optional] Apply post-imaging corrections using `obs_postimage.sh`.
10. Construct residual time-step images and run the transient detection filters on them using `obs_transient.sh` and `obs_tfilter.sh`.

The convenience driver script `auto_process.sh` chains the common sequence together for a single observation or a list of observations.

## Script descriptions

### `auto_process.sh`

This is the high-level workflow driver for a typical transient-search run. It coordinates the main observation-processing sequence and can optionally fetch data, run autoflagging, calibration, source subtraction, self-calibration, post-imaging corrections, and transient filtering. It is designed to streamline the common end-to-end flow for a project while still allowing individual stages to be run separately when needed.

### `obs_manta.sh`

This stage obtains the relevant MWA measurement sets from the archive and performs the cotter conversion and download steps needed to produce a usable dataset. It is the entry point for retrieving raw or partially processed visibility data before calibration and imaging begin.

### `obs_autoflag.sh`

This script applies known bad-tile and observation-specific flagging information to the data before deeper calibration and RFI cleaning. It is intended to remove obvious problem channels or antenna tiles early in the pipeline, reducing the number of artefacts that later stages must handle.

### `obs_autocal.sh`

This stage generates calibration solutions using the sky-model-based approach used throughout the transient-search workflow. It derives a set of calibration solutions for each observation and provides the basis for applying a stable instrumental solution before deeper imaging and transient detection work.

### `obs_apply_cal.sh`

This task applies a previously derived calibration solution to a measurement set. It is used after calibration solutions have been generated and selected, so that the calibrated visibilities can be used in subsequent flagging, imaging, and subtraction steps.

### `obs_uvflag.sh`

This script performs visibility-domain RFI detection and flagging by examining the data as a function of uv-distance and other summary statistics. It is intended to remove contaminated visibilities before imaging and source subtraction, which is especially important for transient and low-level variability searches.

### `obs_uvsub.sh`

This stage subtracts bright contaminating sources, especially sources that are predicted to lie just outside the field of view and produce sidelobe contamination. It builds small local models around problematic sources and subtracts them from the visibilities so that later imaging is cleaner and more stable.

### `obs_selfcal.sh`

This stage performs in-field self-calibration to improve the calibration solutions, especially after source subtraction or other aggressive data processing. The goal is to refine the phase and amplitude solutions so that deeper imaging and transient searching are less affected by residual instrumental errors.

### `obs_sidelobe_sub.sh`

This task removes sidelobe contamination that is strongest at low elevations or in parts of the beam where the sidelobes approach the main-lobe response. It is useful for reducing image artefacts that would otherwise confuse source-finding and transient detection.

### `obs_image.sh`

This stage creates the main calibrated image products for an observation. It produces the deep image products needed for source detection, validation, and the later residual-image transient work. The workflow is built around multi-frequency and multi-channel imaging with a standard clean strategy.

### `obs_postimage.sh`

This stage applies post-imaging corrections such as source finding and image-based corrections for directional distortions or residual systematic effects. It is used to refine source catalogues and image products before the final transient-analysis stages.

### `obs_transient.sh`

This is the core transient-imaging stage. It subtracts the deep clean model from the visibilities and forms time-step residual images, which are then used to search for long-period and other transient behaviour. This is the workhorse stage of the search pipeline.

### `obs_tfilter.sh`

This stage applies transient detection filtering to the residual data products produced by the transient imaging stage. The filters are designed to isolate candidate events and suppress artefacts, producing a cleaned candidate list or filtered image products for further inspection.

## Notes

- The scripts in this repository are designed to be run on an HPC system with SLURM and a containerised software stack.
- Each stage is intended to operate on a project directory containing observation folders, with the observation number forming the key identifier for the processing pipeline.
- The template-based design makes it easy to reuse the same workflow across many observations while keeping the per-observation details in a small number of generated scripts.
