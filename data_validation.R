# IMPORTANT: make_nsofa_dataset.R must first be run to create the nsofa_scores dataset

source("functions.R")

load_libraries()

# compare to nsofa data provided by irb ---------------------------------------

# data from 2018 onwards
read_irb_nsofa <- get_data("nsofa_scores.csv") %>% 
  mutate(q1hr = floor_date(recorded_time, "1 hour")) %>% 
  group_by(child_mrn_uf, q1hr) %>% 
  filter(recorded_time == max(recorded_time)) %>% 
  ungroup()

unique_id <- read_irb_nsofa %>% 
  distinct(child_mrn_uf)

filtered_irb_nsofa <- read_irb_nsofa %>% 
  filter(child_mrn_uf %in% unique_id$child_mrn_uf) %>% 
  select(child_mrn_uf, q1hr, inotropes:steroids) %>%
  fill(c(platelets, steroids, inotropes, oxygenation),
       .direction = "down") %>%   
  mutate(cv = case_when(inotropes == 0 & steroids == 0 ~ 0,
                        inotropes == 0 & steroids == 1 ~ 1,
                        inotropes == 1 & steroids == 0 ~ 2,
                        (inotropes >= 2 & steroids == 0) | 
                          (inotropes == 1 & steroids == 1) ~ 3,
                        inotropes >= 2 & steroids == 1 ~ 4)) %>%
  # how is nosfa claculated if inotropic score is used
  mutate(nsofa_score = platelets + oxygenation + cv)

# Read input dataset if not already in environment
read_nsofa_scores <- vroom(here("output", "nsofa_scores.csv"), delim = ",")
nsofa_scores <- read_nsofa_scores %>%        
  rename(inotropes = inotrope_score) %>% 
  select(-number_inotropic_drugs)
  
# this only compares data beginning in 2018
compare_irb_ctsi <- filtered_irb_nsofa %>% 
  inner_join(nsofa_scores, by = c("child_mrn_uf", "q1hr"), suffix = c("_irb", "_ctsi")) %>% 
  select(child_mrn_uf, q1hr, starts_with("inotrope"),
         starts_with("oxygenation"),
         starts_with("platelets"), starts_with("steroids"),
         starts_with("nsofa")
         )

write.xlsx(compare_irb_ctsi, here("output", "compare_irb_ctsi.xlsx"), na = "")

# compare scores
nsofa_score_compare <- compare_irb_ctsi %>% 
  filter(nsofa_score_irb != nsofa_score_ctsi)
nrow(nsofa_score_compare)/nrow(compare_irb_ctsi)

inotropes_compare <- compare_irb_ctsi %>% 
  filter(inotropes_irb != inotropes_ctsi)
nrow(inotropes_compare)/nrow(compare_irb_ctsi)

oxygenation_compare <- compare_irb_ctsi %>% 
  filter(oxygenation_irb != oxygenation_ctsi)
nrow(oxygenation_compare)/nrow(compare_irb_ctsi)

platelets_compare <- compare_irb_ctsi %>% 
  filter(platelets_irb != platelets_ctsi)
nrow(platelets_compare)/nrow(compare_irb_ctsi)

steroids_compare <- compare_irb_ctsi %>% 
  filter(steroids_irb != steroids_ctsi)
nrow(steroids_compare)/nrow(compare_irb_ctsi)



