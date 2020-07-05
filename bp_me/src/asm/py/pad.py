from argparse import ArgumentParser
import os
import sys

parser = ArgumentParser(description='CCE Microcode 34-bit to 64-bit converter')
parser.add_argument('-i', dest='in_file', type=str, default=None,
                    help='Input memory file (.mem)', required=True)
parser.add_argument('-o', dest='out_file', type=str, default='./out',
                    help='Output directory path')

args = parser.parse_args()

with open(os.path.abspath(args.in_file), 'r') as rf, open(os.path.abspath(args.out_file), 'w') as wf:
    for line in rf:
        # Using 64 because we need 64 + 1 (next line) character
        line = line.zfill(65)
        wf.write(line)

rf.close()
wf.close()
