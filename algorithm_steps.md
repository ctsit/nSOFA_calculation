## Introduction
This document describes the steps that went into creating the functions that generate the nSOFA dataset in [functions.R](functions.R). These steps were specifically created to transform data received from the University of Florida Integrated Data Repository (IDR). Thus, every step may not be necessary for data from a different source. Please review your data to determine which of these steps are necessary.

## Child Encounter
1. When a subject has multiple encouters choose the first encounter
1. Only choose subjects with both an admit and discharge datetime
1. Each row of the dataset should represent a unique subject
1. Round admit and discharge datetime down to the nearest hour
1. Create `q1hr` timepoints for every hour between admit and discharge datetime

## Platelets
1. Read labs file
1. Choose only subjects that are in the `child_encounter` dataset
1. Filter
```
lab_name = 'PLATELET COUNT' 
and lab_result contains a digit
```
3. Any lab result values that are words like "Clump" or "Quantity not sufficient" should be removed
4. Drop any non-numeric characters in `lab_result` before the first digit. i.e. For, "<3", "<" should be dropped
5. Create a field named `platelets` using the following logic 
```
 lab_result < 50 then platelets = 3,
 lab_result < 100 then platelets = 2,
 lab_result < 150 then platelets = 1,
 else platelets = 0
```
6. Create `q1hr` timepoints by rounding `inferred_specimen_datetime` down to the nearest hour
7. Choose the last recorded `inferred_specimen_datetime` within a given `q1hr`


## Transform Medication Data
The function `align_drug_start_end_times` depends on the data quality so some parts may be optional. It's purpose is to transform the medications file to assist with creating the inotropes and steroids datasets. This function was built to transform the data obtained from the UF IDR. 
It can be refactored to work with other datasets. View [transformation.pdf](transformation.pdf) for an example of how the data is transformed. It does the following:

1. Ensures that `med_order_datetime` occurs before `med_order_end_datetime`
1. Handles conflicting `med_order_datetime` and `med_order_end_datetime`
1. Sets a value of 1 when the subject is on a given medication and 0 if no medications are present

## Steroids
1. Read medications file
1. Choose only subjects that are in the `child_encounter` dataset
1. Apply the following filters
```
med_order_desc in DEXAMETHASONE, HYDROCORTISONE or METHYLPREDNISOLONE
and med_order_route in Intravenous, Oral, Per NG tube, Per G Tube,Per OG Tube
and mar_action is not NA
```   
1. Extract the first word of `med_order_desc`. i.e. "HYDROCORTISONE PEDIATRIC INJ DOSE < 5MG UF" will be converted to HYDROCORTISONE.
1. Align drug start and end times
1. Create field named `number_steroids` which represents the number of steroids a subject is on during an hour
1. Create field named `steroids` by using the following logic
```
number_steroids = 0 then steroids = 0
else steroids = 1
```

## Inotropes
1. Read medications file
1. Choose only subjects that are in the `child_encounter` dataset
1. Apply the following filters
```
med_order_desc in DOBUTAMINE, DOPAMINE, EPINEPHRINE, MILRINONE, NOREPINEPHRINE, VASOPRESSIN or PHENYLEPHRINE"
and med_order_route = "Intravenous"
```
1. Extract the first word of `med_order_desc`
1. Align drug start end times
1. Create a field named `number_inotropic_drugs` which represents the number of inotropes a subject is on during an hour
1. Create field named `inotrope_score` using the following logic
```
number_inotropic_drugs = 0 then inotrope_score = 0,
number_inotropic_drugs = 1 then inotorpe_score = 2,
number_inotropic_drugs > 1 then inotorpe_score = 3
```
      
## Respiratory

#### Determine intubation devices
1. Read categorized_respiratory_devices.xlsx and filter to intubated in yes or no to create `respiratory_devices` dataset.
This file contains devices that represent intubation based on the data received from the UF IDR. If necessary, update the file to match intubated devices from a different data source.

#### Transform flowsheets dataset
1. Read flowsheets data
1. Filter to subjects that are in the `child_encounter` dataset
1. Create `q1hr` timepoints by rounding `recorded_time` down to the nearest hour

#### Create a dataset to determine if a subject was intubated at a given hour (intubate_yes_no). This dataset does not have the FiO2 or SpO2 scores.
1. Use the transformed flowsheets data
1. Filter
```
flowsheet_group = "Oxygenation"
and disp_name = "meas_value"
```
1. Inner join `respiratory_devices` using `meas_value` as the primary key. This join identifies if a subject was intubated or not during a given hour.
1. Choose the last recorded value within an hour to ensure that no subject has multiple values within an hour
1. Join child_encounter using `mrn` and `q1hr` as the primary keys 
1. Replace empty values of `meas_value` and `intubated` with the last recorded value for that field. This determines whether a subject was intubated or not for every hour during the encounter.

#### FiO2 
1. Use transformed flowsheets data
1. Filter
```
flowsheet_group in "Oxygenation" or "Vent Settings" 
and disp_name contains "FiO2"
```
1. Inner join `intubated_yes_no` where `intubated` = 'yes'. Use `mrn` and `q1hr` as the primary keys
1. An FiO2 score can come from “oxygenation” flowsheet or “vent settings” flowsheet. When there are simultaneously-recorded FiO2 in both the “oxygenation” flowsheet and the “vent settings” flowsheet  within an hour chose the “oxygenation” flowsheet value. 
When there are more than two FiO2 values within the same hour choose the highest value regardless of if that value comes from  "oxygenation" or "vent settings" flowsheet group.

#### SpO2 
1. Use transformed flowsheets data
1. Filter
```
flowsheet_group in "Vitals" 
and disp_name contains "SpO2"
```
1. Inner join `intubated_yes_no` where `intubated` = 'yes'. Use `mrn` and `q1hr` as the primary keys
1. Choose an SpO2 value following this order: SpO2, SpO2 #3, then SpO2 #2

#### Create a dataset for intubated (intubated_yes)
1. Combine FiO2 and SpO2 into one dataset
1. Create oxygenation_ratio from SpO2/FiO2
1. Create oxygenation score using the followinng logic: 
```
oxygenation_ratio >= 3 then oxygenation = 0,
oxygenation_ratio >= 2 then oxygenation = 2,
oxygenation_ratio >= 1.5 then oxygenation = 4,
oxygenation_ratio >= 1 then oxygenation = 6,
oxygenation_ratio < 1 then oxygenation = 8,
Else oxygenation = NA
```

#### Create a dataset for not intubated (intubated_no)
1. Use `intubated_yes_no` dataset
1. Filter `intubated = no`
1. Set oxygenation to 0

#### Create respiratory dataset
1. Combine `intubated_yes` and `intubated_no`
1. Arrange by `mrn` and `q1hr`

## nSOFA Dataset
1. Join the `platelets`, `steroids`, `inotropes` and `respiratory` datasets to the `child_encounter` data using `mrn` and `q1hr` as the primary keys
1. Replace all values of NA with the last recorded value
1. Calculate the cardivascular score using the rules given in the Score Calculation section of the [README](README.md)
1. Calculate the nSOFA score by summing Respiratory score, Cardiovascular score and Hematologic score