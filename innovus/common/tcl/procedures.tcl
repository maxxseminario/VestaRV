################################################################################
# Messages
################################################################################

# Verbosity level for custom messages.  Higher values generate more output.

set VERBOSITY 3
set START_TIME 0
set STOP_TIME 0

# Create a custom print statement that works in both RC and Encounter.  This is
# to bypass the fact that "Puts" only works in Encounter and guarantees such
# statements appear in the log files as well as the terminal.
if {[file tail [info nameofexecutable]] == "innovus"} {
    set PUTS_STRING "Puts"
} elseif {[file tail [info nameofexecutable]] == "genus"} {
    set PUTS_STRING "puts"
} else {
    puts "Program not recognized: using puts for message printing."
    set PUTS_STRING "puts"
}

# Send a text message notification
proc emailMessage {text} {
    exec echo "$text" | mailx 7196631243@vtext.com
    exec mail -s "$text" mseminario2@huskers.unl.edu < /dev/null
}

# Prints a simple, easy-to-spot informational message.
 
proc printStatus {text args} { 
    global VERBOSITY 
    global PUTS_STRING 
    global MESSAGE_FILE
    if { $VERBOSITY >= 3 } { 
        $PUTS_STRING "### UNL STATUS #### : $text"
    }
}
 
proc printInfo {text args} { 
    global VERBOSITY 
    global PUTS_STRING 
    global MESSAGE_FILE
    if { $VERBOSITY >= 3 } { 
        $PUTS_STRING "#### UNL INFO ##### : $text"
    }
}

proc printWarning {text args} { 
    global VERBOSITY 
    global PUTS_STRING 
    global MESSAGE_FILE
    if { $VERBOSITY >= 2 } {
        $PUTS_STRING "### UNL WARNING ### : $text"
    }
}

proc printError {text args} { 
    global VERBOSITY 
    global PUTS_STRING 
    global MESSAGE_FILE
    if { $VERBOSITY >= 1 } {
        $PUTS_STRING "#### UNL ERROR #### : $text"
    }
}

proc getHMS {start stop} {
    # Constants for the conversion
    set s_per_m 60
    set m_per_h 60
    set s_per_h [expr $s_per_m * $m_per_h]
    # Find the number of seconds remaining to be divided into H:M:S.         
    set s_rem  [expr [expr $stop - $start] / 1000]
    # Find the number of hours, minutes, seconds.  Remove this time from the
    # remaining seconds at each stage.
    set h [expr $s_rem / $s_per_h]
    set s_rem [expr $s_rem - [expr $h * $s_per_h]]
    set m [expr $s_rem / $s_per_m]
    set s_rem [expr $s_rem - [expr $m * $s_per_m]]
    set s $s_rem       
    set hms [format "%02d:%02d:%02d" $h $m $s]
    return $hms
}

proc printRuntime {start stop} {
    global VERBOSITY
    global PUTS_STRING 
    global MESSAGE_FILE
    set hms [getHMS $start $stop]
    if { $VERBOSITY >= 3 } {
        $PUTS_STRING "### UNL RUNTIME ### : $hms"
    }
}

proc printClock {} {
    global VERBOSITY 
    global PUTS_STRING 
    global MESSAGE_FILE
    if { $VERBOSITY >= 3 } {
        set text [timestamp -format "%m-%d-%Y %H:%M:%S"]
        $PUTS_STRING "#### UNL TIME ##### : $text"
    }
}

proc tic {} {
    global START_TIME
    set START_TIME [clock clicks -milliseconds]
}

proc toc {} {
    global START_TIME
    global STOP_TIME
    set STOP_TIME [clock clicks -milliseconds]
    printRuntime $START_TIME $STOP_TIME
}          

proc tictoc {} {
    global START_TIME
    toc
    set START_TIME [clock clicks -milliseconds]
}
 
################################################################################
# Add metal fill to meet IBM requirements.
################################################################################

