from argparse import ArgumentParser
import os

parser = ArgumentParser(description='CCE Microcode 34-bit to 64-bit converter')
parser.add_argument('-c', '--cce', dest='cce_file', type=str, required=True, default=None, help='Input CCE ucode memory file (.mem)')
parser.add_argument('-p', '--prog', dest='prog_file', type=str, required=False, default=None, help='Input program memory file (.mem)')
parser.add_argument('-o', '--output', dest='out_file', type=str, default='./sd_card.mem', help='Output binary file')

args = parser.parse_args()
wf = open(os.path.abspath(args.out_file), 'w')

with open(os.path.abspath(args.cce_file), 'r') as rf:
    lines = rf.readlines() 
    for line in lines:
      wf.write(format(int(line, 2), 'X').zfill(16))
      wf.write("\n")
rf.close()

# with open(os.path.abspath(args.prog_file), 'r') as rf:
#   lines = rf.readlines()
#   for line in lines:
#     stripped_line = line.strip()
#     if stripped_line:
#       if stripped_line.startswith("@"):
#         continue
#       else:
#         byte_list = stripped_line.split()
#         final_string = ""
#         count = 0
#         for hex_num in byte_list:
#           final_string += hex_num
#           count += 1
#           if count == 8:
#             wf.write(final_string)
#             wf.write("\n")
#             final_string = ""
#             count = 0
# rf.close()

wf.close()
