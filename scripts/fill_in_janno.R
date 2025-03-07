#!/usr/bin/env Rscript

require(optparse)
library(magrittr)
if (!require('eager2poseidon')) {
  if(!require('remotes')) install.packages('remotes')
  write("Installing required package 'sidora-tools/eager2poseidon'...", file=stderr())
  remotes::install_github('sidora-tools/eager2poseidon')
  # require(eager2poseidon)
} else {require(eager2poseidon)}
if (!require('eagerR')) {
    write("Installing required package 'TCLamnidis/eagerR'...", file=stderr())
    remotes::install_github('TCLamnidis/eagerR')
    # require(eagerR)
} else {require(eagerR)}
if (!require('poseidonR')) {
    write("Installing required package 'poseidon-framework/poseidonR'...", file=stderr())
    remotes::install_github('poseidon-framework/poseidonR')
    # require(poseidonR)
} else {require(poseidonR)}
if (!require('rPandoraHelper')) {
    write("Installing required local package 'rPandoraHelper'...", file=stderr())
    install.packages("/mnt/archgen/tools/helper_scripts/r_helpers/rPandoraHelper/", repos = NULL, type = "source")
    # require(rPandoraHelper)
} else {require(rPandoraHelper)}

## Parse arguments ----------------------------
parser <- OptionParser()
parser <- add_option(parser, c("-j", "--input_janno"),
  type = "character",
  action = "store", dest = "janno_fn",
  help = "The input janno file."
)
parser <- add_option(parser, c("-i", "--ind_id"),
  type = "character",
  action = "store", dest = "ind_id",
  help = "The individual ID whose package janno should be updated."
)
parser <- add_option(parser, c("-c", "--credentials"),
  type = "character",
  action = "store", dest = "credentials",
  help = "Path to a credentials file containing four lines listing the database host, the port of the database server, user and password, respectively."
)
parser <- add_option(parser, c("-s", "--contamination_snp_cutoff"),
  type = "integer",
  action = "store", default = "100", dest = "snp_cutoff",
  help = "The snp cutoff for nuclear contamination results. Nuclear contamination results with fewer than this number of SNPs will be ignored when calculating the values for 'Contamination_*' columns. [100]"
)
parser <- add_option(parser, c("-S", "--ss_suffix"),
  type = "character",
  action = "store", default = "", dest = "ss_suffix",
  help = "The suffix appended to the sample name of single_stranded data in the eager TSV. ['']"
)
parser <- add_option(parser, c("-p", "--genotypePloidy"),
  type = 'character',
  action = "store", dest = "genotype_ploidy",
  metavar="ploidy",
  help = "The genotype ploidy of the genotypes produced by eager. This value will be used to fill in all missing entries in the 'Genotype_Ploidy' in the output janno file."
)
parser <- add_option(parser, c("-o", "--output_janno"),
  type = "character",
  action = "store", dest = "output_fn", default = "",
  help = "By default, the input janno is overwritten. Providing a path to this option instead writes the new janno file to the specified location."
)

args <- parse_args(parser)

## DEBUG For debugging ease
# print(args, file=stderr())

## If no output is provided, output_fn is the input janno path.
if (args$output_fn == "") {
  output_fn <- args$janno_fn
} else {
  output_fn <- args$output_fn
}

input_janno_table <- eager2poseidon::standardise_janno(args$janno_fn)

## Create new column `Pandora_ID` that removes the ss_suffix (if present) from the Poseidon ID to infer the Pandora_ID of the individual.
## Uses rParndoraHelper::get_ind_id to infer the Pandora ID of the individual.
sample_ids <- dplyr::select(input_janno_table, Poseidon_ID) %>%
  rowwise() %>%
  dplyr::mutate(Pandora_ID=rPandoraHelper::get_ind_id(Poseidon_ID, keep_ss_suffix=F )) %>%
  ungroup()

##################
## Pandora info ##
##################

## Collect Pandora results for Pandora IDs.
pandora_results <- eager2poseidon::import_pandora_data(sample_ids %>% dplyr::select(Pandora_ID) %>% dplyr::distinct(), args$credentials, trust_uncalibrated_dates = TRUE) %>%
  dplyr::full_join(sample_ids, ., by = "Pandora_ID") %>% 
  ## drop Pandora_ID column. not needed anymore
  dplyr::select(-Pandora_ID)

## Use rPandoraHelper to infer Pandora IDs from input ind_id
pandora_site_id <- rPandoraHelper::get_site_id(args$ind_id, keep_ss_suffix=F)
pandora_ind_id  <- rPandoraHelper::get_ind_id(args$ind_id, keep_ss_suffix=F)
## Infer locations of different JSONs to read results in with eagerR. (More flexible than e2p and can pull results from SG runs if present)
base_dir <- "/mnt/archgen/Autorun_eager"
# base_dir <- "/Users/lamnidis/mount"
eager_tsv_fn <- paste0(base_dir, "/eager_inputs/TF/", pandora_site_id, "/", pandora_ind_id,"/", pandora_ind_id, ".tsv")
eager_tf_results_dir <- paste0(base_dir, "/eager_outputs/TF/", pandora_site_id, "/", pandora_ind_id,"/")
eager_sg_endorspy_dir <- paste0(base_dir, "/eager_outputs/SG/", pandora_site_id, "/", pandora_ind_id,"/endorspy/")
eager_sg_damageprofiler_dir <- paste0(base_dir, "/eager_outputs/SG/", pandora_site_id, "/", pandora_ind_id,"/damageprofiler/")

##############
## TSV info ##
##############

