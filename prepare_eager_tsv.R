#!/usr/bin/env Rscript

if (!require('sidora.core')) {
  if(!require('remotes')) install.packages('remotes')
  remotes::install_github('sidora-tools/sidora.core', quiet=T)
} else {library(sidora.core)}
if (!require('pandora2eager')) {
  if(!require('remotes')) install.packages('remotes')
  remotes::install_github('sidora-tools/pandora2eager', quiet=T)
} else {library(pandora2eager)}
require(purrr)
require(dplyr, warn.conflicts = F)
require(optparse)
require(readr)

## Validate analysis type option input
validate_analysis_type <- function(option, opt_str, value, parser) {
  valid_entries=c("TF", "SG")
  ifelse(value %in% valid_entries, return(value), stop(call.=F, "\nInvalid analysis type: '", value, 
                                                       "'\nAccepted values: ", paste(valid_entries,collapse=", "),"\n\n"))
}

## MAIN ##

## Parse arguments ----------------------------
parser <- OptionParser(usage = "%prog [options] .credentials")
parser <- add_option(parser, c("-i", "--input_iid"), type = 'character', 
                     action = "store", dest = "input_iid", 
                     help = "The Pandora individual ID of the input individual. A TSV file will be prepared with all relevant processed BAM files from this\n\t\tindividual")
parser <- add_option(parser, c("-a", "--analysis_type"), type = 'character',
                     action = "callback", dest = "analysis_type",
                     callback = validate_analysis_type, default=NA,
                     help="The analysis type to compile the data from. Should be one of: 'SG', 'TF'.")
parser <- add_option(parser, c("-r", "--rename"), type='logical',
                     action='store_true', dest='rename', default=F,
                     help="Changes all dots (.) in the Library_ID field of the output to underscores (_).
			Some tools used in nf-core/eager will strip everything after the first dot (.)
			from the name of the input file, which can cause naming conflicts in rare cases."
                     )
arguments <- parse_args(parser, positional_arguments = 1)

opts <- arguments$options
cred_file <- arguments$args


tibble_input_iid <- tibble("Ind"=opts$input_iid)
analysis_type <- opts$analysis_type

#############
## PANDORA ##
#############

con <- get_pandora_connection(cred_file)

## Get complete pandora table
complete_pandora_table <- join_pandora_tables(
  get_df_list(
    c(make_complete_table_list(
      c("TAB_Site", "TAB_Analysis")
    )), con = con
  )
) %>% convert_all_ids_to_values(., con = con)

## Pull information from pandora, keeping only matching IIDs and requested Sequencing types.
results <- inner_join(complete_pandora_table, tibble_input_iid, by=c("individual.Full_Individual_Id"="Ind")) %>%
  filter(grepl(paste0("\\.", analysis_type), sequencing.Full_Sequencing_Id)) %>%
  select(individual.Full_Individual_Id,individual.Organism,library.Full_Library_Id,library.Protocol,analysis.Result_Directory,sequencing.Sequencing_Id) %>%
  distinct() %>%
  mutate(
    BAM=paste0(analysis.Result_Directory,"out.bam"),
    ## Colour chemistry should not matter since we start with BAMs
    Colour_Chemistry=4,
    ## SeqType and Seq Lane should not matter since we start with BAMs
    SeqType="SE",
    Lane=row_number(),
    Strandedness=map_chr(library.Protocol, function (.) {pandora2eager::infer_library_specs(.)[1]}), 
    UDG_Treatment=map_chr(library.Protocol, function(.){pandora2eager::infer_library_specs(.)[2]}),
    R1=NA,
    R2=NA
    ) %>%
  select(
    "Sample_Name"=individual.Full_Individual_Id,
     "Library_ID"=library.Full_Library_Id,
     "Lane",
     "Colour_Chemistry",
     "SeqType",
     "Organism"=individual.Organism,
     "Strandedness",
     "UDG_Treatment",
     "R1",
     "R2",
     "BAM"
    )
if (opts$rename) {
  cat(
    format_tsv(results %>% 
                 mutate(Library_ID=str_replace_all(Library_ID, "[.]", "_")) %>% ## Replace dots in the Library_ID to underscores.
                 select(Sample_Name, Library_ID,  Lane, Colour_Chemistry, 
                        SeqType, Organism, Strandedness, UDG_Treatment, R1, R2, BAM))
  )
} else {
  cat(
    format_tsv(results %>% 
                 select(Sample_Name, Library_ID,  Lane, Colour_Chemistry, 
                        SeqType, Organism, Strandedness, UDG_Treatment, R1, R2, BAM))
  )
}
