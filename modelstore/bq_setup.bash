#!/bin/bash

BQ_DS=modelstore
BQ_TABLE=pipelines

echo Creating dataset
bq mk --dataset \
--project_id=$PROJECT \
--location=$REGION \
--force=true \
$BQ_DS

echo Creating table
bq mk --table \
--project_id=$PROJECT \
--location=$REGION \
--clustering_fields=update_time \
--schema=cloudfunction/schema.json \
$BQ_DS.$BQ_TABLE