source("functions.R")

# load necessary packages
load_libraries()

child_encounter <- expand_child_encounter()

platelets <- get_platelets()

steroids <- get_steroids()

inotropes <- get_inotropes()

oxygenation <- get_oxygenation()

# use create_csv = TRUE to create csv file
nsofa_scores <- get_nsofa_dataset(create_csv = FALSE)


max_score_within_24_hrs <- get_max_score_within_n_hours_of_admission(
  min_hour = 1,
  max_hour = 24,
  "max_score_within_24_hrs",
  create_csv = TRUE
)

max_score_between_3_and_24_hrs <- get_max_score_within_n_hours_of_admission(
  min_hour = 3,
  max_hour = 24,
  "max_score_between_3_and_24_hrs",
  create_csv = TRUE
)

max_score_within_28_days <- get_max_score_within_n_hours_of_admission(
  min_hour = 1,
  max_hour = 672,
  "max_score_within_28_days",
  create_csv = TRUE
)

nsofa_summary <- nsofa_scores %>%
  mutate(nsofa_above_zero = if_else(nsofa_score > 0, 1, 0)) %>%
  group_by(child_mrn_uf) %>%
  summarise(across(c(platelets, oxygenation, cv, nsofa_score), list(max = max, sum = sum), .names = "{.col}_{fn}"),
            num_hours_nsofa_above_zero = sum(nsofa_above_zero),
            total_hospitalization_time_in_hours = n()
  ) %>%
  mutate(
    total_time_in_encounter = round(
      num_hours_nsofa_above_zero / total_hospitalization_time_in_hours,
      2
    )
  )

drug_dose_summary <- nsofa_scores %>%
  rename_all(tolower) %>% 
  mutate(total_dosage = dopamine + dobutamine + milrinone + vasopressin + epinephrine + norepinephrine,
         dosage_above_zero = if_else(total_dosage > 0, 1, 0)) %>%
  group_by(child_mrn_uf) %>%
  summarise(
    across(
      c(dopamine,
        dobutamine,
        milrinone,
        vasopressin,
        epinephrine,
        norepinephrine,
        total_dosage
      ),
      list(max = max, sum = sum),
      .names = "{.col}_{fn}"
    ),
    num_hours_dosage_above_zero = sum(dosage_above_zero),
    total_hospitalization_time_in_hours = n()
  ) %>%
  mutate(
    total_time_in_encounter = round(
      num_hours_dosage_above_zero / total_hospitalization_time_in_hours,
      2
    )
  ) %>%
  select(-contains("above_zero"))

vis_summary <- nsofa_scores %>%
  rename_all(tolower) %>% 
  mutate(
    vis_milrinone = 10 * milrinone,
    vis_vasopressin = 10 * vasopressin,
    vis_epinephrine = 100 * epinephrine,
    vis_norepinephrine = 100 * norepinephrine,
    vis_score = dopamine + dobutamine + vis_milrinone + vis_vasopressin + vis_epinephrine + vis_norepinephrine,
    vis_above_zero = if_else(vis_score > 0, 1, 0)
  ) %>%
  group_by(child_mrn_uf) %>%
  summarise(
    across(
      c(dopamine,
        dobutamine,
        starts_with("vis_"),
        vis_score),
      list(max = max, sum = sum),
      .names = "{.col}_{fn}"
    ),
    num_hours_vis_above_zero = sum(vis_above_zero),
    total_hospitalization_time_in_hours = n()
  ) %>%
  mutate(
    total_time_in_encounter = round(
      num_hours_vis_above_zero / total_hospitalization_time_in_hours,
      2
    )
  ) %>%
  select(-contains("above_zero"))

write_csv(nsofa_summary, "output/nsofa_summary.csv")
write_csv(drug_dose_summary, "output/nsofa_drug_summary.csv")
write_csv(vis_summary, "output/nsofa_vis_summary.csv")