proc addIbmMetalFill {x1 y1 x2 y2} {
                                               
    # Give EDI the fill rules for the upper metal layers.  Note that the
    # documentation has different values, but these generally work and produce nice looking patterns.
          
    ## Note that Assura requires the area to be < 100 um^2 despite DS569.
    #setMetalFill \
    #    -layer MA \
    #    -windowSize 400 400 \
    #    -windowStep 400 400 \
    #    -minWidth 4 -maxWidth 12 \
    #    -minLength 4 -maxLength 8.3 \
    #    -minDensity 32 -maxDensity 65 \
    #    -preferredDensity 50 \
    #    -gapSpacing 5 -activeSpacing 5 \
    #    -iterationName default
    #                    
    #addMetalFill \
    #    -area $x1 $y1 $x2 $y2 \
    #    -layer { MA }
                                  
    # Note that Assura requires the area to be < 100 um^2 despite DS569.
    setMetalFill \
        -layer MA \
        -windowSize 400 400 \
        -windowStep 400 400 \
        -minWidth 5 -maxWidth 10 \
        -minLength 5 -maxLength 10 \
        -decrement 1 \
        -minDensity 32 -maxDensity 70 \
        -preferredDensity 70 \
        -gapSpacing 5 -activeSpacing 5 \
        -diagOffset 1 14 \
        -iterationName default

    addMetalFill \
        -area $x1 $y1 $x2 $y2 \
        -squareShape \
        -stagger diag \
        -layer { MA }
                                    
    ## Note that Assura requires the area to be < 100 um^2 despite DS569.
    #setMetalFill \
    #    -layer MA \
    #    -windowSize 400 400 \
    #    -windowStep 400 400 \
    #    -minWidth 5 -maxWidth 5 \
    #    -minLength 20 -maxLength 20 \
    #    -minDensity 32 -maxDensity 70 \
    #    -preferredDensity 65 \
    #    -gapSpacing 5 -activeSpacing 5 \
    #    -iterationName default

    #addMetalFill \
    #    -area $x1 $y1 $x2 $y2 \
    #    -layer { MA }
    #                               
    ## Note that Assura requires the area to be < 100 um^2 despite DS569.
    #setMetalFill \
    #    -layer MA \
    #    -windowSize 400 400 \
    #    -windowStep 400 400 \
    #    -minWidth 4 -maxWidth 4 \
    #    -minLength 4 -maxLength 16 \
    #    -minDensity 32 -maxDensity 70 \
    #    -preferredDensity 65 \
    #    -gapSpacing 5 -activeSpacing 5 \
    #    -iterationName default
                      
    # The copper layers have a tighter local density check as well (E1).
                   
    # 100x100, <85%
    setMetalFill \
        -layer E1 \
        -windowSize 100 100 \
        -windowStep 100 100 \
        -minWidth 3 -maxWidth 6 \
        -minLength 3  -maxLength 6 \
        -decrement 1 \
        -minDensity 28 -maxDensity 70 \
        -preferredDensity 70 \
        -gapSpacing 2 -activeSpacing 2 \
        -iterationName step100

    addMetalFill \
        -iterationNameList {step100} \
        -area $x1 $y1 $x2 $y2 \
        -squareShape \
        -layer { E1 }
                                       
    ## 200x200, <70%
    #setMetalFill \
    #    -layer E1 \
    #    -windowSize 200 200 \
    #    -windowStep 200 200 \
    #    -minWidth 6 -maxWidth 6 \
    #    -minLength 6  -maxLength 6 \
    #    -minDensity 28 -maxDensity 70 \
    #    -preferredDensity 70 \
    #    -gapSpacing 2 -activeSpacing 2 \
    #    -iterationName step200
    #                
    #addMetalFill \
    #    -iterationNameList {step200} \
    #    -area $x1 $y1 $x2 $y2 \
    #    -squareShape \
    #    -layer { E1 }
    #               
    ## 400x400, >10%
    #setMetalFill \
    #    -layer E1 \
    #    -windowSize 400 400 \
    #    -windowStep 400 400 \
    #    -minWidth 6.0 -maxWidth 6.0 \
    #    -minLength 6.0  -maxLength 6.0 \
    #    -minDensity 28 -maxDensity 70 \
    #    -preferredDensity 70 \
    #    -gapSpacing 2 -activeSpacing 2 \
    #    -iterationName default
    #                                         
    #addMetalFill \
    #    -iterationNameList {step400} \
    #    -area $x1 $y1 $x2 $y2 \
    #    -squareShape \
    #    -layer { E1 }                        
 
    setMetalFill \
        -layer LY \
        -windowSize 400 400 \
        -windowStep 400 400 \
        -minWidth 1 -maxWidth 6 \
        -minLength 1 -maxLength 6 \
        -decrement 1 \
        -minDensity 32 -maxDensity 65 \
        -preferredDensity 65 \
        -gapSpacing 2 -activeSpacing 2 \
        -diagOffset 1 1 \
        -iterationName default

    addMetalFill \
        -area $x1 $y1 $x2 $y2 \
        -squareShape \
        -stagger diag \
        -layer { LY }
                               
}

     

