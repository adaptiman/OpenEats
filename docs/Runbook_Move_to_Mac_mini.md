# Runbook: move the cookbook from the Azure VM to the Mac mini

Moves https://www.cookbook.thesweeneys.org from the Azure VM (resource group **CookbookRG**) to the
Mac mini at home (`adapticlaw.local`). The Mac mini runs the same four containers; a separate
Caddy container (repo `adapticlaw-edge`) is the only thing reachable from the internet and handles
HTTPS. The VM keeps running until the new site has worked for a week.

```
internet --443--> home router --443--> Mac mini: Caddy (adapticlaw-edge)
                                              |  edge network, plain HTTP
                                              v
                                         OpenEats nginx --> api (Django) --> db (MariaDB)
                                                        \-> web (built UI), site-media
```

**Where:** Terminal on the Mac mini unless a step says otherwise. Allow about two hours; the site is
read-only for the family during steps 6 to 9 (about 30 minutes).

## 0. Before the day

1. **Lower the DNS TTL** a day ahead. In Bluehost: Domains → thesweeneys.org → DNS. Find the
   records for `cookbook` and `www.cookbook` and set their TTL to the lowest allowed (often 300 or
   600 seconds). Note what they point to now (the VM's address) so you can switch back.
2. **Fixed LAN address for the Mac mini.** In your router's admin page, find the DHCP settings and
   add a reservation for the Mac mini's Ethernet (or Wi-Fi) MAC address. On the Mac mini:
   `ipconfig getifaddr en0` shows the current address; System Settings → Network → (interface) →
   Details shows the MAC ("Hardware address"). Restart the Mac mini or renew the lease and check
   it kept the reserved address.
3. **no-ip.** Make sure your no-ip hostname (for example `something.ddns.net`) tracks your home
   address: either the router's built-in Dynamic DNS (often under WAN or DDNS settings, provider
   "No-IP") or no-ip's DUC app on the Mac mini. Check it: `dig +short something.ddns.net` should
   match `curl -s https://api.ipify.org`.
4. **Check that your ISP lets 443 in** (some block it, or put homes behind shared addresses,
   "CGNAT"). If the router's WAN address differs from `curl -s https://api.ipify.org`, you are
   behind CGNAT and port forwarding will not work; stop and tell Claude.

## 1. Install OrbStack (Docker for the Mac)

```bash
brew install orbstack
open -a OrbStack
```

In OrbStack's settings: turn on **Start at login**. Then check:

```bash
docker version
docker run --rm hello-world
```

## 2. Get the code

```bash
cd ~
git clone git@github.com:adaptiman/OpenEats.git
git clone git@github.com:adaptiman/openeats-api.git
git clone git@github.com:adaptiman/openeats-web.git
git clone git@github.com:adaptiman/adapticlaw-edge.git
cd ~/OpenEats && git checkout mac-mini
```

The compose file builds `../openeats-api` and `../openeats-web`, so the three repos sit side by side
in your home folder.

## 3. Settings with new secrets

```bash
cd ~/OpenEats
cp env_macmini.example.list env_macmini.list
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
python3 -c "import secrets; print(secrets.token_urlsafe(24))"
vi env_macmini.list
```

Paste the first value after `DJANGO_SECRET_KEY=` and the second after `MYSQL_ROOT_PASSWORD=`
(`/DJANGO` to find the line, `A` to append, paste, `Esc`; same for `/MYSQL_ROOT`; `:wq`). These
replace the values committed in `env_prod.list`, which is public on GitHub. Keep a copy of
`env_macmini.list` somewhere safe (for example a password manager note); it is not in git.

## 4. Build the images

```bash
docker network create edge
cd ~/OpenEats
docker compose -f docker-compose.macmini.yml build
```

The API image is based on an old Python (3.6) image. If the build fails on the Mac's ARM chip
(errors compiling Pillow or mysqlclient), build the Intel images instead; OrbStack runs them with
Rosetta, fast enough for this site:

```bash
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker compose -f docker-compose.macmini.yml build
```

(If you do this, put `DOCKER_DEFAULT_PLATFORM=linux/amd64` in front of every `docker compose`
command below, or add `platform: linux/amd64` to the `api`, `web` and `db` services.)

## 5. Rehearsal with yesterday's backup (site stays live on Azure)

Copy the latest backup set from the VM. The commands below assume you sign in to the VM as
`adaptiman@sweeneydev.southcentralus.cloudapp.azure.com` (the name in the old `env_prod.list`);
use whatever you normally `ssh` to. On the Mac mini:

```bash
mkdir -p ~/cookbook-move
ssh adaptiman@sweeneydev.southcentralus.cloudapp.azure.com \
  'ls -1dt ~/thesweeneyscookbooksa/openeats-backups/* | head -n1'
```

That prints the newest backup folder. Copy its database dump and photos:

```bash
B=<the folder it printed>
scp adaptiman@sweeneydev.southcentralus.cloudapp.azure.com:"$B/db/openeats.sql" ~/cookbook-move/
scp -r adaptiman@sweeneydev.southcentralus.cloudapp.azure.com:"$B/site-media" ~/cookbook-move/
```

Then follow steps 7 and 8 with these files. When the site works on http://localhost:8088, the
rehearsal is done. Leave it running; step 7 starts again from an empty database.

## 6. Freeze the site and take the final backup (on the day)

Tell the family not to add or edit recipes for half an hour. On the VM:

```bash
ssh adaptiman@sweeneydev.southcentralus.cloudapp.azure.com
cd ~/OpenEats
docker exec openeats-db-1 sh -c 'exec mysqldump openeats -uroot -p"$MYSQL_ROOT_PASSWORD"' > ~/openeats-final.sql
docker cp openeats-api-1:/code/site-media ~/site-media-final
tar -czf ~/site-media-final.tgz -C ~ site-media-final
ls -lh ~/openeats-final.sql ~/site-media-final.tgz
exit
```

(If `docker ps` shows the containers as `openeats_db_1` and `openeats_api_1`, use those names.)

Copy them to the Mac mini:

```bash
cd ~/cookbook-move
scp adaptiman@sweeneydev.southcentralus.cloudapp.azure.com:openeats-final.sql .
scp adaptiman@sweeneydev.southcentralus.cloudapp.azure.com:site-media-final.tgz .
tar -xzf site-media-final.tgz && rm -rf site-media && mv site-media-final site-media
```

## 7. Load the data into a fresh database

Starting from an empty database is what makes the new root password take effect.

```bash
cd ~/OpenEats
docker compose -f docker-compose.macmini.yml down
docker volume rm openeats_database_current 2>/dev/null || true
docker compose -f docker-compose.macmini.yml up -d db
until docker compose -f docker-compose.macmini.yml ps db | grep -q healthy; do echo "waiting for db"; sleep 3; done
set -a; source env_macmini.list; set +a
docker compose -f docker-compose.macmini.yml exec -T db \
  mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" openeats < ~/cookbook-move/openeats-final.sql
```

(For the rehearsal, the file is `~/cookbook-move/openeats.sql`.)

Start everything, then copy the photos in:

```bash
docker compose -f docker-compose.macmini.yml up -d
docker compose -f docker-compose.macmini.yml cp ~/cookbook-move/site-media/. api:/code/site-media/
docker compose -f docker-compose.macmini.yml ps
```

Wait until `api` and `nginx` show `healthy` (a minute or two; the `web` container builds the site
and then exits, which is expected).

## 8. Check it on the Mac mini

```bash
curl -s -o /dev/null -w 'home=%{http_code}\n' http://localhost:8088/
curl -s -o /dev/null -w 'api=%{http_code}\n' 'http://localhost:8088/api/v1/recipe/recipes/?limit=1'
curl -s 'http://localhost:8088/api/v1/recipe/recipes/?limit=1' | head -c 300; echo
```

Both should be `200`, and the last line should show a recipe. Then open http://localhost:8088 in a
browser on the Mac mini: browse a few recipes, check the photos load, and log in. Don't add or
change anything here during the rehearsal.

## 9. Open the entrance and switch DNS

1. **Start Caddy.** It will try to get certificates and fail until DNS points home; that's fine.

   ```bash
   cd ~/adapticlaw-edge
   docker compose up -d
   ```

2. **Router:** add a port forward, external **TCP 443** → the Mac mini's reserved address, port
   **443**. Forward nothing else. (If the router has a "DMZ host" setting, leave it off.)
3. **Bluehost DNS:** change `www.cookbook` and `cookbook` to **CNAME** records pointing at your
   no-ip hostname (for example `something.ddns.net`). If Bluehost only lets you edit them as A
   records, delete those and add CNAMEs.
4. **Watch the certificates arrive** (a few minutes after DNS updates):

   ```bash
   dig +short www.cookbook.thesweeneys.org     # should show the no-ip name, then your home address
   cd ~/adapticlaw-edge && docker compose logs -f caddy
   ```

   Look for `certificate obtained successfully` for both names; `Ctrl-C` to stop watching.

## 10. Check from outside

On your phone, **with Wi-Fi off**, open https://cookbook.thesweeneys.org. It should redirect to
https://www.cookbook.thesweeneys.org with a valid padlock. Browse, open a photo, log in, and add a
test note to a recipe, then remove it. Tell the family the site is back.

Home-network note: some routers can't loop back to their own public address, so the site may not
load from inside the house by name even though it works outside. If that happens, tell Claude; the
fix is a local DNS entry or the router's "NAT loopback" setting.

## 11. Backups on the Mac mini

Daily, keep 14 days (Claude will add this to the Mac mini's existing nightly backup so it also
goes to Azure Blob, encrypted). For now, a manual backup is:

```bash
mkdir -p ~/adapticlaw-data/cookbook-backups/$(date +%F)
cd ~/OpenEats && set -a && source env_macmini.list && set +a
docker compose -f docker-compose.macmini.yml exec -T db \
  sh -c 'exec mariadb-dump openeats -uroot -p"$MYSQL_ROOT_PASSWORD"' \
  > ~/adapticlaw-data/cookbook-backups/$(date +%F)/openeats.sql
docker compose -f docker-compose.macmini.yml cp api:/code/site-media ~/adapticlaw-data/cookbook-backups/$(date +%F)/
```

Caddy's certificates live in the `edge_caddy-data` volume; they renew themselves and can be
re-issued if lost, so they need no backup.

## 12. After a week: retire the VM

When the site has worked for a week: in the Azure portal, stop the VM in **CookbookRG** (Stop
deallocates it, so it no longer costs compute), wait another week, then delete **CookbookRG**.
Before deleting, check whether anything else in it is still wanted, for example the
`thesweeneyscookbooksa` storage account with the old backups (download the latest set first if
you want to keep it).

Then clean up the repo: remove `env_prod.list`, `env_stg.list` and `env_dev.list` from git (their
secrets are retired now) and make `docker-compose.macmini.yml` the main compose file.

## Rolling back

Until step 12, the VM still has everything. To go back: in Bluehost, point `www.cookbook` and
`cookbook` back at the VM's address (from step 0), and remove the router's 443 forward. Anything
the family added on the Mac mini in the meantime would need copying back with the same dump and
restore steps.
