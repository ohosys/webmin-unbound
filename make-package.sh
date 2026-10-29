#!/bin/sh
# Build the installable Webmin module package unbound.wbm.gz
cd "$(dirname "$0")" && tar czf unbound.wbm.gz --owner=0 --group=0 unbound && ls -l unbound.wbm.gz
