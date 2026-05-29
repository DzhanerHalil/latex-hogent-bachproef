"""BP Fase 4 — analyse alle data + statistiek + grafieken"""
import json, re
from pathlib import Path
import pandas as pd
from scipy import stats
import matplotlib.pyplot as plt
import seaborn as sns

DATA = Path('~/bp_data').expanduser()
OUT = DATA / 'analysis'
OUT.mkdir(exist_ok=True)
plt.style.use('seaborn-v0_8-whitegrid')

# === parsers ===
def cpu_eps(p): m=re.search(r'events per second:\s+([\d.]+)',p.read_text()); return float(m.group(1)) if m else None
def mem_mibs(p): m=re.search(r'(\d+\.\d+) MiB/sec',p.read_text()); return float(m.group(1)) if m else None
def fio(p):
    j=json.loads(p.read_text())['jobs'][0]
    return {'fio_read_iops':j['read']['iops'],'fio_write_iops':j['write']['iops'],
            'fio_read_bw_kibs':j['read']['bw'],'fio_write_bw_kibs':j['write']['bw']}
def iperf_tcp(p): return json.loads(p.read_text())['end']['sum_received']['bits_per_second']/1e9
def wrk_rps(p): m=re.search(r'Requests/sec:\s+([\d.]+)',p.read_text()); return float(m.group(1)) if m else None
def oltp(p): m=re.search(r'transactions:\s+\d+\s+\(([\d.]+)\s+per sec',p.read_text()); return float(m.group(1)) if m else None
def rss(p):
    t=p.read_text()
    a=re.search(r'MemAvailable:\s+(\d+)',t); b=re.search(r'MemTotal:\s+(\d+)',t)
    return (int(b.group(1))-int(a.group(1)))/1024 if a and b else None  # MB

# === load runs ===
def load_run(env, run, host):
    base = DATA / host / 'results' / env / f'run_{run}'
    if not base.exists(): return None
    r = {'env':env, 'run':run, 'host':host}
    files = {'cpu_1_thread.txt':('cpu_1t_eps',cpu_eps), 'cpu_4_threads.txt':('cpu_4t_eps',cpu_eps),
             'memory.txt':('mem_mibs',mem_mibs), 'network_tcp.json':('net_tcp_gbps',iperf_tcp),
             'web_static.txt':('wrk_static_rps',wrk_rps), 'web_dynamic.txt':('wrk_dynamic_rps',wrk_rps),
             'web_proxy.txt':('wrk_proxy_rps',wrk_rps), 'db_oltp.txt':('oltp_tps',oltp),
             'idle_baseline.txt':('idle_used_mb',rss)}
    for fn,(key,fn_parse) in files.items():
        f = base/fn
        if f.exists():
            try: r[key]=fn_parse(f)
            except: r[key]=None
    f = base/'disk_io.json'
    if f.exists():
        try: r.update(fio(f))
        except: pass
    return r

rows=[]
for env in ['vm-pmx8','lxc-pmx8']:
    for r in range(1,6):
        d=load_run(env,r,'pmx8'); 
        if d: rows.append(d)
for env in ['vm-pmx9','lxc-pmx9']:
    for r in range(1,6):
        d=load_run(env,r,'pmx9')
        if d: rows.append(d)

