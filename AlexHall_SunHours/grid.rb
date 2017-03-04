
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

# Functions contained within this module:
# get_surface( face )
# fit_grid_params(facesToFit, model, entities, params, is_surface)
# fit_selection(selection, model, entities, params)
# fit_grids()

# The program essentially works as follows:
# The fit_grids function is called when the user clicks on the menu item.
# It collects parameters from the user and calls fit_selection when the user clicks OK on the dialog
# This groups the selection into curved surfaces and groups of flat faces in the same plane (generally singletons)
# For each of these surfaces/groups, fit_grid_params is called on the group and a single grid is fitted to that.

Sketchup::require("sketchup")
Sketchup::require("AlexHall_SunHours/offset") # Based on version 2.201 (c) Rick Wilson, used by permission.  http://www.smustard.com/script/Offset

module AlexHall
    module SunHours

        # Thanks to thomthom from the Sketchucation forums for this function.
        # Returns the surface containing the given face by finding all faces connected (including indirectly) by soft edges
        def SunHours.get_surface(face)
          surface = {} # Use hash for speedy lookup
          stack = [ face ]
          until stack.empty?
            face = stack.shift
            edges = face.edges.select { |e| e.soft? }
            for edge in edges
              for face in edge.faces
                next if surface.key?( face )
                stack << face
                surface[ face ] = face
              end
            end
          end
          return surface
        end

        class SunHours::CustomBounds
            def initialize(entityArray)
                inf = 1.0/0
                @maxx = -inf
                @minx = inf
                @maxy = -inf
                @miny = inf
                @maxz = -inf
                @minz = inf
                for ent in entityArray
                    if ent.is_a? Sketchup::Edge or ent.is_a? Sketchup::Face
                        for vert in ent.vertices
                            v = vert.position
                            @maxx = [@maxx, v.x].max
                            @minx = [@minx, v.x].min
                            @maxy = [@maxy, v.y].max
                            @miny = [@miny, v.y].min
                            @maxz = [@maxz, v.z].max
                            @minz = [@minz, v.z].min
                        end
                    end
                end
            end

            def center
                return [(@maxx+@minx)/2, (@maxy+@miny)/2, (@maxz+@minz)/2]
            end

            attr_reader :maxx, :minx, :maxy, :miny, :maxz, :minz 
        end

        # Called (possibly repeatedly) by fit_selection
        # Takes an array of faces, either all in one plane or forming a surface (hopefully) and fits a single grid to them, which it returns.
        # facesToFit is the array of faces
        # params contains the user settings
        # How it works: rotate a copy of the faces so that they're parallel to the XY plane
        # Create a grid of nodes by iterating linearly over x and y within the bounding rectangle of the faces, with constant z
        # Leave out nodes that aren't within any of the faces
        # Draw rectangular faces  throughout the grid where all four corner nodes are present
        # Apply the inverse rotation to the grid
        # For curved surfaces, there are two main differences:
        # The nodes are projected onto the surface
        # The faces in the grid are triangles, since four corners might not be planar
        def SunHours.fit_grid_params(facesToFit, model, entities, params, is_surface)

            stamp = [Time.now, rand]
            facesToFit.each{ |f| f.set_attribute("grid_fit_properties", "stamp", stamp) }

            # Calculating a translation that will used soon, before making groups
            bb = model.bounds
            minDist = [bb.max.x, bb.min.x, bb.max.y, bb.min.y, bb.max.z, bb.min.z].collect{|n| n.abs.ceil}.min
            safeDistance = 10000.m
            if bb.max.x.abs.ceil==minDist
                point = [bb.max.x + safeDistance, 0, 0]
            elsif bb.min.x.abs.ceil==minDist
                point = [bb.min.x - safeDistance, 0, 0]
            elsif bb.max.y.abs.ceil==minDist
                point = [0, 0, bb.max.y + safeDistance]
            elsif bb.min.y.abs.ceil==minDist
                point = [0, 0, bb.min.y - safeDistance]
            elsif bb.max.z.abs.ceil==minDist
                point = [0, bb.max.z + safeDistance, 0]
            elsif bb.min.z.abs.ceil==minDist
                point = [0, bb.min.z - safeDistance, 0]
            end
            point -= CustomBounds.new(facesToFit).center
            safetyMove = Geom::Transformation.translation(point)

            #### Making a copy of the faces (that is offset if appropriate) being fitted as a group

            offsetDist = params[5].m
            offsetDist = 0.01.m if offsetDist==0

            # Create an array of groups called 'groups', where each group is actually a single face (this helps to avoid intersection problems)
            groupsOriginal = facesToFit.collect{ |f| entities.add_group([f]) }
            groups = groupsOriginal.collect{ |g| g.copy }
            groupsOriginal.each{ |g| g.explode }

            # Prevent interference with the original faces by moving them far away
            entities.transform_entities(safetyMove, groups)

            # Reset facesToFit to be an array containing the new copied faces.
            # All the groups are placed inside a bigger group so because the faces might intersect after offsetting,
            # which causes deletions. This way they can be found again using entities

            # Offset each face if this is not part of a curved surface. This has to be done carefully.
            # In particular, if two faces to be fit are joined, erase the edge between them before offsetting
            if not is_surface

                faceGroup = entities.add_group(groups)
                groups.each{|g|
                    g.explode
                }
                facesToFit = faceGroup.entities.to_a.select{ |ent| ent.is_a? Sketchup::Face }

                edgesToErase = []

                faceGroup.entities.each { |ent|
                    if ent.is_a? Sketchup::Edge
                        connectedFaces = ent.faces
                        edgesToErase << ent if connectedFaces.length>1 and connectedFaces.collect{ |f| facesToFit.include?(f) }.all?
                    end
                }

                if not edgesToErase.empty?
                    faceGroup.entities.erase_entities(edgesToErase)
                end

                groups = []
                facesToFit = faceGroup.explode.grep(Sketchup::Face)

                for face in facesToFit
                    singleFaceGroup = entities.add_group([face])
                    faces = singleFaceGroup.entities.to_a.select{ |e| e.is_a? Sketchup::Face }
                    raise "Multiple faces found in singleton group before offset" if faces.length>1
                    face = faces[0]
                    offsetFace = SunHours.offset_face(face, -offsetDist)
                    toErase = singleFaceGroup.entities.to_a.select{ |e| not (e==offsetFace or offsetFace.edges.include? e) }
                    singleFaceGroup.entities.erase_entities(toErase)
                    groups << singleFaceGroup
                end
            end

            faceGroup = entities.add_group(groups)
            groups.each{|g|
                g.explode
            }
            facesToFit = faceGroup.explode.grep(Sketchup::Face)

            #### Rotating

            # Obtain the unit normal of the faces. For surfaces, this is the average normal of the component faces
            norm = Geom::Vector3d.new
            for face in facesToFit
                norm += face.normal
                break if not is_surface
            end

            begin
                norm.length = 1
            rescue
                norm = Geom::Vector3d.new(0,0,1)
            end

            # Make sure the normal is pointing upwards. 0 is not used to avoid precision errors for vertical faces
            norm.reverse! if norm.z < -0.001

            # To rotate the faces so that they lie horizontally, imagine that the face was once horizontal (the normal being (0,0,1))
            # and then was rotated into its current orientation by two rotations: one rotation around the y-axis, then one about the x-axis.
            # If you multiply the two rotation matrices by the column vector (0,0,1) you get the current normal vector of the faces.
            # Solving for the angles of rotation gives the below. Since the normal is pointing upwards, the angles must be in the range of asin: [-90, 90] (degrees)
            yangle = Math.asin(norm.x)
            sin = [[-norm.y/Math.cos(yangle), -1].max, 1].min # Dealing with an issue of floating point precision and the domain of asin
            xangle = Math.asin(sin)

            # Create the full rotation transformation and apply it
            cent = CustomBounds.new(facesToFit).center
            y_rotation = Geom::Transformation.rotation(cent,Y_AXIS,yangle)
            x_rotation = Geom::Transformation.rotation(cent,X_AXIS,xangle)
            rotation = x_rotation * y_rotation # this is the rotation that turns the unit z vector into the faces' upward unit normal
            entities.transform_entities(rotation.inverse, facesToFit) # the faces should now be horizontal (for non-surfaces)

            ## Find information about the bounds and size of the array
            bbox = CustomBounds.new(facesToFit)
            width = bbox.maxx - bbox.minx
            height = bbox.maxy - bbox.miny

            if is_surface

                # Since the grid is projected onto the surface, we create the grid directly below it
                zpos = bbox.minz-10

            else

                # We want a constant z. All the nodes should already have this, but this is what is used in case of precision errors, e.g. if the rotation was imperfect
                zpos=(bbox.minz+bbox.maxz)/2.0
            end


            # Calculate number of cells on shorter side of grid (and extract the user settings)
            # The idea is to make the cells as close to squares as possible by making the proportions of the grid
            # in terms of number of cells approximately the same as the proportions of what's being fitted
            # nx and ny are the number of cells in the x and y direction
            densityType = params[0]
            if densityType == "Approximate width of cells (m)"
                desiredWidth = params[1].m
                if width > height
                    nx = (width/desiredWidth).round
                    ny = (height/width*nx).round
                else
                    ny = (height/desiredWidth).round
                    nx = (width/height*ny).round
                end
            else
                if (width > height and densityType == "Number of cells on long side" or width <= height and densityType == "Number of cells on short side")
                    nx = params[1]
                    ny = (height/width*nx).round
                else
                    ny = params[1]
                    nx = (width/height*ny).round
                end
            end

            raiseHeight = params[2]

            #Sidelengths of cells
            cellWidth = width / nx
            cellHeight = height / ny

            #### Populate grid with nodes. Set a node to false if it is not on the face

            # This is a 2D array: each element is an array representing a row of the nodes in the grid, i.e. a horizontal line, with y constant
            nodes = []

            # Iterate through all possible nodes
            for y in 0..ny
                row = []
                for x in 0..nx

                    # Position of the node in (x,y,z) coordinates: used as a Point3d
                    pt = [bbox.minx+x*cellWidth, bbox.miny+y*cellHeight, zpos]

                    # Boolean asking whether the node is valid, i.e. is it within any of the faces
                    ptOnGroup = false

                    # Testing if the node is valid, and projecting for surfaces
                    if is_surface

                        # Draw a ray from the node's current position below the grid directly upwards
                        # If the ray intersects with anything, move the node to the point of intersection
                        # Test if it's on the desired surface. Raytests can return either Faces or Edges: this is dealt with
                        # If it's not, redo the raytest from the new position
                        # The loop ends when either the ray no longer hits anything or it hits the surface. ptOnGroup is set appropriately
                        while true
                            item = model.raytest([pt, Z_AXIS])
                            break if not item
                            pt, ent = item
                            ent = ent[0]
                            if ent.is_a? Sketchup::Face and facesToFit.include?(ent)
                                ptOnGroup = true
                                break
                            elsif ent.is_a? Sketchup::Edge
                                for f in ent.faces
                                    if facesToFit.include?(f)
                                        ptOnGroup = true
                                        break
                                    end
                                end
                                break if ptOnGroup
                            end
                        end
                    else

                        # Classifying nodes (valid or not) for non-surfaces
                        facesToFit.collect { |face| 
                            case face.classify_point(pt)
                            when Sketchup::Face::PointInside, Sketchup::Face::PointOnVertex, Sketchup::Face::PointOnEdge
                                ptOnGroup = true
                                break
                            when Sketchup::Face::PointOutside
                                next
                            when Sketchup::Face::PointUnkown
                                puts "ERROR: Couldn't classify point"
                            when Sketchup::Face::PointNotOnPlane

                                # This implies that the rotation didn't make the face properly horizontal and is a serious problem
                                # Fortunately this hasn't been encountered :P ...yet
                                puts "ERROR: Point not on plane"
                            else
                                puts "Unknown point classification"
                            end
                        }
                    end
                    pt = false if not ptOnGroup

                    # Every element of the nodes array is therefore either a 'false' indicating invalidity, or a position
                    row << pt
                end
                nodes << row
            end

            # Now, if the user chose the option, find all interior nodes which should be excluded
            if params[3]
                numExclude = params[4]
                for y in 0..ny
                    for x in 0..nx
                        include = false
                        for dy in -numExclude..numExclude
                            for dx in -numExclude..numExclude
                                include = x+dx<0 || x+dx>nx || y+dy<0 || y+dy>ny || !nodes[y+dy][x+dx]
                                break if include
                            end
                            break if include
                        end
                        nodes[y][x] = "exclude" if !include
                    end
                end

                # Then invalidate them all
                for y in 0..ny
                    for x in 0..nx
                        if nodes[y][x] == "exclude"
                            nodes[y][x]=false
                        end
                    end
                end
            end

            # Rotate the grid (the nodes) back to the original orientation
            nodes.each { |row| row.each { |node| node.transform!(rotation) if node } }

            # Delete the copy of the faces fitted
            faceGroup = entities.add_group(facesToFit)
            entities.erase_entities([faceGroup])

            # Move the grid by the raiseHeight amount provided by the user in the appropriate direction
            moveVector = norm.clone
            moveVector.length = raiseHeight
            moveVector.reverse! if ( moveVector.z * raiseHeight < 0 ) # the '*' tests if these have different signs
            translation = Geom::Transformation.translation(moveVector)
            translation *= safetyMove.inverse # bring the grid back to where the faces were, undoing the safety move
            nodes.each { |row| row.each { |node| node.transform!(translation) if node } }

            #### Add faces
            grid = entities.add_group

            for y in 0...ny
                for x in 0...nx

                    # For surfaces, each cell is a pair of triangles
                    if is_surface
                        pts = [ nodes[y][x], nodes[y+1][x], nodes[y+1][x+1] ]

                        # A face is only fitted if all its corner nodes are valid
                        if pts.all?
                            grid.entities.add_face(pts)
                        end
                        pts = [ nodes[y][x], nodes[y][x+1], nodes[y+1][x+1] ]

                        if pts.all?
                            grid.entities.add_face(pts)
                        end
                    else
                        pts = [ nodes[y][x], nodes[y+1][x], nodes[y+1][x+1], nodes[y][x+1] ]
                        if pts.all?
                            grid.entities.add_face(pts)
                        end
                    end
                end
            end

            # Identify the grid as a grid and store important information about it
            grid.set_attribute("SunHours_grid_properties", "nodes", nodes)
            grid.set_attribute("SunHours_grid_properties", "is_surface", is_surface)
            grid.set_attribute("SunHours_grid_properties", "norm", norm.to_a)

            # Stamp to identify this grid with the faces it was fitted to for refitting purposes
            grid.set_attribute("SunHours_grid_properties", "stamp", stamp)

            return grid
        end

        # Called by fit_grids after 'OK' has been clicked, calls fit_grid_params on each group of faces that need fitting
        def SunHours.fit_selection(selection, model, entities, params)

            # All fittings are grouped under a single operation that can be undone by a single click of the user
            model.start_operation("Fit grid", true)

            begin

                # Filter faces
                faces = selection.to_a.select { |ent| ent.is_a? Sketchup::Face }

                if faces.empty?
                    UI.messagebox("No face found in selection.")
                    model.abort_operation
                end

                # Stored so that they can be selected afterwards
                grids = []

                ### Find curved surfaces, fit them, and note the remaining faces
                flatFaces = []

                # Go through all the faces in the selection
                while faces.length>0
                    face = faces.pop
                    surface = SunHours.get_surface(face)

                    if surface.empty?

                        # If this face is isolated, i.e. not part of a surface, note it as flat
                        flatFaces << face

                    else

                        # Otherwise, remove all the faces from the array of the faces to be fitted
                        i = 0
                        while i<faces.length
                            if surface.key?(faces[i])
                                faces[i,1] = []
                            else
                                i+=1
                            end
                        end

                        # Then fit a grid to the surface
                        grids << SunHours.fit_grid_params(surface.keys, model, entities, params, true)

                    end
                end

                faces = flatFaces

                ### Find groups of faces in the same plane and fit them each with a single grid
                # Iterate through all faces
                while faces.length>0

                    # Take a single face and put it in an array, which will be all the faces in that plane
                    face = faces.pop
                    plane = face.plane
                    facesToFit = [face]

                    # Find all faces in the same plane
                    i = 0
                    while i<faces.length

                        # if faces[i].plane ~= plane
                        if (0...4).collect{ |j| (faces[i].plane[j] - plane[j]).abs < 1e-10 }.all?
                            facesToFit << faces[i]
                            faces[i,1] = []
                        else
                            i+=1
                        end
                    end

                    # Fit the array of faces
                    grids << SunHours.fit_grid_params(facesToFit, model, entities, params, false)
                end

                # Select all fitted grids
                Sketchup.send_action "selectSelectionTool:"
                model.selection.clear
                model.selection.add(grids)
                
                get_initialised_model_dict

                model.commit_operation
            rescue
                model.abort_operation
                UI.messagebox("Error occurred during grid fitting")
                raise
            end
        end

        # Called by interface.rb when the user clicks the 'Fit grid' menu item
        def SunHours.fit_grids(oldGrids)
            model = Sketchup.active_model
            entities = model.active_entities
            selection = model.selection

            # Filter faces
            faces = selection.to_a.select { |ent| ent.is_a? Sketchup::Face }

            if faces.empty?
                UI.messagebox("No face found in selection.")
            else
                
                # When any face is found, bring up the interface
                width = 550; height = 250;
                dialog = UI::WebDialog.new("Analysis grid details", false, "Analysis grid details", width, height, 200, 200, true)
                path = File.join(File.dirname(__FILE__), "grid_dialog.html")
                dialog.set_file(path)
                dialog.show

                dialog.add_action_callback("pop") { |wd, p|
                    model_dict = model.attribute_dictionary("SunHours", false)
                    dialog.execute_script("populate(" + (model_dict ? model_dict["SunHours_default_grid_settings"] : IEQ_default_grid_settings).to_json + ");")
                    dialog.set_size(width, height+1)
                }

                # If the user clicks a button:
                dialog.add_action_callback("get_data") { |web_dialog, data_string|

                    parameters = data_string.split(" ")
                    action_name = parameters.shift

                    # If the button clicked was 'OK'
                    if action_name=="submit"

                        # Collect the user settings and fit all grids selected
                        params = [["Number of cells on long side", "Number of cells on short side", "Approximate width of cells (m)"][Integer(parameters.shift)], \
                                    Float(parameters.shift), Float(parameters.shift).m, \
                                  (parameters.shift=="t"), Integer(parameters.shift), \
                                  Float(parameters.shift)]
                        dialog.close()
                        entities.erase_entities(oldGrids)
                        SunHours.fit_selection(selection, model, entities, params)
                    elsif action_name=="default"
                        model.start_operation("Fit grid default settings", true)
                        model_dict = get_initialised_model_dict()
                        model_dict["SunHours_default_grid_settings"] = data_string
                        model.commit_operation
                        UI.messagebox("Defaults set")
                    else
                        dialog.close()
                    end

                }
            end

        end
            
        def SunHours.get_initialised_model_dict()
            # Create, if necessary, the model attribute dictionary with default settings, current grid ID, etc.
            model = Sketchup.active_model
            model_dict = model.attribute_dictionary("SunHours", false)

            # For new models...
            if not model_dict

                # Restore the ID from the old dictionary if necessary.
                # Otherwise set to 1
                model_dict = model.attribute_dictionary("SunHours", true)
                old_model_dict = model.attribute_dictionary("sunlight_analysis", false)
                if old_model_dict and old_model_dict["grid_id"]
                    model_dict["grid_id"] = old_model_dict["grid_id"]

                    model.active_entities.each { |ent|
                        if ent.is_a? Sketchup::Group and ent.attribute_dictionaries
                            old_grid_dict = ent.attribute_dictionaries["grid_properties"]
                            if old_grid_dict and old_grid_dict["nodes"]
                                new_grid_dict = ent.attribute_dictionary("SunHours_grid_properties", true)
                                new_grid_dict["nodes"] = old_grid_dict["nodes"]
                                new_grid_dict["norm"] = old_grid_dict["norm"]
                                new_grid_dict["is_surface"] = old_grid_dict["is_surface"]

                                new_grid_dict["id"] = old_grid_dict["id"]

                                new_grid_dict["old_grid"] = true
                                new_grid_dict["append_numbers"] = false

                            end
                        end
                    }

                else
                    model_dict["grid_id"] = 1
                end

                # Default settings for the main dialogs
                model_dict["SunHours_default_dates_times"] = IEQ_default_dates_times
                model_dict["SunHours_default_grid_settings"] = IEQ_default_grid_settings

                # Color settings
                color_dict = model.attribute_dictionary("SunHours_default_color_settings", true)
                color_dict["colorBasis"] = "average"
                color_dict["numCols"] = 3
                color_dict["colours"] = [Sketchup::Color.new("Blue"), Sketchup::Color.new("Yellow"), Sketchup::Color.new("Red") ]
                color_dict["maxCol"] = Sketchup::Color.new(128,0,0)
                color_dict["maxColVal"] = 80.0
                color_dict["minCol"] = Sketchup::Color.new("Lime")
                color_dict["minColVal"] = 0

                ScaleAppObserver.onOpenModel(model)
            end
            
            return model_dict
        end
    
    end
end
