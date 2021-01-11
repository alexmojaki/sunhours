# All this is to allow the plugin to be disabled in the extensions preferences and to control versions a bit

require 'sketchup.rb'
require 'extensions.rb'

#Sketchup.send_action "showRubyPanel:"

version = '2.0.8'

# Unregister other versions if necessary
Sketchup.extensions.each { |ext|
	if (ext.name == "Sunlight analysis" or ext.name == "SunHours" or ext.name == "SunHours (stadium version)") and ext.creator == "Alex Hall" and ext.registered? and ext.version != version
		ext.uncheck
		UI.messagebox("Other version of SunHours detected and disabled. We recommend restarting Sketchup.")
	end
}

sunHoursExtension = SketchupExtension.new "SunHours (stadium version)", "AlexHall_SunHours/interface.rb"
sunHoursExtension.version = version
sunHoursExtension.creator = 'Alex Hall'
sunHoursExtension.copyright = '2015 Alex Hall'

sunHoursExtension.description = "Lets you fit grids to faces and then analyse how much sunlight hits them over a year: see 'Plugins' menu."
Sketchup.register_extension sunHoursExtension, true

module AlexHall
    module SunHours
    end
end
