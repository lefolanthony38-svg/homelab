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
| altinformatique | **altinfo** | `systemd/altinformatique.service.d/securite.conf` |

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
