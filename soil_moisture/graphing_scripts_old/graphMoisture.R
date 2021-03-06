library(tidyverse)
library(dplyr)
library("ggplot2")
library(matrixStats)

rg = read_csv("data/moistureVStime.csv")
names(rg)



# Graphs the soil moisture curves provided into a file, named after the treatments selected+ to plot.
# Only plots the values for days between startDate and endDate.
# @parameter ... : a variable number of strings Should be the name of a specific soil moisture sensor,
#                  for example AO (Arborist Chips Outflow) or CI (Control Inflow)
# @parameter startDate: a string that contains the earliest date you want to plot from. Must be of the format
#                       'YYYY-MM-DD'. Default value is 2020-02-01 (Feburary 1st, 2020)  
# @parameter endDate: a string that contains the latest day you want to plot to. Must be of the form
#                     'YYYY-MM-DD'. Default value is 2020-11-01 (November 1st, 2020)
# @return: None. Just writes to a file.
graphRGMoisture <- function(..., startDate="2020-02-01", endDate="2020-11-01") {
    treatmentNames <- list(...)
    startDate <- as.Date(startDate)
    endDate <- as.Date(endDate)
    summaryRG <- rg %>% mutate(X1 = NULL, Source.Name = NULL, 'Line#' = NULL, "m^3/m^3,  Soil Moisture Stn" = NULL) %>%
        mutate(Date = as.Date(Date, format="%m/%d/%y %H:%M")) %>%
        rename_all(funs(str_replace_all(., " ", "_"))) %>%  #Renaming columns
        rename_all(funs(str_replace_all(.,"-", "_"))) %>%
        rename_all(funs(str_replace_all(., "(_\\(m\\^3/m\\^3\\))", ""))) %>%
        group_by(Date) %>% summarise_if(is.numeric, funs(mean, sd)) %>%#Grouping data by day, taking MEAN instead of MEDIAN
        filter(Date > startDate) %>% filter(Date < endDate) #Removing rows outside our targeted date range
    summaryRG[summaryRG < 0] <- NA #Removing negative soil moisture values
    
    
    ids <- c("AI", "AO", "CI", "CO", "MI","MO", "NI", "NO")
    for (id in ids) { #Average soil moistures of the 4 replications
        replicates <- c() #The four RGs with the same treatment
        replicatesSD <- c()
        for (col_name in names(summaryRG)) {
            if (grepl(id, col_name, fixed=TRUE)) {
                if (grepl("sd", col_name, fixed=TRUE)) {
                    replicatesSD <- c(replicatesSD, col_name)
                } else {
                    replicates <- c(replicates, col_name)
                }
            }
        }
        
        avgMoisture <- rowMeans(summaryRG[replicates])
        sdMoisture <- getSD(summaryRG[replicatesSD])
        summaryRG[paste(id, "_avg", sep="")] <- avgMoisture
        summaryRG[paste(id, "_sd" ,sep="")] <- sdMoisture
    }
    
    plot <- ggplot(data=summaryRG, aes(x=Date))
    lines <- ""
    ribbons <- ""
    title <- ""
    colors <-list()
    fileName <- ""
    for (treatmentName in treatmentNames) {
        lines <- paste(lines, "geom_line(aes(y=", sep="")
        ribbons <- paste(ribbons, "geom_ribbon(aes(ymin=", sep="")
        
        col_name <- paste(treatmentName, "_avg", sep="")
        col_sd_name <- paste(treatmentName, "_sd", sep="")
        lines <- paste(lines, col_name, ",color='", getFullName(treatmentName), "')) + ", sep="")
        ribbons <- paste(ribbons, col_name, "-", col_sd_name, ", ymax=", col_name, "+", col_sd_name, "), fill='", getColor(treatmentName, TRUE), "') + ", sep="")
        title <- paste(title, treatmentName, sep=" ")
        colors[[treatmentName]] <- getColor(treatmentName, FALSE)
        fileName <- paste(fileName, treatmentName, sep="_")
    }
    colors <- unlist(colors[order(names(colors))], use.names=FALSE)
    fileName <- substr(fileName, 2, nchar(fileName))
    title <- paste(title, "Soil Moisture vs Time")
    lines <- substr(lines, 1, nchar(lines)-3)
    ribbons <- substr(ribbons, 1, nchar(ribbons)-3)
    
    lines <- paste("plot <- plot +", ribbons, "+", lines, sep="")
    eval(parse(text=lines))
    legend_pls <- scale_color_manual(values=colors)
    labels <- labs(color="Treatments")
    xlabel <- xlab("Time")
    ylabel <- ylab("Soil Moisture")
    title <- ggtitle(title)
    
    plot <- plot + title + ylabel + xlabel + legend_pls + labels# + ribbon
    fileName <- paste("graphs/", fileName, ".png", sep="")
    png(file = fileName, height = 4, width = 6, units="in", res=1200)
    print(plot)
    dev.off()
}

