#!/usr/bin/env Rscript
# filename: serve.R - serve predictions from a Random Forest model
Sys.getenv()

library(plumber)
library(randomForest)
library(jsonlite)

system2("gsutil", c("cp", "-r", Sys.getenv("AIP_STORAGE_URI"), "."))
system("du -a .")

rf <- readRDS("artifacts/rf.rds")

predict_route <- function(req, res) {
  print("Handling prediction request")
  df <- as.data.frame(req$body$instances)
  print("--- instances")
  print(head(df, 5)) # debug output
  preds <- predict(rf, df)
  print("--- predictions")
  print(head(preds, 5))
  return(list(predictions=preds))
}

print("Starting Serving")
print(rf)

print(paste("Predict route is ", Sys.getenv("AIP_PREDICT_ROUTE")))
print(paste("Running on port ", as.integer(Sys.getenv("AIP_HTTP_PORT", 8080))))

pr() %>%
  pr_get(Sys.getenv("AIP_HEALTH_ROUTE"), function() "OK") %>%
  pr_post(Sys.getenv("AIP_PREDICT_ROUTE"), predict_route) %>%
  pr_run(host = "0.0.0.0", port=as.integer(Sys.getenv("AIP_HTTP_PORT", 8080)))
