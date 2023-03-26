# insert one entry to the flag_table
# run with ./run_bfshell.sh -b ./setup.py -i

p4 = bfrt.packet_reorder.pipe

flag_table = p4.SwitchIngress.flag_table
rorder_table = p4.SwitchIngress.rorder_table

flag_table.add_with_send(flag=1, port=1)
rorder_table.add_with_rorder_assign(order=1, rorder=3)
rorder_table.add_with_rorder_assign(order=2, rorder=2)
rorder_table.add_with_rorder_assign(order=3, rorder=1)

bfrt.complete_operations()

print ("Table flag_table:")
flag_table.dump(table=True)

print ("Table rorder_table:")
rorder_table.dump(table=True)



