---
title: wikiDAI
sdk: docker
app_port: 7860
---

# wikiDAI (MVP com BookStack no Hugging Face Space)

Este repositório é a **fonte principal** do projeto `franciscoteston/wikiDAI`.
O Hugging Face Space é usado como ambiente de demonstração/deploy.

## Objetivo do MVP

Subir o BookStack em um Docker Space e semear automaticamente um conteúdo inicial em português para validar a hierarquia:

- **Livro**
- **Capítulo**
- **Página**

## O que este MVP entrega

- BookStack + MariaDB no mesmo container (apenas demonstração).
- Bootstrap do ambiente por `start.sh`.
- Seed idempotente via API do BookStack em `scripts/seed_bookstack.py`.
- Conteúdo inicial definido em `seed/manual_banco_mercado.json`.
- Instalação fresca usa o admin padrão do BookStack (`admin@admin.com` / `password`).
- Criação opcional de admin customizado via variáveis de ambiente.

## Limitações importantes

- Ambiente público de demonstração.
- Persistência pode ser limitada/reinicializada dependendo do Space.
- **Não é configuração de produção**.
- Não armazenar credenciais reais no repositório.

## Variáveis de ambiente

Exemplo mínimo para execução local/Space:

```bash
APP_URL=https://franciscoteston-wikidai.hf.space
APP_KEY=
BOOKSTACK_ADMIN_NAME=Admin Demo
BOOKSTACK_ADMIN_EMAIL=
BOOKSTACK_ADMIN_PASSWORD=
DB_DATABASE=bookstack
DB_USERNAME=bookstack
DB_PASSWORD=bookstack
DB_ROOT_PASSWORD=rootbookstack
USE_DATA_FOR_DB=false
BOOKSTACK_API_TOKEN_ID=
BOOKSTACK_API_TOKEN_SECRET=
```

Observações:
- `APP_KEY` pode ser vazio: o `start.sh` gera automaticamente com `php artisan key:generate`.
- Em deploy público, use segredos do ambiente (HF Secrets) para senhas.
- Em instalação fresca, faça login com `admin@admin.com` e senha `password` (altere imediatamente após o primeiro acesso).
- Para criar admin customizado, defina **ambas** `BOOKSTACK_ADMIN_EMAIL` e `BOOKSTACK_ADMIN_PASSWORD` (opcionalmente `BOOKSTACK_ADMIN_NAME`).
- `BOOKSTACK_API_TOKEN_ID` e `BOOKSTACK_API_TOKEN_SECRET` devem vir dos Secrets do Hugging Face, criados pela interface do BookStack.
- `USE_DATA_FOR_DB=false` é o padrão recomendado no MVP Hugging Face, com banco efêmero em `/tmp/wikidai-mariadb`.
- Para persistência real do banco, prefira banco externo (gerenciado) ou valide um volume dedicado com permissões corretas para o usuário `mysql`.
- `USE_DATA_FOR_DB=true` é experimental e usa `/data/mariadb`.
- No MVP, `/data` pode ser usado para uploads em `/data/bookstack_uploads` sem mover o banco.
- `RESET_DB_ON_START=true` deve ser usado somente em ambiente de demonstração para reset controlado do MariaDB.
- Com `USE_DATA_FOR_DB=false`, reinícios frios já recriam o banco efêmero em `/tmp`; `RESET_DB_ON_START` continua disponível para forçar reset no mesmo ciclo de execução.

## Como testar localmente

1. Build da imagem:

```bash
docker build -t wikidai:local .
```

2. Rodar container:

```bash
docker run --rm -p 7860:80 \
  -e APP_URL=https://franciscoteston-wikidai.hf.space \
  -e DB_DATABASE=bookstack \
  -e DB_USERNAME=bookstack \
  -e DB_PASSWORD=bookstack \
  -e DB_ROOT_PASSWORD=rootbookstack \
  wikidai:local
```

3. Acessar:

- BookStack: `http://localhost:7860` (mapeando a porta interna 80 para 7860 localmente)

4. Verificar seed:

- Livro: **Manual do Banco de Dados de Mercado — DAI / SBDS**
- 4 capítulos e páginas previstas.

## Publicação no Hugging Face Space (Docker)

1. Criar Space Docker em `franciscoteston/wikiDAI`.
2. Subir este conteúdo para o Space.
3. Definir Secrets no Space:
   - `DB_PASSWORD`
   - `DB_ROOT_PASSWORD`
   - `BOOKSTACK_API_TOKEN_ID`
   - `BOOKSTACK_API_TOKEN_SECRET`
4. Iniciar o Space; a aplicação sobe na porta `80`.

### Configurar token de API e executar seed manual via GitHub Actions

Como o comando `bookstack:api-token:create` não é utilizado no bootstrap, o token precisa ser criado manualmente pela interface do BookStack:

1. Em instalação fresca, acesse o Space e faça login com `admin@admin.com` / `password`.
2. Na interface do BookStack, crie um token de API para esse usuário.
3. Copie o **Token ID** e o **Token Secret** gerados.
4. No GitHub do repositório, adicione os Secrets em **Settings > Secrets and variables > Actions > Repository secrets**:
   - `BOOKSTACK_API_TOKEN_ID`
   - `BOOKSTACK_API_TOKEN_SECRET`
5. Execute o seed manual sem reiniciar o Space em **Actions > Seed BookStack > Run workflow**.

### Uso rápido do workflow manual (sem deploy)

- Workflow: **Seed BookStack** (`.github/workflows/seed-bookstack.yml`).
- Gatilho: `workflow_dispatch` (execução manual pela aba Actions).
- O workflow **não faz deploy** e **não reinicia** o Hugging Face Space; ele apenas chama a API pública do Space já em execução.
- Comando executado:

```bash
python3 scripts/seed_bookstack.py seed/manual_banco_mercado.json
```

## Idempotência do seed

O script de seed:
- procura livro por nome;
- procura capítulos pelo nome no livro;
- procura páginas pelo nome no capítulo;
- cria quando não existe e atualiza descrição/conteúdo quando já existe.

Assim, executar o seed novamente não duplica dados.

## Estrutura

- `Dockerfile`
- `start.sh`
- `scripts/seed_bookstack.py`
- `seed/manual_banco_mercado.json`
- `docs/estrutura-bookstack.md`
- `.gitignore`
