# -- Libraries
library(tidyverse)
library(lubridate)
library(splines)

# fit glm spline ----------------------------------------------------------
# no longer used. we now use moving average to match other dashboards
# spline_fit <- function(d, y, n = NULL, 
#                        week_effect = TRUE, 
#                        knots_per_month = 2, 
#                        family = quasibinomial, 
#                        alpha = 0.05){
#   
#   z <- qnorm(1 - alpha/2)
#   
#   x <- as.numeric(d)
#   
#   df  <- round(knots_per_month * length(x) / 30) + 1
#   
#   if(family()$family %in% c("binomial", "quasibinomial")){
#     if(is.null(n)) stop("Must supply n with binomial or quasibinomial")
#     y <- cbind(y, n-y)
#   }
#   
#   if(week_effect){
#     
#     w <- factor(wday(d))
#     contrasts(w) <- contr.sum(length(levels(w)), contrasts = TRUE)
#     w <- model.matrix(~w)[,-1]
#     
#     glm_fit  <- glm(y ~ ns(x, df = df, intercept = TRUE) + w - 1, family = family)
#     
#   } else {
#     
#     glm_fit  <- glm(y ~ ns(x, df = df, intercept = TRUE) - 1, family = family)
#     
#   }
#   
#   glm_pred <- predict(glm_fit, type = "terms", se.fit = TRUE)
#   
#   fit <- family()$linkinv(glm_pred$fit[,1])
#   
#   lower <- family()$linkinv(glm_pred$fit[,1] - z * glm_pred$se.fit[,1])
#   
#   upper <- family()$linkinv(glm_pred$fit[,1] + z * glm_pred$se.fit[,1])
#   
#   return(tibble(date = d, fit = fit, lower = lower, upper = upper))  
# }

# moving average ----------------------------------------------------------

ma7 <- function(d, y, k = 7) 
  tibble(date = d, moving_avg = as.numeric(stats::filter(y, rep(1/k, k), side = 1)))


# -- Fixed values
icu_beds <- 229 #if available beds is missing change to this

first_day <- make_date(2020, 3, 12)

the_years <- seq(2020, year(today()))

age_levels <-  c("0 to 9", "10 to 19", "20 to 29", "30 to 39", "40 to 49", "50 to 59", "60 to 69", 
                 "70 to 79", "80 to 89", "90 to 99", "100 to 109", "110 to 119", "120 to 129")

test_url <- "https://bioportal.salud.gov.pr/api/administration/reports/minimal-info-unique-tests"

cases_url <- "https://bioportal.salud.gov.pr/api/administration/reports/orders/basic"

imputation_delay  <- 2

alpha <- 0.05

# Reading and wrangling test data from database ----------------------------------------------

all_tests <- jsonlite::fromJSON(test_url)

all_tests <- all_tests %>%  
  rename(patientCity = city) %>%
  as_tibble() %>%
  mutate(testType = str_to_title(testType),
         testType = ifelse(testType == "Antigeno", "Antigens", testType),
         collectedDate  = mdy(collectedDate),
         reportedDate   = mdy(reportedDate),
         createdAt      = mdy_hm(createdAt),
         ageRange       = na_if(ageRange, "N/A"),
         ageRange       = factor(ageRange, levels = age_levels),
         patientCity    = ifelse(patientCity == "Loiza", "Loíza", patientCity),
         patientCity    = ifelse(patientCity == "Rio Grande", "Río Grande", patientCity),
         patientCity    = factor(patientCity),
         result         = tolower(result),
         result         = case_when(grepl("positive", result) ~ "positive",
                                    grepl("negative", result) ~ "negative",
                                    result == "not detected" ~ "negative",
                                    TRUE ~ "other")) %>%
  arrange(reportedDate, collectedDate) 

## fixing bad dates: if you want to remove bad dates instead, change FALSE TO TRUE
if(FALSE){
  ## remove bad dates
  all_tests <- all_tests %>% 
  filter(!is.na(collectedDate) & year(collectedDate) %in% the_years & collectedDate <= today()) %>%
  mutate(date = collectedDate) 
} else{
  ## Impute missing dates and remove inconsistent dates
  all_tests <- all_tests %>% 
    mutate(date = if_else(is.na(collectedDate), reportedDate - days(imputation_delay),  collectedDate)) %>%
    mutate(date = if_else(!year(date) %in% the_years | date > today(), reportedDate - days(imputation_delay),  date)) %>%
    filter(year(date) %in% the_years & date <= today()) %>%
    arrange(date, reportedDate)
}


