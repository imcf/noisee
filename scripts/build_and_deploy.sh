#!/bin/bash

### exit on any error
set -e

cd $(dirname $0)/..

### build
mvn

### deploy
find /opt/Fiji.app/plugins/ -name 'NoiSee-*.jar' | xargs --no-run-if-empty rm -v
cp -v $(find target -iname '*.jar' -and -not -iname '*-sources.jar') /opt/Fiji.app/plugins/
