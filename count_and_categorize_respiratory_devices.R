# count_and_categorize_respiratory_devices.R
library(tidyverse)
library(vroom)
library(janitor)
library(lubridate)
library(here)
library(openxlsx)

get_data <- function(file_name){
  df <- vroom(here("data", file_name), delim = ",") %>%
    clean_names()
}

child_encounter <- get_data("child_encounter_data.csv")

birth_info <- child_encounter %>%
  distinct(child_mrn_uf, child_birth_date)

my_flowsheets <- get_data("child_flowsheets.csv") %>%  
  filter(child_mrn_uf %in% birth_info$child_mrn_uf) %>% 
  left_join(birth_info, by = c("child_mrn_uf")) %>%
  group_by(child_mrn_uf) %>% 
  mutate(q1hr = floor_date(recorded_time, "1 hour"))

distinct_respiratory_devices <- my_flowsheets %>% 
  # determine if subject was intubated at a given timepoint
  filter(flowsheet_group == "Oxygenation" & 
           disp_name == "Respiratory Device") %>%   
  #filter(!meas_value %in% meas_values_that_mean_intubated) %>%
  #filter(!meas_value %in% meas_values_that_mean_extubated) %>%
  ungroup() %>%
  group_by(meas_value) %>%
  tally()

categorized_respiratory_devices <- distinct_respiratory_devices %>%
  mutate(intubated = case_when(
    is.na(meas_value) ~ "???",
    str_detect(meas_value, "ETT") ~ "yes",
    str_detect(meas_value, "Oscillator") ~ "yes",
    str_detect(meas_value, "Ventilator") ~ "yes",
    str_detect(meas_value, "Aerosol mask") ~ "no",
    str_detect(meas_value, "BiPAP") ~ "no",
    str_detect(meas_value, "Blow-by") ~ "no",
    str_detect(meas_value, "BVM") ~ "no",
    str_detect(meas_value, "CPAP") ~ "no",
    str_detect(meas_value, "Cricothyrotomy") ~ "no",
    str_detect(meas_value, "Face tent") ~ "no",
    str_detect(meas_value, "High flow nasal cannula") ~ "no",
    str_detect(meas_value, "Nasal cannula") ~ "no",
    str_detect(meas_value, "Non-rebreather mask") ~ "no",
    str_detect(meas_value, "Oxyhood") ~ "no",
    str_detect(meas_value, "Oxyimiser") ~ "no",
    str_detect(meas_value, "Partial rebreather mask") ~ "no",
    str_detect(meas_value, "Room Air") ~ "no",
    str_detect(meas_value, "Simple mask") ~ "no",
    str_detect(meas_value, "T-piece") ~ "no",
    str_detect(meas_value, "Trach mask") ~ "no",
    str_detect(meas_value, "Venturi mask") ~ "no",
    str_detect(meas_value, "King Tube") ~ "???",
    str_detect(meas_value, "Tracheostomy") ~ "???",
    str_detect(meas_value, "Other") ~ "???",
    str_detect(meas_value, "Transtracheal catheter") ~ "???"
  )) %>%
  arrange(intubated, meas_value)

write.xlsx(categorized_respiratory_devices, "categorized_respiratory_devices.xlsx")

