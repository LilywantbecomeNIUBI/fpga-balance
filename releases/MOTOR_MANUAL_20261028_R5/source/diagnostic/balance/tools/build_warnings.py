"""Warnings that invalidate a hardware-driving synthesis result."""
import re

def critical_warnings(log):
    return re.findall(r'^.*(?:Undeclared symbol|WARN\s+\((?:EX3638|EX1998|EX2565)\)).*$',log,re.M)