if len(rows) > 0:
    df = pd.DataFrame(rows)
    df.to_csv(OUT/'performance_aggregated.csv', index=False)
    print(f"Performance: {len(df)} runs geladen")
    print(df.groupby('env').size())

    # === stats summary ===
    metrics = ['cpu_1t_eps','cpu_4t_eps','mem_mibs','fio_read_iops','fio_write_iops',
               'net_tcp_gbps','wrk_static_rps','wrk_dynamic_rps','oltp_tps','idle_used_mb']
    
    # Filter out metrics that have absolutely no data (e.g. all NaNs)
    available_metrics = [m for m in metrics if m in df.columns and df[m].notna().sum() > 0]
    
    if available_metrics:
        summary = df.groupby('env')[available_metrics].agg(['mean','std','count']).round(2)
        print("\n=== Performance per environment (mean ± std) ===")
        print(summary)
        summary.to_csv(OUT/'performance_summary.csv')

        # === t-tests VM vs LXC per Pmx version ===
        print("\n=== T-tests VM vs LXC ===")
        ttest_rows=[]
        for ver in ['pmx8','pmx9']:
            for m in available_metrics:
                vm = df[df['env']==f'vm-{ver}'][m].dropna()
                lxc = df[df['env']==f'lxc-{ver}'][m].dropna()
                if len(vm)>=3 and len(lxc)>=3:
                    t,p = stats.ttest_ind(vm, lxc)
                    pct_diff = (lxc.mean()-vm.mean())/vm.mean()*100
                    sig = '***' if p<0.001 else '**' if p<0.01 else '*' if p<0.05 else 'ns'
                    ttest_rows.append({'pmx':ver,'metric':m,'vm_mean':vm.mean(),'lxc_mean':lxc.mean(),
                                      'pct_diff':pct_diff,'p_value':p,'significance':sig})
                    print(f"  {ver} {m:20s}: VM={vm.mean():>8.1f}  LXC={lxc.mean():>8.1f}  Δ={pct_diff:+6.1f}%  p={p:.4f} {sig}")
        pd.DataFrame(ttest_rows).to_csv(OUT/'ttests.csv', index=False)

        # === boxplots performance ===
        for m in available_metrics:
            plt.figure(figsize=(8,5))
            sns.boxplot(x='env', y=m, data=df)
            sns.swarmplot(x='env', y=m, data=df, color='black', size=4, alpha=0.5)
            plt.title(m); plt.xticks(rotation=15); plt.tight_layout()
            plt.savefig(OUT/f'box_{m}.png', dpi=150); plt.close()
else:
    print("Geen performance runs gevonden.")

# === boot data ===
boot_dfs=[]
for h in ['pmx8','pmx9']:
    p = DATA/h/'boot_results.csv'
    if p.exists(): boot_dfs.append(pd.read_csv(p))

if len(boot_dfs) > 0:
    df_boot = pd.concat(boot_dfs, ignore_index=True)
    df_boot['boot_seconds'] = pd.to_numeric(df_boot['boot_seconds'], errors='coerce')
    boot_sum = df_boot.groupby('label')['boot_seconds'].agg(['mean','std','count']).round(3)
    print("\n=== Boot tijd ===")
    print(boot_sum)
    boot_sum.to_csv(OUT/'boot_summary.csv')

    plt.figure(figsize=(8,5))
    sns.boxplot(x='label', y='boot_seconds', data=df_boot)
    plt.ylabel('Boot tijd (s)'); plt.xticks(rotation=15); plt.tight_layout()
    plt.savefig(OUT/'box_boot.png', dpi=150); plt.close()
else:
    print("\n[INFO] Geen boot_results.csv bestanden gevonden. Boot-analyse overgeslagen.")

# === backup data ===
bk_dfs=[]
for h in ['pmx8','pmx9']:
    p = DATA/h/'backup_results.csv'
    if p.exists(): bk_dfs.append(pd.read_csv(p))

if len(bk_dfs) > 0:
    df_bk = pd.concat(bk_dfs, ignore_index=True)
    if 'run' in df_bk.columns:
        df_bk = df_bk[df_bk['run']!=99]  # gooi sanity weg
    df_bk['seconds'] = pd.to_numeric(df_bk['seconds'], errors='coerce')
    bk_sum = df_bk.groupby(['label','size_gb','phase'])['seconds'].agg(['mean','std','count']).round(2)
    print("\n=== Backup tijd per (env, size, phase) ===")
    print(bk_sum)
    bk_sum.to_csv(OUT/'backup_summary.csv')

    # Backup grafiek - grouped barplot (Only if 12GB exists)
    if not df_bk[df_bk['size_gb']==12].empty:
        plt.figure(figsize=(14,6))
        sns.barplot(x='phase', y='seconds', hue='label', data=df_bk[df_bk['size_gb']==12], errorbar='sd')
        plt.title('Backup tijden bij 12 GB dataset (mean ± std)')
        plt.tight_layout(); plt.savefig(OUT/'backup_12gb.png', dpi=150); plt.close()

    # Backup grafiek - grouped barplot (Only if 5GB exists)
    if not df_bk[df_bk['size_gb']==5].empty:
        plt.figure(figsize=(14,6))
        sns.barplot(x='phase', y='seconds', hue='label', data=df_bk[df_bk['size_gb']==5], errorbar='sd')
        plt.title('Backup tijden bij 5 GB dataset (mean ± std)')
        plt.tight_layout(); plt.savefig(OUT/'backup_5gb.png', dpi=150); plt.close()
else:
    print("\n[INFO] Geen backup_results.csv bestanden gevonden. Backup-analyse overgeslagen.")

print(f"\n✓ Script voltooid. Alle beschikbare output staat in: {OUT}")
