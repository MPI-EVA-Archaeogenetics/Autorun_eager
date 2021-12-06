#!/usr/bin/env Rscript

## Need sidora.core to pull sequencing metainfo
if (!require('sidora.core')) {
  if(!require('remotes')) install.packages('remotes')
  remotes::install_github('sidora-tools/sidora.core', quiet=T)
} else {library(sidora.core)}

## Need pandora2eager to generate TSV table
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
  valid_entries=c("TF", "SG") ## TODO comment: should this be embedded within the function? You would want to maybe update this over time no? 
  ifelse(value %in% valid_entries, return(value), stop(call.=F, "\n[prepare_eager_tsv.tsv] error: Invalid analysis type: '", value, 
                                                       "'\nAccepted values: ", paste(valid_entries,collapse=", "),"\n\n"))
}

## Save one eager input TSV per individual. Rename if necessary. Input is already subset data.
save_ind_tsv <- function(data, rename, output_dir, ...) {

  ## Infer Individual Id(s) from input.
  ind_id <- data %>% select(Sample_Name) %>% distinct() %>% pull()
  
  if (rename) {
    data <- data %>% mutate(Library_ID=str_replace_all(Library_ID, "[.]", "_")) %>% ## Replace dots in the Library_ID to underscores.
      select(Sample_Name, Library_ID,  Lane, Colour_Chemistry, 
             SeqType, Organism, Strandedness, UDG_Treatment, R1, R2, BAM)
  }
  
  ind_dir <- paste0(output_dir,"/",ind_id)
  
  if (!dir.exists(ind_dir)) {write(paste0("[prepare_eager_tsv.tsv]: Creating output directory '",ind_dir,"'"), stdout())}
  
  dir.create(ind_dir, showWarnings = F, recursive = T) ## Create output directory and subdirs if they do not exist.
  readr::write_tsv(data, file=paste0(ind_dir,"/",ind_id,".tsv")) ## Output structure can be changed here.
}

## MAIN ##

## Parse arguments ----------------------------
parser <- OptionParser(usage = "%prog [options] .credentials")
parser <- add_option(parser, c("-s", "--sequencing_batch_id"), type = 'character', 
                     action = "store", dest = "sequencing_batch_id", 
                     help = "The Pandora sequencing batch ID to update eager input for. A TSV file will be prepared
			for each individual in this run, containing all relevant processed BAM files
			from the individual")
parser <- add_option(parser, c("-a", "--analysis_type"), type = 'character',
                     action = "callback", dest = "analysis_type",
                     callback = validate_analysis_type, default=NA,
                     help = "The analysis type to compile the data from. Should be one of: 'SG', 'TF'.")
parser <- add_option(parser, c("-r", "--rename"), type = 'logical',
                     action = 'store_true', dest = 'rename', default=F,
                     help = "Changes all dots (.) in the Library_ID field of the output to underscores (_).
			Some tools used in nf-core/eager will strip everything after the first dot (.)
			from the name of the input file, which can cause naming conflicts in rare cases."
                     )
parser <- add_option(parser, c("-o", "--outDir"), type = 'character',
                     action = "store", dest = "outdir",
                     help= "The desired output directory. Within this directory, one subdirectory will be 
			created per analysis type, within that one subdirectory per individual ID,
			and one TSV within each of these directory."
                     )
parser <- add_option(parser, c("-d", "--debug_output"), type = 'logical',
                     action = "store_true", dest = "debug", default=F,
                     help= "When provided, the entire result table for the run will be saved as '<seq_batch_ID>.results.txt'.
			Helpful to check all the output data in one place."
)
                     
arguments <- parse_args(parser, positional_arguments = 1)
opts <- arguments$options

cred_file <- arguments$args
sequencing_batch_id <- opts$sequencing_batch_id
analysis_type <- opts$analysis_type

if (is.na(analysis_type)) {
  stop(call.=F, "\n[prepare_eager_tsv.tsv] error: No analysis type provided with -a. Please see --help for more information.\n")
}

output_dir <- paste0(opts$outdir,"/",analysis_type)

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

tibble_input_iids <- complete_pandora_table %>% filter(sequencing.Batch == sequencing_batch_id) %>% select(individual.Full_Individual_Id)

## Pull information from pandora, keeping only matching IIDs and requested Sequencing types.
results <- inner_join(complete_pandora_table, tibble_input_iids, by=c("individual.Full_Individual_Id"="individual.Full_Individual_Id")) %>%
  filter(grepl(paste0("\\.", analysis_type), sequencing.Full_Sequencing_Id)) %>%
  select(individual.Full_Individual_Id,individual.Organism,library.Full_Library_Id,library.Protocol,analysis.Result_Directory,sequencing.Sequencing_Id,sequencing.Full_Sequencing_Id,sequencing.Single_Stranded) %>%
  distinct() %>% ## TODO comment: would be worrying if not already unique, maybe consider throwing a warn?
  group_by(individual.Full_Individual_Id) %>%
  filter(!is.na(analysis.Result_Directory)) %>% ## Exclude individuals with no results directory (seem to mostly be controls)
  mutate(
    BAM=paste0(analysis.Result_Directory,sequencing.Full_Sequencing_Id,".bam"),
    ## Colour chemistry should not matter since we start with BAMs
    Colour_Chemistry=4,
    ## SeqType and Seq Lane should not matter since we start with BAMs
    SeqType="SE",
    Lane=row_number(),
    Strandedness=case_when(
      sequencing.Single_Stranded == 'yes' ~ "single",
      sequencing.Single_Stranded == 'no' ~ "double",
      is.na(sequencing.Single_Stranded) ~ "Unknown"), ## So far, any NAs are for libraries that were never sequenced, but just in case.
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

## Save results into single file for debugging
if ( opts$debug ) { write_tsv(results, file=paste0(sequencing_batch_id, ".", analysis_type, ".results.txt")) }

## Group by individual IDs and save each chunk as TSV
results %>% group_by(Sample_Name) %>% group_walk(~save_ind_tsv(., rename=F, output_dir=output_dir), .keep=T)
