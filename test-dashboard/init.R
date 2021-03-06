# -- Libraries
library(shinythemes)
library(tidyverse)
library(lubridate)
library(splines)
library(scales)
library(plotly)
library(shiny)
library(sf)

# -- Set locale
Sys.setlocale("LC_TIME", "es_ES")

# -- Helper functions
logit <- function(x) { log(x / (1-x)) }
expit <- function(x) { 1/ (1 + exp(-x))  }

# -- Loading data
load("rdas/tests.rda")
load("rdas/tests_by_strata.rda")

# -- For confidence intervals
alpha <- 0.01
z <- qnorm(1-alpha/2)

# -- For maps
map <- st_read("pri_adm_2019_shp/pri_admbnda_adm1_2019.shp") %>%
  st_transform(crs = 4326) %>%
  st_crop(xmin = -67.3, xmax = -65.3, ymin = 17.9, ymax = 18.5)
map <- cbind(map, st_coordinates(st_centroid(map)))

# -- Population data
pop <- read_csv("poblacion-municipios.csv") %>%
  slice(1) %>% unlist()
pop <- pop[-1]
names(pop)[names(pop)=="Comerio"]<- "Comerío"
pop <- tibble(patientCity = names(pop), pop) %>%
  filter(patientCity != "Puerto Rico")
