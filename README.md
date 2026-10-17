# Home lab K52F — réglages système versionnés

Les fichiers ici sont des **copies de référence** des réglages installés dans `/etc`.
On modifie ici, on vérifie, puis on installe avec `sudo` (commandes ci-dessous).

## Principes (sécurité avant tout)
- Un **compte Linux dédié** par service exposé, sans mot de passe ni shell.
- Un **bac à sable systemd** pour chaque service (note visée : < 3 avec `systemd-analyze security`).
- Les secrets hors du code et hors de Git ; le code appartient à `utilisateur`, le service ne peut que le lire.
- Écoute sur 127.0.0.1 quand c'est possible ; accès distant via Tailscale.

## Services
| Service | Compte | Bac à sable |
|---|---|---|
| sam | utilisateur (à migrer) | `~/sam/deploiement/sam.service` |
| k52f-pilote | utilisateur (compte dédié : étape suivante) | `systemd/k52f-pilote.service.d/securite.conf` + `polkit/50-k52f-pilote.rules` |
| searxng | **searxng** (Podman sans root) | `searxng/` |
| altinformatique | **altinfo** ✅ (2026-10-16, note 9,2 → 1,4) | `systemd/altinformatique.service.d/securite.conf` |

## ALTinformatique sous le compte `altinfo`
```bash
sudo adduser --system --group --no-create-home --home /nonexistent --shell /usr/sbin/nologin altinfo
sudo chgrp altinfo /var/www/demo/altinformatique/backend/.env && sudo chmod 640 /var/www/demo/altinformatique/backend/.env
sudo install -D -m 644 systemd/altinformatique.service.d/securite.conf /etc/systemd/system/altinformatique.service.d/securite.conf
sudo systemctl daemon-reload && sudo systemctl restart altinformatique
```
Retour arrière : `sudo rm /etc/systemd/system/altinformatique.service.d/securite.conf && sudo systemctl daemon-reload && sudo systemctl restart altinformatique`.

## Pilote : polkit au lieu de sudo
Le Pilote appelle `systemctl` directement ; polkit lui permet UNIQUEMENT : restart de nginx,
mysql et altinformatique, start/stop de sam, redémarrer/éteindre le K52F.
Ces droits sont réservés aux processus qui tournent **dans le service du Pilote** (vérification
du cgroup via `polkit.spawn`) : ni le terminal, ni la session, ni un autre service du compte
`utilisateur` n'en profitent.
```bash
sudo install -m 644 -o root -g root polkit/50-k52f-pilote.rules /etc/polkit-1/rules.d/50-k52f-pilote.rules
sudo install -m 755 -o root -g root bin/k52f-maj-sites /usr/local/bin/k52f-maj-sites
sudo install -D -m 644 systemd/k52f-pilote.service.d/securite.conf /etc/systemd/system/k52f-pilote.service.d/securite.conf
```
Puis, une fois tout vérifié, suppression des règles sudo devenues inutiles :
`sudo rm /etc/sudoers.d/k52f-pilote /etc/sudoers.d/k52f-sam`.

## sudoers (ancien système, remplacé par polkit)
- `sudoers.d/k52f-sam` : arrêt / relance de Sam depuis le Pilote (vérifier avec `sudo visudo -cf` avant installation).

## Relevé SMART quotidien (pour les tendances de Sam)
`k52f-smart.service` (root, sans réseau, bac à sable) lance `k52f-smart-releve` chaque matin
à 7 h 20 et écrit seulement `/var/lib/k52f-mesures/smart-interne.json` (640 root:utilisateur).
```bash
sudo install -m 755 bin/k52f-smart-releve /usr/local/sbin/k52f-smart-releve
sudo install -m 644 systemd/k52f-smart.service systemd/k52f-smart.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now k52f-smart.timer && sudo systemctl start k52f-smart.service
```

## SearXNG (recherche web de Sam) : Podman sans root
Compte dédié `searxng` (pas de mot de passe, pas de shell, pas de sudo), conteneur rootless
(« quadlet » `searxng/searxng.container`), image à version et empreinte fixées, écoute sur
127.0.0.1:8888 seulement. Secret généré à l'installation, jamais dans Git.
```bash
sudo apt install podman
sudo ~/projets/k52f-homelab/bin/k52f-searxng-installer
```
Mettre à jour : changer la ligne `Image=` (version + empreinte) puis relancer l'installateur.

## ntfy : un sujet secret, hors du code
- `/etc/k52f-ntfy.conf` (root:utilisateur 640) : sujet lu par le Pilote et le tunnel.
- `/etc/k52f-alertes.conf` (root 600) : sujet lu par k52f-alertes.
- Changer de sujet (génère, met à jour les deux fichiers, envoie un test, l'affiche une fois) :
```bash
sudo install -m 755 bin/k52f-ntfy-changer /usr/local/sbin/k52f-ntfy-changer
sudo install -m 644 lib/k52f-tunnel-lib.sh /usr/local/lib/k52f-tunnel-lib.sh
sudo k52f-ntfy-changer
```
Sam a son propre sujet (`NTFY_SUJET` dans `~/sam/.env`).

## Journal des interventions
- **2026-10-16** — ALTinformatique passe sous le compte `altinfo` + bac à sable (note systemd 9,2 → 1,4).
  `.env` en 640 `utilisateur:altinfo`.
  Panne découverte au passage (depuis au moins le 11/10) : MySQL refusait `altinfo_user`
  (mot de passe différent du `.env`) → mot de passe resynchronisé depuis le `.env` sans l'afficher ;
  base jamais initialisée (tables absentes) → `npm run db:init` lancé par Anthony.
- **2026-10-16** — Pilote : sudo remplacé par polkit (`50-k52f-pilote.rules`) + bac à sable
  (note 9,2 → 1,8). Testé depuis le téléphone : arrêt d'urgence + relance de Sam, mise à jour
  des sites, sans aucune demande de mot de passe. Incident pendant mes tests : un essai
  « stop nginx » a déclenché une fenêtre polkit sur le bureau, approuvée → Nginx coupé ~1 min.
  Règle retenue : tester les droits avec `pkcheck` ou depuis le service, jamais avec une commande réelle.
- **2026-10-16** — Droits polkit réservés au cgroup du Pilote ; sujet ntfy sorti de
  k52f-tunnel-lib.sh puis changé (ancien sujet supprimé partout). Testé depuis le téléphone :
  restart altinformatique, arrêt d'urgence + relance de Sam, sans aucune fenêtre de mot de passe ;
  le terminal ne peut plus redémarrer/éteindre le PC sans mot de passe.

## À faire
- ~~Supprimer les règles sudo devenues inutiles~~ : fait le 2026-10-16 (k52f-pilote, k52f-sam).
- ~~Droits polkit réservés au Pilote~~ : fait via le cgroup du service (sans changer de compte).
- Bonus (migration matérielle) : compte dédié `pilote` + tunnel en service systemd partagé
  entre le bureau et le Pilote (aujourd'hui l'état du tunnel est dans ~/.cache et partagé).
- ~~Sujet ntfy~~ : sorti du code et changé le 2026-10-16 (k52f-ntfy-changer).
- PIN → mots de passe : revoir validation, champs et style (Sam et Pilote) le moment venu.
