#!/bin/bash

# Creates .zip and .rbz files for distribution

set -eux

rm *.rbz *.zip

version=`sed -En "s/^version = '([.0-9]+)'$/\1/p" AlexHall_SunHours.rb`
name=SunHours_v${version}
zip=${name}.zip
rbz=${name}.rbz

find . | grep .DS_Store | xargs rm

# This .rb file and folder are the actual plugin files that are ultimately
# placed in SketchUp's plugins folder and run.
zip -r -X ${zip} AlexHall_SunHours AlexHall_SunHours.rb

# The .rbz archive is uploaded to the Extension Warehouse.
cp ${zip} ${rbz}

# Finally this .zip can be downloaded from http://sunhoursplugin.com/index.php#download
# It contains the offline documentation plus both the .zip and .rbz,
# which are identical apart from the file extension.
# This is so that users can easily use one or the other without knowing how to rename the
# extension. The .rbz can be installed directly by SketchUp while the .zip is for manual
# copying to the plugins folder.
zip -r -X ${name}_SolidGreen.zip ${zip} ${rbz} SunHours_Documentation.pdf
