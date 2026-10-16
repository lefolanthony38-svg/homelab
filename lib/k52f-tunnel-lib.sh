# /usr/local/lib/k52f-tunnel-lib.sh
# Fonctions communes du tunnel de démo, utilisées par :
#   - k52f-tunnel     (fenêtres sur le bureau)
#   - k52f-tunnelctl  (ligne de commande, utilisée par l'appli téléphone)
ETAT_DIR="$HOME/.cache/k52f-tunnel"; ETAT="$ETAT_DIR/etat"
CARNET="$HOME/.config/k52f/contacts.csv"     # Nom;adresse;client|mentor;formule
NTFY_TOPIC=$(sed -n "s/^NTFY_TOPIC=//p" /etc/k52f-ntfy.conf 2>/dev/null | head -1)   # lu (jamais exécuté) dans /etc/k52f-ntfy.conf
SIGNATURE="Anthony Lefol
Développeur web & web mobile
Portfolio : https://lefolanthony38-svg.github.io"
mkdir -p "$ETAT_DIR" "$(dirname "$CARNET")"; touch "$CARNET"

# Pages proposées — clé|nom|port|chemin
PAGES="accueil|Tous mes projets (page d'accueil)|80|/
kendo|Club de kendo|80|/kendo/build/
ptcruiser|N7 PT Cruiser Club|80|/ptcruiser/
portfolio|Portfolio|80|/portfolio/
asso|Site associatif (en préparation)|80|/asso/
alt|ALTinformatique (application complète)|3000|/"

champ()    { printf '%s\n' "$PAGES" | awk -F'|' -v k="$1" -v n="$2" '$1==k{print $n}'; }
lien_log() { grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$1" 2>/dev/null | grep -v '//api\.' | tail -1; }
en_cours() { [ -f "$ETAT" ] && . "$ETAT" && kill -0 "$PID1" 2>/dev/null; }
fin_txt()  { LC_TIME=fr_FR.UTF-8 date -d "@$FIN" "+%A %-d %B à %Hh%M"; }
url_principale() { if [ "$CLE" = alt ]; then echo "$BASE/"; else echo "$BASE$CHEMIN"; fi; }

telephone() { # titre message [lien]
  [ -n "$NTFY_TOPIC" ] || return 0   # sujet ntfy illisible ou absent : pas de notification
  python3 - "$NTFY_TOPIC" "$1" "$2" "${3:-}" <<'PY' | curl -s -m 15 -H "Content-Type: application/json" -d @- https://ntfy.sh/ >/dev/null
import json, sys
topic, titre, msg, url = sys.argv[1:5]
d = {"topic": topic, "title": titre, "message": msg, "tags": ["link"]}
if url:
    d["click"] = url
    d["actions"] = [{"action": "view", "label": "Ouvrir", "url": url}]
print(json.dumps(d))
PY
}

# ---------- Tunnel ----------
ouvrir() { # port log durée_s → PID
  : > "$2"
  setsid nohup timeout "$3" cloudflared tunnel --no-autoupdate --url "http://localhost:$1" >"$2" 2>&1 </dev/null &
  echo $!
}

arreter() {
  if [ -f "$ETAT" ]; then . "$ETAT"; kill $PID1 ${PID2:-} 2>/dev/null; fi
  rm -f "$ETAT"
}

surveiller() { # tourne en arrière-plan : prévient quand le tunnel se ferme
  . "$ETAT"; local p1=$PID1 p2=${PID2:-}
  while kill -0 "$p1" 2>/dev/null; do sleep 15; done
  [ -n "$p2" ] && kill "$p2" 2>/dev/null
  if [ -f "$ETAT" ] && grep -qx "PID1=$p1" "$ETAT"; then rm -f "$ETAT"; fi
  notify-send -i network-server "Tunnel de démo" "Le tunnel est fermé : le lien ne fonctionne plus." 2>/dev/null
  telephone "Tunnel fermé" "Le lien de démo ne fonctionne plus."
}

# demarrer CLÉ HEURES — ouvre le tunnel, affiche la progression (« # … »),
# écrit l'état et prévient le téléphone. Code retour 0 = OK.
demarrer() {
  local cle=$1 h=$2 s port chemin nom log1="$ETAT_DIR/tunnel1.log" log2="$ETAT_DIR/tunnel2.log"
  local pid1 pid2="" base="" app="" a i j
  port=$(champ "$cle" 3); chemin=$(champ "$cle" 4); nom=$(champ "$cle" 2)
  [ -n "$port" ] || { echo "# Page inconnue : $cle"; return 2; }
  [[ "$h" =~ ^[0-9]+$ ]] && [ "$h" -ge 1 ] && [ "$h" -le 48 ] || { echo "# Durée invalide : $h"; return 2; }
  s=$((h * 3600))
  arreter                                   # ferme un éventuel ancien tunnel
  pid1=$(ouvrir "$port" "$log1" "$s")
  [ "$cle" = accueil ] && pid2=$(ouvrir 3000 "$log2" "$s")
  for i in $(seq 1 45); do
    base=$(lien_log "$log1"); a=x; [ "$cle" = accueil ] && a=$(lien_log "$log2")
    [ -n "$base" ] && [ -n "$a" ] && break
    echo "# Création du tunnel… ($i s)"; sleep 1
  done
  if [ -z "$base" ]; then
    kill $pid1 $pid2 2>/dev/null
    echo "# Le tunnel n'a pas démarré (connexion Internet ?)"; return 1
  fi
  for j in $(seq 1 20); do
    [ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$base/")" = 200 ] && break
    echo "# Vérification du lien… ($j)"; sleep 1
  done
  [ "$cle" = accueil ] && app=$(lien_log "$log2")
  cat > "$ETAT" <<EOF
PID1=$pid1
PID2=$pid2
CLE=$cle
NOM="$nom"
BASE=$base
CHEMIN=$chemin
APP=$app
FIN=$(( $(date +%s) + s ))
EOF
  setsid nohup k52f-tunnelctl surveiller >/dev/null 2>&1 </dev/null &
  . "$ETAT"
  telephone "Tunnel ouvert : $NOM" "Lien valable jusqu'à $(fin_txt) :
$(url_principale)" "$(url_principale)"
  echo "# Tunnel ouvert"
}

# ---------- Messages ----------
liste_liens() {
  if [ "$CLE" = accueil ]; then
    printf '%s\n' "$PAGES" | while IFS='|' read -r k n p c; do
      case $k in
        accueil) echo "• Page d'accueil (tous les projets) : $BASE/" ;;
        alt)     [ -n "$APP" ] && echo "• ALTinformatique, application complète (boutique, devis, espace client) : $APP/" ;;
        asso)    ;;  # pas encore de contenu
        *)       echo "• $n : $BASE$c" ;;
      esac
    done
  else
    echo "• $NOM : $(url_principale)"
  fi
}

