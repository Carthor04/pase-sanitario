# Pase Sanitario

PWA para controlar salidas de alumnos al baño y a enfermería. Contexto, reglas y plan en [CLAUDE.md](CLAUDE.md) y [docs/](docs/).

## Arranque

Requisitos: Node 20+ (probado con 24). Para la BD local (Fase 1 en adelante): Docker Desktop.

```bash
npm install
cp .env.example .env.local
npm run dev
```

Scripts: `dev`, `build`, `preview`, `lint`, `typecheck`, `test`, `test:db` (pruebas SQL contra la BD vinculada), `format`.

Supabase (CLI incluida como dependencia de desarrollo):

```bash
npx supabase init     # solo la primera vez; genera supabase/config.toml
npx supabase start    # requiere Docker
npx supabase db reset # aplica migraciones + seed
```

En desarrollo, los roles se simulan con `?roles=` hasta que exista el login (Fase 1), por ejemplo `/en-vivo?roles=prefect` o `/grupo?roles=coordinator,teacher`.

## Red con inspección HTTPS (Fortinet)

Si `npm install` falla con `UNABLE_TO_VERIFY_LEAF_SIGNATURE`, la red está interceptando HTTPS. Usa otra red, o pide a TI el certificado raíz y configúralo solo para npm:

```bash
npm config set cafile "C:\ruta\al\certificado-fortinet.pem"
```
