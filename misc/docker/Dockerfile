FROM ubuntu:18.04

# qt5, python
RUN apt-get update -y && apt-get install -y --no-install-recommends \
  python3 python3-pip python3-dev \
  qt5-default

RUN python3 -m pip install --upgrade pip
RUN python3 -m pip install setuptools
