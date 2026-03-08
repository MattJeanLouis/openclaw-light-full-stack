# openclaw-light-full-stack

Un stack complet et auto-hebergeable d'assistant IA, construit sur [OpenClaw](https://openclaw.ai). Clone, configure, lance.

Fonctionne sur n'importe quelle machine compatible Docker : Raspberry Pi, serveur maison, VPS cloud ou laptop.

## Ce que tu obtiens

- **OpenClaw** — passerelle IA avec messagerie multi-canal (WhatsApp, Discord, Telegram, Slack, et bien d'autres)
- **LiteLLM** — proxy unifie pour OpenAI, Anthropic, Google, Mistral, Ollama et 100+ fournisseurs IA
- **PostgreSQL + pgvector** — base de donnees persistante avec recherche vectorielle pour la memoire et le RAG
- **API accessible par cle** — API compatible OpenAI sur ton reseau local (port 18789 par defaut), utilisable depuis n'importe quel projet
- **Services optionnels** : reverse proxy Caddy (HTTPS automatique), Cloudflare Tunnel, notifications de mises a jour (Diun), backups Google Drive (rclone)

## Demarrage rapide

```bash
git clone https://github.com/MattJeanLouis/openclaw-light-full-stack.git
cd openclaw-light-full-stack
make setup
```

L'assistant de configuration genere les secrets, demande ta cle API, configure les canaux et demarre tout.

### Alternative : setup guide par Claude Code

Ouvre ce repo dans Claude Code et demande-lui de configurer le stack. Il lit le `CLAUDE.md` et te guide etape par etape, avec la possibilite de diagnostiquer les erreurs et d'adapter les conseils a ton systeme.

```bash
cd openclaw-light-full-stack
claude
# "Configure mon stack openclaw-light-full-stack"
```

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Docker Compose                 │
                    │                                             │
 Navigateur ───────►│  ┌──────────┐    ┌───────────────┐         │
                    │  │  Caddy   │───►│   OpenClaw    │         │──► Fournisseurs IA
 WhatsApp ─────────►│  │ (proxy)  │    │   Gateway     │──┐      │    (OpenAI,
 Discord ──────────►│  └──────────┘    └──────┬────────┘  │      │     Anthropic,
 Telegram ─────────►│                         │           │      │     Google, ...)
 API (tes projets) ►│                         ▼           ▼      │
                    │                   ┌──────────┐  ┌────────┐ │
                    │                   │ LiteLLM  │  │ Postgr │ │
                    │                   │  Proxy   │  │ pgvec  │ │
                    │                   └──────────┘  └────────┘ │
                    │                                             │
                    │   Optionnel: Cloudflare Tunnel, Diun,       │
                    │              rclone backup                  │
                    └─────────────────────────────────────────────┘
```

## Commandes

| Commande | Description |
|----------|-------------|
| `make setup` | Assistant de configuration initial (premiere utilisation) |
| `make up` | Demarrer tous les services |
| `make down` | Arreter tous les services |
| `make restart` | Redemarrer tous les services |
| `make status` | Afficher l'etat et la sante des services |
| `make logs` | Suivre les logs de tous les services |
| `make logs-openclaw` | Suivre les logs d'OpenClaw uniquement |
| `make logs-litellm` | Suivre les logs de LiteLLM uniquement |
| `make update` | Mettre a jour les images et redemarrer proprement |
| `make backup` | Sauvegarder la base de donnees et les configs |
| `make restore` | Restaurer depuis une sauvegarde |
| `make setup-backup` | Configurer la sauvegarde Google Drive |
| `make cli` | Ouvrir le CLI OpenClaw |
| `make config-get KEY=...` | Lire une valeur de configuration |
| `make config-set KEY=... VALUE=...` | Modifier une valeur de configuration |
| `make channels-status` | Verifier l'etat des canaux de messagerie |
| `make clean` | Supprimer conteneurs, volumes et sauvegardes (DESTRUCTIF) |
| `make help` | Afficher toutes les commandes disponibles |

## Fichiers de configuration

| Fichier | Role |
|---------|------|
| `.env` | Secrets et variables d'environnement (jamais commite) |
| `config/openclaw.json` | Configuration de la passerelle OpenClaw (modeles, canaux, agents) |
| `config/litellm.yaml` | Liste des modeles et parametres du proxy LiteLLM |
| `config/Caddyfile` | Regles du reverse proxy Caddy |
| `config/rclone.conf` | Identifiants Google Drive pour les backups (jamais commite) |

Voir `CLAUDE.md` pour une reference detaillee de chaque cle de configuration.

## Services et profils Docker

### Services principaux (toujours actifs)

| Service | Image | Role |
|---------|-------|------|
| `openclaw` | `ghcr.io/openclaw/openclaw:latest` | Passerelle IA, canaux, API |
| `litellm` | `ghcr.io/berriai/litellm:main-stable` | Routage des modeles IA, budgets |
| `postgres` | `pgvector/pgvector:0.8.0-pg17` | Base de donnees + recherche vectorielle |

### Services optionnels (actives via profils)

| Service | Profil | Role |
|---------|--------|------|
| `caddy` | `proxy` | Reverse proxy HTTPS automatique |
| `cloudflared` | `tunnel` | Cloudflare Tunnel pour acces public securise |
| `diun` | `notify` | Notifications de mises a jour d'images Docker |
| `backup` (rclone) | `backup` | Synchronisation des sauvegardes vers Google Drive |

Active les profils dans `.env` :
```bash
COMPOSE_PROFILES=tunnel,notify
```

## Acces distant

Deux methodes recommandees, combinables :

- **Tailscale** (sur la machine hote, pas dans Docker) — VPN mesh prive pour l'acces admin. Zero config reseau, gratuit pour usage perso.
- **Cloudflare Tunnel** (profil `tunnel` dans Docker) — expose l'API publiquement sans ouvrir de port, avec authentification par token.

## Strategie de mise a jour

Les mises a jour ne sont **jamais automatiques**. Le service Diun (profil `notify`) surveille les nouvelles versions d'images et te previent.

Quand tu veux mettre a jour :
```bash
make update
```

Le script :
1. Fait un backup automatique avant la mise a jour
2. Enregistre les images actuelles (pour rollback)
3. Telecharge les nouvelles images
4. Redemarre progressivement : postgres, puis litellm, puis openclaw
5. Verifie les healthchecks
6. Propose un rollback si quelque chose ne va pas

## Strategie de sauvegarde

```bash
make backup          # Sauvegarde manuelle
make setup-backup    # Configurer Google Drive
make restore         # Restaurer depuis une sauvegarde
```

Les sauvegardes incluent :
- Dump complet de PostgreSQL (compresse)
- Fichiers de configuration (.env, openclaw.json, litellm.yaml)
- Donnees OpenClaw (sessions, identite des agents)

Retention : 7 jours en local, 30 jours sur Google Drive.

Pour automatiser : ajoute un cron sur la machine hote :
```bash
crontab -e
# Ajouter : 0 3 * * * cd /chemin/vers/openclaw-light-full-stack && make backup
```

## Securite

- **Secrets** : `.env` et `config/rclone.conf` sont dans `.gitignore`, jamais commites
- **Tokens** : generes automatiquement (64 caracteres hex) par le setup
- **Reseau** : PostgreSQL et LiteLLM ne sont jamais exposes en dehors du reseau Docker interne
- **Ports exposes** : seul le port OpenClaw (18789) est expose sur la machine hote
- **Acces distant** : privilegier Cloudflare Tunnel ou Tailscale plutot que l'exposition directe de ports
- **Conteneurs** : utilisateur non-root (node:1000) pour OpenClaw

## Pre-requis

- Docker + Docker Compose v2
- 2 Go de RAM minimum (4 Go recommandes)
- ARM64 (Raspberry Pi 4/5, Apple Silicon) ou x86_64
- Au moins une cle API d'un fournisseur IA

## Utiliser l'API dans tes projets

L'API OpenClaw est compatible OpenAI. Tu peux l'utiliser depuis n'importe quel projet :

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://<ip-du-pi>:18789/v1",
    api_key="<ton-OPENCLAW_GATEWAY_TOKEN>",
)

response = client.chat.completions.create(
    model="litellm/gpt-4o-mini",
    messages=[{"role": "user", "content": "Bonjour !"}],
)
print(response.choices[0].message.content)
```

## Licence

MIT
