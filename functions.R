load_libraries <- function() {
  if (!require("pacman")) install.packages("pacman")
  pacman::p_load(
    tidyverse,
    vroom,
    janitor,
    lubridate,
    here,
    openxlsx,
    readxl
  )
}

get_data <- function(file_name){
  vroom(here("data", file_name), delim = ",") %>%
    clean_names()
}

# Child Encounter ---------------------------------------------------------

expand_child_encounter <- function() {
  child_encounter <- get_data("child_encounter_data.csv") %>%  
    # choose first encounter when a subject has multiple encounters
    arrange(child_mrn_uf, admit_datetime) %>%  
    distinct(child_mrn_uf, .keep_all = T) %>% 
    group_by(child_mrn_uf) %>%  
    filter(!is.na(admit_datetime) & !is.na(dischg_datetime)) %>% 
    select(child_mrn_uf, admit_datetime, child_birth_date,
           dischg_disposition, dischg_datetime) %>% 
    # create q1hr timepoints 
    expand(child_mrn_uf, child_birth_date, dischg_disposition, admit_datetime,
           dischg_datetime,
           q1hr = seq(floor_date(admit_datetime, "1 hour"), 
                      floor_date(dischg_datetime, "1 hour"), 
                      by = "hours"))
  
  return(child_encounter)
}

# Platelets ---------------------------------------------------------------

get_platelets <- function() {
  platelets <- get_data("child_labs.csv") %>%
    # only choose subjects that are also in child_encounter data
    filter(child_mrn_uf %in% child_encounter$child_mrn_uf) %>% 
    filter(lab_name == 'PLATELET COUNT' & str_detect(lab_result, "\\d")) %>% 
    mutate(
      # remove special characters from lab resluts. e.x <3
      lab_result = parse_number(lab_result),
      platelets = case_when(lab_result < 50 ~ 3,
                                 lab_result < 100 ~ 2,
                                 lab_result < 150 ~ 1,
                                 TRUE ~ 0),
      # round down to the nearest hour
      q1hr = floor_date(inferred_specimen_datetime, "1 hour")) %>%
    group_by(child_mrn_uf, q1hr) %>%
    # choose last recorded value within the 1 hr timepoint
    filter(inferred_specimen_datetime == max(inferred_specimen_datetime)) %>%
    select(child_mrn_uf, q1hr, platelets)
  
  return(platelets)
}

# align drug start and end times  ------------------------------------------


align_drug_start_end_times <- function(df) {
  aligned_times <- df %>% 
    filter(med_order_datetime < med_order_end_datetime) %>%
    select(child_mrn_uf,med_order_desc, med_order_datetime, med_order_end_datetime) %>%          
    group_by(child_mrn_uf, med_order_desc) %>% 
    mutate(med_order_datetime = floor_date(med_order_datetime, "1 hour"),
           floor_med_order_end_datetime = floor_date(med_order_end_datetime, "1 hour")) %>% 
    distinct(child_mrn_uf,med_order_desc, med_order_datetime, med_order_end_datetime, 
             .keep_all = T) %>%  
    arrange(med_order_desc, med_order_datetime, desc(med_order_end_datetime)) %>%        
    distinct(med_order_datetime, .keep_all = T) %>%    
    mutate(lag_med_order = lag(med_order_datetime),
           lag_med_order_end = lag(med_order_end_datetime)) %>%      
    mutate(med_order_datetime = if_else(lag_med_order_end >= med_order_datetime & !is.na(lag_med_order_end),
                                        lag_med_order_end, med_order_datetime)) %>%       
    arrange(med_order_desc, med_order_datetime, desc(med_order_end_datetime)) %>%     
    distinct(med_order_datetime, .keep_all = T) %>% 
    filter(med_order_datetime < med_order_end_datetime) %>%
    select(child_mrn_uf, med_order_desc, med_order_datetime, med_order_end_datetime) %>%  
    pivot_longer(cols = c(med_order_datetime, med_order_end_datetime),
                 names_to = "time_name", values_to = "q1hr") %>% 
    mutate(drug_given = if_else(time_name == "med_order_datetime", 1, 0)) %>%   
    arrange(desc(drug_given)) %>%       
    distinct(q1hr, .keep_all = T) %>%  
    pivot_wider(id_cols = c(child_mrn_uf, q1hr),
                names_from = med_order_desc,
                values_from = drug_given) %>%         
    arrange(q1hr) %>% 
    group_by(child_mrn_uf) %>% 
    fill(-c(q1hr, child_mrn_uf), .direction = "down") %>%   
    mutate(q1hr = floor_date(q1hr, "1 hour")) %>% 
    ungroup() %>% 
    mutate_if(is.numeric, ~replace(., is.na(.), 0)) 
  
  return(aligned_times)
}


