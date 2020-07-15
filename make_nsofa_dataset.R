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

max_score <- get_max_score_within_n_days_of_birth(n_days = 28, 
                                                  create_csv = FALSE)


