#!/bin/sh

echo "61C test"
time ./busroute -d data/daily.raw.gz -s "Murray Ave. AT Beacon" -e "Forbes Ave. AT Craig" -t 9:00p
