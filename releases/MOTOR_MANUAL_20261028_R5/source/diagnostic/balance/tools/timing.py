import re,hashlib
def read_timing_reports(folder):
    """Gowin may omit the long HTML filename on Windows; text STA is authoritative too."""
    records=[]
    for name,html in [('motor_selftest_tr_content.html',True),('motor_selftest.tr',False)]:
        p=folder/name
        if not p.exists():continue
        data=p.read_text(errors='replace');counts={}
        for label in ('Setup','Hold'):
            pattern=(r'Numbers of '+label+r' Violated Endpoints</td>\s*<td[^>]*>(\d+)' if html else
                     r'<Numbers of '+label+r' Violated Endpoints>:\s*(\d+)')
            matches=re.findall(pattern,data)
            if len(matches)!=1:raise ValueError('Incomplete/ambiguous STA: '+str(p))
            counts[label.lower()+'_violations']=int(matches[0])
        records.append((p,counts))
    if not records:raise ValueError('No STA report')
    if any(c!=records[0][1] for _,c in records):raise ValueError('STA HTML/text disagreement')
    p,counts=records[0]
    return dict(counts,sta_report_file=p.name,sta_report_sha256=hashlib.sha256(p.read_bytes()).hexdigest())
