# insert one entry to the flag_table
# run with ./run_bfshell.sh -b ./setup.py -i

p4 = bfrt.timestamp.pipe

flag_table = p4.SwitchIngress.flag_table

flag_table.add_with_send(flag=1, port=1)

bfrt.complete_operations()

print ("Table flag_table:")
flag_table.dump(table=True)



