# All this is to allow the plugin to be disabled in the extensions preferences and to control versions a bit

require 'sketchup.rb'
require 'extensions.rb'

#Sketchup.send_action "showRubyPanel:"

version = '2.0.9'

sunHoursExtension = SketchupExtension.new "SunHours", "AlexHall_SunHours/interface"
sunHoursExtension.version = version
sunHoursExtension.creator = 'Alex Hall'
sunHoursExtension.copyright = '2015 Alex Hall'

sunHoursExtension.description = "Lets you fit grids to faces and then analyse how much sunlight hits them over a year: see 'Plugins' menu."
Sketchup.register_extension sunHoursExtension, true

module AlexHall
    module SunHours
    end
end
