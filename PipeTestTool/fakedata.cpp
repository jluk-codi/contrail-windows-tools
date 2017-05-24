#include "fakedata.h"
#include <WinSock2.h>

#define ETHERTYPE_IP 0x0800
#define ETHER_ADDR_LEN 6

const FakeData::ether_header FakeData::FakeEtherHdr = []() {
    ether_header hdr = {};

    hdr.ether_shost[ETHER_ADDR_LEN - 1] = 1;
    hdr.ether_dhost[ETHER_ADDR_LEN - 1] = 2;
    hdr.ether_type = htons(ETHERTYPE_IP);

    return hdr;
}();

const FakeData::agent_hdr FakeData::FakeAgentHdr = []() {
    agent_hdr hdr = {};

    hdr.hdr_ifindex     = htons(12);
    hdr.hdr_vrf         = htons(11);
    hdr.hdr_cmd         = htons(0);
    hdr.hdr_cmd_param   = htonl(0);
    hdr.hdr_cmd_param_1 = htonl(0);

    return hdr;
}();
