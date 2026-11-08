# Summarise per-project MultiQC general stats into two tables across projects:
#   1. sample_qc: one row per sample (mosdepth, samtools flagstat, Picard)
#   2. read_qc:   one row per lane (fastp on the read pair; FastQC on R1 and R2)
#
# Called from rule qc_summary via `script:`, so inputs come from the
# `snakemake` S4 object. Units follow MultiQC's general stats export:
# read counts are in millions, percentages are 0-100.

log <- file(snakemake@log[[1]], open = "wt")
sink(log, type = "message")
sink(log, type = "output")

suppressPackageStartupMessages({
    library(readr)
    library(dplyr)
    library(tidyr)
    library(stringr)
    library(purrr)
})

multiqc_dirs <- snakemake@input[["multiqc"]]
projects     <- snakemake@params[["projects"]]
stopifnot(length(multiqc_dirs) == length(projects))

# Expected lanes and their FASTQs, from the pipeline's FASTQ discovery
lane_map <- tibble(
    sample   = as.character(snakemake@params[["lane_sample"]]),
    lane     = as.integer(snakemake@params[["lane_index"]]),
    r1_fastq = as.character(snakemake@params[["lane_r1"]]),
    r2_fastq = as.character(snakemake@params[["lane_r2"]])
)

sheet <- read_tsv(snakemake@input[["samples"]], col_types = cols(.default = col_character())) |>
    select(sample, project = initial_project)

# Sample-level metrics kept in sample_qc (MultiQC column -> output column)
SAMPLE_METRICS <- c(
    "mosdepth-median_coverage"                   = "median_coverage",
    "mosdepth-mean_coverage"                     = "mean_coverage",
    "samtools_flagstat-flagstat_total"           = "total_reads_M",
    "samtools_flagstat-mapped_passed_pct"        = "pct_mapped",
    "picard_mark_duplicates-PERCENT_DUPLICATION" = "pct_duplication"
)

fail <- function(...) stop(paste0(...), call. = FALSE)
show <- function(x, n = 10) paste0(paste(head(x, n), collapse = ", "), if (length(x) > n) ", ..." else "")

read_project <- function(dir, proj) {
    path <- file.path(dir, "multiqc_general_stats.txt")
    gs <- read_tsv(path, col_types = cols(Sample = col_character(), .default = col_double()))
    if (nrow(problems(gs)) > 0) {
        fail(path, ": non-numeric values in metric columns:\n",
             paste(capture.output(print(problems(gs))), collapse = "\n"))
    }
    proj_samples <- sheet$sample[sheet$project == proj]

    # Row names are {sample} (mosdepth, flagstat, sometimes Picard),
    # {sample}_lane{i} (fastp, sometimes Picard) or {sample}_lane{i}_R{1,2} (FastQC)
    m <- str_match(gs$Sample, "^(.+)_lane(\\d+)(?:_R([12]))?$")
    is_sample_row <- gs$Sample %in% proj_samples
    parsed <- gs |>
        mutate(
            sample = if_else(is_sample_row, Sample, m[, 2]),
            lane   = if_else(is_sample_row, NA_integer_, as.integer(m[, 3])),
            read   = if_else(is_sample_row, NA_character_, m[, 4]),
            project = proj
        )

    unmatched <- parsed$Sample[is.na(parsed$sample) | !parsed$sample %in% proj_samples]
    if (length(unmatched) > 0) {
        fail(path, ": ", length(unmatched), " row(s) do not map to a sample of project '",
             proj, "' in the sample sheet: ", show(unmatched))
    }
    parsed
}

gs_all <- bind_rows(Map(read_project, multiqc_dirs, projects))  # base Map: errors surface unwrapped

# ── 1. Sample-level QC ──────────────────────────────────────────────────────
missing_cols <- setdiff(names(SAMPLE_METRICS), names(gs_all))
if (length(missing_cols) > 0) fail("MultiQC general stats lack column(s): ", show(missing_cols))

# Percent of genome at >= tX, for whichever thresholds MultiQC exported
# (default 1, 5, 10, 30, 50X); inserted after mean_coverage
cov_cols <- str_subset(names(gs_all), "^mosdepth-\\d+_x_pc$")
if (length(cov_cols) == 0) fail("MultiQC general stats lack mosdepth genome-coverage columns (mosdepth-<t>_x_pc)")
cov_cols <- cov_cols[order(as.integer(str_extract(cov_cols, "\\d+")))]
cov_metrics <- setNames(paste0("pct_genome_ge_", str_extract(cov_cols, "\\d+"), "x"), cov_cols)
i <- match("mosdepth-mean_coverage", names(SAMPLE_METRICS))
SAMPLE_METRICS <- c(SAMPLE_METRICS[1:i], cov_metrics, SAMPLE_METRICS[-(1:i)])

