library(tidyverse)
library(randomForest)
library(jsonlite)


df <- list.files("data", full.names = TRUE) %>% map_df(~fread(.))
head(df, 5)

rf <- randomForest(median_house_value ~ ., data=df, ntree=10)
rf

saveRDS(rf, "model/rf2.rds")
rf <- readRDS("model/rf2.rds")
print(rf)

#instances <- list(instances=head(df[, names(df) != "median_house_value"], 5))
#instances

json_instances <- toJSON(instances)


print("Handling prediction request")


preds <- predict(rf, head(df,5))

print("--- predictions")
head(preds, 5)

list(predictions=preds)
