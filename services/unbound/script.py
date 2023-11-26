#!/usr/bin/env python3

# Azure Unbound module to infer when a zone is private and linked
# Copyright (C) 2023, coreMem Limited <info@coremem.com>
# SPDX-License-Identifier: AGPL-3.0-only

# PYTHONPATH is just a tirefire...
# https://github.com/NLnetLabs/unbound/issues/769
sys.path.insert(0, '/usr/lib/python3/dist-packages/')

import random
import time
from dns.exception import Timeout
import dns.query
from dns.rcode import NOERROR, NXDOMAIN
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

def _error(module_id, event, qstate, qdata, peer, rcode=RCODE_SERVFAIL, reason=None):

    if reason is None:
        reason = 'refused' if rcode == RCODE_REFUSED else f'error {rcode}'
    log_warn(f'cloud-managed-dns: peer={peer} name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str} reason={reason}')
    qstate.return_rcode = rcode
    qstate.ext_state[module_id] = MODULE_FINISHED
    return True

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
        return _error(module_id, event, qstate, qdata, peer, RCODE_REFUSED)

    qname = qstate.qinfo.qname_str.lower()
    query = dns.message.make_query(qname=qname, rdtype=SOA)
    response = None
    for i in range(3):
        try:
            response = dns.query.udp(q=query, where='168.63.129.16', timeout=0.1)
        except Timeout:
            time.sleep(0.1 * i + (random.randrange(0, 10) / 100))
            continue
        break
    if response is None:
        return _error(module_id, event, qstate, qdata, peer, RCODE_SERVFAIL, 'timeout')
    if response.rcode() not in (NOERROR, NXDOMAIN):
        return _error(module_id, event, qstate, qdata, peer, RCODE_SERVFAIL, f'error ({response.rcode().name})')
    if not (len(response.answer) == 1 and response.answer[0][0].rdtype == SOA and response.answer[0][0].mname != 'azureprivatedns.net.'):
        return _error(module_id, event, qstate, qdata, peer, RCODE_REFUSED)

    log_info(f'cloud-managed-dns: peer={peer} name={qstate.qinfo.qname_str} class={qstate.qinfo.qclass_str} type={qstate.qinfo.qtype_str}')
    qstate.ext_state[module_id] = MODULE_WAIT_MODULE
    return True

def inform_super(module_id, qstate, superqstate, qdata):

    return True
