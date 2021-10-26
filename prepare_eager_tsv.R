#!/usr/bin/env Rscript

if (!require('sidora.core')) {
  if(!require('remotes')) install.packages('remotes')
  remotes::install_github('sidora-tools/sidora.core', quiet=T)
} else {library(sidora.core)}
if (!require('pandora2eager')) {
  if(!require('remotes')) install.packages('remotes')
  remotes::install_github('sidora-tools/pandora2eager', quiet=T)
} else {library(sidora.core)}
library(tidyverse, warn.conflicts = F)

## MAIN ##

## Parse arguments ----------------------------
parser <- OptionParser(usage = "%prog [options] .credentials")
parser <- add_option(parser, c("-i", "--input_iid"), type = 'character', 
                     action = "store", dest = "input_iid", 
                     help = "The Pandora individual ID of the input individual. A TSV file will be prepared with all relevant processed BAM files from this\n\t\tindividual")
parser <- add_option(parser, c("-a", "--analysis_type"), type='character',
                     action ='store', dest = "analysis_type",
                     help="The analysis type to compile the data from. Should be one of: 'SG', 'TF'.")
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

