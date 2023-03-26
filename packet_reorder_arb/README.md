# Prototype of Packet Reordering Using Tofino

This application can reorder a TCP flow into arbitrary sequences. The program contains a hash register table to keep track of  flows, and will add a temporary `rec` header to the packets for recirculation.

By modifying the `rorder_table`, user can achieve arbitrary order of output flow. For example, by setting the table in `script/setup.py`：

```python
rorder_table.add_with_rorder_assign(order=1, rorder=3)
rorder_table.add_with_rorder_assign(order=2, rorder=2)
rorder_table.add_with_rorder_assign(order=3, rorder=1)
```

an input flow with sequence 1, 2, 3 will be reordered to 3, 2, 1.
