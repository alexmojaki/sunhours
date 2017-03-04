# This is a slight modification of the script provided at http://www.smustard.com/script/offset
# Only the Face.offset method is kept, and it is wrapped in a function instead of modifying the base class to avoid conflicts

=begin rdoc

= Offset.rb
Copyright 2004,2005,2006,2009 by Rick Wilson - All Rights Reserved

== Disclaimer
THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

== License
This software is distributed under the Smustard End User License Agreement
http://www.smustard.com/eula

== Information
Author:: Rick Wilson
Organization:: Smustard
Name:: offset.rb
Version:: 2.201
SU Version:: 4.0
Date:: 2010-10-15
Description:: Offset edges of a selected face (new method for class Sketchup::Face)

Usage::
* 1:: Intended for developers as a method to call from within a script.  Add a "require 'offset.rb'" line right after the "require 'sketchup.rb'" line.  Developers may distribute with their scripts since not everyone will have this already, but best to link to http://www.smustard.com/script/offset for the most current version.  Returns the face created by the offset, or 'nil' if no face can be created.
* 2:: ArcCurve.offset(dist) -- if dist is (+), offsets outside the curve (larger radius); if dist is (-), offsets inside the curve (smaller radius).
* 3:: Curve.offset(dist) -- if dist is (+), offsets to the right of the curve (relative to the first segment direction and plane); if dist is (-), offsets to the left of the curve.

History::
* 2.201:: 2010-10-15
	* fixed Face.offset(dist) bug that prevented some faces from being offset
* 2.200:: 2009-02-05
	* added point analysis tools and error trapping to the face.offset method
* 2.100:: 2006-06-28
	* changed the face creation to parent.entities.add_face to allow for correct creation regardless of nested status
* 2.000:: 2005-08-12
	* added offset methods for ArcCurve and Curve objects
* 1.000:: 2004-09-07
	* first version

=end
#/

module AlexHall
    module SunHours
        def SunHours.offset_face(face, dist)
            begin
                    pi = Math::PI
                    if (not ((dist.class==Fixnum || dist.class==Float || dist.class==Length) && dist!=0))
                        return nil
                    end
                    verts=face.outer_loop.vertices
                    pts = []

                    # CREATE ARRAY pts OF OFFSET POINTS FROM FACE

                    0.upto(verts.length-1) do |a|
                        vec1 = (verts[a].position-verts[a-(verts.length-1)].position).normalize
                        vec2 = (verts[a].position-verts[a-1].position).normalize
                        vec3 = (vec1+vec2).normalize
                        if vec3.valid?
                            ang = vec1.angle_between(vec2)/2
                            ang = pi/2 if vec1.parallel?(vec2)
                            vec3.length = dist/Math::sin(ang) #/
                            t = Geom::Transformation.new(vec3)
                            if pts.length > 0
                                vec4 = pts.last.vector_to(verts[a].position.transform(t))
                                if vec4.valid?
                                    unless (vec2.parallel?(vec4))
                                        t = Geom::Transformation.new(vec3.reverse)
                                    end
                                end
                            end

                            pts.push(verts[a].position.transform(t))
                        end
                    end

                    # CHECK FOR DUPLICATE POINTS IN pts ARRAY

                    duplicates = []
                    pts.each_index do |a|
                        pts.each_index do |b|
                            next if b==a
                            duplicates<<b if pts[a]===pts[b]
                        end
                        break if a==pts.length-1
                    end
                    duplicates.reverse.each{|a| pts.delete(pts[a])}

                    # CREATE FACE FROM POINTS IN pts ARRAY

                    (pts.length > 2) ? (face.parent.entities.add_face(pts)) : (return nil)

            rescue
                puts "#{face} did not offset: #{pts}"
                raise
            end
        end
    end
end