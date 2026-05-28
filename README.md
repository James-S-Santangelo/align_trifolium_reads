## Analyses of genomic data for Toronto_GWSD

### Description of repository

INSERT PROJECT DESCRIPTION HERE

The pipeline uses `Conda`, `Snakemake`, and `Apptainer` (formerly
`Singularity`) for workflow management and reproducibility. All Snakefiles and
directories are well-documented, but here is a brief overview of the pipeline
and directories in this repository:

#### Overview of directories

- [config](./config): Snakemake configuration files for different clusters.
- [resources](./resources): Text files used in pipeline (e.g., sample
  information, chromosomes, etc.)
- [workflow](./workflow): Main Snakemake workflow with rules, environments,
  scripts, notebooks, and cluster profiles for running the pipeline on Compute
  Canada SLURM-based clusters.

### Using the pipeline

This pipeline requires `Conda` and `Singularity`:

- A minimal installation of `Conda` (i.e., Miniconda) can be installed by
  following the instructions for your platform
  [here](https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html)
- Installation of `Apptainer` (formerly `Singularity`) requires Admin
  privileges, but using `Apptainer` to run pre-created containers does not.
  Installation instructions can be found
  [here](https://apptainer.org/docs/admin/main/installation.html). All
  containers used in this pipeline are avalaible in [this public
  reposity](https://cloud.sylabs.io/library/james-s-santangelo), though they
  will be automatically pulled and executed by the pipeline. 

Assuming `Conda` is installed, the this repository's `Conda` environment can be
replicated by running the following command:

`conda env create -f environment.yaml -n <env_name>`

This will create a `Conda` environment named _<env\_name>_ containing a minimal
set of dependencies required to run the pipeline (e.g., Python 3.12 and
Snakemake 9.21.0).

After activating the environment (`conda activate <env_name>`), the pipeline can
be executed from the [workflow](./workflow) directory by running a command that
looks something like:

`snakemake --configfile ../config/serverl.yaml --profile profile/ -j <cores>`

Here, `<cores>` is the number of cores available for executing parallel processes. 

Note that the YAML configfile at [config](./config/server.yaml) will
likely need to be modified to accommodate the paths to files on you server.

For execution on a SLURM cluster, the pipeline can be executed by running:

`snakemake --configfile ../config/server.yaml --profile profile/ --workflow-profile slurm/`

Note that the YAML configfile at [slurm](./workflow/slurm/confilg.yaml) will
likely need to be modified to accommodate the paths on your cluster.

