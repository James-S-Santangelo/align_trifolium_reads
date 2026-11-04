#!/bin/bash
#SBATCH --job-name=smk_controller
#SBATCH --account=def-santang3_cpu
#SBATCH --time=3-00:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=12G
#SBATCH --output=smk_controller_%j.out
# Submit from the workflow directory (the one containing profile/ and slurm/),
# since --configfile ../config/server.yaml is a relative path.

set -eo pipefail   # no -u: conda activate scripts reference unset variables

# ---- EDIT: output of `conda info --base` on the login node ----
CONDA_BASE="${HOME}/miniforge3"
ENV_NAME="clover_align"

cd "${SLURM_SUBMIT_DIR}"

# Load apptainer before conda so the env's PATH wins. Child jobs inherit PATH
# (the SLURM plugin submits with --export=ALL).
module load apptainer

source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${ENV_NAME}"

# Strip this allocation's SLURM_* variables so they don't leak into the sbatch
# calls snakemake makes for each rule. Newer plugin versions do this
# themselves; this covers older ones. Keep SLURM_CONF if the site sets it.
for v in $(compgen -e | grep '^SLURM_' | grep -v '^SLURM_CONF$'); do
    unset "$v"
done

# Record versions for provenance
echo "Host: $(hostname)  Start: $(date)"
snakemake --version
conda list | grep -E 'snakemake-executor-plugin' || true

snakemake \
    --configfile ../config/server.yaml \
    --workflow-profile profile/ \
    --profile slurm/ \
    --conda-prefix /scratch/santang3/conda_envs/ \
    --sdm conda apptainer \
    --rerun-triggers mtime

echo "End: $(date)"