# Reading and wrangling cases data from database ---------------------------

all_tests_with_id <- jsonlite::fromJSON(cases_url)

all_tests_with_id <- all_tests_with_id %>%  
  as_tibble() %>%
  mutate(testType = str_to_title(testType),
         testType = ifelse(testType == "Antigeno", "Antigens", testType),
         collectedDate  = ymd_hms(collectedDate, tz = "America/Puerto_Rico"),
         reportedDate   = ymd_hms(reportedDate, tz = "America/Puerto_Rico"),
         orderCreatedAt = ymd_hms(orderCreatedAt, tz = "America/Puerto_Rico"),
         resultCreatedAt = ymd_hms(resultCreatedAt, tz = "America/Puerto_Rico"),
         ageRange       = na_if(ageRange, "N/A"),
         ageRange       = factor(ageRange, levels = age_levels),
         region         = ifelse(region == "Bayamon", "Bayamón", region),
         region         = ifelse(region == "Mayaguez", "Mayagüez", region),
         region         = factor(region),
         result         = tolower(result),
         result         = case_when(grepl("positive", result) ~ "positive",
                                    grepl("negative", result) ~ "negative",
                                    result == "not detected" ~ "negative",
                                    TRUE ~ "other")) %>%
  arrange(reportedDate, collectedDate, patientId) 

## fixing bad dates: if you want to remove bad dates instead, change FALSE TO TRUE
if(FALSE){
  ## remove bad dates
  all_tests_with_id <- all_tests_with_id %>% 
    filter(!is.na(collectedDate) & year(collectedDate) %in% the_years & collectedDate <= today()) %>%
    mutate(date = as_date(collectedDate))
} else{
  ## Impute missing dates
  all_tests_with_id <- all_tests_with_id %>% 
    mutate(date = if_else(is.na(collectedDate), reportedDate - days(imputation_delay),  collectedDate)) %>%
    mutate(date = if_else(!year(date) %in% the_years | date > today(), reportedDate - days(imputation_delay),  date)) %>%
    mutate(date = as_date(date)) %>%
    filter(year(date) %in% the_years & date <= today()) %>%
    arrange(date, reportedDate)
}

# -- Computing observed positivity rate
## adding a new test type that combines molecular and antigens
mol_anti <-  all_tests_with_id %>%
  filter(date >= first_day & testType %in% c("Molecular", "Antigens") & 
           result %in% c("positive", "negative")) %>%
  mutate(testType = "Molecular+Antigens") 

tests <- all_tests_with_id %>%
  bind_rows(mol_anti) %>%
  filter(date >= first_day & testType %in% c("Molecular", "Serological", "Antigens", "Molecular+Antigens") & 
           result %in% c("positive", "negative")) %>%
  group_by(testType, date) %>%
  summarize(positives = n_distinct(patientId[result == "positive"]),
            tests = n_distinct(patientId),
            all_positives = sum(result == "positive"),
            all_tests = n(),
            .groups = "drop") %>%
  mutate(rate = positives / tests,
         old_rate = all_positives / all_tests)


positivity <- function(dat){
  day_seq <- seq(first_day + weeks(1), max(dat$date), by = "day")
  map_df(day_seq, function(the_day){
  dat %>% filter(date > the_day - weeks(1) & date <= the_day) %>%
    summarize(date = the_day, 
              positives = n_distinct(patientId[result == "positive"]),
              tests = n_distinct(patientId),
              fit = positives / tests,
              lower = qbinom(0.025, tests, fit) / tests,
              upper = qbinom(0.975, tests, fit) / tests) %>%
      select(date, fit, lower, upper)
  })
}

fits <- all_tests_with_id %>% 
  bind_rows(mol_anti) %>%
  filter(date >= first_day & testType %in% c("Molecular", "Serological", "Antigens", "Molecular+Antigens") & 
           result %in% c("positive", "negative")) %>%
  nest_by(testType) %>%
  summarize(positivity(data), .groups = "drop")
  
tests <- left_join(tests, fits, by = c("testType", "date"))


if(FALSE){
  library(scales)
  source("functions.R")
  plot_positivity(tests, first_day, today(), type = "Molecular") +
    geom_smooth(method = "loess", formula = "y~x", span = 0.2, method.args = list(degree = 1, weight = tests$tests), color = "red", lty =2, fill = "pink") 
}

tests_fits <- tests %>% 
  group_by(testType) %>%
  do(ma7(d = .$date, y = .$all_tests)) %>%
  rename(tests_week_avg = moving_avg)

tests <- left_join(tests, tests_fits, by = c("testType", "date"))

