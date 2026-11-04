# T3 Dev

Vývojový server v kontejneru pro [T3 Code](https://t3.codes) a AI agenty (Codex, Claude Code, OpenCode). Chová se jako samostatný Linux server: má vlastní Docker, Javu, Node a všechny běžné nástroje, a přitom co nejméně ohrožuje hostitele, na kterém běží i jiné aplikace.

Postavené pro ZimaOS, ale funguje na libovolném Linuxu s Dockerem.

## Co v něm je

- **T3 Code** s T3 Connect: server je dostupný z Macu, mobilu i webu bez otevřeného portu.
- **Agenti:** Codex, Claude Code a OpenCode. Instalují se při prvním startu do domovského adresáře a dál se aktualizují samy. Přihlášení přežije restart i nový image.
- **Docker uvnitř** (rootless) s Compose a Buildx: `docker run`, `docker compose` i Testcontainers.
- **Jazyky:** Java 25 (Temurin), Node 24 s npm a pnpm, systémové knihovny pro Playwright Chromium. Další verze a jazyky přes [`mise`](https://mise.jdx.dev) bez roota.
- **Nástroje:** git, gh, build-essential, jq, yq, ripgrep, fd, fzf, tmux, vim, htop, zsh se starship a další.
- **SSH** na portu 2222, jen klíčem (veřejné klíče z GitHubu).

## Instalace na ZimaOS

1. **Stáhněte bezpečnostní profil** (jednorázově, přes SSH na ZimaOS):

   ```bash
   sudo mkdir -p /DATA/AppData/t3-dev
   sudo curl -fsSL -o /DATA/AppData/t3-dev/seccomp.json https://raw.githubusercontent.com/bzumik1/t3-dev-container/main/seccomp.json
   ```

2. **Nainstalujte aplikaci:** v ZimaOS App Store → **Custom Install** → import, vložte obsah [`compose.yml`](compose.yml). V nastavení vyplňte aspoň `SERVER_NAME` (např. `HP Prodesk`) a `GITHUB_USER`. Nic jiného měnit nemusíte.

3. **Přihlaste T3 Connect:** otevřete log kontejneru `t3-dev`. Při prvním startu se tam objeví odkaz `https://accounts.t3.codes/device?...` a kód. Otevřete ho a schvalte svým účtem. Server se pak objeví v T3 na všech vašich zařízeních.

4. **Přihlaste agenty a GitHub:** v T3 otevřete nové vlákno na tomto serveru a přihlaste Codex (`codex login`), Claude (`claude auth login`), OpenCode (`opencode auth login`) a GitHub (`gh auth login`). Všechny používají přihlášení přes odkaz a kód, nic se nezadává do proměnných.

Bez ZimaOS stačí stáhnout `compose.yml` a `seccomp.json` do jedné složky, upravit cesty a spustit `docker compose up -d`.

## Nastavení

Všechny proměnné jsou nepovinné.

| Proměnná | Výchozí | Význam |
|---|---|---|
| `SERVER_NAME` | `T3 Dev` | Jméno serveru v T3 a T3 Connect |
| `GITHUB_USER` | prázdné | Čí veřejné klíče z GitHubu smí přes SSH. Prázdné = SSH vypnuté |
| `GIT_NAME`, `GIT_EMAIL` | prázdné | Autor commitů |
| `TZ` | `Europe/Prague` | Časové pásmo |
| `T3_CONNECT` | `true` | Přihlášení k T3 Connect při prvním startu |
| `FIREWALL` | `on` | `off` vypne blokování domácí sítě (nedoporučeno) |
| `FIREWALL_ALLOW` | prázdné | Výjimky z firewallu, např. `192.168.1.50 10.0.0.0/24` |

Tajné údaje (tokeny, API klíče) do proměnných nepatří: ZimaOS je ukazuje v UI a vidí je `docker inspect`. Přihlášení agentů se ukládá do svazku `home`.

### Svazky

| Hostitel | Kontejner | Obsah |
|---|---|---|
| `/DATA/AppData/t3-dev/home` | `/home/dev` | Domovský adresář: přihlášení, agenti, nastavení, cache. Zálohovat. |
| `/DATA/AppData/t3-dev/workspace` | `/workspace` | Projekty. Zálohovat. |
| `/DATA/AppData/t3-dev/docker` | `/home/dev/.local/share/docker` | Data Dockeru uvnitř (image, kontejnery). Nezálohovat, při zálohování zachovat číselné vlastníky (100000+). |

## SSH

```bash
ssh -p 2222 dev@<adresa-zimaos>
```

Přihlásit se lze jen klíčem z `github.com/<GITHUB_USER>.keys` (načítá se při každém startu) nebo klíčem přidaným ručně do `~/.ssh/authorized_keys`. Funguje i přesměrování portů, třeba `ssh -p 2222 -L 4200:localhost:4200 dev@...` pro dev server Angularu.

## Zabezpečení

Kontejner **není privilegovaný** a nemá přístup k Dockeru hostitele. Konkrétně:

- **Žádný root za běhu.** Startovací skript jako root jen připraví svazky, jméno serveru a firewall, pak se přepne na uživatele `dev` (UID 1000) a zahodí všechna oprávnění. Zůstane jen `SETUID` a `SETGID` v omezující sadě, které potřebují `newuidmap`/`newgidmap` pro rootless Docker. V image není `sudo` a setuid bit mají jen tyto dva programy.
- **Rootless Docker.** Démon běží jako `dev` ve vlastním uživatelském jmenném prostoru. Root ve vnořeném kontejneru je na hostiteli neprivilegovaný uživatel.
- **Vlastní seccomp profil** ([`seccomp.json`](seccomp.json), generuje ho [`scripts/generate-seccomp.mjs`](scripts/generate-seccomp.mjs)): výchozí profil Dockeru plus jen volání pro jmenné prostory, mount a klíčenku. Pořád blokuje `bpf`, `perf_event_open`, moduly jádra, `kexec`, `userfaultfd`, `io_uring` a další.
- **Firewall** v síťovém jmenném prostoru kontejneru: internet je volný, domácí síť, Docker hostitel, ostatní kontejnery a Tailscale (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, link-local) jsou blokované. Platí i pro vnořené kontejnery.
- **Limity:** 8 GB RAM, 10 CPU, 4096 procesů. Kontejner nevyčerpá hostitele.
- **Ochrana proti zavirovaným balíčkům:** npm neinstaluje skripty balíčků a bere jen verze starší 3 dnů, pnpm a uv také.
- **T3 Code** poslouchá jen uvnitř kontejneru, ven vede jen tunel T3 Connect.

**Kompromisy, bez kterých Docker uvnitř nejde:** profil AppArmor a maskování `/proc` jsou pro kontejner vypnuté (`apparmor=unconfined`, `systempaths=unconfined`) a kontejner smí vytvářet uživatelské jmenné prostory. Chyba jádra v těchto oblastech by mohla vést k úniku na hostitele, proto udržujte ZimaOS aktualizovaný. Silnější izolaci dá jen virtuální stroj.

**Hlavní riziko není únik z kontejneru, ale krádež tokenů** (Codex, Claude, GitHub) přes zavirovaný balíček nebo prompt injection. Pomáhá ochrana balíčků výše, GitHub token s co nejmenšími právy a přehled o tom, co agenti dělají.

## Aktualizace

Image se každý týden přestaví s bezpečnostními aktualizacemi (`ghcr.io/bzumik1/t3-dev-container:latest`). Na ZimaOS ho aktualizujete v UI aplikace, nebo přes SSH:

```bash
sudo docker pull ghcr.io/bzumik1/t3-dev-container:latest
```

a restartem aplikace. Agenti se aktualizují sami, ručně `t3-dev update-agents`.

## Pomocník `t3-dev`

```text
t3-dev status           stav služeb, verze nástrojů a T3 Connect
t3-dev install-agents   nainstaluje chybějící agenty
t3-dev update-agents    aktualizuje agenty
t3-dev connect          znovu spustí přihlášení k T3 Connect
t3-dev restart <služba> restartuje dockerd, sshd nebo t3
```

Z hostitele: `sudo docker exec -it -u dev t3-dev zsh`.

## Řešení problémů

- **Kontejner nenastartuje, v logu je chyba seccomp:** chybí `/DATA/AppData/t3-dev/seccomp.json` (krok 1 instalace).
- **„nelze nastavit firewall“:** v nastavení aplikace chybí oprávnění `NET_ADMIN`; použijte `compose.yml` beze změn.
- **Docker uvnitř nejede:** `t3-dev status` a log kontejneru. ZimaOS UI musí zachovat `security_opt` a `devices` z `compose.yml`. Pokud je zahodí, nainstalujte přes SSH: `sudo docker compose -f compose.yml up -d`.
- **Odkaz na T3 Connect vypršel:** restartujte kontejner, objeví se nový.

## Vývoj

Změny přes PR. CI sestaví image, spustí ho se stejnými bezpečnostními volbami jako `compose.yml` ([`tests/ci.sh`](tests/ci.sh): izolace, Docker uvnitř, firewall, SSH, nástroje, Testcontainers s PostgreSQL, agenti) a proskenuje ho Trivy. Z `main` se publikuje do ghcr.io s atestací původu.