# Given a treatment name, returns the color the treatment will be graphed with
# @parameter treatemntName: a two character string denoting the treatment. Example: "AO", "NO", "AI"
# @parameter ribbon: a boolean indicating whether we should return the color for the ribbon of a line. FALSE for the line itself
# @return: a string containing the hex code of the color we will graph the treatment as.
# @stop: if the inputted treatmentName is not a valid string, then we will throw an error.

getColor <- function(treatmentName, ribbon) {
    treatmentNames <- list("AO", "NO", "MO", "CO", "AI", "NI", "CI", "MI")
    if (!(treatmentName %in% treatmentNames)){
        stop("The treatment name provided is not valid")
    } else {
        io <- substring(treatmentName, 2, 2)
        type <- substring(treatmentName, 1, 1)
        if (io == "I") {
            if (ribbon) {
                color <- switch(type, "A" = "#a9fcc2", "N" = "#fcef99", "C"="#f9b6b6", "M" ="#a9fcfc")
            } else {
                color <- switch(type, "A" = "#58fc89", "N" = "#fcdc0a", "C"="#fc6464", "M" ="#02fcfc")
            }
        } else {
            if (ribbon) {
                color <- switch(type, "A" = "#648c70", "N" = "#c6bd83", "C"="#bc7a7a", "M" ="#71baba")
            } else {
                color <- switch(type, "A" = "#037024", "N" = "#a08b01", "C"="#990000", "M" ="#00b7b7")
            }
        }
        return(color)
    }
}

# Returns the correctly calculated SD of the given df. Not for general use, just a helper function
# @parameter df: should be a df whose columns are the SDs of the 4 replicate treatments. These SDs are SD of each day.
# @return : returns a vector with the SDs corretly aggregated. They are aggregated in the following way:
#                   sdVector = sum(daily_sd ** 2)/ 4 over every day

getSD <- function(df) {
    df <- df ** 2
    sdAvg <- rowMeans(df)
    
    sdAvg <- sdAvg** .5
    return(sdAvg)
}

# Given a treatment name, returns the full treatment name that will be displayed on the grah.
# @parameter treatemntName: a two character string denoting the treatment. Example: "AO", "NO", "AI"
# @return: a string containing the full name of the treatment. For example, "Arborist Chips Out", "Nuggets Out, "Arborist Chips In"
# @stop: if the inputted treatmentName is not a valid string, then we will throw an error.

getFullName <- function(treatmentName) {
    treatmentNames <- list("AO", "NO", "MO", "CO", "AI", "NI", "CI", "MI")
    if (!(treatmentName %in% treatmentNames)) {
        stop("The treatment name provided is not valid")
    } else {
        type <- substring(treatmentName, 1, 1)
        fullName <- switch(type, "A" = "Arborist Chips", "N" = "Nuggets", "C"="Control", "M" ="Medium Bark")
        
        io <- substring(treatmentName, 2, 2)
        end <- switch(io, "I" = "In", "O"="Out")
        return(paste(fullName, end))
        
    }
}