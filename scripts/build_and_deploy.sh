#!/bin/bash

### exit on any error
set -e

cd $(dirname $0)/..



FIJI_APP="/opt/Fiji.app"
if [ -n "$1" ] ; then
    FIJI_APP="$1"
fi


### build and deploy
mvn -Dimagej.app.directory="$FIJI_APP"
