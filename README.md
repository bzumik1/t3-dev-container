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
   ```

2. **Nainstalujte aplikaci:** v ZimaOS App Store → **Custom Install** → import, vložte obsah [`compose.yml`](compose.yml). V nastavení služby `t3-dev` vyplňte aspoň `SERVER_NAME` (např. `HP Prodesk`) a `GITHUB_USER`. Nic jiného měnit nemusíte.

3. **Přihlaste T3 Connect:** otevřete log kontejneru `t3-dev`. Při prvním startu se tam objeví odkaz `https://accounts.t3.codes/device?...` a kód. Otevřete ho a schvalte svým účtem. Server se pak objeví v T3 na všech vašich zařízeních.

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
| `GITHUB_USER` | `t3-dev` | prázdné | Čí veřejné klíče z GitHubu smí přes SSH. Prázdné = SSH vypnuté |
| `GIT_NAME`, `GIT_EMAIL` | `t3-dev` | prázdné | Autor commitů |
| `TZ` | `t3-dev` | `Europe/Prague` | Časové pásmo |
| `T3_CONNECT` | `t3-dev` | `true` | Přihlášení k T3 Connect při prvním startu |
| `FIREWALL` | `t3-dev-net` | `on` | `off` vypne blokování domácí sítě (nedoporučeno) |
| `FIREWALL_ALLOW` | `t3-dev-net` | prázdné | Výjimky z firewallu, např. `192.168.1.50 10.0.0.0/24` |

Tajné údaje (tokeny, API klíče) do proměnných nepatří: ZimaOS je ukazuje v UI a vidí je `docker inspect`. Přihlášení agentů se ukládá do svazku `home`.

### Svazky

| Hostitel | Kontejner | Obsah |
|---|---|---|
| `/DATA/AppData/t3-dev/home` | `/home/dev` | Domovský adresář: přihlášení, agenti, nastavení, cache. Zálohovat. |
| `/DATA/AppData/t3-dev/workspace` | `/workspace` | Projekty. Zálohovat. |
| `/DATA/AppData/t3-dev/docker` | `/home/dev/.local/share/docker` | Data Dockeru uvnitř (image, kontejnery). Nezálohovat, při zálohování zachovat číselné vlastníky (100000+). Jednou denně se čistí stará cache a nepoužité image. |

## SSH

```bash
ssh -p 2222 dev@<adresa-zimaos>
```

Přihlásit se lze jen klíčem z `github.com/<GITHUB_USER>.keys` (načítá se při každém startu) nebo klíčem přidaným ručně do `~/.ssh/authorized_keys`. Funguje přesměrování portů k vám, třeba `ssh -p 2222 -L 4200:localhost:4200 dev@...` pro dev server Angularu. Opačný směr (`-R`) je vypnutý.

## Zabezpečení

Kontejner **není privilegovaný**, nemá přístup k Dockeru hostitele a **za běhu v něm není žádný root**:

- **Bez roota.** `t3-dev` běží celý jako `dev`. Výchozí uživatel image je `dev`, takže i `docker exec` a healthcheck jdou bez roota. Root, který si někdo vynutí přes `docker exec -u 0`, nemá žádná užitečná oprávnění. V image není `sudo` ani žádný setuid program. `newuidmap`/`newgidmap` mají jen úzké souborové oprávnění (`cap_setuid`, `cap_setgid`) a SSH ani T3 je díky `no_new_privs` použít nemůžou. Smí je jen Docker démon.
- **Rootless Docker.** Démon běží jako `dev` ve vlastním uživatelském jmenném prostoru. Root ve vnořeném kontejneru je navenek `dev`. Kontejnery s `--network host` nevidí loopback `t3-dev` (T3 server).
- **Vlastní seccomp profil** ([`seccomp.json`](seccomp.json), generuje ho [`scripts/generate-seccomp.mjs`](scripts/generate-seccomp.mjs)): výchozí profil Dockeru plus jen volání pro jmenné prostory a mount. Pořád blokuje `bpf`, `perf_event_open`, moduly jádra, `kexec`, `userfaultfd`, `io_uring` a klíčenku.
- **Firewall** (`t3-dev-net`): internet je volný. Domácí síť, Docker hostitel, ostatní kontejnery a Tailscale (`10/8`, `172.16/12`, `192.168/16`, `100.64/10`, link-local) jsou blokované, a to i pro vnořené kontejnery. Dovnitř vede jen SSH. IPv6 je vypnuté. `dev` pravidla změnit nemůže.
- **Limity:** 8 GB RAM, 10 CPU s nižší prioritou než ostatní aplikace, 4096 procesů, omezené logy. Při nedostatku paměti na hostiteli jádro obětuje nejdřív `t3-dev`.
- **Ochrana proti zavirovaným balíčkům:** npm neinstaluje skripty balíčků a bere jen verze starší 3 dnů (nastavené v prostředí, takže to `.npmrc` projektu nevypne), pnpm a uv také. Platí i při sestavení image.
- **T3 Code** poslouchá jen uvnitř kontejneru, ven vede jen tunel T3 Connect.

**Kompromisy, bez kterých Docker uvnitř nejde:** `t3-dev` má vypnutý profil AppArmor a maskování `/proc` (`apparmor=unconfined`, `systempaths=unconfined`) a smí vytvářet uživatelské jmenné prostory. Chyba jádra v těchto oblastech by mohla vést k úniku na hostitele, proto udržujte ZimaOS aktualizovaný. ZimaOS 1.8.0 má jádro 6.18.9 se známými chybami ([IceWhaleTech/ZimaOS#641](https://github.com/IceWhaleTech/ZimaOS/issues/641)). Silnější izolaci dá jen virtuální stroj.

**Hlavní riziko není únik z kontejneru, ale krádež tokenů** (Codex, Claude, GitHub) přes zavirovaný balíček nebo prompt injection. Pomáhá ochrana balíčků výše a **GitHub token s co nejmenšími právy**: agentům dejte token bez přístupu k tomuto repozitáři a k produkčním repozitářům, ať nemůžou podstrčit image, který pak poběží na vašem serveru.

## Aktualizace

Image se každý týden přestaví s bezpečnostními aktualizacemi (`ghcr.io/bzumik1/t3-dev-container:latest`). Publikuje se jen tehdy, když projdou všechny testy. Na ZimaOS ho aktualizujete v UI aplikace, nebo přes SSH:

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

Z hostitele: `sudo docker exec -it t3-dev zsh`.

## Řešení problémů

- **Kontejner nenastartuje, v logu je chyba seccomp:** chybí `/DATA/AppData/t3-dev/seccomp.json` (krok 1 instalace).
- **`t3-dev` nenastartuje a `t3-dev-net` hlásí „nelze nastavit firewall“:** chybí oprávnění `NET_ADMIN`; použijte `compose.yml` beze změn.
- **Docker uvnitř nejede:** `t3-dev status` a log kontejneru. UI ZimaOS musí zachovat `security_opt`, `cap_add` a `devices` z `compose.yml`. Pokud je zahodí, nainstalujte přes SSH: `sudo docker compose -f compose.yml up -d`.
- **Odkaz na T3 Connect vypršel:** restartujte kontejner `t3-dev`, objeví se nový.
- **Po restartu `t3-dev-net` nemá `t3-dev` síť:** restartujte i `t3-dev` (sdílí síť s `t3-dev-net`).

## Vývoj

Změny přes PR. CI sestaví image a ve 22 souběžných jobech ho spustí se stejnými volbami jako `compose.yml`: izolace a oprávnění, Docker uvnitř, firewall, SSH, seccomp, limity, nástroje, Testcontainers v Javě i Node, agenti, restart a aktualizace, Docker 27.5.1 jako na ZimaOS a skutečný projekt (backend, frontend, e2e a celý stack). Pak image proskenuje Trivy a z `main` ho publikuje do ghcr.io s atestací původu.
