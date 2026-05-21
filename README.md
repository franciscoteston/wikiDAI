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
- Criação de usuário admin de demonstração apenas por variáveis de ambiente.

## Limitações importantes

- Ambiente público de demonstração.
- Persistência pode ser limitada/reinicializada dependendo do Space.
- **Não é configuração de produção**.
- Não armazenar credenciais reais no repositório.

## Variáveis de ambiente

Exemplo mínimo para execução local/Space:

```bash
APP_URL=http://localhost:7860
APP_KEY=
BOOKSTACK_ADMIN_NAME=Admin Demo
BOOKSTACK_ADMIN_EMAIL=admin@example.local
BOOKSTACK_ADMIN_PASSWORD=trocar-esta-senha
DB_DATABASE=bookstack
DB_USERNAME=bookstack
DB_PASSWORD=bookstack
DB_ROOT_PASSWORD=rootbookstack
```

Observações:
- `APP_KEY` pode ser vazio: o `start.sh` gera automaticamente com `php artisan key:generate`.
- Em deploy público, use segredos do ambiente (HF Secrets) para senhas.

## Como testar localmente

1. Build da imagem:

```bash
docker build -t wikidai:local .
```

2. Rodar container:

```bash
docker run --rm -p 7860:7860 \
  -e APP_URL=http://localhost:7860 \
  -e BOOKSTACK_ADMIN_NAME='Admin Demo' \
  -e BOOKSTACK_ADMIN_EMAIL='admin@example.local' \
  -e BOOKSTACK_ADMIN_PASSWORD='trocar-esta-senha' \
  -e DB_DATABASE=bookstack \
  -e DB_USERNAME=bookstack \
  -e DB_PASSWORD=bookstack \
  -e DB_ROOT_PASSWORD=rootbookstack \
  wikidai:local
```

3. Acessar:

- BookStack: `http://localhost:7860`

4. Verificar seed:

- Livro: **Manual do Banco de Dados de Mercado — DAI / SBDS**
- 4 capítulos e páginas previstas.

## Publicação no Hugging Face Space (Docker)

1. Criar Space Docker em `franciscoteston/wikiDAI`.
2. Subir este conteúdo para o Space.
3. Definir Secrets no Space:
   - `BOOKSTACK_ADMIN_NAME`
   - `BOOKSTACK_ADMIN_EMAIL`
   - `BOOKSTACK_ADMIN_PASSWORD`
   - `DB_PASSWORD`
   - `DB_ROOT_PASSWORD`
4. Iniciar o Space; a aplicação sobe na porta `7860`.

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