if(FALSE){
  plot_test(tests, first_day, today())
  plot_test(tests, first_day, today(), type  = "Serological")
  plot_test(tests, first_day, today(), type  = "Antigens")
  plot_test(tests, first_day, today(), type  = "Molecular+Antigens")
}

# unique cases ------------------------------------------------------------
all_cases <- all_tests_with_id %>%  
  bind_rows(mol_anti) %>%
  filter(date>=first_day & result == "positive" &
           testType %in% c("Molecular", "Serological", "Antigens",  "Molecular+Antigens")) %>%
  group_by(testType, patientId) %>%
  mutate(n=n()) %>%
  arrange(date) %>%
  slice(1) %>% 
  ungroup() %>%
  mutate(region = fct_explicit_na(region, "No reportado")) %>%
  mutate(ageRange = fct_explicit_na(ageRange, "No reportado")) %>%
  select(-patientId, -result) %>%
  arrange(testType, date)

# Add cases to tests data frame -------------------------------------------
cases <- all_cases %>%
  group_by(testType, date) %>% 
  summarize(cases = n(), .groups = "drop")

# Make sure all dates are included
cases <-  left_join(select(tests, testType, date), cases, by = c("testType", "date")) %>%
  replace_na(list(cases = 0))

fits <- cases %>% 
  group_by(testType) %>%
  do(ma7(d = .$date, y = .$cases))

cases <- left_join(cases, fits, by = c("testType", "date"))

if(FALSE){
  plot_cases(cases)
  plot_cases(cases, first_day, today(), type  = "Serological")
  plot_cases(cases, first_day, today(), type  = "Antigens")
  plot_cases(cases, first_day, today(), type  = "Molecular+Antigens")
  
}

# -- summaries stratified by age group and patientID
mol_anti <-  all_tests %>%
  filter(date >= first_day & testType %in% c("Molecular", "Antigens") & 
           result %in% c("positive", "negative")) %>%
  mutate(testType = "Molecular+Antigens") 


tests_by_strata <- all_tests %>%  
  bind_rows(mol_anti) %>%
  filter(date >= first_day & testType %in% c("Molecular", "Serological", "Antigens", "Molecular+Antigens") & 
           result %in% c("positive", "negative")) %>%
  filter(date>=first_day) %>%
  mutate(patientCity = fct_explicit_na(patientCity, "No reportado")) %>%
  mutate(ageRange = fct_explicit_na(ageRange, "No reportado")) %>%
  group_by(testType, date, patientCity, ageRange, .drop = FALSE) %>%
  summarize(positives = sum(result == "positive"), tests = n(), .groups="drop") %>%
  ungroup()

# --Mortality and hospitlization
hosp_mort <- read_csv("https://raw.githubusercontent.com/rafalab/pr-covid/master/dashboard/data/DatosMortalidad.csv") %>%
  mutate(date = mdy(Fecha)) %>% 
  filter(date >= first_day) 

## we started keeping track of available beds on 2020-09-20 
hosp_mort <- hosp_mort %>% 
  replace_na(list(CamasICU_disp = icu_beds))


# -- seven day averages 
fits <- with(hosp_mort, 
             ma7(d = date, y = IncMueSalud))
hosp_mort$mort_week_avg <- fits$moving_avg

fits <- with(hosp_mort, 
             ma7(d = date, y = HospitCOV19))
hosp_mort$hosp_week_avg <- fits$moving_avg

fits <- with(hosp_mort, 
             ma7(d = date, y = CamasICU))
hosp_mort$icu_week_avg <- fits$moving_avg

if(FALSE){
  plot_deaths(hosp_mort)
}

# Compute time it takes tests to come in ----------------------------------

rezago <- all_tests_with_id  %>% 
  filter(result %in% c("positive", "negative") & 
           testType %in% c("Molecular", "Serological", "Antigens") &
           resultCreatedAt >= collectedDate) %>% ## based on @midnucas suggestion: can't be added before it's reported
  group_by(testType) %>%
  mutate(diff = (as.numeric(resultCreatedAt) - as.numeric(collectedDate)) / (60 * 60 * 24),
          Resultado = factor(result, labels = c("Negativos", "Positivos"))) %>%
  ungroup %>%
  select(testType, date, Resultado, diff) %>%
  filter(!is.na(diff))


# Computing positivity rate by lab ----------------------------------------

url <- "https://bioportal.salud.gov.pr/api/administration/reports/tests-by-collected-date-and-entity"

all_labs_data <- jsonlite::fromJSON(url)