################################################################################
# Manually Repair Antenna Diode Violations
#
# Taken from support.cadence.com solution ID 11837936
# Adds antenna diodes to all nets from an input file.  The antenna violation
# report is used for this purpose.  It places diodes near each violation and
# then reruns place and route to legalize the new instances.
################################################################################

proc addDiode {antennaFile antennaCell} {
    unlogCommand dbGet
    if [catch {open $antennaFile r} fileId] {
        puts stderr "Cannot open $antennaFile: $fileId"
    } else {
        foreach line [split [read $fileId] \n] {
            # Search for lines matching "instName (cellName) pinName" that have violations
            if {[regexp {^  (\S+)  (\S+) (\S+)} $line] == 1} {
                puts $line
                # Remove extra white space
                regsub -all -- {[[:space:]]+} $line " " line
                set line [string trimlef $line]
                # Store instance and pin name to insert diodes on
                set instName [lindex [split $line] 0]
                set pinName [lindex [split $line] 2]
                set instPtr [dbGet -p top.insts.name $instName]
                set instLoc [lindex [dbGet $instPtr.pt] 0]
                set instLocX [lindex $instLoc 0]
                set instLocY [lindex $instLoc 1]
                puts "$instName:$pinName@$instPtr ($instLoc)"
                if {$instName != ""} {
                    # Attach diode and place at location of instance
                    attachDiode -diodeCell $antennaCell -pin $instName $pinName -loc $instLocX $instLocY
                }
            }
        }
    }
    close $fileId
    # Legalize placement of diodes and run ecoRoute to route them
    refinePlace -preserveRouting true
    ecoRoute
    logCommand dbGet
} 

################################################################################
# Hilite all routes associated with a net. (even if a special net)
#
# Modified from support.cadence.com solution ID 11168582
# This is usefull to track down unexpected usage of power/ground nets in
# routing.  For example, a ground net was routing the inputs of several
# standard cells when it should not have been.
################################################################################
          
#proc hiliteWire { netName } {
#    dehiliteAll
#    deselectAll
#    redraw
#    set netPtr [dbGetNetByName $netName]
#    set QN [dbIsNetSpecial $netPtr]
#    if { $QN == "1" } {
#        puts "The highlighted net $netName is a Special Net"
#        dbForEachFPlanStrip [dbHeadFPlan] stripPtr {
#            set name [dbGetStripByName $netName]
#            dbForEachStripBox $name stripBoxPtr {
#                #puts [dbStripBoxBox $stripBoxPtr]
#                dbHiliteObj $stripBoxPtr
#                dbSelectObj $stripBoxPtr
#                }
#            }
#        } else {
#            puts "The highlighted net $netName is a Signal net"
#            dbForEachNetWire $netPtr wirePtr {
#                dbHiliteObj $wirePtr
#                dbSelectObj $wirePtr
#            }
#        }
#    zoomSelected
#}
          
proc hiliteWire { netName } {
    dehiliteAll
    deselectAll
    redraw
    set netPtr [dbGetNetByName $netName]
    set QN [dbIsNetSpecial $netPtr]
    if { $QN == "1" } {
        dbForEachFPlanStrip [dbHeadFPlan] stripPtr {
            set name [dbGetStripByName $netName]
            dbForEachStripBox $name stripBoxPtr {
                dbHiliteObj $stripBoxPtr
                dbSelectObj $stripBoxPtr
            }
        }
    }
    dbForEachNetWire $netPtr wirePtr {
        dbHiliteObj $wirePtr
        dbSelectObj $wirePtr
    }
    zoomSelected
}
         
################################################################################
# Binary Tree Net Router
################################################################################
 
