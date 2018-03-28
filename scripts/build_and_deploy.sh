#!/bin/bash

### exit on any error
set -e

cd $(dirname $0)/..



FIJI_APP="/opt/Fiji.app"
if [ -n "$1" ] ; then
    FIJI_APP="$1"
fi

PLUGINS="$FIJI_APP/plugins/"
if ! [ -d "$PLUGINS" ] ; then
    echo "ERROR: can't find Fiji plugins directory: [$PLUGINS]"
    echo "Make sure to specify the *ABSOLUTE* path to a Fiji installation!"
    exit 1
fi


### build
mvn

### deploy
find "$PLUGINS" -name 'NoiSee-*.jar' | xargs --no-run-if-empty rm -v
cp -v $(find target -iname '*.jar' -and -not -iname '*-sources.jar') "$PLUGINS"