labs <- all_labs_data %>%
  select(-molecular, -serological, -antigens) %>%
  rename(Laboratorio = entityName,
         date = collectedDate) %>%
  mutate(date = as_date(date),
         Laboratorio = str_remove(tolower(Laboratorio), "\t"))

##check the most common labs
if(FALSE){
  freqs <- bind_cols(labs, all_labs_data$molecular) %>% 
    filter(date > make_date(2020, 10, 1)) %>%
    group_by(Laboratorio) %>%
    summarize(freq = sum(total), .groups = "drop") %>% 
    ungroup()
  freqs %>% View()
}

labs <- labs %>%
  mutate(Laboratorio = case_when(str_detect(Laboratorio, "toledo") ~ "Toledo",
                                 str_detect(Laboratorio, "bcel") ~ "BCEL",
                                 str_detect(Laboratorio, "nichols") ~ "Quest USA",
                                 str_detect(Laboratorio, "quest") ~ "Quest",
                                 str_detect(Laboratorio, "borinquen") ~ "Borinquen",
                                 str_detect(Laboratorio, "immuno reference lab") ~ "Immuno Reference",
                                 str_detect(Laboratorio, "coreplus") ~ "CorePlus",
                                 str_detect(Laboratorio, "martin\\s") ~ "Marin",
                                 str_detect(Laboratorio, "noy") ~ "Noy",
                                 str_detect(Laboratorio, "hato rey pathology|hrp") ~ "HRP",
                                 str_detect(Laboratorio, "inno") ~ "Inno Diagnostics",
                                 #str_detect(Laboratorio, "southern pathology services") ~ "Southern Pathology",
                                 #str_detect(Laboratorio, "cmt") ~ "CMT",
                                 TRUE ~ "Otros"))

molecular <- all_labs_data$molecular %>% 
  mutate(testType = "Molecular",
         positives = positives + presumptivePositives,
         negatives = negatives,
         tests = positives + negatives) %>%
  select(testType, positives, tests)
molecular <- bind_cols(labs, molecular) 

serological <-  all_labs_data$serological %>%
  mutate(testType = "Serological",
         positives = positives,
         negatives = negatives,
         tests = positives + negatives) %>%
  select(testType, positives, tests)
serological <- bind_cols(labs, serological) 

antigens <-  all_labs_data$antigens %>%
  mutate(testType = "Antigens",
         positives = positives,
         negatives = negatives,
         tests = positives + negatives) %>%
  select(testType, positives, tests)
antigens <- bind_cols(labs, antigens) 

labs <- bind_rows(molecular, serological, antigens) %>%
  filter(date >= first_day & date <= today()) %>%
  group_by(testType, date, Laboratorio) %>%
  summarize(positives = sum(positives),
            tests = sum(tests),
            missing_city = sum(totalMissingCity),
            missing_phone = sum(totalMissingPhoneNumber),
            .groups = "drop")


lab_positivity <- function(dat){
  day_seq <- seq(first_day + weeks(1), max(labs$date), by = "day")
  map_df(day_seq, function(the_day){
    ret <- dat %>% 
      filter(date > the_day - weeks(1) & date <= the_day) %>%
      summarize(date = the_day, 
                n = sum(tests),
                tests_week_avg  = n / 7, 
                fit = ifelse(n==0, 0, sum(positives) / n),
                lower = qbinom(0.025, n, fit) / n,
                upper = qbinom(0.975, n, fit) / n) %>%
      select(date, fit, lower, upper, tests_week_avg)
  })
}

fits <- labs %>% 
  nest_by(testType, Laboratorio) %>%
  summarize(lab_positivity(data), .groups = "drop") %>%
  group_by(testType, date) %>%
  mutate(prop = tests_week_avg / sum(tests_week_avg)) 

labs <- left_join(fits, labs, by = c("testType", "date", "Laboratorio"))


# -- Save data
## if on server, save with full path
## if not on server, save to home directory
if(Sys.info()["nodename"] == "fermat.dfci.harvard.edu"){
  rda_path <- "/homes10/rafa/dashboard/rdas"
} else{
  rda_path <- "rdas"
}

## define date and time of latest download
the_stamp <- now()
save(first_day, alpha, the_stamp, 
     tests, tests_by_strata, cases,
     hosp_mort, labs,
     file = file.path(rda_path, "data.rda"))
save(rezago, file = file.path(rda_path, "rezago.rda"))

## For backward compatibility
all_tests <- all_tests %>%  filter(testType == "Molecular")
saveRDS(all_tests, file = file.path(rda_path, "all_tests.rds"), compress = "xz")