proc makeBinaryTree {x y w layer depth} {
    # Recursively draw 2 other trees at leaves of the current tree.  This is
    # done to allow Encounter to automatically connect higher-level tree nets
    # to the lower tree nets.
    if {$depth > 0} {
        # Find the child spacing on this level of the tree.
        set num_children [expr pow(2, $depth)]
        set pitch [expr $w / [expr $num_children - 1]]
        # Recursively generate subtrees.
        set dx -1.2
        set dy [expr $pitch * [expr pow(2, [expr $depth - 2])]]
        set child_width [expr [expr [expr $w + $pitch] / 2] - $pitch]
        makeTree [expr $x + $dx] [expr $y - $dy] $child_width $layer [expr $depth - 1]
        makeTree [expr $x + $dx] [expr $y + $dy] $child_width $layer [expr $depth - 1]
        # Draw a tree over the specified region.
        editAddRoute     [expr $x + 0  ] [expr $y - $dy]
        editCommitRoute  [expr $x + $dx] [expr $y - $dy]
        editAddRoute     [expr $x + 0  ] [expr $y + $dy]
        editCommitRoute  [expr $x + $dx] [expr $y + $dy]
        editAddRoute     [expr $x + 0  ] [expr $y - $dy]
        editCommitRoute  [expr $x + 0  ] [expr $y + $dy]
    }
}

################################################################################
# Generic H Tree Net Router
################################################################################
 
proc makeHTree {x y w h offsetx offsety offseth depth} {
    # Calculate the corner coordinate offvariables from the center.
    set halfw [expr $w / 2]
    set halfh [expr $h / 2]
    # Recursively draw 4 other H trees in each quadrant if the depth requires.
    # This is done to allow Encounter to automatically connect higher-level H
    # tree nets to the lower H tree nets.
    if {$depth > 1} {
        makeHTree [expr $x - $halfw] [expr $y - $halfh] $halfw $halfh $offsetx $offsety $offseth [expr $depth - 1]
        makeHTree [expr $x - $halfw] [expr $y + $halfh] $halfw $halfh $offsetx $offsety $offseth [expr $depth - 1]
        makeHTree [expr $x + $halfw] [expr $y - $halfh] $halfw $halfh $offsetx $offsety $offseth [expr $depth - 1]
        makeHTree [expr $x + $halfw] [expr $y + $halfh] $halfw $halfh $offsetx $offsety $offseth [expr $depth - 1]
    }
    # Draw an H tree over the entire region.  If this is the lowest level, use
    # special dimensions since the arms only need to reach the border of the
    # photodiode, not the center.
    puts "$x,$y"
    if {$depth > 1} {
        editAddRoute    [expr $x - $halfw] [expr $y - $halfh]
        editCommitRoute [expr $x + $halfw] [expr $y - $halfh]
        editAddRoute    [expr $x - $halfw] [expr $y + $halfh]
        editCommitRoute [expr $x + $halfw] [expr $y + $halfh]
        editAddRoute    $x                 [expr $y - $halfh]
        editCommitRoute $x                 [expr $y + $halfh]
    } else {
        set halfh [expr $halfh + [expr $offseth / 2]]
        editAddRoute    [expr $offsetx + [expr $x - $halfw]] [expr $offsety + [expr $y - $halfh]]
        editCommitRoute [expr $offsetx + [expr $x + $halfw]] [expr $offsety + [expr $y - $halfh]]
        editAddRoute    [expr $offsetx + [expr $x - $halfw]] [expr $offsety + [expr $y + $halfh]]
        editCommitRoute [expr $offsetx + [expr $x + $halfw]] [expr $offsety + [expr $y + $halfh]]
        editAddRoute    $x                                   [expr $offsety + [expr $y - $halfh]]
        editCommitRoute $x                                   [expr $offsety + [expr $y + $halfh]]
    }
    uiSetTool select
}
 
################################################################################
# C Tree Router
################################################################################
 
