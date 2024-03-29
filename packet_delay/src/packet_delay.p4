#include <core.p4>
#include <tna.p4>

const bit<16> TYPE_TS = 0x1212;
const PortId_t rec_port = 68;        // recirculation port
const bit<32> latency = 100000000;   // 100000000 nanoseconds - 100ms

#include "common/headers.p4"
#include "common/util.p4"

header ts_h {
    bit<16> proto_id;
    bit<16> rec_num; // record how many times the packet is recirculated, initially 0
    bit<32> ts;      // record the initial timestamp
    bit<8>  flag;    // when the total recirculation time exceeds latency, flag=1
}

struct headers {
    ethernet_h   ethernet;
    ts_h         timestamp;
    ipv4_h       ipv4;
}

struct metadata_t {
    bit<32>  ts_diff;
    bit<32>  latency;
}

// ---------------------------------------------------------------------------
// Ingress parser
// ---------------------------------------------------------------------------
parser SwitchIngressParser(
        packet_in pkt,
        out headers hdr,
        out metadata_t ig_md,
        out ingress_intrinsic_metadata_t ig_intr_md) {

    TofinoIngressParser() tofino_parser;

    state start {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select (hdr.ethernet.ether_type) {
            TYPE_TS : parse_ts;
            ETHERTYPE_IPV4 : parse_ipv4;
            default : reject;
        }
    }

    state parse_ts {
        pkt.extract(hdr.timestamp);
        transition select (hdr.timestamp.proto_id) {
            ETHERTYPE_IPV4 : parse_ipv4;
            default : reject;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

// ---------------------------------------------------------------------------
// Ingress Deparser
// ---------------------------------------------------------------------------
control SwitchIngressDeparser(
        packet_out pkt,
        inout headers hdr,
        in metadata_t ig_md,
        in ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md) {

    apply {
        pkt.emit(hdr);
    }
}

control SwitchIngress(
        inout headers hdr,
        inout metadata_t ig_md,
        in ingress_intrinsic_metadata_t ig_intr_md,
        in ingress_intrinsic_metadata_from_parser_t ig_intr_prsr_md,
        inout ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md,
        inout ingress_intrinsic_metadata_for_tm_t ig_intr_tm_md) {

    bit<1> validity;

    // Register to validate the latency value 
    Register <bit<32>, _> (32w1)  tscal;

    // Comparing two variables on Tofino (though one is constant) 
    // can not be done in the apply part due to ALU limitations, 
    // so we need a RegisterAction
    RegisterAction<bit<32>, bit<1>, bit<8>>(tscal) tscal_action = {
        void apply(inout bit<32> value, out bit<8> readvalue) {
            value = 0;
            if (ig_md.ts_diff > ig_md.latency){
                readvalue = 1;
            }
            else {
                readvalue = 0;
            }
        }
    };

    // Calculate the difference between the initial timestamp and the current timestamp
    action comp_diff() {
        ig_md.ts_diff = ig_intr_md.ingress_mac_tstamp[31:0] - hdr.timestamp.ts;
    }

    action send(PortId_t port) {
        ig_intr_tm_md.ucast_egress_port = port;
        hdr.timestamp.setInvalid(); // remove ts header
        hdr.ethernet.ether_type = ETHERTYPE_IPV4;
    }

    // Recirculate the packet to the recirculation port
    // Increase the recirculation number
    action recirculate(){
        ig_intr_tm_md.ucast_egress_port = rec_port;
        hdr.timestamp.rec_num = hdr.timestamp.rec_num + 1;      
    }

    action add_ts_header(){
        hdr.ethernet.ether_type = TYPE_TS;
        hdr.timestamp.setValid();
        hdr.timestamp.proto_id = ETHERTYPE_IPV4;
        hdr.timestamp.rec_num = 0;
        hdr.timestamp.ts = ig_intr_md.ingress_mac_tstamp[31:0];
        hdr.timestamp.flag = 0;
    }

    action write_latency(bit<32> lat) {
        ig_md.latency = lat;
    }

    table flag_table {
        key = {
            hdr.timestamp.flag : exact;
        }
        actions = {
            send;
            recirculate;
        }
        default_action = recirculate();
        size = 1;
    }

    table valid_table {
        key = {
            validity : exact;
        }
        actions = {
            add_ts_header;
        }
        size = 1;
    }

    table latency_table {
        key = {
            hdr.ipv4.dst_addr : exact;
        }
        actions = {
            write_latency;
        }
        size = 1;
    }

    apply {
        validity = (bit<1>)hdr.timestamp.isValid();

        valid_table.apply();

        latency_table.apply();

        ig_md.ts_diff = 0;
        comp_diff();
        hdr.timestamp.flag = tscal_action.execute(1);

        flag_table.apply();        

        // No need for egress processing, skip it and use empty controls for egress.
        ig_intr_tm_md.bypass_egress = 1w1;
    }

}

Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         EmptyEgressParser(),
         EmptyEgress(),
         EmptyEgressDeparser()) pipe;

Switch(pipe) main;