#!/usr/bin/env python

################################################################
# Daria Pankova 
################################################################

import matplotlib.pyplot as plt
from math import log
from math import ceil
import numpy as np
from matplotlib.ticker import FormatStrFormatter
import argparse
parser = argparse.ArgumentParser(prog="raw_to_hist",description="Makes hist")
parser.add_argument("--fin",type=str,help="Raw data file from which to read")
parser.add_argument("--fout",type=str,help="output file",default="./data_hist.txt")
parser.add_argument("--hist",help="histogram the data",action="store_true")
parser.add_argument("--version",action="version",version="%(prog)s 0.1")
parser.add_argument("--verbose",help="Print additional debugging info",action="store_true")

args = parser.parse_args()
if args.verbose:
    # print args
    print "----------------------------------------------------------"

###############################################################
# Open the file
if args.fin == None:
    print "\nError: Must specify a valid raw file! Bailing!\n"
    exit(-1)
else:
    filename = "./" + args.fin
    try: fin = open(filename)
    except IOError: print "\nError: Cannot open %s ! Bailing!\n" % filename
    else: 
        if args.verbose: print fin
################################################################
# Open the file find start   
start = 0
flag = 0
i = 0
fsm = 0
for line in fin:
    i = i+1
    if i>9 : fsm = int(line.split(", ")[46])
    if (start == 0) and (fsm == 2): start = i-1
    if (start != 0) and (fsm == 4): break
    
if args.verbose: print "Read %d data points" % len(data)
stop = i-5
print "start %d stop %d" % (start, stop)
fin.close()
###############################################################
# Open the file  and read the data   
filename = "./" + args.fin
try: fin = open(filename)
except IOError: print "\nError: Cannot open %s ! Bailing!\n" % filename
else: 
    if args.verbose: print fin
i = 0
data = []
last = []
intdata = []
for line in fin:
    i = i+1
   # print i
    if (i >= start) and (i <= stop): 
        data.append(int(line.split(", ")[4])) 
    if (i > stop): 
        last.append(int(line.split(", ")[4]))
    if (i == stop+3): break
    


###############################################################
fout = open(args.fout,"w")
for x in range(len(data)):
  #  print data[x]
    line = str(data[x])+'\n'
    fout.write(line)
    if args.verbose: print line
###############################################################
fin.close()
fout.close()

if( args.hist ):
    fig, ax = plt.subplots()
    bins=range(min(data), max(data) + 1, 1)
    counts, bins, patches = ax.hist(data,bins)
    ax.set_xticks(bins)
    ax.xaxis.set_major_formatter(FormatStrFormatter('%0.f'))	
    bin_centers = 0.5 * np.diff(bins) + bins[:-1]
    for c, b in zip(counts, bin_centers):
    # Label the raw counts
        ax.annotate(str.format('{0:.0f}', c), xy=(b, 0), xycoords=('data', 'axes fraction'),
                    xytext=(0, -20), textcoords='offset points', va='top', ha='center')

    plt.title('DDC2 Data: bin 15 = '+str(8188)+', total count = '+str(stop-start+1)+' F'+
              str(data[0]))
    plt.xlabel('ADC Count (LSB) '+ str(data[-3])+' '+str(data[-2])+' L'+str(data[-1])+' '+str(last[0])+' '+str(last[1])+' '+str(last[2]), labelpad =20)
    plt.ylabel("Number of Entries")
    plt.subplots_adjust(bottom=0.15)
    plt.show()