proc makeCTree {x y dx dy nx ny direction rotation depth} {
    printInfo "Generating C Tree with parameters ($x $y $dx $dy $nx $ny $direction $rotation $depth)"
    # Verify that a valid direction for the tree was specified.
    set VERTICAL "v"
    set HORIZONTAL "h"
    if {$direction != $VERTICAL && $direction != $HORIZONTAL} {
        printInfo "Invalid direction passed to makeCTree: $direction"
        return
    }
    set R0 "r0"
    set R180 "r180"
    if {$rotation != $R0 && $rotation != $R180} {
        printInfo "Invalid rotation passed to makeCTree: $rotation"
        return
    }
    # Round up to the nearest power of two, which is used for consistent
    # connectivity.
    set nmax [expr max($nx, $ny)]
    set nlog2 [expr round([expr log($nmax) / log(2)])]
    set xhook 9.00
    set yhook 0.00
    #set spacing 1.20
    set spacing 3.5
    for {set k 0} {$k < $depth} {incr k} {
        printInfo "Routing layer [expr $k + 1] of [expr $depth + 1]\r" -nonewline
        flush stdout
        redraw
        update
        if {$rotation == $R180} {
            set xhook [expr $xhook * -1]
            set yhook [expr $yhook * -1]
        }
        # Route the C-shaped nets.  The sign of the hooks on each end depents
        # on the direction of the tree being built.
        if {$direction == $VERTICAL} {
            for {set i 0} {$i < $ny} {incr i 2} {
                for {set j 0} {$j < $nx} {incr j} {
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + 0]]      [expr $y + [expr [expr $dy * $i] + 0]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + 0]]      [expr $y + [expr [expr $dy * $i] + $yhook]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + $xhook]] [expr $y + [expr [expr $dy * $i] + $yhook]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + $xhook]] [expr $y + [expr [expr $dy * $i] + [expr $yhook + $dy]]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + 0]]      [expr $y + [expr [expr $dy * $i] + [expr $yhook + $dy]]]
                    editCommitRoute [expr $x + [expr [expr $dx * $j] + 0]]      [expr $y + [expr [expr $dy * $i] + $dy]]
                }
            }
            set direction $HORIZONTAL
            set x [expr $x + $xhook] 
            set y [expr $y + [expr [expr $dy / 2] + $yhook]] 
            set xhook $spacing
            set yhook [expr [expr $dy / 2] + $spacing]
            set dx $dx
            set dy [expr $dy * 2]
            set nx $nx
            set ny [expr $ny / 2]
        } elseif {$direction == $HORIZONTAL} {
            for {set i 0} {$i < $ny} {incr i} {
                for {set j 0} {$j < $nx} {incr j 2} {
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + 0]]                   [expr $y + [expr [expr $dy * $i] + 0]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + $xhook]]              [expr $y + [expr [expr $dy * $i] + 0]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + $xhook]]              [expr $y + [expr [expr $dy * $i] + $yhook]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + [expr $xhook + $dx]]] [expr $y + [expr [expr $dy * $i] + $yhook]]
                    editAddRoute    [expr $x + [expr [expr $dx * $j] + [expr $xhook + $dx]]] [expr $y + [expr [expr $dy * $i] + 0]]
                    editCommitRoute [expr $x + [expr [expr $dx * $j] + $dx]]                 [expr $y + [expr [expr $dy * $i] + 0]]
                }
            }
            set direction $VERTICAL
            set x [expr $x + [expr [expr $dx / 2] + $xhook]] 
            set y [expr $y + $yhook] 
            set xhook [expr [expr $dx / 2] + $spacing]
            set yhook $spacing
            set dx [expr $dx * 2]
            set dy $dy
            set nx [expr $nx / 2]
            set ny $ny
        }
        # Update the x and y wrap-arounds.
        #set xhook [expr $xhook + $spacing]
        #set yhook [expr $yhook + $spacing]
    }
    printInfo "Tree complete."
    uivariableTool select
}
  
################################################################################
# EXPERIMENTAL/UNVERIFIED
#
# Get Coordinates of an Instance Pin
# Taken from support.cadence.com forum post "pin location" by Yemelya
# http://www.cadence.com/community/forums/T/20140.aspx
# Finds the coordinates of a specified pin.
################################################################################

