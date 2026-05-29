# Eindrapport — Evaluatie van LXC-containers als alternatief voor klassieke VM's op Proxmox binnen het VIC

**Auteur:** Dzhaner Halil
**Promotor:** Alexander Veldeman
**Co-promotor:** Robyn Moreno (Excentis)
**Academiejaar:** 2025–2026

---

## 1. Onderzoeksopzet in één pagina

Het onderzoek vergelijkt klassieke virtual machines (KVM) met LXC-containers binnen het Proxmox-platform van het Virtual IT Company (VIC), met als doel een onderbouwd beslissingskader op te leveren voor de keuze tussen beide technologieën per workload. De studie hanteert een gemengd onderzoeksdesign waarin kwantitatieve performantiemetingen (CPU, geheugen, schijf-I/O, netwerk, opstarttijd, backup) en kwalitatieve isolatie-evaluatie (privileged versus unprivileged LXC, namespaces, capabilities, seccomp) worden gecombineerd. De testopstelling bestond uit twee geneste Proxmox-testnodes (versie 8.x en 9.x) op één Dell PowerEdge R440. Per testnode werden drie guests uitgerold: één Ubuntu 24.04 LTS-VM, één unprivileged LXC en één privileged LXC. Elke prestatie-meting werd vijf keer herhaald, elke backup-meting drie keer voor twee datagroottes (5 GB en 12 GB).

## 2. Belangrijkste empirische bevindingen

### 2.1 Prestatieprofielen

| Metriek | VM (gem.) | LXC (gem.) | Verschil | $p$ |
|---|---:|---:|---:|---|
| CPU 1-thread (events/s) | 448 | 472 | +5,4 % | <0,001 *** |
| CPU 4-thread (events/s) | 1 302 | 1 370 | +5,3 % | <0,001 *** |
| Geheugendoorvoer (MB/s) | 18 122 | 20 435 | +12,8 % | <0,001 *** |
| Idle RAM-overhead (MB) | 540 | 146 | **−72,9 %** | <0,001 *** |
| Schijf read-IOPS (4K, QD32) | 20 429 | 58 647 | **+187,1 %** | <0,001 *** |
| Schijf write-IOPS (4K, QD32) | 8 757 | 25 142 | **+187,1 %** | <0,001 *** |
| Netwerk TCP (Gbps) | 25,5 | 27,3 | +7,1 % | n.s. |
| Webserver statisch (req/s) | 63 695 | 69 413 | +9,0 % | n.s. |
| Webserver dynamisch (req/s) | 247 | 262 | +6,2 % | gemengd |
| MariaDB OLTP (TPS) | 525 | 752 | **+43,2 %** | <0,001 *** |

LXC-containers leveren in nagenoeg elke gemeten dimensie vergelijkbare of betere prestaties dan VM's. De drie meest doorslaggevende verschillen zijn de geheugenfootprint (factor ~3,7 lager), de schijf-IOPS (factor ~2,9 hoger) en de database-throughput (factor ~1,4 hoger). De netwerk- en statische-webserver-prestaties verschillen niet significant: hier zit de bottleneck respectievelijk bij de software-bridge en bij het Nginx-proces zelf.

### 2.2 Opstarttijd

| Omgeving | Gemiddelde (s) | Std. dev. (s) | $n$ |
|---|---:|---:|---:|
| VM Proxmox 8 | 28,60 | 0,47 | 5 |
| VM Proxmox 9 | 28,60 | 0,33 | 5 |
| LXC Proxmox 8 | 3,66 | 0,04 | 5 |
| LXC Proxmox 9 | 3,82 | 0,11 | 5 |

LXC's starten ongeveer **acht keer sneller** dan VM's tot een werkend HTTP 200-antwoord. De spreiding is zeer klein (standaarddeviatie onder de halve seconde), wat aantoont dat de boot-procedure deterministisch is.

### 2.3 Beveiliging en isolatie

