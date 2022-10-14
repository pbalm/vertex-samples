#!/usr/bin/env Rscript
# filename: serve.R - serve predictions from a Random Forest model
Sys.getenv()
library(plumber)

system2("gsutil", c("cp", "-r", Sys.getenv("AIP_STORAGE_URI"), "."))
system("du -a .")

rf <- readRDS("artifacts/rf.rds")
library(randomForest)

predict_route <- function(req, res) {
  print("Handling prediction request")
  df <- as.data.frame(req$body$instances)
  preds <- predict(rf, df)
  return(list(predictions=preds))
}

print("Staring Serving")

pr() %>%
  pr_get(Sys.getenv("AIP_HEALTH_ROUTE"), function() "OK") %>%
  pr_post(Sys.getenv("AIP_PREDICT_ROUTE"), predict_route) %>%
  pr_run(host = "0.0.0.0", port=as.integer(Sys.getenv("AIP_HTTP_PORT", 8080)))