# Steroids ----------------------------------------------------------------
get_steroids <- function() {
  drug_route <- c("Intravenous", "Oral", "Per NG tube", "Per G Tube","Per OG Tube")
  
  read_steroids <- get_data("child_medications.csv")
  
  steroids <- read_steroids %>%
    # only choose subjects that are also in child_encounter data
    filter(child_mrn_uf %in% child_encounter$child_mrn_uf) %>%
    filter(str_detect(med_order_desc, "DEXAMETHASONE|HYDROCORTISONE|METHYLPREDNISOLONE") &
             med_order_route %in% drug_route) %>% 
    filter(!is.na(mar_action)) %>% 
    mutate(med_order_desc = word(med_order_desc, 1)) %>%
    align_drug_start_end_times() %>% 
    mutate(number_steroids = rowSums(.[-c(1,2)]),
           steroids = if_else(number_steroids == 0, 0, 1)) %>%  
    select(child_mrn_uf, q1hr ,steroids) %>%   
    distinct()
  
  return(steroids)
}


# Inotropes ---------------------------------------------------------------

get_inotropes <- function() {
  read_inotropes <- get_data("child_medications.csv")  
  
  inotropes <- read_inotropes %>% 
    filter(child_mrn_uf %in% child_encounter$child_mrn_uf) %>%
    filter(str_detect(med_order_desc,
                      paste0("DOBUTAMINE|DOPAMINE|EPINEPHRINE|MILRINONE|",
                             "NOREPINEPHRINE|VASOPRESSIN|PHENYLEPHRINE")) &
             med_order_route == "Intravenous",
           med_order_discrete_dose_unit %in% c("mcg/kg/min","Units/min",
                                               "milli-units/kg/min",
                                               "milli-units/kg/hr")) %>%       
    filter(!str_detect(med_order_desc, "ANESTHESIA")) %>%
    mutate(med_order_desc = word(med_order_desc, 1)) %>%     
    align_drug_start_end_times() %>%  
    mutate(number_inotropic_drugs = rowSums(.[-c(1,2)]),
           inotrope_score = case_when(number_inotropic_drugs == 0 ~ 0,
                                      number_inotropic_drugs == 1 ~ 2,
                                      number_inotropic_drugs > 1 ~  3,
                                      TRUE ~ NA_real_))
  
  return(inotropes)
  
}


# Oxygenation -------------------------------------------------------------

get_oxygenation <- function() {
  respiratory_devices <- read_excel("data/categorized_respiratory_devices.xlsx") %>% 
    filter(intubated %in% c('yes', 'no'))
  
  flowsheets <- get_data("child_flowsheets.csv") %>%
    filter(child_mrn_uf %in% child_encounter$child_mrn_uf) %>% 
    group_by(child_mrn_uf) %>% 
    mutate(q1hr = floor_date(recorded_time, "1 hour"))
  
  intubated_yes_no <- flowsheets %>% 
    filter(flowsheet_group == "Oxygenation" & 
             disp_name == "Respiratory Device") %>%
    inner_join(respiratory_devices, by = "meas_value") %>%  
    group_by(child_mrn_uf, q1hr) %>% 
    # choose last recorded value within q1hr
    filter(recorded_time == max(recorded_time)) %>% 
    arrange(child_mrn_uf, q1hr, desc(intubated)) %>%  
    distinct(child_mrn_uf, q1hr, .keep_all = T) %>% 
    ungroup() %>% 
    select(child_mrn_uf, q1hr, meas_value, intubated)
  
  # set intubated to yes or no at every hour during an encounter
  intubated_yes_no <- child_encounter %>% 
    left_join(intubated_yes_no, by = c("child_mrn_uf", "q1hr")) %>% 
    group_by(child_mrn_uf) %>% 
    fill(c(meas_value, intubated), .direction = "down")
  
  fio2_score <- flowsheets %>%
    filter(flowsheet_group %in% c('Oxygenation','Vent Settings') &
             str_detect(disp_name, "FiO2")) %>% 
    # identify the timepoints at which a subject was intubated
    inner_join(intubated_yes_no %>%
                 filter(intubated == 'yes') %>%
                 select(child_mrn_uf, q1hr),
               by = c("child_mrn_uf", "q1hr")) %>%    
    select(child_mrn_uf, recorded_time, q1hr, flowsheet_group, meas_value, disp_name) %>% 
    distinct() %>%   
    arrange(recorded_time) %>% 
    # count number of fio2 scores recorded within an hour
    add_count(child_mrn_uf, q1hr, name = "number_of_scores") %>%   
    mutate(meas_value = as.numeric(meas_value)) %>% 
    group_by(child_mrn_uf, q1hr) %>% 
    mutate(na_meas_value = if_else(is.na(meas_value), 0, 1)) %>% 
    mutate(
      priority = case_when(
        number_of_scores == 1 ~ 1,
        # When there are simultaneously-recorded FiO2 in both the “oxygenation” and “vent settings”
        # flowsheet  within an hour chose the “oxygenation” flowsheet value.
        number_of_scores == 2 &
          flowsheet_group == "Oxygenation" &
          !is.na(meas_value) ~ 1,
        # When there are more than two FiO2 values within the same hour choose the highest value
        # regardless of if that value comes from  "oxygenation" or "vent settings" flowsheet group.
        number_of_scores > 2 &
          meas_value == suppressWarnings(max(meas_value, na.rm = TRUE)) ~ 1,
        TRUE ~ 0
      )
    ) %>% 
    arrange(q1hr, desc(na_meas_value), desc(priority)) %>%    
    distinct(child_mrn_uf, q1hr, .keep_all = T) %>% 
    select(child_mrn_uf, q1hr, value = meas_value) %>% 
    mutate(score_name = "fio2")
  
  spo2_score <- flowsheets %>%
    filter(flowsheet_group == "Vitals" & str_detect(disp_name, "SpO2")) %>% 
    # identify the timepoints at which a subject was intubated
    inner_join(intubated_yes_no %>%
                 filter(intubated == 'yes') %>%
                 select(child_mrn_uf, q1hr),
               by = c("child_mrn_uf", "q1hr")) %>%  
    select(child_mrn_uf, recorded_time, q1hr, flowsheet_group, meas_value, disp_name) %>% 
    distinct() %>% 
    mutate(meas_value = as.numeric(meas_value)) %>% 
    # Choose an SpO2 value following this order: SpO2, SpO2 #3, then SpO2 #2
    mutate(score_priority = case_when(disp_name == "SpO2" ~ 1,
                                      disp_name == "SpO2 #3 (or SpO2po)" ~ 2,
                                      disp_name == "SpO2 #2 (or SpO2pr)" ~ 3)) %>% 
    group_by(child_mrn_uf, q1hr) %>% 
    # when there are multiple values for any given SpO within an hour
    # choose the lowest meas_value
    arrange(q1hr, score_priority, meas_value) %>% 
    distinct(child_mrn_uf, q1hr, .keep_all = T) %>% 
    select(child_mrn_uf, q1hr, value = meas_value) %>% 
    mutate(score_name = "spo2")
  
  intubated_yes <- fio2_score %>% 
    bind_rows(spo2_score) %>% 
    group_by(child_mrn_uf) %>%  
    # convert fio2 and spo2 to columns
    pivot_wider(names_from = score_name, values_from = value) %>%  
    arrange(q1hr) %>%  
    # fill NAs with the last recorded value
    fill(c(fio2, spo2), .direction = "down") %>%
    mutate(oxygenation_ratio = spo2/fio2) %>% 
    mutate(oxygenation = case_when(oxygenation_ratio >= 3 ~ 0,
                                   oxygenation_ratio >= 2 ~ 2,
                                   oxygenation_ratio >= 1.5 ~ 4,
                                   oxygenation_ratio >= 1 ~ 6,
                                   oxygenation_ratio < 1 ~ 8,
                                   TRUE ~ NA_real_))
  
  intubated_no <- intubated_yes_no %>% 
    filter(intubated == 'no') %>% 
    mutate(oxygenation = 0)
  
  oxygenation <- intubated_yes %>% 
    bind_rows(intubated_no) %>%   
    select(child_mrn_uf, q1hr,fio2, spo2, oxygenation) %>% 
    arrange(child_mrn_uf, q1hr)
  
  return(oxygenation)
}

