#!/usr/bin/env python3

# PYTHONPATH is just a tirefire...
# https://github.com/NLnetLabs/unbound/issues/769
sys.path.insert(0, '/usr/lib/python3/dist-packages/')

import random
import time
from dns.exception import Timeout
import dns.query
from dns.rcode import REFUSED
from dns.rdatatype import SOA

def _peer(qstate):

    q = None
    rl = qstate.mesh_info.reply_list
    while rl:
        if rl.query_reply:
            q = rl.query_reply
            break
        rl = rl.next

    if q is None:
        return None

    addr = q.addr if q.family == 'ip6' else f'::ffff:{q.addr}'

    return f'[{addr}]:{q.port}'

def __warn(module_id, event, qstate, qdata, peer, reason):

    log_warn(f'cloud-managed-dns: peer={peer} name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str} reason={reason}')
    qstate.ext_state[module_id] = MODULE_FINISHED
    return True

def _timeout(module_id, event, qstate, qdata, peer):

    qstate.return_rcode = RCODE_SERVFAIL
    return __warn(module_id, event, qstate, qdata, peer, 'timeout')

def _refused(module_id, event, qstate, qdata, peer):

    qstate.return_rcode = RCODE_REFUSED
    return __warn(module_id, event, qstate, qdata, peer, 'refused')

def init_standard(module_id, env):

    return True

def deinit(module_id):

    return True

def operate(module_id, event, qstate, qdata):

    if event == MODULE_EVENT_MODDONE:
        qstate.ext_state[module_id] = MODULE_FINISHED
        return True

    peer = _peer(qstate)
    # internal query
    if peer is None:
        log_info(f'cloud-managed-dns: name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str} reason=INTERNAL')
        qstate.ext_state[module_id] = MODULE_WAIT_MODULE
        return True

    if event not in [ MODULE_EVENT_NEW, MODULE_EVENT_PASS ]:
        log_err(f'cloud-managed-dns: peer={peer} name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str} reason=UNEXPECTED event={event}')
        qstate.ext_state[module_id] = MODULE_ERROR
        return True

    if qstate.qinfo.qclass != RR_CLASS_IN:
        return _refused(module_id, event, qstate, qdata, peer)

    # by disabling recursion Azure returns REFUSED if this is a linked zone
    qname = qstate.qinfo.qname_str.lower()
    query = dns.message.make_query(qname=qname, rdtype=SOA, flags=0)
    response = None
    for i in range(3):
        try:
            response = dns.query.udp(q=query, where='168.63.129.16', timeout=0.1)
        except Timeout:
            time.sleep(0.1 * i + (random.randrange(0, 10) / 100))
            continue
        break
    if response is None:
        return _timeout(module_id, event, qstate, qdata, peer)
    if response.rcode() != REFUSED:
        return _refused(module_id, event, qstate, qdata, peer)

    log_info(f'cloud-managed-dns: peer={peer} name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str}')
    qstate.ext_state[module_id] = MODULE_WAIT_MODULE
    return True

def inform_super(module_id, qstate, superqstate, qdata):

    return True
