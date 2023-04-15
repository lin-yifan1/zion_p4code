#include <core.p4>
#include <tna.p4>

#define REGISTER_ENTRY bit<8>

const bit<16> TYPE_REC = 0x1212;
const PortId_t rec_port = 68;       // recirculation port

#include "common/headers.p4"
#include "common/util.p4"

header rec_h {
    bit<16> proto_id;
    bit<8>  flag; // 0 --> packet should be recirculated
    bit<8>  index; // index in hash table
    bit<8>  order; // original order
    bit<8>  reorder; // the order we want
}

struct headers {
    ethernet_h   ethernet;
    rec_h        rec;
    ipv4_h       ipv4;
    tcp_h        tcp;
}

struct metadata_t { }

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
            TYPE_REC : parse_rec;
            ETHERTYPE_IPV4 : parse_ipv4;
            default : reject;
        }
    }

    state parse_rec {
        pkt.extract(hdr.rec);
        transition select (hdr.rec.proto_id) {
            ETHERTYPE_IPV4 : parse_ipv4;
            default : reject;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select (hdr.ipv4.protocol) {
            IP_PROTOCOLS_TCP : parse_tcp;
            default : reject;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
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
    bit<8> id;
    Register<REGISTER_ENTRY, bit<8>>(32w256, 8w0) order_table;
    Register<REGISTER_ENTRY, bit<8>>(32w256, 8w0) reorder_table;

    Hash<bit<8>>(HashAlgorithm_t.CRC8) hash;

    RegisterAction<REGISTER_ENTRY, bit<8>, bit<8>>(order_table) order_table_action = {
        void apply(inout REGISTER_ENTRY hash_value, out bit<8> order) {
            hash_value = hash_value + 1;
            order = hash_value;
        }
    };

    RegisterAction<REGISTER_ENTRY, bit<8>, bit<8>>(reorder_table) reorder_table_action = {
        void apply(inout REGISTER_ENTRY hash_value, out bit<8> flag) {
            flag = 0;
            if (hdr.rec.reorder - hash_value == 1) {
                flag = 1;
                hash_value = hash_value + 1;
            }   
        }
    };

    action valid_action() {
        hdr.rec.flag = reorder_table_action.execute(hdr.rec.index);
    }

    action notvalid_action() {
        // add rec header
        hdr.rec.setValid();
        hdr.rec.index = id;
        hdr.ethernet.ether_type = TYPE_REC;
        hdr.rec.proto_id = ETHERTYPE_IPV4;
        hdr.rec.order = order_table_action.execute(id);
        hdr.rec.flag = 0;
    }

    action rorder_assign(bit<8> rorder) {
        hdr.rec.reorder = rorder;
    }

    action send(PortId_t port) {
        hdr.rec.setInvalid(); // remove rec header
        hdr.ethernet.ether_type = ETHERTYPE_IPV4;
        ig_intr_tm_md.ucast_egress_port = port;
    }

    // Recirculate the packet to the recirculation port
    // Increase the recirculation number
    action recirculate(){
        ig_intr_tm_md.ucast_egress_port = rec_port;  
    }

    action set_flag_1(){
        hdr.rec.flag = 1;
    }

    table rorder_table {
        key = {
            hdr.rec.order : exact;
        }
        actions = {
            rorder_assign;
            set_flag_1;
        }
        default_action = set_flag_1();
    }

    table flag_table {
        key = {
            hdr.rec.flag : exact;
        }
        actions = {
            send;
            recirculate;
        }
        default_action = recirculate();
        size = 1;
    }

    apply {
        id = hash.get({ hdr.ipv4.src_addr, hdr.ipv4.dst_addr, 
                        hdr.tcp.src_port, hdr.tcp.dst_port, hdr.ipv4.protocol});
        if (!hdr.rec.isValid()) {
            notvalid_action();
            rorder_table.apply();
        }
        else {
            valid_action();
        }
        flag_table.apply();
        
        

        // No need for egress processing, skip it and use empty controls for egress.
        ig_intr_tm_md.bypass_egress = 1w1;
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

Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         EmptyEgressParser(),
         EmptyEgress(),
         EmptyEgressDeparser()) pipe;

Switch(pipe) main;