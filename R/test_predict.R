library(tidyverse)
library(randomForest)
library(jsonlite)
library(plumber)

setwd("~/vertex-samples/R")
df <- read_csv("data/california-housing-tabular-regression-sample.csv",
               show_col_types = F)
head(df, 5)

rf <- randomForest(median_house_value ~ ., data=df, ntree=10)
rf

#saveRDS(rf, "model/rf2.rds")
#rf <- readRDS("model/rf2.rds")
#print(rf)

instances <- list(instances=head(df[, names(df) != "median_house_value"], 5))
#instances

json_instances <- toJSON(instances)


print("Handling prediction request")
preds <- predict(rf, head(df,5))

print("--- predictions")
head(preds, 5)

list(predictions=preds)

# Test a local server
predict_route <- function(req, res) {
  print("Handling prediction request 2")
  #json_data = req$body$instances
  #print(json_data)
  #df <- as.data.frame(json_data)
  print("--- instances")
  print(head(df, 5)) # debug output
  preds <- predict(rf, df)
  print("--- predictions")
  print(head(preds, 5))
  return(list(predictions=preds))
}

print("Starting Serving")

pr() %>%
  pr_get("/health", function() "OK") %>%
  pr_post("/predict", predict_route) %>%
  pr_run(host = "0.0.0.0", port=8080)