## Read eager TSV data
tsv_dat <- eagerR::read_input_tsv_data(eager_tsv_fn) %>% 
  eagerR::infer_merged_bam_names(run_trim_bam = T) %>%
  dplyr::ungroup()

## Add number of libraries, capture type, overall UDG treatment and Strandedness columns
poseidon_tsv_cols <- tsv_dat %>% dplyr::select(Sample_Name, Library_ID, Strandedness, UDG_Treatment) %>%
  dplyr::group_by(Sample_Name, Strandedness) %>%
  dplyr::summarise(.groups='keep',
    UDG=dplyr::case_when(
      unique(UDG_Treatment) %>% length(.) > 1 ~ 'mixed',
      TRUE ~ unique(UDG_Treatment)
    ),
    Nr_Libraries=dplyr::n(),
    Capture_Type=paste0(rep("1240K", Nr_Libraries), collapse=";"),
    Library_Built=dplyr::case_when(
      Strandedness == 'single' ~ 'ss',
      Strandedness == 'double' ~ 'ds',
      TRUE ~ NA_character_
    )
  ) %>%
  dplyr::distinct() ## This is at sample level, so only keep one entry per sample ID

################
## TF RESULTS ##
################

## Collect Sexdet results
sexdet <- eagerR::read_sexdet_json(paste0(eager_tf_results_dir,"/sex_determination/sexdeterrmine.json")) %>% 
  dplyr::filter(sexdet_input_bam %in% tsv_dat$sexdet_bam)

## Collect snp_cov results
## If both ssDNA and dsDNA data exist, collect results from both
snp_cov_fns <- list.files(path=paste0(eager_tf_results_dir,"/genotyping/"), pattern = "_eigenstrat_coverage_mqc.json", full.names=T)
snpcov <- purrr::map_dfr(snp_cov_fns, eagerR::read_snp_coverage_json)

## Collect nuclear contamination results
nuccont <- eagerR::read_angsd_cont_json(paste0(eager_tf_results_dir,"/nuclear_contamination/nuclear_contamination_mqc.json"))

################
## SG RESULTS ##
################
## In some cases, no SG is created, and instead data is directly TF captured. then no endogenous and dmg results will be available.

## Collect damageprofiler output from SG results
if (file.exists(eager_sg_damageprofiler_dir)) {
  damageprof <- eagerR::read_damageprofiler_jsons_from_dir(eager_sg_damageprofiler_dir)
} else {
  ## If this file doesnt exist, set to NULL, that the compiling function can deal with
  damageprof <- NULL
}

## Collect Endogenous DNA results from SG results
if (file.exists(eager_sg_endorspy_dir)) {
  endogenous <- eagerR::read_endorspy_jsons_from_dir(eager_sg_endorspy_dir) #%>%
  #dplyr::filter(endorspy_library_id %in% tsv_dat$Library_ID) ## Might not be needed with the right join function, right?
} else {
  ## If this file doesnt exist, set to NULL, that the compiling function can deal with
  endogenous <- NULL
}

## Put together the different tables
updated_columns <- eager2poseidon::compile_eager_result_tables(
    tsv_table = tsv_dat,
    sexdet_table = sexdet,
    snpcov_table = snpcov,
    dmg_table = damageprof,
    endogenous_table = endogenous,
    nuccont_table = nuccont,
    contamination_method = "1",
    contamination_algorithm = "ml",
    XX_cutoffs = c(0.7, 1.2, 0.0, 0.1),
    XY_cutoffs = c(0.2, 0.6, 0.3, 0.6),
    capture_type = "1240K"
  ) %>%
  ## Compile across-library results (weighted sums etc)
  eager2poseidon::compile_across_lib_results(snp_cutoff = args$snp_cutoff) %>%
  ## Keep only relevant columns from eager results
  dplyr::select(tidyselect::all_of(c(
    "Sample_Name",
    "Genetic_Sex",
    "Sex_Determination_Note",
    "Nr_SNPs",
    "Endogenous",
    "Contamination",
    "Contamination_Err",
    "Contamination_Note",
    "Contamination_Meas",
    "Damage",
    "UDG",
    "Nr_Libraries",
    "Library_Names", ## Column including all the Library_IDs merged into these genotypes
    "Library_Built",
    "Capture_Type"
  ))) %>%
  ## Remove ss_suffix from library names, so they match Pandora Library IDs
  ## NOTE: Should this be changed to use rPandoraHelper? Would require some tweaking to work with list columns, as it currently expects a single ID.
  dplyr::mutate(
    Library_Names=gsub('_ss','',.data$Library_Names) %>% vctrs::vec_unique()
  ) %>%
  ## Keep distinct rows, now that Library_ID has been dropped
  dplyr::distinct() %>%
  ## Add pandora columns
  dplyr::left_join(., pandora_results, by=c("Sample_Name"="Poseidon_ID"))

## Stitch together the results!
new_janno <- dplyr::left_join(input_janno_table, updated_columns, by=c("Poseidon_ID"="Sample_Name"), suffix = c(".x", ".y")) %>%
  ## !! OVERWRITE !! Replace any columns existing in both with the updated column contents
  dplyr::select(-tidyselect::ends_with(".x")) %>%
  dplyr::rename_with(.fn=~sub('\\.y$', '', .), .cols=tidyselect::ends_with(".y")) %>%
  ## Then follow janno standardisation operations
  ##    First, convert everything to characters
  dplyr::mutate(
    dplyr::across(
      .fn = as.character
    )
  ) %>%
  ##    Now can change NAs to weird janno 'n/a'
  base::replace(is.na(.), "n/a") %>%
  ##    And read as a janno table
  poseidonR::as.janno()

## Finally, save the new janno
poseidonR::write_janno(new_janno, output_fn)

