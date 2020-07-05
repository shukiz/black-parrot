from argparse import ArgumentParser
import os

parser = ArgumentParser(description='CCE Microcode 34-bit to 64-bit converter')
parser.add_argument('-i', dest='in_file', type=str, default=None,
                    help='Input memory file (.mem)', required=True)
parser.add_argument('-o', dest='out_file', type=str, default='./temp.bin',
                    help='Output binary file')

args = parser.parse_args()
wf = open(os.path.abspath(args.out_file), 'w')

with open(os.path.abspath(args.in_file), 'r') as rf:
    lines = rf.readlines() 
    for line in lines:
      wf.write(format(int(line, 2), 'X').zfill(16))

rf.close()
wf.close()
