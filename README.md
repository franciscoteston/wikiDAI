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
- `APP_KEY` deve ser configurado como Secret no Hugging Face no formato `base64:<valor>`.
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
4. Iniciar o Space; o Hugging Face expõe a porta `7860` e, internamente, o proxy encaminha para o BookStack na porta `80`.

### Fluxo validado para executar o seed

1. Aguardar o Hugging Face Space subir.
2. Acessar `https://franciscoteston-wikidai.hf.space`.
3. Em instalação fresca, fazer login com `admin@admin.com` / `password`.
4. Trocar a senha imediatamente no primeiro acesso.
5. Criar API Token no perfil do usuário admin no BookStack.
6. Salvar no GitHub Repository secrets:
   - `BOOKSTACK_API_TOKEN_ID`
   - `BOOKSTACK_API_TOKEN_SECRET`
7. Rodar no GitHub: **Actions > Seed BookStack > Run workflow**.
8. Confirmar no BookStack a criação do livro **Manual do Banco de Dados de Mercado — DAI / SBDS**.

### Uso rápido do workflow manual (sem deploy)

- Workflow: **Seed BookStack** (`.github/workflows/seed-bookstack.yml`).
- Gatilho: `workflow_dispatch` (execução manual pela aba Actions).
- O workflow **não faz deploy** e **não reinicia** o Hugging Face Space; ele apenas chama a API pública do Space já em execução.
- Comando executado:

```bash
python3 scripts/seed_bookstack.py seed/manual_banco_mercado.json
```


## Marco validado do MVP

- **Data:** maio/2026.
- **Status:** MVP funcional validado.
- **Ambiente:** Hugging Face Space `franciscoteston/wikiDAI`.
- **Repositório principal:** GitHub `franciscoteston/wikiDAI`.
- BookStack sobe no Space e fica acessível publicamente.
- Login inicial padrão funciona: `admin@admin.com` / `password`.
- A senha foi alterada no primeiro acesso após bootstrap.
- Seed manual via GitHub Actions validado com sucesso contra `https://franciscoteston-wikidai.hf.space`.
- Conteúdo inicial criado: livro **Manual do Banco de Dados de Mercado — DAI / SBDS**, com 4 capítulos e páginas previstas.
- **Observação:** enquanto o banco estiver efêmero, reinícios do Space podem apagar usuário, token e conteúdo.

## Decisões técnicas do MVP

- O Hugging Face Space é ambiente de demonstração, não produção.
- O GitHub é a fonte principal do código.
- O seed foi separado do deploy para evitar reiniciar o Space.
- O token de API é criado manualmente pela interface do BookStack.
- O banco ainda deve ser tratado como efêmero no MVP.
- A persistência real do banco fica para etapa posterior, preferencialmente com banco externo ou volume validado.

## Próximas etapas

- Refinar conteúdo do manual no arquivo `seed/manual_banco_mercado.json`.
- Avaliar persistência real do banco.
- Avaliar banco externo.
- Automatizar bootstrap completo sem depender de token manual, se tecnicamente viável.
- Criar novos livros para outros manuais/processos da DAI.
- Melhorar governança do conteúdo: revisão, versionamento e atualização.

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