# nsofa calculation -------------------------------------------------------

get_nsofa_dataset <- function(create_csv = FALSE) {
  nsofa <- list(child_encounter, platelets, steroids, 
                inotropes, oxygenation) %>% 
    reduce(left_join, by = c("child_mrn_uf", "q1hr")) %>%  
    group_by(child_mrn_uf) %>%  
    fill(c(platelets, steroids, inotrope_score, number_inotropic_drugs, oxygenation),
         .direction = "down") %>% 
    ungroup() %>% 
    mutate_if(is.numeric, ~replace(., is.na(.), 0)) %>% 
    mutate(cv = case_when(number_inotropic_drugs == 0 & steroids == 0 ~ 0,
                          number_inotropic_drugs == 0 & steroids == 1 ~ 1,
                          number_inotropic_drugs == 1 & steroids == 0 ~ 2,
                          (number_inotropic_drugs >= 2 & steroids == 0) | 
                            (number_inotropic_drugs == 1 & steroids == 1) ~ 3,
                          number_inotropic_drugs >= 2 & steroids == 1 ~ 4)) %>% 
    mutate(nsofa_score = platelets + oxygenation + cv) %>% 
    select(child_mrn_uf,dischg_disposition,child_birth_date, q1hr, inotrope_score,
           number_inotropic_drugs, oxygenation, platelets, steroids, cv, nsofa_score)
  
  if (create_csv) {
    write.csv(nsofa, here("output", paste0("nsofa_score_", today(), ".csv")), 
              row.names = F, na = "")
  }
  
  return(nsofa)
}
  
get_max_score_within_n_days_of_birth <- function(n_days, create_csv = FALSE) {
  max_score <- nsofa_scores %>% 
    group_by(child_mrn_uf) %>% 
    filter(between(unique(child_birth_date), unique(child_birth_date), 
                   unique(child_birth_date) + days(n_days))) %>% 
    summarise(nsofa_score = max(nsofa_score), 
              dischg_disposition = unique(dischg_disposition))
  
  if (create_csv) {
    write.csv(max_score, here("output", paste0("max_nsofa_score_", today(), ".csv")), 
              row.names = F, na = "")
  }
  
  return(max_score)
}
