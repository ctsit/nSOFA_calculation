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
    distinct(child_mrn_uf, q1hr, platelets)
  
  return(platelets)
}

# align drug start and end times  ------------------------------------------


align_drug_start_end_times <- function(df) {
  aligned_times <- df %>% 
    filter(med_order_start_datetime < med_order_datetime) %>% 
    filter(med_order_start_datetime < med_order_end_datetime) %>%
    select(child_mrn_uf,med_order_desc, med_order_start_datetime, med_order_end_datetime) %>%          
    group_by(child_mrn_uf, med_order_desc) %>% 
    mutate(med_order_start_datetime = floor_date(med_order_start_datetime, "1 hour"),
           floor_med_order_end_datetime = floor_date(med_order_end_datetime, "1 hour")) %>% 
    distinct(child_mrn_uf,med_order_desc, med_order_start_datetime, med_order_end_datetime, 
             .keep_all = T) %>%  
    arrange(med_order_desc, med_order_start_datetime, desc(med_order_end_datetime)) %>%        
    distinct(med_order_start_datetime, .keep_all = T) %>%    
    mutate(lag_med_order = lag(med_order_start_datetime),
           lag_med_order_end = lag(med_order_end_datetime)) %>%      
    mutate(med_order_start_datetime = if_else(lag_med_order_end >= med_order_start_datetime & !is.na(lag_med_order_end),
                                        lag_med_order_end, med_order_start_datetime)) %>%       
    arrange(med_order_desc, med_order_start_datetime, desc(med_order_end_datetime)) %>%     
    distinct(med_order_start_datetime, .keep_all = T) %>% 
    filter(med_order_start_datetime < med_order_end_datetime) %>%
    select(child_mrn_uf, med_order_desc, med_order_start_datetime, med_order_end_datetime) %>%  
    pivot_longer(cols = c(med_order_start_datetime, med_order_end_datetime),
                 names_to = "time_name", values_to = "q1hr") %>% 
    mutate(drug_given = if_else(time_name == "med_order_start_datetime", 1, 0)) %>%   
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
                                      TRUE ~ NA_real_)) %>% 
    distinct()
  
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
    filter(flowsheet_group  == 'Oxygenation' & str_detect(disp_name, "FiO2")) %>%   
    # identify the timepoints at which a subject was intubated
    inner_join(intubated_yes_no %>%
                 filter(intubated == 'yes') %>%
                 select(child_mrn_uf, q1hr),
               by = c("child_mrn_uf", "q1hr")) %>%  
    select(child_mrn_uf, recorded_time, q1hr, flowsheet_group, meas_value, disp_name) %>% 
    distinct() %>%   
    arrange(recorded_time) 
  
  spo2_score <- flowsheets %>%
    filter(flowsheet_group == "Vitals" & str_detect(disp_name, "SpO2")) %>% 
    # identify the timepoints at which a subject was intubated
    inner_join(intubated_yes_no %>%
                 filter(intubated == 'yes') %>%
                 select(child_mrn_uf, q1hr),
               by = c("child_mrn_uf", "q1hr")) %>%  
    select(child_mrn_uf, recorded_time, q1hr, flowsheet_group, meas_value, disp_name) %>% 
    distinct()   
  
  combined_intubation <- spo2_score %>% 
    inner_join(fio2_score, by = c("child_mrn_uf", "q1hr"),
               suffix = c("_spo2", "_fio2")) %>%  
    filter(recorded_time_spo2 == recorded_time_fio2) %>% 
    drop_na(meas_value_fio2, meas_value_spo2) %>%       
    select(child_mrn_uf, q1hr, starts_with("recorded_time"), starts_with("meas")) %>% 
    group_by(child_mrn_uf) %>% 
    arrange(q1hr) %>% 
    distinct() %>% 
    ungroup()
  
  intubated_yes <- combined_intubation %>% 
    mutate_at(vars(c(meas_value_fio2, meas_value_spo2)), as.numeric) %>% 
    mutate(oxygenation_ratio = meas_value_fio2/meas_value_spo2) %>% 
    mutate(oxygenation = case_when(oxygenation_ratio >= 3 ~ 0,
                                   oxygenation_ratio >= 2 ~ 2,
                                   oxygenation_ratio >= 1.5 ~ 4,
                                   oxygenation_ratio >= 1 ~ 6,
                                   oxygenation_ratio < 1 ~ 8,
                                   TRUE ~ NA_real_)) %>% 
    # take lowest oxygenation value when there are multiple within an hour
    arrange(child_mrn_uf, q1hr, oxygenation) %>%  
    distinct(child_mrn_uf, q1hr, .keep_all = T)
  
  intubated_no <- intubated_yes_no %>% 
    filter(intubated == 'no') %>% 
    mutate(oxygenation = 0)
  
  oxygenation <- intubated_yes %>%
    bind_rows(intubated_no) %>%
    select(child_mrn_uf,
           q1hr,
           fio2 = meas_value_fio2,
           spo2 = meas_value_spo2,
           oxygenation) %>%
    arrange(child_mrn_uf, q1hr)
  
  return(oxygenation)
}


