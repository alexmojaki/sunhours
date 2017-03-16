#!/bin/bash

set -eux

rm *.rbz *.zip

version=`sed -En "s/^version = '([.0-9]+)'$/\1/p" AlexHall_SunHours.rb`
name=SunHours_v${version}
zip=${name}.zip
rbz=${name}.rbz

find . | grep .DS_Store | xargs rm
zip -r -X ${zip} AlexHall_SunHours AlexHall_SunHours.rb
cp ${zip} ${rbz}
zip -r -X ${name}_SolidGreen.zip ${zip} ${rbz} SunHours_Documentation.pdf