modele_client() {
cat <<EOF
Objet : Aperçu de votre site – $NOM

{BONJOUR}

Voici le lien pour consulter l'avancement de votre site :
$(url_principale)

Quelques indications :
• Le lien fonctionne jusqu'au $(fin_txt). Passé ce délai, demandez-moi simplement un nouveau lien.
• Il s'ouvre sur ordinateur, tablette ou téléphone, sans compte ni installation.
• C'est une version de travail : textes, images et fonctions peuvent encore évoluer.
• Le site n'est pas encore public ni référencé sur Google, merci de ne pas diffuser ce lien.
• Si la page ne s'affiche pas, réessayez une minute plus tard ou répondez à ce mail.

Vos remarques sont les bienvenues : répondez directement à ce mail (ce qui vous plaît, ce qu'il faut modifier, textes ou photos à ajouter).

Bonne visite,

$SIGNATURE
EOF
}

modele_mentor() {
cat <<EOF
Objet : Démonstration de mes projets – serveur de démo

{BONJOUR}

Comme convenu, voici l'accès à mes projets, hébergés sur mon serveur de démonstration :

$(liste_liens)

Les liens sont actifs jusqu'au $(fin_txt).

À propos du serveur : c'est un ancien ordinateur portable (Asus K52F) que j'ai reconverti en serveur sous Linux Mint. Nginx sert les sites, Node.js/Express + MySQL font tourner l'application ALTinformatique (service systemd), les mises à jour se font par Git, le pare-feu (ufw) limite les accès au réseau local et une surveillance m'envoie des alertes sur mon téléphone. L'accès depuis Internet passe par un tunnel Cloudflare : aucun port n'est ouvert sur ma box.

Pour consulter :
• aucun compte ni installation n'est nécessaire, sur ordinateur comme sur mobile ;
• les sites sont des versions de travail, non référencées ;
• si une page ne répond pas, n'hésitez pas à me le signaler en réponse à ce mail.

Merci pour votre temps, je suis preneur de tous vos retours.

$SIGNATURE
EOF
}

envoyer_mail() { # destinataire sujet corps
  local exp; exp=$(awk '$1=="from"{print $2; exit}' /etc/msmtprc)
  {
    printf 'From: Anthony Lefol <%s>\n' "$exp"
    printf 'To: %s\n' "$1"
    printf 'Subject: =?UTF-8?B?%s?=\n' "$(printf '%s' "$2" | base64 -w0)"
    printf 'Date: %s\n' "$(LC_ALL=C date -R)"
    printf 'MIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\n\n'
    printf '%s\n' "$3"
  } | msmtp -t
}

mail_valide() { [[ "$1" =~ ^[^@[:space:]\;]+@[^@[:space:]\;]+\.[^@[:space:]\;]+$ ]]; }

# ajouter_contact NOM MAIL PROFIL FORMULE — enregistre dans le carnet (sans doublon)
ajouter_contact() {
  local nom=${1//;/,} mail=$2 prof=$3 sal=${4//;/,}
  mail_valide "$mail" || return 1
  [ "$prof" = mentor ] || prof=client
  [ -n "$nom" ] || nom=$mail
  grep -qF ";$mail;" "$CARNET" || echo "$nom;$mail;$prof;$sal" >> "$CARNET"
}

contact() { grep -m1 -F ";$1;" "$CARNET"; }   # ligne du carnet pour une adresse

# envoyer_texte "TEXTE" "nom;mail;profil;formule"… — envoie le même texte
# ({BONJOUR} remplacé pour chacun). Affiche « OK nom (mail) » / « ECHEC nom (mail) ».
envoyer_texte() {
  local texte=$1 sujet corps d nom mail prof sal; shift
  sujet=$(printf '%s\n' "$texte" | head -1 | sed 's/^Objet *: *//')
  corps=$(printf '%s\n' "$texte" | tail -n +3)
  for d in "$@"; do
    IFS=';' read -r nom mail prof sal <<< "$d"
    mail_valide "$mail" || { echo "ECHEC $nom ($mail)"; continue; }
    if [ -n "$sal" ]; then sal="Bonjour $sal,"; else sal="Bonjour,"; fi
    if envoyer_mail "$mail" "$sujet" "${corps//\{BONJOUR\}/$sal}"; then echo "OK $nom ($mail)"
    else echo "ECHEC $nom ($mail)"; fi
  done
}