# carry platelets forward 24 hours ----------------------------------------


carry_forward_platelets <- function(df) {
  
  carry_platelets_forward <- df %>%
    group_by(child_mrn_uf) %>%
    mutate(row_with_platelet_value = if_else(!is.na(platelets), row_number(), NA_integer_),
           na_count = if_else(is.na(row_with_platelet_value), 1, NA_real_),
           copy_platelets = platelets) %>% 
    fill(c(copy_platelets, row_with_platelet_value), .direction = "down") %>% 
    group_by(child_mrn_uf, copy_platelets, row_with_platelet_value)  %>% 
    mutate(cum_na_count = if_else(!is.na(na_count), cumsum(!is.na(na_count)), as.integer(0))) %>%  
    # copy last recorded platelet forward 24 hours
    mutate(platelets = if_else(cum_na_count < 25, coalesce(platelets, copy_platelets), platelets)) %>% 
    ungroup() %>% 
    select(-c(row_with_platelet_value, na_count, copy_platelets, cum_na_count)) %>% 
    mutate_at("platelets", replace_na, 0)
  
  return(carry_platelets_forward)
}

# nsofa calculation -------------------------------------------------------

get_nsofa_dataset <- function(create_csv = FALSE) {
  nsofa <- list(child_encounter, platelets, steroids, 
                    inotropes, oxygenation) %>% 
    reduce(left_join, by = c("child_mrn_uf", "q1hr")) %>% 
    distinct(child_mrn_uf, q1hr, .keep_all = T) %>% 
    carry_forward_platelets() %>% 
    group_by(child_mrn_uf) %>%
    fill(c(steroids, inotrope_score, number_inotropic_drugs),
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
    write.csv(nsofa, here("output", paste0("chicago_nsofa_score_", today(), ".csv")), 
              row.names = F, na = "")
  }
  
  return(nsofa)
}

get_max_score_within_n_hours_of_admission <- function(min_hour,
                                                      max_hour, 
                                                      filename = NULL,
                                                      create_csv = FALSE) {
  max_score <- nsofa_scores %>% 
    group_by(child_mrn_uf) %>% 
    arrange(q1hr) %>% 
    # every row represents an hour
    mutate(hour = 1:n()) %>%   
    filter(between(hour, min_hour, max_hour)) %>%   
    summarise(nsofa_score = max(nsofa_score), 
              number_hours_in_encounter = max(hour),
              dischg_disposition = unique(dischg_disposition))
  
  if (create_csv) {
    write.csv(max_score, here("output", paste0(filename,"_", today(), ".csv")), 
              row.names = F, na = "")
  }
  
  return(max_score)
}