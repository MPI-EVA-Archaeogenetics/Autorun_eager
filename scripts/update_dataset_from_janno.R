#!/usr/bin/env Rscript

require(optparse)
require(magrittr)
if (!require('eager2poseidon')) {
  if(!require('remotes')) install.packages('remotes')
  write("Installing required package 'sidora-tools/eager2poseidon'...", file=stderr())
  remotes::install_github('sidora-tools/eager2poseidon')
  # require(eager2poseidon)
}
require(yaml)

## Function to read the indFile data depending on format
read_indFile_data <- function(ind_fn, db_format) {
  ## Validate db_format input
  if (! db_format %in% c('EIGENSTRAT', 'PLINK') ) {
    stop(paste0("[read_indFile_data()]: Invalid database format provided: '", db_format,"'. Must be one of 'EIGENSTRAT' or 'PLINK'."))
  }

  ## Read in data
  if (db_format == 'EIGENSTRAT') {
    data <- readr::read_tsv(
      ind_fn, 
      col_names = c("Sample_Name", "Genetic_Sex", "Population"),
      col_types='ccc'
    )
  } else if (db_format == 'PLINK') {
    data <- readr::read_tsv(
      ind_fn,
      col_names = c("Population", "Sample_Name", 'father', 'mother', "sex_code", "case_control"),
      col_types='cccccc'
    ) %>%
    dplyr::mutate(
      Genetic_Sex=dplyr::case_when(
        .data$sex_code == '1' ~ "M",
        .data$sex_code == '2' ~ "F",
        TRUE ~ "U"
      )
    )
  }
  data
}

## Function to write the indFile data based on format.
write_indFile_data <- function(ind_fn, data, db_format) {
  ## Validate db_format input
  if (! db_format %in% c('EIGENSTRAT', 'PLINK') ) {
    stop(paste0("[write_indFile_data()]: Invalid database format provided: '", db_format,"'. Must be one of 'EIGENSTRAT' or 'PLINK'."))
  }

  ## Write indFile data
  if (db_format == 'EIGENSTRAT') {
    out_data <- data %>%
      dplyr::select("Sample_Name", "Genetic_Sex", "Population")
  } else if (db_format == 'PLINK') {
    out_data <- data %>%
      ## Recode the genetic sex to the plink number format.
      dplyr::mutate(
        Sex_Code = dplyr::case_when(
          .data$Genetic_Sex == "M" ~ "1",
          .data$Genetic_Sex == "F" ~ "2",
          TRUE ~ "0"
        )
      ) %>%
      ## Put the columns in the right order
      ##   fam format: "Population", "Sample_Name", 'father', 'mother', "sex_code", "case_control"
      dplyr::select("Group_Name", "Sample_Name", "father", "mother", "Sex_Code", "case_control")
  }
  readr::write_tsv(out_data, ind_fn, append = F, col_names = F, num_threads = 1)
}

## Parse arguments ----------------------------
parser <- OptionParser()
parser <- add_option(parser, c("-y", "--poseidon_yml_fn"),
  default = '',
  type = "character",
  action = "store", dest = "poseidon_yml_fn",
  help = "The input poseidon yaml file."
)
args <- parse_args(parser)

if (args$poseidon_yml_fn == '') {
  stop("No input POSEIDON.yml file provided.")
} else if (! file.exists(args$poseidon_yml_fn)) {
  stop(paste0("File does not exist: '", args$poseidon_yml_fn, "'"))
}

## Read in poseidon yaml data
poseidon_yml_data <- yaml::read_yaml(args$poseidon_yml_fn)

## Infer path to ind file from path to yml
ind_fn <- paste0(dirname(args$poseidon_yml_fn),"/",poseidon_yml_data$genotypeData$indFile)
janno_fn <- paste0(dirname(args$poseidon_yml_fn),"/",poseidon_yml_data$jannoFile)
db_format <- poseidon_yml_data$genotypeData$format

## Read in indFile data
ind_fn_data <- read_indFile_data(ind_fn, db_format)

## Read in janno and keep relevant columns
input_janno_table <- eager2poseidon::standardise_janno(janno_fn) %>%
  dplyr::select("Poseidon_ID", "Genetic_Sex", "Group_Name") %>%
  ## Create field with only first Group_Name in case multiple are in the janno
  tidyr::separate( Group_Name, into="Population", sep=';', extra = 'drop' )

output <- dplyr::left_join(ind_fn_data, input_janno_table, by=c("Sample_Name"="Poseidon_ID"), suffix = c(".x", ".y")) %>%
  dplyr::select(-tidyselect::ends_with(".x")) %>%
  dplyr::rename_with(.fn=~sub('\\.y$', '', .), .cols=tidyselect::ends_with(".y"))

## Overwrite indFile with new information.
write_indFile_data(ind_fn, output, db_format)
