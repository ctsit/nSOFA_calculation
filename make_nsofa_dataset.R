source("functions.R")

# load necessary packages
load_libraries()

cohort <- "pcicu"

respiratory_devices <- read_excel(here("data", "categorized_respiratory_devices.xlsx")) %>% 
  filter(intubated %in% c('yes', 'no'))

read_child_encounter <- read_csv(here("data", cohort, "encounter.csv")) %>%
  clean_names() %>%
  filter(!is.na(dischg_datetime))

# Filter to term neonates (<=30 days old at admission) for PICU/PCICU. Also, note that
# expand_child_encounter only returns the first encounter for nsofa calculation
if (cohort != 'nicu') {
read_child_encounter <- read_child_encounter %>% 
  arrange(child_mrn_uf, admit_datetime) %>% 
  filter(as_date(admit_datetime) - child_birth_date <= 30) 
}

child_encounter <- expand_child_encounter(read_child_encounter)

read_child_labs <- read_csv(here("data", cohort, "labs.csv")) %>%
  clean_names()

read_medications <- read_csv(here("data", cohort, "medications.csv")) %>%
  clean_names() 

read_flowsheets <- read_csv(here("data", cohort, "flowsheets.csv")) %>%
  clean_names() 
  
platelets <- get_platelets(read_child_labs, child_encounter)

steroids <- get_steroids(read_medications, child_encounter)

inotropes <- get_inotropes(read_medications, child_encounter)

oxygenation <- get_oxygenation(read_flowsheets, respiratory_devices)

# use create_csv = TRUE to create csv file
nsofa_scores <- get_nsofa_dataset(cohort, create_csv = TRUE)


# max_score_within_24_hrs <- get_max_score_within_n_hours_of_admission(
#   min_hour = 1,
#   max_hour = 24,
#   cohort = cohort,
#   "max_score_within_24_hrs",
#   create_csv = TRUE
# )
# 
# max_score_between_3_and_24_hrs <- get_max_score_within_n_hours_of_admission(
#   min_hour = 3,
#   max_hour = 24,
#   cohort = cohort,
#   "max_score_between_3_and_24_hrs",
#   create_csv = TRUE
# )
# 
# max_score_within_28_days <- get_max_score_within_n_hours_of_admission(
#   min_hour = 1,
#   max_hour = 672,
#   cohort = cohort,
#   "max_score_within_28_days",
#   create_csv = TRUE
# )

# nsofa_summary <- nsofa_scores %>%
#   mutate(nsofa_above_zero = if_else(nsofa_score > 0, 1, 0)) %>%
#   group_by(child_mrn_uf, admit_datetime, dischg_datetime, dischg_disposition) %>%
#   summarise(across(c(platelets, oxygenation, cv, nsofa_score), list(max = max, sum = sum), .names = "{.col}_{fn}"),
#             num_hours_nsofa_above_zero = sum(nsofa_above_zero),
#             total_hospitalization_time_in_hours = n()
#   ) %>%
#   mutate(
#     total_time_in_encounter = round(
#       num_hours_nsofa_above_zero / total_hospitalization_time_in_hours,
#       2
#     )
#   )
