#!/usr/bin/env python

# Rearranges the ports on a verilog module to be alphabetical.  This allows the
# port order to match what is expected by the Cadence CDL netlister (run with
# si executable).  Normally environemnt variables would tell the netlister to
# respect/use the auCdl portOrder property, but it doesn't seem to actually
# work.

import sys

with open(sys.argv[1]) as f:

    # Set if the module port definition block has been reached, but not completed
    reading_ports = False
    ports_parsed = False
    lines_with_ports = []

    for line in f:

        # Is this the start of the port section?
        if line.startswith('module '):
            sys.stdout.write(line.replace('(', '( // Alphabatized using %s' % sys.argv[0]))
            reading_ports = True

        # Is this the last port with a closing parenthesis? (Assumes formatting from Innovus)
        elif reading_ports and ');' in line:
            lines_with_ports.append(line.replace(');', ','))
            reading_ports = False

            # Sort lines and then output all of them
            lines_with_ports.sort()
            for i in range(len(lines_with_ports) - 1):
                sys.stdout.write(lines_with_ports[i])
            sys.stdout.write(lines_with_ports[-1].replace(',', ');'))

        # Just a standard port line
        elif reading_ports:
            lines_with_ports.append(line)

        # Standard line
        else:
            sys.stdout.write(line)
