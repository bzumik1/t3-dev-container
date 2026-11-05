# T3 Dev

Vývojový server v kontejneru pro [T3 Code](https://t3.codes) a AI agenty (Codex, Claude Code, OpenCode). Chová se jako samostatný Linux server: má vlastní Docker, Javu, Node a všechny běžné nástroje, a přitom co nejméně ohrožuje hostitele, na kterém běží i jiné aplikace. Za běhu v něm není žádný root.

Postavené pro ZimaOS, ale funguje na libovolném Linuxu s Dockerem.

## Co v něm je

- **T3 Code** s T3 Connect: server je dostupný z Macu, mobilu i webu bez otevřeného portu.
- **Agenti:** Codex, Claude Code a OpenCode. Instalují se při prvním startu do domovského adresáře a dál se aktualizují samy. Přihlášení přežije restart i nový image.
- **Docker uvnitř** (rootless) s Compose a Buildx: `docker run`, `docker compose` i Testcontainers.
- **Jazyky:** Java 25 (Temurin), Node 24 s npm a pnpm, systémové knihovny pro Playwright Chromium. Další verze a jazyky přes [`mise`](https://mise.jdx.dev) bez roota.
- **Nástroje:** git, gh, build-essential, jq, yq, ripgrep, fd, fzf, tmux, vim, htop, zsh se starship, bubblewrap a další.
- **SSH** na portu 2222, jen klíčem (veřejné klíče z GitHubu).

## Instalace na ZimaOS

1. **Stáhněte bezpečnostní profil** (jednorázově, přes SSH na ZimaOS):

   ```bash
   sudo mkdir -p /DATA/AppData/t3-dev
   sudo curl -fsSL -o /DATA/AppData/t3-dev/seccomp.json https://raw.githubusercontent.com/bzumik1/t3-dev-container/main/seccomp.json
   echo "f9300ccf2722f9c3b456d3fbbca16e4595f1b7c4717ae1fcf5506c781c78a6f1  /DATA/AppData/t3-dev/seccomp.json" | sha256sum -c -
   ```

2. **Nainstalujte aplikaci:** v ZimaOS App Store → **Custom Install** → import, vložte obsah [`compose.yml`](compose.yml). U služby `t3-dev` vyplňte `SERVER_NAME` (např. `HP Prodesk`), u služby `t3-dev-net` `GITHUB_USER`, pokud chcete SSH. Nic jiného měnit nemusíte.

3. **Přihlaste T3 Connect:** otevřete log kontejneru `t3-dev`. Při prvním startu se tam objeví odkaz `https://accounts.t3.codes/device?...` a kód. Otevřete ho a schvalte svým účtem. Schvalujte jen odkaz na `accounts.t3.codes` a jen hned po prvním startu, kdy ho čekáte: do logu může psát i kód uvnitř kontejneru. Server se pak objeví v T3 na všech vašich zařízeních.

4. **Přihlaste agenty a GitHub:** v T3 otevřete nové vlákno na tomto serveru a přihlaste Codex (`codex login`), Claude (`claude auth login`), OpenCode (`opencode auth login`) a GitHub (`gh auth login`). Všechny používají přihlášení přes odkaz a kód, nic se nezadává do proměnných.

Bez ZimaOS stačí stáhnout `compose.yml` a `seccomp.json` do jedné složky, upravit cesty a spustit `docker compose up -d`.

## Jak je to poskládané

`compose.yml` spouští tři kontejnery ze stejného image:

| Kontejner | Běží jako | Oprávnění | Úkol |
|---|---|---|---|
| `t3-dev-init` | root, jednorázově | jen `CHOWN`, bez sítě, systém jen pro čtení | Předá kořeny svazků uživateli `dev` a skončí. |
| `t3-dev-net` | root | jen `NET_ADMIN`, systém jen pro čtení | Drží síť a nastaví firewall. Pak už jen čeká. |
| `t3-dev` | `dev` (UID 1000) od začátku | jen `SETUID`/`SETGID` v omezující sadě | Docker, SSH, T3 a agenti. Sdílí síť s `t3-dev-net`. |

`t3-dev` nastartuje, až `t3-dev-init` doběhl a firewall v `t3-dev-net` je nastavený. Když firewall nastavit nejde, `t3-dev` se nespustí.

## Nastavení

Všechny proměnné jsou nepovinné.

| Proměnná | Služba | Výchozí | Význam |
|---|---|---|---|
| `SERVER_NAME` | `t3-dev` | `T3 Dev` | Jméno serveru v T3 a T3 Connect |
| `GIT_NAME`, `GIT_EMAIL` | `t3-dev` | prázdné | Autor commitů |
| `TZ` | `t3-dev` | `Europe/Prague` | Časové pásmo |
| `T3_CONNECT` | `t3-dev` | `true` | Přihlášení k T3 Connect při prvním startu |
| `GITHUB_USER` | `t3-dev-net` | prázdné | Čí veřejné klíče z GitHubu smí přes SSH. Prázdné = SSH vypnuté |
| `SSH_AUTHORIZED_KEYS` | `t3-dev-net` | prázdné | Další veřejné SSH klíče, jeden na řádek |
| `FIREWALL` | `t3-dev-net` | `on` | `off` vypne blokování domácí sítě (nedoporučeno) |
| `FIREWALL_ALLOW` | `t3-dev-net` | prázdné | Výjimky z firewallu, např. `192.168.1.50:8080/tcp 10.0.5.0/24`. Bez portu nejvýš rozsah /24, s portem /16. |
| `FIREWALL_EXPECTED` | `t3-dev` | `on` | Při `FIREWALL=off` nastavte také na `off`, jinak `t3-dev` čeká na firewall a nespustí se. |

Tajné údaje (tokeny, API klíče) do proměnných nepatří: ZimaOS je ukazuje v UI a vidí je `docker inspect`. Přihlášení agentů se ukládá do svazku `home`.

### Svazky

| Hostitel | Kontejner | Obsah |
|---|---|---|
| `/DATA/AppData/t3-dev/home` | `/home/dev` | Domovský adresář: přihlášení, agenti, nastavení, cache. Zálohovat. |
| `/DATA/AppData/t3-dev/workspace` | `/workspace` | Projekty. Zálohovat. |
| `/DATA/AppData/t3-dev/docker` | `/var/lib/t3-dev/docker` | Data Dockeru uvnitř (image, kontejnery). Nezálohovat, při zálohování zachovat číselné vlastníky (100000+). Jednou denně se čistí stará cache a nepoužité image. |
| `/DATA/AppData/t3-dev/shared` | `/etc/t3-dev/shared` | Povolené SSH klíče a značka firewallu. Zapisuje jen `t3-dev-net` (root), `t3-dev` ho vidí jen pro čtení. |

## SSH

```bash
ssh -p 2222 dev@<adresa-zimaos>
```

Přihlásit se lze jen klíčem z `github.com/<GITHUB_USER>.keys` nebo z `SSH_AUTHORIZED_KEYS`. Kořenem důvěry je váš účet GitHub: kdo má jeho veřejné klíče pod kontrolou (nebo token s `admin:public_key`), dostane SSH. Když účet přejmenujete, `GITHUB_USER` upravte, jinak by klíče mohl dodat nový majitel starého jména. Klíče načítá `t3-dev-net` při každém startu do souboru, který `t3-dev` vidí jen pro čtení, takže si žádný proces v kontejneru nemůže přidat vlastní klíč. Klíč smazaný na GitHubu nebo odebraný z `SSH_AUTHORIZED_KEYS` přestane platit po restartu `t3-dev-net`. Uložené klíče se použijí jen při výpadku GitHubu, jen pro stejného uživatele a nejdéle 7 dní. Port 2222 se otevře, jen když existuje aspoň jeden klíč. 

Doporučené nastavení klienta (`~/.ssh/config`), s klíčem jen pro tento server:

```text
Host t3-dev
  HostName <adresa-zimaos>
  Port 2222
  User dev
  IdentityFile ~/.ssh/t3-dev
  IdentitiesOnly yes
  ForwardAgent no
  PasswordAuthentication no
  KbdInteractiveAuthentication no
```

Server se nikdy neptá na heslo. sshd běží jako `dev`, takže kompromitovaný proces v kontejneru by ho mohl nahradit vlastním. Výzva k zadání hesla proto znamená podvržený server. Funguje přesměrování portů z kontejneru k vám, třeba `ssh -p 2222 -L 4200:localhost:4200 dev@...` pro dev server Angularu. Přesměrovat jde jen na `localhost` kontejneru, ne do sítě. Opačný směr (`-R`) je vypnutý.

## Zabezpečení

Kontejner **není privilegovaný**, nemá přístup k Dockeru hostitele a **za běhu v něm není žádný root**:

- **Bez roota.** `t3-dev` běží celý jako `dev`. Výchozí uživatel image je `dev`, takže i příkazy spuštěné přes Docker a healthcheck jdou bez roota. Před startem služeb kontejner ověří vlastní sandbox (oprávnění, seccomp, IPv6, firewall, limity) a když něco chybí, nespustí se. V image není `sudo` ani žádný setuid program. `newuidmap`/`newgidmap` mají jen úzké souborové oprávnění (`cap_setuid`, `cap_setgid`) a SSH, T3, agenti ani údržba je použít nemůžou: běží s `no_new_privs` a navíc ve vlastním uživatelském jmenném prostoru, takže nemůžou ani přes `ptrace` převzít procesy, které `no_new_privs` nemají. Jsou to jen Docker démon (rootlesskit, slirp4netns), supervisord a tini. Spouštějí se jen ze systémových cest a bez Python modulů z domovského adresáře.
- **Rootless Docker.** Démon běží jako `dev` ve vlastním uživatelském jmenném prostoru. Root ve vnořeném kontejneru je navenek `dev`. Kontejnery s `--network host` nevidí loopback `t3-dev` (T3 server).
- **Vlastní seccomp profil** ([`seccomp.json`](seccomp.json), generuje ho [`scripts/generate-seccomp.mjs`](scripts/generate-seccomp.mjs)): výchozí profil Dockeru plus jen volání pro jmenné prostory a mount. Pořád blokuje `bpf`, `perf_event_open`, moduly jádra, `kexec`, `userfaultfd`, `io_uring` a klíčenku.
- **Firewall** (`t3-dev-net`): internet je volný. Domácí síť, Docker hostitel, ostatní kontejnery a Tailscale (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, link-local) jsou blokované, a to i pro vnořené kontejnery. Blokovaná jsou i spojení otevřená ještě před nahráním pravidel. Dovnitř vede jen SSH, a to jen když je zapnuté. IPv6 je vypnuté. `dev` pravidla změnit nemůže. DNS jde přes veřejné resolvery (Quad9), ne přes domácí síť.
- **Limity:** 8 GB RAM, 10 CPU s nižší prioritou než ostatní aplikace, 4096 procesů, omezené logy. Při nedostatku paměti na hostiteli jádro obětuje nejdřív `t3-dev`.
- **Ochrana proti zavirovaným balíčkům:** npm neinstaluje skripty balíčků a bere jen verze starší 3 dnů, pnpm a uv také. Nastavení je v prostředí, takže ho klonovaný projekt nevypne a nepřesměruje na jiný registr. Projekt ale může cooldown pro konkrétní balíčky výslovně vypnout (`minimumReleaseAgeExclude` v `pnpm-workspace.yaml`, `exclude-newer-package` v `pyproject.toml`). Při review takové řádky hlídejte. Je to bezpečnostní pás, ne sandbox. Platí i při sestavení image.
- **T3 Code** poslouchá jen uvnitř kontejneru, ven vede jen tunel T3 Connect.

**Kompromisy, bez kterých Docker uvnitř nejde:** `t3-dev` má vypnutý profil AppArmor a maskování `/proc` (`apparmor=unconfined`, `systempaths=unconfined`) a smí vytvářet uživatelské jmenné prostory. Chyba jádra v těchto oblastech by mohla vést k úniku na hostitele, proto udržujte ZimaOS aktualizovaný. ZimaOS 1.8.0 má jádro 6.18.9 se známými chybami ([IceWhaleTech/ZimaOS#641](https://github.com/IceWhaleTech/ZimaOS/issues/641)). Silnější izolaci dá jen virtuální stroj.

**Hlavní riziko není únik z kontejneru, ale krádež tokenů** (Codex, Claude, GitHub) přes zavirovaný balíček nebo prompt injection. Pomáhá ochrana balíčků výše a **GitHub token s co nejmenšími právy**: agentům dejte token bez přístupu k tomuto repozitáři a k produkčním repozitářům, ať nemůžou podstrčit image, který pak poběží na vašem serveru.

## Aktualizace

Image se každý týden přestaví s bezpečnostními aktualizacemi (`ghcr.io/bzumik1/t3-dev-container:latest`). Publikuje se jen tehdy, když projdou všechny testy. Na ZimaOS ho aktualizujete v UI aplikace, nebo přes SSH:

```bash
sudo docker pull ghcr.io/bzumik1/t3-dev-container:latest
```

a restartem aplikace.

Když nový image potřebuje nový `compose.yml` (proměnná `T3_DEV_COMPOSE`), kontejnery se nespustí a v logu je „compose.yml je zastaralý“. Pak importujte aktuální `compose.yml` a stáhněte `seccomp.json` znovu podle kroku 1 instalace. Po přechodu z verze 3 můžete smazat nepoužívaný adresář se starými klíči: `sudo rm -rf /DATA/AppData/t3-dev/ssh`. Agenti se aktualizují sami, ručně `t3-dev update-agents`.

## Pomocník `t3-dev`

```text
t3-dev status           stav služeb, verze nástrojů a T3 Connect
t3-dev install-agents   nainstaluje chybějící agenty
t3-dev update-agents    aktualizuje agenty
t3-dev connect          znovu spustí přihlášení k T3 Connect
t3-dev restart <služba> restartuje dockerd, sshd nebo t3
```

Z hostitele: `sudo docker exec -it t3-dev t3-dev shell` (shell se stejnými omezeními jako agenti).

**Nepoužívejte `docker exec -u 0` ani `docker cp` do `t3-dev`.** Kvůli vypnutým maskám `/proc` (nutné pro Docker uvnitř) by root v tomto kontejneru mohl měnit nastavení jádra hostitele. `docker cp` má na Dockeru 27 chybu CVE-2026-42306.

## Řešení problémů

- **Kontejner nenastartuje, v logu je chyba seccomp:** chybí `/DATA/AppData/t3-dev/seccomp.json` (krok 1 instalace).
- **`t3-dev` nenastartuje a `t3-dev-net` hlásí „nelze nastavit firewall“:** chybí oprávnění `NET_ADMIN`; použijte `compose.yml` beze změn.
- **Docker uvnitř nejede:** `t3-dev status` a log kontejneru. UI ZimaOS musí zachovat `security_opt`, `cap_add` a `devices` z `compose.yml`. Pokud je zahodí, nainstalujte přes SSH: `sudo docker compose -f compose.yml up -d`.
- **Odkaz na T3 Connect vypršel:** restartujte kontejner `t3-dev`, objeví se nový.
- **Po restartu `t3-dev-net` nemá `t3-dev` síť:** restartujte i `t3-dev` (sdílí síť s `t3-dev-net`).

## Vývoj

Změny přes PR. CI sestaví image a v desítkách souběžných jobů ho spustí se stejnými volbami jako `compose.yml`: izolace a oprávnění, Docker uvnitř, firewall, SSH, seccomp, limity, nástroje, Testcontainers v Javě i Node, agenti, restart a aktualizace, Docker 27.5.1 jako na ZimaOS a skutečný projekt (backend, frontend, e2e a celý stack). Pak image proskenuje Trivy a z `main` ho publikuje do ghcr.io s atestací původu.