proc queryInstPin_loc { { instPin "" } } {
    #loguse procedures queryInstPin_loc
    # queryInstPin_loc: returns the location of the <inst>/<pin>
    if { $instPin == "" } {
        puts ""
        puts "   Usage:  queryInstPin_loc  <inst>/<pin>"
        puts ""
        puts "      returns the location of pin <inst>/<pin>"
        puts ""
    } else {
        #setscale [pdsDBU2Micron 1]
        set scale [dbDBUToMicrons 1]
        set numbFields [regsub -all "/" $instPin " " inst_pin]
        set pin [lindex $inst_pin $numbFields]
        regsub -all {[[$^?+*()|\\]} $pin {\\&} escPin
        regsub -all "/${escPin}$" $instPin "" inst
        set instPtr [dbGetInstByName $inst]
        if { $instPtr == "0x0" } {
            puts "Didn't find inst $inst"
        } else {
            set termPGPtr "0x0"
            set termPtr [dbGetTermByName $instPtr $pin]
            if { $termPtr == "0x0" } {
                set termPGPtr [dbGetPGTermByName $instPtr $pin]
            }
            if { $termPtr == "0x0"  &&  $termPGPtr == "0x0" } {
                puts "Didn't find signal or power pin named $pin on inst $inst"
            } else {
                if { $termPGPtr == "0x0" } {
                set dbXY  [dbTermLoc $termPtr]
                set x [dbDBUToMicrons [lindex $dbXY 0]]
                set y [dbDBUToMicrons [lindex $dbXY 1]]
                } else {
                    #set pinLoc [dbTermLoc $termPGPtr]
                    #set dbXY  [dbTermLoc $termPGPtr]
                    # Using dbTermLoc doesn't seem to work for PG pins, so find the
                    # coordinates through another method.
                    foreach pgCellTerm [dbGet $instPtr.pgCellTerms] {
                        if { [dbGet $pgCellTerm.name] == $pin} {
                            set temp [dbTransform -localPt [dbGet $pgCellTerm.pt] -inst $instPtr]
                            set xy [regexp -all -inline {\d+\.\d+} $temp]
                            set x [lindex $xy 0]
                            set y [lindex $xy 1]
                        }
                    }
                }
                return [list $x $y]
            }
        }
    }
} 
  
################################################################################
# Find all instances connected to a net
# Taken from support.cadence.com
# Solution ID 11419952
################################################################################

proc getInstsConnectedToNet {netName} {
    set netPtr [dbGet -p top.nets.name $netName]
    set termPtrList [dbGet $netPtr.allTerms]
    # Use the following to output the pins and ports connected to the net:
    # Puts " Pins/Ports: [dbGet $netPtr.allTerms.name]"
    # Puts ""
    # The following outputs the instances connected to the specified net:
    foreach term $termPtrList {
        if {[dbGet $term.objType] == "instTerm"} {
            puts " Instance: [dbGet $term.inst.name]"
        }
    }
    puts ""
}
 
################################################################################
# Add simple stripes more quickly than the built-in addStripe
################################################################################

proc addStripeNP {xsw ysw xne yne nets layer direction offset colstart colstop width space} {

    global PXL_DIM_X
    global PXL_DIM_Y

    uiSetTool addWire
    setEdit \
        -layer_horizontal $layer \
        -layer_vertical $layer \
        -width_horizontal $width \
        -width_vertical $width 

    if {$direction == "vertical"} {
        for {set i $colstart} {$i < $colstop} {incr i} {
            set origin [expr $xsw + [expr $i * $PXL_DIM_X]]
            set edge [expr $origin + $offset]
            set center [expr $edge + [expr $width / 2]]
            foreach net $nets {
                setEdit -nets $net
                editAddRoute    $center $ysw
                editCommitRoute $center $yne 
                set center [expr $center + [expr $width + $space]]
            }
        }
    } elseif {$direction == "horizontal"} {
        for {set i $colstart} {$i < $colstop} {incr i} {
            set origin [expr $ysw + [expr $i * $PXL_DIM_Y]]
            set edge [expr $origin + $offset]
            set center [expr $edge + [expr $width / 2]]
            foreach net $nets {
                setEdit -nets $net
                editAddRoute    $xsw $center 
                editCommitRoute $xne $center 
                set center [expr $center + [expr $width + $space]]
            }
        }
    } else {
        puts "Invalid direction passed to addStripeNP"
    }
    uiSetTool select
}

################################################################################
# Generates an accordion route between two points in a given channel.
#
# Note: Start and stop locations are assumed to be horizontally or vertically
# aligned.
################################################################################

proc makeAccordionRoute {x1 y1 x2 y2 width length channel_width} {
    # set the wire width manually since this directly affects the accordion.
    setedit \
        -width_horizontal $width \
        -width_vertical   $width
    # Calculate the manhattan distance between the points.
    set dx [expr $x2 - $x1]
    set dy [expr $y2 - $y1]
    set dmanhattan [expr $dx + $dy]
    # Set the length of the two tails where no folds are created.
    set tail_length [expr double($channel_width) / 1]
    # Find the difference between the desired length and manhattan distance.
    set coil_length [expr $length - $dmanhattan]
    # Find the number of folds required to achieve the desired length.
    set num_folds [expr floor([expr $coil_length / [expr $channel_width - $width]])]
    # Find the spacing between folds.
    set fold_spacing [expr double([expr $dmanhattan - [expr 2 * $tail_length]]) / $num_folds]
    # Route the wire, spreading out the folds to minimize EM coupling.
    set x $x1
    set y $y1
    # Vertical route
    if {$dx == 0} {
        editAddRoute $x $y
        set y [expr $y + $tail_length]
        editAddRoute $x $y
        for {set n 0} {$n < $num_folds} {incr n} {
            set jog [expr [expr $channel_width / 2] - [expr $width / 2]]
            if {[expr $n % 2] == 0} {
                set jog [expr $jog * -1]
            }
            editAddRoute [expr $x + $jog] [expr $y + [expr $fold_spacing * $n]]
            editAddRoute [expr $x + $jog] [expr $y + [expr $fold_spacing * [expr $n + 1]]]
            editAddRoute       $x         [expr $y + [expr $fold_spacing * [expr $n + 1]]]
        }
        editCommitRoute $x2 $y2
    } else {
    # Horizontal route
        editAddRoute $x $y
        set x [expr $x + $tail_length]
        editAddRoute $x $y
        for {set n 0} {$n < $num_folds} {incr n} {
            set jog [expr [expr $channel_width / 2] - [expr $width / 2]]
            if {[expr $n % 2] == 0} {
                set jog [expr $jog * -1]
            }
            editAddRoute [expr $x + [expr $fold_spacing * $n]]            [expr $y + $jog] 
            editAddRoute [expr $x + [expr $fold_spacing * [expr $n + 1]]] [expr $y + $jog] 
            editAddRoute [expr $x + [expr $fold_spacing * [expr $n + 1]]]       $y         
        }
        editCommitRoute $x2 $y2
    }
    puts "New accordion route - dm: $dmanhattan, cl: $coil_length, nf: $num_folds, fs: $fold_spacing"
}
                                             
################################################################################
# Adds antenna diodes manually to a list of IO pins.
#
# Based off the userAddDiodesToIOs script in the gifts directory.
################################################################################
proc addDiodesToIOs {ioList diodeCellName} {
    set orient R0
    dbForEachCellFTerm [dbHeadTopCell] fterm {
        set ftermName [dbFTermName $fterm]
        set netPtr [dbFTermNet $fterm]
        dbForEachNetTerm $netPtr termPtr {
            if { [dbObjType $termPtr] == "dbcObjTerm" } {
                if {[lsearch -exact $ioList $ftermName] != -1} {
                    set termName [dbTermName $termPtr]
                    set instPtr [dbTermInst $termPtr]
                    set instName [dbInstName $instPtr]
                    set loc [dbTermLoc $fterm]
                    set x [dbDBUToMicrons [dbLocX [dbTermLoc $fterm]]]
                    set y [dbDBUToMicrons [dbLocY [dbTermLoc $fterm]]]
                    puts "IO Pin name: $ftermName ;Terminal  name: $termName; InstName: $instName"
                    attachDiode -diodeCell $diodeCellName -pin $instName $termName -loc $x $y
                }
            }
        }
    }
    ecoPlace
}

################################################################################
# Adds antenna diodes to the pins of a cell.
################################################################################

proc addDiodesToInst {instName diodeCellName} {
    set pinPtrs [dbGet [dbGetInstByName $instName].instTerms.cellTerm]
    set instX [lindex [lindex [dbGet [dbGetInstByName $instName].pt] 0] 0]
    set instY [lindex [lindex [dbGet [dbGetInstByName $instName].pt] 0] 1]
    puts "$instX $instY"
    foreach pinPtr $pinPtrs {
        set pinName [lindex [dbGet $pinPtr.name] 0]
        set pinLoc [lindex [dbGet $pinPtr.pt] 0]
        set x [expr $instX + [lindex $pinLoc 0]]
        set y [expr $instY + [lindex $pinLoc 1]]
        puts "attachDiode -diodeCell $diodeCellName -pin $instName $pinName -loc $x $y"
        attachDiode -diodeCell $diodeCellName -pin $instName $pinName -loc $x $y
    }
    ecoPlace
}
     
################################################################################
# Manually places inverters in a column across standard cell rows.  This
# prevents floating nwell violations on rows where only TIEHILO and FILLER cells
# are present.
################################################################################

proc fixGR594 {x y num_rows uid} {
    global STD_CELL_HEIGHT
    set INVX2TF_WIDTH 1.2
    set TIELOTF_WIDTH 1.2
    set index 0
    for {set i 0} {$i < $num_rows} {incr i} {
        addNet gr134_${uid}_net_${index} 
        addInst -cell TIELOTF -inst gr134_${uid}_tielo_${index}
        addInst -cell INVX2TF -inst gr134_${uid}_inv_${index}
        attachTerm gr134_${uid}_tielo_${index} Y gr134_${uid}_net_${index}
        attachTerm gr134_${uid}_inv_${index}   A gr134_${uid}_net_${index}
        placeInstance gr134_${uid}_tielo_${index} \
            $x \
            [expr $y + [expr $i * $STD_CELL_HEIGHT]]
        placeInstance gr134_${uid}_inv_${index} \
            [expr $x + $TIELOTF_WIDTH] \
            [expr $y + [expr $i * $STD_CELL_HEIGHT]]
        set index [expr $index + 1]
    }
}
                
################################################################################
# Inserts antenna diodes near the input pins of any instance whose routing
# touches MQ.  This minimizes GR131f violations, but it may not remove them all
# since the diodes are not guaranteed to connect to the input pin on M1-M3
# before the MQ layer is reached during fab.
################################################################################

proc fixGR594f {} {
    set net_ptrs [dbGet -u -p2 top.nets.wires.layer {.name == "M4"}]
    foreach net_ptr $net_ptrs {
        set net_terms [dbGet $net_ptr.allTerms]
        set uid 0
        foreach net_term $net_terms {
            if {[dbGet $net_term.isInput] == 1} {
                set net  [dbGet $net_term.net.name]
                set inst [dbGet $net_term.inst.name]
                # Use lindex to handle "{PinName}" pins on NS430 along with normal
                # "PinName" pins elsewhere.
                set pin [lindex [dbGet $net_term.cellTerm.name] 0]
                set x   [lindex [lindex [dbGet $net_term.inst.pt] 0] 0]
                set y   [lindex [lindex [dbGet $net_term.inst.pt] 0] 1]
                puts "Placing diode $uid on $inst/$pin @ ($x,$y)"
                attachDiode \
                    -diodeCell ANTENNATF \
                    -prefix GR131F_MX_FIX_$uid \
                    -pin $inst $pin \
                    -loc $x $y
                set uid [expr $uid + 1]
            }
        }
    }
    refinePlace -preserveRouting true
    deselectAll
    foreach net_ptr $net_ptrs {
        selectNet [dbGet $net_ptr.name]
    }
    ecoRoute
    deselectAll
}
 
proc fix_drc_routing {violation} {
    deselectAll;
    set SELECTED_WIRES 0
    set SELECTED_VIAS 0
    set net {}
    set wire_status {}
    foreach MARKER  [dbGet top.markers.userType -p $violation] {
		set MARKER_BOX [dbGet $MARKER.box]
		puts "MARKER = $MARKER"
		puts "MARKER_BOX = $MARKER_BOX"
		set LAYER [dbGet $MARKER.layer.name]
			foreach OBJECT [dbQuery -area ${MARKER_BOX} -objType regular] {
			set OBJTYPE [dbGet $OBJECT.objType]
			puts "$OBJTYPE"
			if {[regexp wire $OBJTYPE]} {
			   set WIRE_POINTER [dbGet -p1 $OBJECT.layer {.name eq $LAYER}]
			   set WIRE_STATUS [dbGet $OBJECT.status]                         
			   if {![regexp 0x0 $WIRE_POINTER]} {
					dbSelectObj $WIRE_POINTER
					lappend net [ dbGet $WIRE_POINTER.net.name]
					incr SELECTED_WIRES
					lappend wire_status $WIRE_STATUS
				}
			} elseif {[regexp viaInst $OBJTYPE]} {
				set VIA_POINTER [dbGet -p2 $OBJECT.via.botlayer {.name eq $LAYER}]
			   if {![regexp 0x0 $VIA_POINTER]} {
				   dbSelectObj $VIA_POINTER
					incr SELECTED_VIAS
				}
			}
		}
    }
    
    puts "selected $SELECTED_WIRES wires and $SELECTED_VIAS associated vias"

    #Reset the wire status to routed from fixed for all clock nets showing violations.
    foreach n $net {
        dbSet [dbGetNetByName [lindex $n 0]].wires.status routed
    }

    #Deleting segements with violations
    editDelete -selected
}
