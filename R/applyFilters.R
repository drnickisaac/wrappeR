#' \code{applyFilters} - Apply filters to occupancy model outputs.
#' 
#' @description This function can be used to subset the occupancy model
#'              outputs based on number of records, priority/ pollinator status
#'              and region. It works at the level of the taxonomic group so
#'              must be applied across multiple groups if needed.
#'
#' @param roster String. A dataframe with columns: datPath, modPath, ver, indicator, region,
#'               nSamps, minObs, write, outPath, clipBy, group (see \code{createRoster}). 
#'               
#' @param parallel Boolean. Should the operation run in parallel? If so then use n.cores-1.
#' 	  
#' @return A dataframe with processed model outputs to be passed to \code{calcMSI}.
#'         
#' @export
#' 

applyFilters <- function(roster, parallel = TRUE) {

  data(speciesInfo)
  
  if (roster$indicator == "priority") {

    keepInds <- which(!is.na(speciesInfo[, roster$region])) 
    
    ## use both latin names and concept codes to screen for priority species 
    
    keep <- c(as.character(speciesInfo$Species[keepInds]), 
              as.character(speciesInfo$concept[keepInds]))

    keep <- keep[-which(is.na(keep))]

  } else if (roster$indicator == "pollinators") {
    
    keep <- sampSubset("pollinators",
                       inPath = roster$metaPath)
    
  } else {
    
    modFilePath <- file.path(roster$modPath, roster$group, "occmod_outputs", roster$ver)
    
    # try .rdata
    modFiles_rdata <- list.files(modFilePath, pattern = ".rdata")
    
    # try .rds
    modFiles_rds <- list.files(modFilePath, pattern = ".rds")
    
    if (length(modFiles_rdata) == 0 & length(modFiles_rds) == 0) 
      stop("Model files must be either .rds or .rdata")
    
    else {
      
      if(length(modFiles_rdata) == 0) {
        filetype <- "rds"
        modFiles <- modFiles_rds}
      else {
        filetype <- "rdata"
        modFiles <- modFiles_rdata}
      
    }
    
    # retain the species names (with iteration number if applicable - chained models)
    keep_iter <- gsub(pattern = paste0("\\.", filetype), repl = "", modFiles)
  }
  
  first_spp <- keep_iter[[1]]
  
  # test if first species is chained (i.e., JASMIN models)
  if (substr(first_spp, (nchar(first_spp) + 1) - 2, nchar(first_spp)) %in% c("_1", "_2", "_3")) {
    
    keep <- gsub("(.*)_\\w+", "\\1", keep_iter) # remove all after last underscore (e.g., chain "_1")
    keep <- gsub("(.*)_\\w+", "\\1", keep) # remove all after last underscore (e.g., iteration "_2000")
    
    keep <- unique(keep) # unique species names
    
  } else {
    
    # species names don't have associated iteration numbers - non-chained models
    keep <- keep_iter
    
    keep_iter <- NULL
    
  }
  
  # Subset to speciesToKeep
  if(!is.na(roster$speciesToKeep)){
    
    # Convert the comma separated species names to a vector of species
    speciesToKeep <- unlist(strsplit(roster$speciesToKeep, ','))
    
    # Species not found
    notFound <- speciesToKeep[!tolower(speciesToKeep) %in% tolower(keep)]
    
    if(length(notFound) > 0){
      warning(paste('some species on your "speciesToKeep" list were not found in the data:',
                    paste(notFound, collapse = ', ')))
    }
    
    # Subset keep
    keep <- keep[tolower(keep) %in% tolower(speciesToKeep)]
    
  }
  
  if(roster$drop == TRUE) {
    
    ## select which species to drop based on scheme advice etc. These are removed by stackFilter
  
    drop <- which(!is.na(speciesInfo$Reason_not_included) & speciesInfo$Reason_not_included != "Didn't meet criteria")
  
    drop <- c(as.character(speciesInfo$Species[drop]), 
              as.character(speciesInfo$concept[drop]))
    
    # only keep species as advised
    keep <- keep[!keep %in% drop]
  }
  
  out <- tempSampPost(indata = paste0(roster$modPath, roster$group, "/occmod_outputs/", roster$ver, "/"),
                      keep = keep,
                      keep_iter = keep_iter,
                      output_path = NULL,
                      region = roster$region,
                      sample_n = roster$nSamps,
                      group_name = roster$group,
                      combined_output = TRUE,
                      #max_year_model = 2018,
                      #min_year_model = 1970,
                      write = FALSE,
                      minObs = roster$minObs,
                      scaleObs = roster$scaleObs,
                      t0 = roster$t0,
                      tn = roster$tn,
                      parallel = parallel,
                      filetype = filetype)
  
  samp_post <- out[[1]]
  
  samp_post$species <- tolower(samp_post$species)
  
  meta <- out[[2]]
  
  meta[ ,1] <- tolower(meta[, 1])
  
  if (roster$clipBy != "species") {
    meta[,3] <- min(meta[,3])
    meta[,4] <- max(meta[,4])
  }
  
  stacked_samps <- tempStackFilter(input = "memory",
                                   dat = samp_post,
                                   indata = NULL,
                                   output_path = NULL, 
                                   group_name = paste0(roster$indicator, roster$group), 
                                   metadata = meta, 
                                   region = roster$region,
                                   minObs = roster$minObs, 
                                   maxStartGap = 0, 
                                   maxEndGap = 0,
                                   maxMiddleGap = 10, 
                                   keepSpecies = NULL, 
                                   removeSpecies = drop,
                                   ClipFirst = TRUE, 
                                   ClipLast = TRUE)
  
  if (roster$write == TRUE) {
    
    save(stacked_samps, file = paste0(roster$outPath, roster$group, "_", roster$indicator, 
                                      "_", roster$region, ".rdata"))
    
  }
  
  return(stacked_samps)
  
}
