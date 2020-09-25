source("chicago_functions.R")

# load necessary packages
load_libraries()

child_encounter <- expand_child_encounter()

platelets <- get_platelets()

steroids <- get_steroids()

inotropes <- get_inotropes()

oxygenation <- get_oxygenation()

# use create_csv = TRUE to create csv file
nsofa_scores <- get_nsofa_dataset(create_csv = TRUE)

max_score_within_24_hrs <- get_max_score_within_n_hours_of_admission(
  min_hour = 1,
  max_hour = 24,
  "chicago_max_score_within_24_hrs",
  create_csv = TRUE
)

max_score_between_3_and_24_hrs <- get_max_score_within_n_hours_of_admission(
  min_hour = 3,
  max_hour = 24,
  "chicago_max_score_between_3_and_24_hrs",
  create_csv = TRUE
)

max_score_within_28_days <- get_max_score_within_n_hours_of_admission(
  min_hour = 1,
  max_hour = 672,
  "chicago_max_score_within_28_days",
  create_csv = TRUE
)