| Eigenschap | VM | LXC unpriv. | LXC priv. |
|---|---|---|---|
| Container runtime | not-found | lxc | lxc |
| User-namespace | n.v.t. | ja (UID 0 → 100 000) | nee |
| AppArmor | n.v.t. | geen (default) | geen (default) |
| Bounding capabilities | 37 | 37 (effectief beperkt) | 30 |
| Seccomp-filter | nee | ja | ja |
| Geblokkeerde syscalls | 1 | 18 | 7 |

VM's bieden de sterkste isolatie omdat de hypervisor de grens vormt en niet de gedeelde kernel. Unprivileged LXC's geven een acceptabel beveiligingsniveau dankzij UID-remapping en seccomp-filtering. Privileged LXC's missen de user-namespace en zijn daardoor ongeschikt voor multi-tenant scenario's.

### 2.4 Backup en restore

| Omgeving | Dataset | Full (s) | Incrementeel (s) | Restore (s) |
|---|---:|---:|---:|---:|
| VM Pmx 8 | 5 GB | 40,7 | 2,9 | 35,2 |
| VM Pmx 8 | 12 GB | 67,1 | 3,4 | 55,9 |
| VM Pmx 9 | 5 GB | 40,5 | 2,7 | 31,7 |
| VM Pmx 9 | 12 GB | 65,9 | 2,7 | 61,1 |
| LXC Pmx 8 | 5 GB | 37,7 | 29,2 | 61,4 |
| LXC Pmx 8 | 12 GB | 66,8 | 50,3 | 128,8 |
| LXC Pmx 9 | 5 GB | 34,4 | 25,1 | 58,5 |
| LXC Pmx 9 | 12 GB | 66,5 | 43,9 | 129,9 |

Full backups duren voor VM en LXC ongeveer even lang. De grote contrasten zitten in incrementele backup (VM ~3 s, LXC 25–50 s) en restore (VM ~33–61 s, LXC ~59–130 s). De factor 9 tot 16 voor incrementele backups is direct toe te schrijven aan het verschil tussen block-level (VM met dirty bitmap) en file-level (LXC met file-walking) backup-strategie.

## 3. Beslissingskader

Het volledige beslissingskader staat in `graphics/decision_tree.svg` (en wordt in de LaTeX als figuur opgenomen). De zeven sequentiële vragen zijn:

1. **Is het guest-OS Linux?** — Nee → VM (eigen kernel verplicht).
2. **Vereist de service kernel-modules of speciale kernel-features?** — Ja → VM (kernel-toegang noodzakelijk).
3. **Multi-tenant met externe gebruikers of strikte compliance?** — Ja → VM (sterkste isolatie via hypervisor).
4. **Werklast met >50 GB live data en frequente incrementele backups?** — Ja → VM (block-level + dirty bitmap, ~10× snellere incrementele).
5. **Disk-I/O- of database-zware workload?** — Ja → LXC unprivileged (+187 % IOPS, +44 % DB-TPS).
6. **Veel kleine services en RAM-druk op de host?** — Ja → LXC unprivileged (−73 % RAM-overhead).
7. **Snelle (auto)scaling of snelle herstart belangrijk?** — Ja → LXC unprivileged (~28 s vs ~3,7 s boot).
8. **Default voor alle overige Linux-workloads:** LXC unprivileged.

Privileged LXC blijft enkel toelaatbaar in single-tenant zones met functionele noodzaak.

## 4. Best practices voor LXC-deployment in het VIC

De praktijkervaring tijdens de proof-of-concept levert vijf concrete aanbevelingen op. Containers moeten standaard unprivileged worden uitgerold; privileged-status is een uitzondering die expliciet gemotiveerd moet worden. Het AppArmor-profiel `lxc-container-default-cgns` moet expliciet in de containerconfiguratie geactiveerd worden, omdat de community-scripts dit standaard niet aanzetten. Voor LXC's met datasets boven de 20 GB is een dagelijkse full backup verkieslijker dan een incrementeel schema, omdat de file-walking overhead exponentieel groeit met het aantal bestanden. Vóór elke onderhoudsoperatie wordt systematisch een `baseline`-snapshot gemaakt, wat rollback onder een seconde houdt en menselijke fouten neutraliseert. De PBS-garbage collection moet via een `systemd`-timer minstens dagelijks draaien om de chunk-store onder controle te houden, ook met de standaard 24-uurs atime-grace.

