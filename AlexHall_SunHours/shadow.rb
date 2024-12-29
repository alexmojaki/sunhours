
# Copyright (c) 2012 Alex Hall ( Solid Green Consulting: http://www.solidgreen.co.za/ , Contact: alex.mojaki@gmail.com )

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
# is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Sketchup::require("sketchup")
Sketchup::require("json")



module AlexHall
    module SunHours
        
        # Number of seconds in a day for advancing time by days
        DAY = 60*60*24

        # For each grid:
        #	For each period of days:
        #		For each day in the period:
        #			For each time period in the day:
        #				Iterate through the period, advancing by the time step
        #					For every valid node in the grid:
        #						Determine if the node is in the sun
        #	Colour the grid
        # Export all results to file
        def SunHours.sunlight_analyse_grids_params(parameters_string, grids, dialog)

            begin
                model = Sketchup.active_model
                shinfo = model.shadow_info
                entities = model.active_entities
                selection = model.selection
                model_dict = model.attribute_dictionary("SunHours", false)

                parameters = parameters_string.split
                action_name = parameters.shift

                ### Getting the parameters from the interface

                # Fetch date periods in the form:
                # [ [ [startDay0, startMonth0], [endDay0, endMonth0] ] , [ [startDay1, startMonth1], [end...] ] , ... ]
                dates = []
                datePeriods = (parameters.shift).to_i
                for n in 0...datePeriods
                    n = n.to_s
                    dates << [ [(parameters.shift).to_i, (parameters.shift).to_i] , \
                               [(parameters.shift).to_i  , (parameters.shift).to_i  ] ]
                end

                # Fetch time periods in a similar form to the dates, except that that form represents a single type
                times = []
                types = (parameters.shift).to_i
                for m in 0...types
                    timePeriods = (parameters.shift).to_i
                    type = []
                    for n in 0...timePeriods
                        type << [ [(parameters.shift).to_i, (parameters.shift).to_i] , \
                                   [(parameters.shift).to_i  , (parameters.shift).to_i ] ]
                    end
                    times << type
                end

                # Fetch weekdays to include (an array of booleans: t means include)
                weekdays = []
                for m in 0...types
                    weekdays << (0...7).collect { |i| parameters.shift=="t" }
                end

                # Granularity of the calculation: time step in hours
                timeStep = Float(parameters.shift)*3600
                
                # Location of CSV file
                savePath = dialog.get_element_value("save_path") rescue ""
                
                if not savePath.empty?
                    
                    fullPath = File.expand_path(savePath)
                    
                    if savePath != fullPath
                        savePath = fullPath
                        UI.messagebox("The file will be saved in " + savePath)
                    end
                    
                    # The file needs to be writeable if it already exists so that it can be replaced
                    File.chmod(0666, savePath) rescue nil

                    outfile = nil
                    begin
                        outfile = File.new(savePath, "w")
                    rescue => error
                        UI.messagebox("Failed to create CSV file: " + error.message)
                        return
                    end
                end

                # Whether or not to include minima and maxima in the CSV
                mins = (parameters.shift=="t")
                maxs = (parameters.shift=="t")

                dialog.close if dialog
            rescue => error
                UI.messagebox("Error collecting parameters: " + error.message)
                raise
            end

            ##### ANALYSIS

            begin
                ## Initialisation

                # Hide all grids so that they don't interfere with the calculation (they cast shadows)
                entities.each { |ent| ent.hidden = true if ent.attribute_dictionaries and ent.attribute_dictionaries["SunHours_grid_properties"] }

                # Initialise here for scope: they will be needed after all grids have been analysed for export to file,
                # but get set to zero for each grid anyway
                totalDays = 0; totalTime = 0;

                # String containing all the data that will be exported to file
                allResults = ""

                # Unrelated to grid ID: this is used when showing progress
                gridnum=0

                # This is so that after analysis the model's time can be reset to normal, especially so that shadows don't cover the model
                originalTime = shinfo["ShadowTime"]

                ## Actual analysis

                # For each grid
                grids.each { |grid|

                    gridnum+=1

                    # Fetch grid info
                    dict = grid.attribute_dictionaries["SunHours_grid_properties"]
                    nodes = dict["nodes"]
                    is_surface = dict["is_surface"]
                    norm = Geom::Vector3d.new(dict["norm"])

                    # Number of grid cells in the x and y directions
                    nx = nodes[0].length-1; ny = nodes.length-1

                    # Give the grid an ID if it doesn't already have one
                    if not dict["id"]
                        dict["id"] = model_dict["grid_id"]

                        # Update the model's next available ID
                        model_dict["grid_id"] += 1
                    end

                    allResults += "\nGrid ID:, "+dict["id"].to_s+"\n\n"

                    # Set up the three result grids (with zeroes) to store analysis results
                    totalsGrid = []; maxGrid = []; minGrid = []
                    for y in 0..ny
                        totalsGrid << [0]*(nx+1)
                        maxGrid << [0]*(nx+1)
                        minGrid << [1.0/0.0]*(nx+1)
                    end

                    totalTime = 0 # Maximum potential time in sun, in hours
                    totalDays = 0

                    # Iterate through periods of days
                    for datePeriod in 0...datePeriods

                        # Note that all calculations are done in the year 2015
                        startDate = Time.utc(2015, dates[datePeriod][0][1], dates[datePeriod][0][0], 12)
                        shinfo["ShadowTime"] = startDate

                        endDate = Time.utc(2015, dates[datePeriod][1][1], dates[datePeriod][1][0]) + DAY

                        # Iterate through days in the period
                        while shinfo["ShadowTime"] <= endDate

                            # Selecting the appropriate type based on the weekday
                            excludeDay = true;

                            for type in 0...types
                                if weekdays[type][(shinfo["ShadowTime"].wday-1)%7]
                                    excludeDay = false
                                    break
                                end
                            end

                            # Excluding the day if no type has this weekday
                            if excludeDay
                                shinfo["ShadowTime"] += DAY
                                next
                            end

                            totalDays += 1

                            # Set up a grid of results for just that day (needed for min and max grids particularly)
                            dayGrid = []
                            for y in 0..ny
                                dayGrid << [0]*(nx+1)
                            end

                            timePeriods = times[type].length

                            # Iterate through time periods
                            for timePeriod in 0...timePeriods
                                startTime = shinfo["ShadowTime"].utc
                                startTime = Time.utc(2015, startTime.month, startTime.day, times[type][timePeriod][0][0], times[type][timePeriod][0][1], 0)
                                startTime = [startTime, shinfo["SunRise"].utc].max # Don't start analysis before sunrise
                                startTime += DAY*365*(2015-startTime.year) # Sometimes the year just changes when it calculates sunrise (particularly on the 31 Dec)

                                endTime = shinfo["ShadowTime"].utc
                                endTime = Time.utc(2015, endTime.month, endTime.day, times[type][timePeriod][1][0], times[type][timePeriod][1][1], 0)
                                endTime = [endTime, shinfo["SunSet"].utc].min # End analysis before sunset
                                endTime += DAY*365*(2015-endTime.year) # in case of same bug as above

                                totalTime += (endTime - startTime)/3600

                                shinfo["ShadowTime"] = startTime

                                while shinfo["ShadowTime"] < endTime

                                    # For each node...
                                    for y in 0..ny
                                        for x in 0..nx
                                            p = nodes[y][x] # This is a Point3d (actually it's just a 3-element array)

                                            # If the node is valid (i.e. included in the grid)
                                            if p

                                                # Add time to the results node if the point is in sun at the time
                                                # The raytest is the crucial test for sunlight. Hidden geometry (and hence analysis grids) is ignored
                                                ray = [p, shinfo["SunDirection"]]
                                                intersection = model.raytest(ray)
                                                dayGrid[y][x] += [timeStep, endTime-shinfo["ShadowTime"]].min.to_f/3600 if !intersection
                                            end
                                        end
                                    end

                                    shinfo["ShadowTime"] += timeStep

                                end
                                # End of the time period

                            end
                            # End of the day

                            # Use the day grid to update the three main result grids
                            # For each node:
                            for y in 0..ny
                                for x in 0..nx
                                    val = dayGrid[y][x]
                                    totalsGrid[y][x] += val
                                    maxGrid[y][x] = [maxGrid[y][x], val].max
                                    minGrid[y][x] = [minGrid[y][x], val].min
                                end
                            end

                            # Show progress in the status bar (as text)
                            Sketchup.status_text=shinfo["ShadowTime"].strftime("Just analysed: %d %b") + (grids.length>1 ? (" for grid #{gridnum} out of #{grids.length}") : "")

                            # Next day (adding to a time advances it by seconds)
                            shinfo["ShadowTime"] += DAY

                        end
                        # End of period of days

                    end
                    # End of year and of analysis for this grid

                    # Set all invalid nodes to -1 in the result grids
                    for y in 0..ny
                        for x in 0..nx
                            totalsGrid[y][x] = maxGrid[y][x] = minGrid[y][x] = -1 if not nodes[y][x]
                        end
                    end

                    SunHours.remove_numbers_from_grid(grid)
                    dict["results"] = totalsGrid
                    dict["totalTime"] = totalTime
                    dict["old_grid"] = false

                    #### Colour the cells

                    # Update the progress in the status bar				
                    Sketchup.status_text="Coloring grid" + (grids.length>1 ? (" #{gridnum} out of #{grids.length}") : "") + "..."

                    SunHours.color_grid(grid)

                    ## Add the results from the 3 grids to the output string for exporting to file
                    allResults += "Totals:\n\n"
                    for y in 0..ny
                        line = ""
                        for x in 0..nx
                            line += totalsGrid[y][-1-x].to_s
                            line += ", " if x!=nx
                        end
                        allResults += line+"\n"
                    end

                    if mins
                        allResults += "\nMinimums:\n\n"
                        for y in 0..ny
                            line = ""
                            for x in 0..nx
                                line += minGrid[y][-1-x].to_s
                                line += ", " if x!=nx
                            end
                            allResults += line+"\n"
                        end
                    end

                    if maxs
                        allResults += "\nMaximums:\n\n"
                        for y in 0..ny
                            line = ""
                            for x in 0..nx
                                line += maxGrid[y][-1-x].to_s
                                line += ", " if x!=nx
                            end
                            allResults += line+"\n"
                        end
                    end


                }
                # All grids analysed

                # Return the model time to what it was before analysis
                shinfo["ShadowTime"] = originalTime

                # Unselect and reselect the grids so that the selection observer shows the scale
                selection.clear
                selection.add(grids)
                ScaleObservers[model].showScale

                # Show all grids again (they were hidden to avoid interfering with the calculation)
                entities.each { |ent| ent.hidden = false if ent.attribute_dictionaries and ent.attribute_dictionaries["SunHours_grid_properties"] }

                # Complete the "Analyse grids" or "IEQ wizard" operation started by the caller
                model.commit_operation
            rescue => error
                model.abort_operation
                UI.messagebox("Error occurred during analysis: " + error.message)
                raise
            end

            # Prepend the results for the file with total times
            allResults = "Total time analysed in hours:, #{totalTime}\n" \
                       + "Total number of days:, #{totalDays}\n" + allResults

            # Clear the status bar which was showing progress
            Sketchup.set_status_text("")

            if outfile
                begin
                    outfile.write(allResults)
                rescue => error
                    UI.messagebox("Error occurred while writing results to file: " + error.message)
                    raise
                end

                # After writing, the user should be unable to change it to prevent import errors
                outfile.chmod(0444)
                
                outfile.close()
            end

        end
        # End of sunlight_analyse_grids_params function definition

        def SunHours.getSavePath()
            savePath = UI.savepanel("Save results file",Sketchup.active_model.path,"Sunlight analysis")
            if savePath

                # Append .csv if it isn't already there
                savePath += ".csv" if not savePath[-4..-1]==".csv"
            end
            return savePath
        end

        # Called when the menu item is clicked, this sets up the parameters dialog and passes the parameters
        # to sunlight_analyse_grids_params.
        def SunHours.sunlight_analyse_grids()

            model = Sketchup.active_model
            selection = model.selection

            # Find all grids in the selection
            grids = []
            selection.each { |ent|
                # A grid is identified by having the "SunHours_grid_properties" attribute dictionary
                if ent.attribute_dictionaries and ent.attribute_dictionaries["SunHours_grid_properties"]
                    grids << ent
                end
            }

            # If no grids are found in the selection, inform the user and stop immediately
            if grids.length == 0
                UI.messagebox("No grid found in selection.")
                return
            end

            # Interface provided by a web dialog (dates_times_dialog.html)
            dialog = UI::WebDialog.new("Calculation parameters", true, "Calculation parameters", 420,700,10,10, true)
            path = File.join(File.dirname(__FILE__), "dates_times_dialog.html")
            dialog.set_file(path)
            dialog.show

            model_dict = model.attribute_dictionary("SunHours", false)

            dialog.add_action_callback("pop") { |wd, p| 
                dialog.execute_script("populate("+model_dict["SunHours_default_dates_times"].to_json+");")

                # If there are any hidden entities in the model, tell the dialog to warn of this
                if model.active_entities.to_a.collect{ |ent| ent.hidden? }.any?
                    dialog.execute_script("warnHidden();")
                end
            }
            
            dialog.add_action_callback("save") { |wd, p|
                command = "setSavePath(" + getSavePath().to_json + ")"
                dialog.execute_script(command)
                
                # For some reason the dialog likes to go into the background when you try to replace a file
                dialog.show()
            }

            # If a button is clicked on the dialog:
            dialog.add_action_callback("get_data") { |web_dialog, parameters_string|

                parameters = parameters_string.split
                action_name = parameters.shift

                if action_name=="default"

                    model_dict["SunHours_default_dates_times"] = parameters_string
                    UI.messagebox("Defaults set")

                # If the button says 'OK' (all analysis inside here)
                elsif action_name=="submit"
                    dialog.close
                    model.start_operation("Analyse grids", true)
                    sunlight_analyse_grids_params(parameters_string, grids, dialog)
                    # The operation is committed inside sunlight_analyse_grids_params

                else # If the user clicked Cancel
                    dialog.close
                end

            }

        end

        def SunHours.color_cells(coords, grid)

            model = Sketchup.active_model

            dict = grid.attribute_dictionaries["SunHours_grid_properties"]

            if not dict["colorBasis"]
                color_dict = model.attribute_dictionaries["SunHours_default_color_settings"]
                dict["colorBasis"] = color_dict["colorBasis"]
                dict["numCols"] = color_dict["numCols"]
                dict["colours"] = color_dict["colours"]
                dict["maxCol"] = color_dict["maxCol"]
                dict["maxColVal"] = color_dict["maxColVal"]
                dict["minCol"] = color_dict["minCol"]
                dict["minColVal"] = color_dict["minColVal"]
            end

            nodes = dict["nodes"]
            totalsGrid = dict["results"]
            colorBasis = dict["colorBasis"]
            totalTime = dict["totalTime"]
            numCols = dict["numCols"]
            colours = dict["colours"]
            maxColVal = dict["maxColVal"]
            minColVal = dict["minColVal"]
            maxCol = dict["maxCol"]
            minCol = dict["minCol"]

            pts = coords.collect{ |c| nodes[c[1]][c[0]] } # the corners of the cell as points

            # If all the vertices are valid nodes (i.e. fitted within the face(s)
            if pts.all?

                # Add the face
                newFace = grid.entities.add_face(pts)

                ## Colour the face

                # Determine a weight depending on how the user has chosen to color cells
                vals = coords.collect{ |c| totalsGrid[c[1]][c[0]] }
                case colorBasis
                when "average"
                    weight = 0 # weight within the whole scale
                    for i in 0...vals.length
                        weight += vals[i]
                    end 
                    weight = weight.to_f/(vals.length)
                when "minimum"
                    weight = vals.min
                when "maximum"
                    weight = vals.max
                end

                weight = weight.to_f/totalTime

                if weight > maxColVal/100
                    colour = maxCol
                elsif weight < minColVal/100
                    colour = minCol
                else

                    weight = [[(weight - minColVal/100)/((maxColVal-minColVal)/100), 1].min, 0].max

                    bands = (numCols-1).to_f

                    found = false

                    # Identify the gradient band (e.g. between blue and yellow) that the overall weight, i.e. the face, falls under
                    for i in 0...bands
                        if weight >= i/bands && weight <= (i+1)/bands
                            w = (weight-i/bands)*bands # Blending weighting within the band
                            colour = Sketchup::Color.new(colours[i+1]).blend(Sketchup::Color.new(colours[i]),w)
                            found = true
                            break
                        end
                    end

                end

                newFace.material = colour; newFace.back_material = colour; 

            end
        end

        def SunHours.str_to_col(colstr)
            red = Integer("0x"+colstr[0,2])
            green = Integer("0x"+colstr[2,2])
            blue = Integer("0x"+colstr[4,2])
            return Sketchup::Color.new(red, green, blue)
        end

        def SunHours.color_grid(grid)

            # Face objects (which the cells array contains) cannot be passed on via attribute dictionaries,
            # so in order to access faces in the grid in order by coordinates, they are removed and recreated

            # Find all faces and remove them
            toRemove = []
            grid.entities.each { |ent|
                if ent.is_a? Sketchup::Face
                    toRemove << ent
                end
            }
            grid.entities.erase_entities(toRemove)

            dict = grid.attribute_dictionaries["SunHours_grid_properties"]

            # Add the faces from scratch, colouring as you go

            nodes = dict["nodes"]

            # For each cell/face:
            for y in 0...nodes.length-1
                for x in 0...nodes[0].length-1

                    # Surface grids are made up of triangular faces, so they're different
                    if dict["is_surface"]
                        SunHours.color_cells([[x,y],[x+1,y],[x+1,y+1]], grid)
                        SunHours.color_cells([[x,y],[x,y+1],[x+1,y+1]], grid)
                    else
                        SunHours.color_cells([[x,y],[x+1,y],[x+1,y+1],[x,y+1]], grid)
                    end
                end
            end
        end
    end
end
                