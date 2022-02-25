library(tidyverse)
library(here)

cohort <- "pcicu"

nsofa_score <- read_rds(here("output", cohort, str_c(cohort, "_nsofa_data.rds")))

# created via psofa coding
q1hr_drug_dosages <- read_rds(here("data", cohort, str_c(cohort, "_q1hr_drug_dosages.rds")))

q1hr_drug_dosage_summary <- q1hr_drug_dosages %>%
  select(-med_order_end_datetime) %>%
  mutate_at(
    vars(
      "epinephrine",
      "dopamine",
      "norepinephrine",
      "dobutamine",
      "vasopressin",
      "milrinone"
    ),
    ~ replace(., is.na(.), 0)
  ) %>%
  mutate(
    vis_dopamine = dopamine,
    vis_dobutamine = dobutamine,
    vis_milrinone = 10 * milrinone,
    vis_vasopressin = 10 * vasopressin,
    vis_epinephrine = 100 * epinephrine,
    vis_norepinephrine = 100 * norepinephrine,
    vis_score = vis_dopamine + vis_dobutamine + vis_milrinone + vis_vasopressin + vis_epinephrine + vis_norepinephrine
  ) %>% 
  select(child_mrn_uf, q1hr, starts_with("vis_"))


output_file <- nsofa_score %>%
  inner_join(q1hr_drug_dosage_summary, by = c("child_mrn_uf", "q1hr"))

write_csv(output_file, here("output", cohort, str_c(cohort, "_nsofa_joined_to_vis.csv")), na = "")
