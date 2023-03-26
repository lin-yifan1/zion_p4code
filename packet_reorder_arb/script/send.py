#!/usr/bin/env python
import time
import os

from scapy.all import IP, Ether, sendp, TCP

def main():
    pkt = Ether() / IP(src="2.2.2.2", dst="3.3.3.3") / TCP(sport=80, dport=20) / "1"

    sendp(pkt, iface="veth251", verbose=False)
    
    pkt = Ether() / IP(src="2.2.2.2", dst="3.3.3.3") / TCP(sport=80, dport=20) / "2"

    sendp(pkt, iface="veth251", verbose=False)
    
    pkt = Ether() / IP(src="2.2.2.2", dst="3.3.3.3") / TCP(sport=80, dport=20) / "3"

    sendp(pkt, iface="veth251", verbose=False)


if __name__ == '__main__':
    main()
