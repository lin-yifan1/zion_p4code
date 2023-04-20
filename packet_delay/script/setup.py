# insert one entry to the flag_table
# run with ./run_bfshell.sh -b ./setup.py -i

p4 = bfrt.packet_delay.pipe

flag_table = p4.SwitchIngress.flag_table
valid_table = p4.SwitchIngress.valid_table

flag_table.add_with_send(flag=1, port=1)
valid_table.add_with_add_ts_header(validity=0)
latency_table.add_with_write_latency(lat=100000000)

bfrt.complete_operations()

print("Table flag_table:")
flag_table.dump(table=True)
