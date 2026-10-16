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
| k52f-pilote | utilisateur (à migrer, polkit au lieu de sudo) | à faire |
| altinformatique | **altinfo** ✅ (2026-10-16, note 9,2 → 1,4) | `systemd/altinformatique.service.d/securite.conf` |

## ALTinformatique sous le compte `altinfo`
```bash
sudo adduser --system --group --no-create-home --home /nonexistent --shell /usr/sbin/nologin altinfo
sudo chgrp altinfo /var/www/demo/altinformatique/backend/.env && sudo chmod 640 /var/www/demo/altinformatique/backend/.env
sudo install -D -m 644 systemd/altinformatique.service.d/securite.conf /etc/systemd/system/altinformatique.service.d/securite.conf
sudo systemctl daemon-reload && sudo systemctl restart altinformatique
```
Retour arrière : `sudo rm /etc/systemd/system/altinformatique.service.d/securite.conf && sudo systemctl daemon-reload && sudo systemctl restart altinformatique`.

## sudoers
- `sudoers.d/k52f-sam` : arrêt / relance de Sam depuis le Pilote (vérifier avec `sudo visudo -cf` avant installation).

## Journal des interventions
- **2026-10-16** — ALTinformatique passe sous le compte `altinfo` + bac à sable (note systemd 9,2 → 1,4).
  `.env` en 640 `utilisateur:altinfo`.
  Panne découverte au passage (depuis au moins le 11/10) : MySQL refusait `altinfo_user`
  (mot de passe différent du `.env`) → mot de passe resynchronisé depuis le `.env` sans l'afficher ;
  base jamais initialisée (tables absentes) → `npm run db:init` lancé par Anthony.