## 5. Beperkingen en vervolgonderzoek

Belangrijkste beperkingen: de geneste virtualisatieopzet begrenst de absolute meetwaarden, vooral voor netwerk en schijf; de "large"-dataset werd op 12 GB beperkt in plaats van 50 GB door de thin-pool-capaciteit; de community-scripts werden gepind op één commit; geen kwalitatieve interviews met VIC-beheerders.

Vervolgrichtingen: bare-metal validatie van het beslissingskader, langetermijnmonitoring van een eerste batch productie-LXC's, integratie van LXC en Kubernetes als gelaagd platform, en uitbreiding van de vergelijking naar Incus en andere OCI-conforme runtimes.

## 6. Repository-structuur

```
latex_hogent_bachproef/
├── bachproef/
│   ├── FamilienaamVoornaamBP.tex        % Hoofdbestand
│   ├── inleiding.tex                     % Hoofdstuk 1
│   ├── standvanzaken.tex                 % Hoofdstuk 2
│   ├── methodologie.tex                  % Hoofdstuk 3 (bijgewerkt)
│   ├── resultaten.tex                    % Hoofdstuk 4 (NIEUW)
│   └── conclusie.tex                     % Hoofdstuk 5 (bijgewerkt)
├── graphics/
│   ├── decision_tree.svg                 % Beslissingskader (NIEUW)
│   └── analysis/                         % Boxplots en barplots (13 PNG's)
├── data/
│   ├── performance_summary.csv           % Geaggregeerde prestatiedata
│   ├── ttests.csv                        % Statistische toetsen
│   ├── boot_results_pmx{8,9}.csv         % Boot-tijd per host
│   ├── backup_results_pmx{8,9}.csv       % Backup-tijden per host
│   └── *.csv                             % Verdere geaggregeerde sets
├── scripts/
│   ├── setup_tools.sh                    % Tool-install per guest
│   ├── setup_workloads.sh                % Nginx/MariaDB/PHP-FPM per guest
│   ├── run_benchmarks.sh                 % Performance-iteratie binnen guest
│   ├── run_iteration.sh                  % Wrapper voor 1 cyclus op host
│   ├── run_cycle_pmx{8,9}.sh             % Volledige host-batch
│   ├── measure_boot.sh                   % Boot-tijd CSV op host
│   ├── run_security_tests.sh             % Beveiligingsaudit binnen guest
│   ├── run_backup_iteration.sh           % Full + incr + restore + prune
│   ├── run_backup_cycle_pmx{8,9}.sh      % Volledige backup-batch
│   ├── deploy_to_guest.sh                % Push + run-helper
│   ├── push_only.sh                      % Push-alleen-helper
│   ├── pull_results.sh                   % Tar + base64 pull-helper
│   ├── pull_security.sh                  % Idem voor security-resultaten
│   ├── host_monitor.sh                   % iostat/vmstat/mpstat parallel
│   └── analyze.py                        % Aggregatie + statistiek + plots
└── EINDRAPPORT.md                        % Dit bestand
```

## 7. Reproductie

```bash
# Op een willekeurige machine met Proxmox VE en de scripts in /root/bp/scripts/:
./scripts/setup_tools.sh                                   # in elke guest
./scripts/setup_workloads.sh                               # in elke main guest
./scripts/run_cycle_pmx8.sh                                # op pve8
./scripts/run_cycle_pmx9.sh                                # op pve9
./scripts/measure_boot.sh qm 100 10.0.110.1 1 VM_pmx8      # × 5 per omgeving
./scripts/run_security_tests.sh LXC_unpriv_pmx8            # × 1 per type
./scripts/run_backup_cycle_pmx8.sh                         # op pve8
./scripts/run_backup_cycle_pmx9.sh                         # op pve9

# Aggregatie + grafieken (op laptop):
python3 scripts/analyze.py
```

De PBS-LXC moet vooraf worden uitgerold (community-script `ct/proxmox-backup-server.sh`) en als storage `pbs-bp` worden toegevoegd aan beide testnodes.