sample_long <- gs_all |>
    select(project, sample, all_of(names(SAMPLE_METRICS))) |>
    pivot_longer(all_of(names(SAMPLE_METRICS)), names_to = "metric", values_drop_na = TRUE)

# Picard can appear on {sample} or {sample}_lane0 depending on how MultiQC names
# the metrics file; each metric must still occur exactly once per sample
multi <- sample_long |> count(project, sample, metric) |> filter(n > 1)
if (nrow(multi) > 0) {
    fail("Sample-level metric reported more than once: ",
         show(paste0(multi$sample, " (", multi$metric, ")")))
}

sample_qc <- sheet |>
    filter(project %in% projects) |>
    left_join(pivot_wider(sample_long, names_from = metric, values_from = value),
              by = c("project", "sample")) |>
    rename(any_of(setNames(names(SAMPLE_METRICS), SAMPLE_METRICS))) |>
    select(sample, project, all_of(unname(SAMPLE_METRICS))) |>
    arrange(project, sample)

incomplete <- sample_qc |> filter(if_any(all_of(unname(SAMPLE_METRICS)), is.na))
if (nrow(incomplete) > 0) {
    fail(nrow(incomplete), " sample(s) are missing sample-level metrics: ", show(incomplete$sample))
}

# ── 2. Read-level QC (one row per lane) ─────────────────────────────────────
tidy_names <- function(x) str_replace(x, "-", "_")

fastp <- gs_all |>
    filter(!is.na(lane), is.na(read)) |>
    select(project, sample, lane, starts_with("fastp-")) |>
    filter(if_any(starts_with("fastp-"), ~ !is.na(.x))) |>
    rename_with(tidy_names, starts_with("fastp-"))

fastqc <- gs_all |>
    filter(!is.na(read)) |>
    select(project, sample, lane, read, starts_with("fastqc-")) |>
    rename_with(~ str_remove(.x, "^fastqc-"), starts_with("fastqc-")) |>
    pivot_wider(names_from = read, values_from = -c(project, sample, lane, read),
                names_glue = "fastqc_r{read}_{.value}")
# Keep R1 columns before R2 columns, metrics in MultiQC order
fastqc <- fastqc |>
    select(project, sample, lane, starts_with("fastqc_r1_"), starts_with("fastqc_r2_"))

expected <- lane_map |>
    inner_join(sheet, by = "sample") |>
    filter(project %in% projects)

read_qc <- expected |>
    full_join(fastp,  by = c("project", "sample", "lane")) |>
    full_join(fastqc, by = c("project", "sample", "lane")) |>
    select(sample, project, lane, r1_fastq, r2_fastq,
           starts_with("fastp_"), starts_with("fastqc_r1_"), starts_with("fastqc_r2_")) |>
    arrange(project, sample, lane)

lane_id <- function(d) paste0(d$sample, "_lane", d$lane)
problems_found <- list(
    "not among the pipeline's lanes"  = read_qc |> filter(is.na(r1_fastq)),
    "missing fastp metrics"           = read_qc |> filter(if_all(starts_with("fastp_"), is.na)),
    "missing FastQC R1 metrics"       = read_qc |> filter(if_all(starts_with("fastqc_r1_"), is.na)),
    "missing FastQC R2 metrics"       = read_qc |> filter(if_all(starts_with("fastqc_r2_"), is.na))
) |> keep(~ nrow(.x) > 0)
if (length(problems_found) > 0) {
    fail("Read-level QC is incomplete:\n",
         paste0("  ", names(problems_found), ": ", map_chr(problems_found, ~ show(lane_id(.x))),
                collapse = "\n"))
}

# MultiQC exports counts as raw/1e6 (e.g. 0.04999999999999999); 6 decimals
# keeps counts exact and removes the floating-point noise
tidy_numbers <- function(d) mutate(d, across(where(is.double), ~ round(.x, 6)))

write_tsv(tidy_numbers(sample_qc), snakemake@output[["sample_qc"]], na = "NA")
write_tsv(tidy_numbers(read_qc),   snakemake@output[["read_qc"]],   na = "NA")

message(sprintf("%d samples and %d lanes across %d project(s): %s",
                nrow(sample_qc), nrow(read_qc), length(projects), paste(projects, collapse = ", ")))
