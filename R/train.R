#!/usr/bin/env Rscript
# filename: train.R - train a Random Forest model on Vertex AI Managed Dataset
library(tidyverse)
library(data.table)
library(randomForest)
Sys.getenv()

# The GCP Project ID
project_id <- Sys.getenv("CLOUD_ML_PROJECT_ID")

# The GCP Region
location <- Sys.getenv("CLOUD_ML_REGION")

# The Cloud Storage URI to upload the trained model artifact to
model_dir <- Sys.getenv("AIP_MODEL_DIR")

# Next, you create directories to download our training, validation, and test set into.
dir.create("training")
dir.create("validation")
dir.create("test")

# You download the Vertex AI managed data sets into the container environment locally.
system2("gsutil", c("cp", Sys.getenv("AIP_TRAINING_DATA_URI"), "training/"))
system2("gsutil", c("cp", Sys.getenv("AIP_VALIDATION_DATA_URI"), "validation/"))
system2("gsutil", c("cp", Sys.getenv("AIP_TEST_DATA_URI"), "test/"))

# For each data set, you may receive one or more CSV files that you will read into data frames.
training_df <- list.files("training", full.names = TRUE) %>% map_df(~fread(.))
validation_df <- list.files("validation", full.names = TRUE) %>% map_df(~fread(.))
test_df <- list.files("test", full.names = TRUE) %>% map_df(~fread(.))

print("Starting Model Training")
rf <- randomForest(median_house_value ~ ., data=training_df, ntree=100)
rf

saveRDS(rf, "rf.rds")
system2("gsutil", c("cp", "rf.rds", model_dir))
