# filename: Dockerfile - container specifications for using R in Vertex AI
FROM gcr.io/deeplearning-platform-release/r-cpu.4-1:latest

WORKDIR /root

COPY train.R /root/train.R
COPY serve.R /root/serve.R

# Install Fortran
RUN apt-get update
RUN apt-get install gfortran -yy

# Install R packages
RUN Rscript -e "install.packages('plumber')"
RUN Rscript -e "install.packages('randomForest')"
RUN Rscript -e "install.packages('jsonlite')"

EXPOSE 8080
