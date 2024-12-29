
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

# Imports
Sketchup::require("AlexHall_SunHours/grid")
Sketchup::require("AlexHall_SunHours/shadow")
Sketchup::require("sketchup")

module AlexHall
    module SunHours

        ## Constants
        IEQ_default_dates_times = "default 1 1 1 31 12 2 1 7 00 18 00 1 9 00 12 00 t t t t t f f f f f f f t f 1 null f f"
        IEQ_default_grid_settings = "default 2 0.5 0.72 t 3 1.5"
        Old_analysed_grid_fix = "If you reanalyse the grid or import analysis, the functionality will become available."

        OSX = Object::RUBY_PLATFORM =~ /(darwin)/i

        Directory = File.dirname(__FILE__)

        ### Add a submenu with four items: Fit grid, Calculate sunlight hours, Select all grids, and IEQ wizard
        submenu = UI.menu("Plugins").add_submenu("SunHours")

        submenu.add_item("Fit grid") {
            SunHours.fit_grids([])
        }

        submenu.add_item("Calculate sunlight hours") {
            model = Sketchup.active_model
            scaleObserver = ScaleObservers[model]
            scaleObserver.closeScale() if scaleObserver
            sunlight_analyse_grids()
        }

        submenu.add_item("Select all grids") {
            Sketchup.send_action "selectSelectionTool:"
            model = Sketchup.active_model
            entities = model.active_entities
            selection = model.selection
            selection.clear
            entities.each { |ent|
                if ent.is_a? Sketchup::Group and ent.attribute_dictionaries and ent.attribute_dictionaries["SunHours_grid_properties"]
                    selection.add(ent)
                end
            }
        }

        submenu.add_item("IEQ wizard") {
            model = Sketchup.active_model
            model.start_operation("IEQ wizard", true)
            fitted = SunHours.fit_selection(model.selection, model, model.active_entities, ["Approximate width of cells (m)", 0.5, 0.72.m, true, 3, 1.5])
            return if not fitted

            # Find all grids in the selection
            grids = []
            model.selection.each { |ent|
                # A grid is identified by having the "grid_properties" attribute dictionary
                if ent.attribute_dictionaries and ent.attribute_dictionaries["SunHours_grid_properties"]
                    grids << ent
                end
            }

            if grids.empty?
                UI.messagebox("Error: No grids were produced")
                model.abort_operation
            else
                sunlight_analyse_grids_params(IEQ_default_dates_times, grids, nil)
                # The operation is committed inside sunlight_analyse_grids_params
            end
        }

        def SunHours.warnOldGrid(fix)
            model = Sketchup.active_model
            entities = model.active_entities
            message = "You have selected a grid for which this function is not available. This is probably because the grid was created in an older version of SunHours. "
            message += fix + "\nMeanwhile, would you like to delete all grids created in the old version?"
            result = UI.messagebox(message, MB_YESNO)
            if result == IDYES # User clicked yes
                toDelete = []
                entities.each { |e|
                    dict = e.attribute_dictionary("SunHours_grid_properties", false)
                    if dict and dict["old_grid"]
                        toDelete << e
                    end
                }
                model.start_operation("Delete old grids", true)
                entities.erase_entities(toDelete)
                model.commit_operation
            end
        end

        # If a grid which has been analysed (and hence given an id) is right-clicked,
        # and is the only thing selected, then the id will be shown at the bottom of
        # the context menu.
        UI.add_context_menu_handler do |context_menu|
            model = Sketchup.active_model
            entities = model.active_entities
            sel = model.selection
            if sel.collect{ |e| e.is_a? Sketchup::Group and e.attribute_dictionaries and e.attribute_dictionaries["SunHours_grid_properties"] }.all?
                context_menu.add_separator

                grid = sel[0]
                if grid.attribute_dictionaries["SunHours_grid_properties"]["id"] and sel.length == 1
                    properties = grid.attribute_dictionaries["SunHours_grid_properties"]
                    context_menu.add_item("Grid ID: "+properties["id"].to_s) { }

                    if not properties["append_numbers"]
                        context_menu.add_item("Attach results to nodes") {
                            if not sel.collect{ |e| e.attribute_dictionaries["SunHours_grid_properties"]["results"] }.all?
                                warnOldGrid(Old_analysed_grid_fix)
                            else
                                add_numbers_to_grid(grid, properties)
                            end
                        }
                    else
                        context_menu.add_item("Remove results from nodes") {
                            Sketchup.active_model.start_operation("Remove results from nodes", true)
                            SunHours.remove_numbers_from_grid(grid)
                            Sketchup.active_model.commit_operation
                        }
                    end
                end

                grids = sel.to_a
                add = grids.collect{ |grid| grid.attribute_dictionaries["SunHours_grid_properties"]["id"] }.any? ? " (WARNING: will remove analysis)" : ""
                context_menu.add_item("Refit grid"+add) {
                    Sketchup.send_action "selectSelectionTool:"
                    sel.clear
                    oldGrids = false
                    grids.each{ |grid|
                        grid_dict = grid.attribute_dictionaries["SunHours_grid_properties"]
                        stamp = grid_dict["stamp"]
                        if not stamp
                            warnOldGrid("If you manually fit a new grid it will be possible to refit it.")
                            oldGrids = true
                            break
                        end
                        model.active_entities.each{ |ent|
                            dics = ent.attribute_dictionaries
                            if dics
                                dic = dics["grid_fit_properties"]
                                sel.add(ent) if dic and ent.is_a? Sketchup::Face and dic["stamp"]==stamp
                            end
                        }
                    }
                    if not oldGrids
                        SunHours.fit_grids(grids)
                    end
                }

                if sel.length == 1
                    context_menu.add_item("Import analysis") {
                        importPath = UI.openpanel("Select file to import from",model.path)
                        if importPath
                            fileLines = File.new(importPath, "r").readlines

                            resultSet = []
                            idSet = []

                            idIndex = 0
                            startIndex = 0
                            endIndex = 0

                            while true

                                endOfFile = idIndex >= fileLines.length
                                while !endOfFile and fileLines[idIndex][0...4] != "Grid"
                                    idIndex += 1
                                    endOfFile = idIndex >= fileLines.length
                                end
                                break if endOfFile

                                startIndex = idIndex+4
                                endIndex = startIndex
                                while endIndex+1 < fileLines.length and fileLines[endIndex+1] != "\n"
                                    endIndex+=1
                                end
                                
                                importedResults = fileLines[startIndex..endIndex].collect{ |line| line.split(", ").collect{ |item| item.to_f }.reverse }
                                
                                dict = grid.attribute_dictionaries["SunHours_grid_properties"]
                                nodes = dict["nodes"]

                                nx = nodes[0].length-1; ny = nodes.length-1

                                valid = (importedResults[0].length-1 == nx and importedResults.length-1 == ny)
                                y = 0
                                while (valid and y <= ny)
                                    x = 0
                                    while (valid and x <= nx)
                                        # The import is still valid if either both nodes are valid or both are invalid
                                        valid &= !( (importedResults[y][x]!=-1) ^ nodes[y][x] )

                                        x += 1
                                    end
                                    y += 1
                                end
                                if valid
                                    resultSet << importedResults
                                    id = fileLines[idIndex].split(", ")[1].to_i
                                    idSet << id
                                end

                                idIndex = endIndex+2

                            end

                            totalTime = fileLines[0].split(", ")[1].to_f

                            if resultSet.length > 1
                                dialog = UI::WebDialog.new("Select a grid", true, "Select a grid", 300,250,300,300, true)
                                path = File.join(Directory, "select_grid_dialog.html")
                                dialog.set_file(path)
                                dialog.show
                                script = "populate(["
                                for id in idSet
                                    script += id.to_s + ","
                                end
                                script = script[0..-2]+"]);"
                                dialog.add_action_callback("pop") { |d, p| dialog.execute_script(script); dialog.show; dialog.set_size(300, 301) }
                                dialog.add_action_callback("select_grid") { |web_dialog, parameters_string|
                                    parameters = parameters_string.split(" ")
                                    action_name = parameters[0]
                                    if action_name == "submit"
                                        index = parameters[1].to_i
                                        SunHours.import_analysis(grid, resultSet[index], idSet[index], totalTime, dict)
                                    end
                                    dialog.close
                                }

                            elsif resultSet.length == 1
                                SunHours.import_analysis(grid, resultSet[0], idSet[0], totalTime, dict)
                            else
                                UI.messagebox("The grid in the model does not match any grid in the file")
                            end
                        end
                    }
                end

                if SunHours.selectionShouldHaveScale(sel) and sel.collect{ |e| e.attribute_dictionaries["SunHours_grid_properties"]["old_grid"] }.any?
                    context_menu.add_item("Where's the color scale?") {
                        warnOldGrid(Old_analysed_grid_fix)
                    }
                end
            end
        end

        def SunHours.import_analysis(grid, importedResults, id, totalTime, dict)
            Sketchup.active_model.start_operation("Import analysis", true)
            had_numbers = dict["append_numbers"]
            SunHours.remove_numbers_from_grid(grid)
            dict["results"] = importedResults
            dict["totalTime"] = totalTime
            dict["id"] = id
            dict["old_grid"] = false

            #### Colour the cells

            SunHours.color_grid(grid)
            scaleObserver = ScaleObservers[Sketchup.active_model]
            scaleObserver.showScale
            Sketchup.active_model.commit_operation
            
            add_numbers_to_grid(grid, dict) if had_numbers
        end
        
        def SunHours.remove_numbers_from_grid(grid)
            grid.attribute_dictionaries["SunHours_grid_properties"]["append_numbers"] = false
            grid.entities.erase_entities(grid.entities.select{ |e| e.is_a? Sketchup::Text }.to_a)
        end
        
        def SunHours.add_numbers_to_grid(grid, properties)
            nodes = properties["nodes"]
            text_norm = Geom::Vector3d.new(properties["norm"])
            text_norm.length = 0.2.m
            text_norm = text_norm.to_a
            results = properties["results"]
            Sketchup.active_model.start_operation("Attach results to nodes", true)
            for y in 0...nodes.length
                for x in 0...nodes[0].length
                    node = nodes[y][x]
                    if node
                        grid.entities.add_text('%.1f' % results[y][x],
                            [node[0]+text_norm[0], node[1]+text_norm[1], node[2]+text_norm[2]])
                    end
                end
            end
            properties["append_numbers"] = true
            Sketchup.active_model.commit_operation
        end

        # Making a scale show when a grid is selected

        class SunHours::ScaleSelectionObserver < Sketchup::SelectionObserver

            def sendScaleScripts
                return if not (@scaleLoaded and @shouldShowScale)
                sel = Sketchup.active_model.selection
                if sel.all? { |g| populate_script(g)[0...-2] == populate_script(sel[0])[0...-2] }
                    makeGradient(sel[0])
                else
                    @dialog.execute_script("grayGradient();")
                end
                if OSX
                    @dialog.execute_script("window.blur();")
                end
            end

            def initialize()
                @width = 155; @height = 220;
                @scaleLoaded = false; @shouldShowScale = false;
                @dialog = UI::WebDialog.new("Color scale", false, "Color scale", @width, @height, 5, 100, true)
                @dialog.set_size(@width, @height)
                @dialog.add_action_callback("pop") { |wd, p|
                    @scaleLoaded = true;
                    sendScaleScripts
                }
                path = File.join(Directory, "scale.html")
                @dialog.set_file(path)
                @dialog.add_action_callback("edit_scale") { |web_dialog, p|
                    grids = Sketchup.active_model.selection.to_a.select{ |g| g.attribute_dictionaries and g.attribute_dictionaries["SunHours_grid_properties"] and g.attribute_dictionaries["SunHours_grid_properties"]["id"]}
                    width = 480; height = 390;
                    scale_dialog = UI::WebDialog.new("Edit color scale", true, "Edit color scale", width, height,300, 100, true)
                    path = File.join(Directory, "scale_dialog.html")
                    scale_dialog.set_file(path)
                    scale_dialog.show
                    scale_dialog.add_action_callback("pop") { |sd, p|
                        scale_dialog.execute_script(populate_script(grids[0]))
                        scale_dialog.set_size(width, height+1)
                    }

                    scale_dialog.add_action_callback("get_data") { |sd, parameters_string|
                        parameters = parameters_string.split
                        action_name = parameters.shift
                        apply = (action_name == "apply" or action_name == "submit")
                        if action_name!="cancel"

                            ### Getting the parameters from the interface
                            # Fetch colours for the gradient
                            numCols = Integer(parameters.shift)
                            colours = []
                            for i in 0...numCols
                                colours << SunHours.str_to_col(parameters.shift)
                            end

                            # How to color cells
                            colorBasis = ["average", "maximum", "minimum"][Integer(parameters.shift)]

                            # Catchall color stuff

                            maxColVal = Float(scale_dialog.get_element_value("maxval"))
                            maxColOn = parameters.shift=="t"
                            if (maxColOn)
                                maxCol = SunHours.str_to_col(scale_dialog.get_element_value("colourmax"))
                            else
                                maxCol = colours[-1]
                            end

                            minColVal = Float(scale_dialog.get_element_value("minval"))
                            minColOn = parameters.shift=="t"
                            if (minColOn)
                                minCol = SunHours.str_to_col(scale_dialog.get_element_value("colourmin"))
                            else
                                minCol = colours[0]
                            end
                            
                            Sketchup.active_model.start_operation((apply ? "Grid" : "Default") + " colour settings", true)

                            for grid in grids
                                if apply
                                    dict = grid.attribute_dictionaries["SunHours_grid_properties"]
                                else
                                    dict = Sketchup.active_model.attribute_dictionaries["SunHours_default_color_settings"]
                                end

                                dict["colorBasis"] = colorBasis
                                dict["numCols"] = numCols
                                dict["colours"] = colours
                                dict["maxCol"] = maxCol
                                dict["maxColVal"] = maxColVal
                                dict["minCol"] = minCol
                                dict["minColVal"] = minColVal

                                if apply
                                    SunHours.color_grid(grid)
                                end
                            end

                            if apply
                                makeGradient(grids[0])
                            else
                                UI.messagebox("Defaults set")
                            end
                            
                            Sketchup.active_model.commit_operation

                        end

                        if action_name=="submit" or action_name=="cancel"
                            scale_dialog.close
                        end
                    }
                }
                @prevSelection = nil
            end

            def onSelectionBulkChange(sel)
                sel = sel.to_a
                if SunHours.selectionShouldHaveScale(sel)
                    if not sel.collect{ |e| e.attribute_dictionaries["SunHours_grid_properties"]["results"] }.all?
                        return
                    end
                    if not sel==@prevSelection
                        showScale
                    end
                else
                    closeScale
                end
                @prevSelection = sel
            end

            def showScale
                if OSX
                    @dialog.show_modal
                else
                    closeScale
                    initialize
                    @dialog.show
                end
                sel = Sketchup.active_model.selection
                @prevSelection = sel.to_a
                @shouldShowScale = true
                sendScaleScripts
            end

            def onSelectionCleared(sel)
                @prevSelection = sel.to_a
                closeScale
            end

            def colToStr(col)
                str=''
                for part in [col.red, col.green, col.blue]
                    hexpart = part.to_s(16).upcase
                    hexpart = '0' + hexpart if hexpart.length==1
                    str += hexpart
                end
                return str
            end

            def quote(str)
                return '"' + str + '"'
            end

            def makeGradient(grid)

                # Legacy code for makeGradientDeprecated in scale.html, which took in an array of RGB arrays
                if false
                    cols = "["

                    colours = dict["colours"]
                    for c in 0...colours.length
                        col = colours[c]
                        cols += "[#{col.red}, #{col.green}, #{col.blue}]"
                        if c < colours.length-1
                            cols += ","
                        end
                    end
                    cols += "]"
                end

                dict = grid.attribute_dictionaries["SunHours_grid_properties"]

                cols = quote(dict["colours"].collect { |col| colToStr(col) }.join("-"))

                maxCol = quote(colToStr(dict["maxCol"]))
                minCol = quote(colToStr(dict["minCol"]))

                script = "makeGradient(#{cols}, #{dict['maxColVal']}, #{dict['minColVal']}, #{dict['totalTime']}, #{maxCol}, #{minCol})"
                @dialog.execute_script(script)
            end

            def populate_script(grid)
                dict = grid.attribute_dictionaries["SunHours_grid_properties"]
                numCols = dict["colours"].length
                script = 'populate(' + numCols.to_s + ','
                n = 0
                for col in ([dict["maxCol"]]+[dict["minCol"]] + dict["colours"].reverse)

                    script += quote(colToStr(col))

                    n+=1

                    if n<numCols+2
                        script += ','
                    else
                        script += '],'
                    end

                    script += '[' if n==2

                end
                script += Integer(dict["maxColVal"]).to_s + ',' + Integer(dict["minColVal"]).to_s + ',' + ["average", "maximum", "minimum"].index(dict["colorBasis"]).to_s + ')'
                return script
            end

            def closeScale()
                begin
                    if @dialog.visible?
                        @dialog.close
                    end
                rescue
                    puts "Can't close: Dialog not showing. No big deal."
                end
            end

        end

        def SunHours.selectionShouldHaveScale(sel)
            sel.collect{ |e| e.is_a? Sketchup::Group and e.attribute_dictionaries and e.attribute_dictionaries["SunHours_grid_properties"] and e.attribute_dictionaries["SunHours_grid_properties"]["id"]}.all? and sel.length>0
        end

        ScaleObservers = Hash.new

        class SunHours::ScaleObserverAppObserver < Sketchup::AppObserver
            def onOpenModel(model)
                if model.attribute_dictionary("SunHours", false)
                    # Add a selection observer to show the scale when appropriate
                    scaleObserver = SunHours::ScaleSelectionObserver.new
                    model.selection.add_observer(scaleObserver)
                    ScaleObservers[model] = scaleObserver
                end
            end
        end

        # Attach the observer
        ScaleAppObserver = SunHours::ScaleObserverAppObserver.new
        Sketchup.add_observer(ScaleAppObserver)
        ScaleAppObserver.onOpenModel(Sketchup.active_model)

    end
end