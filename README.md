# laboratorio.local

> Infraestrutura de laboratório Active Directory com Apache Guacamole, email corporativo e acesso remoto — tudo rodando em contêineres Docker.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-required-2496ED?logo=docker)](https://docker.com)
[![Windows](https://img.shields.io/badge/Windows%20Server-2022-0078D6?logo=windows)](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022)
[![Guacamole](https://img.shields.io/badge/Guacamole-1.5-green?logo=apache)](https://guacamole.apache.org)

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Arquitetura](#arquitetura)
3. [Pré-requisitos](#pré-requisitos)
4. [Quick Start](#quick-start)
5. [Serviços](#serviços)
   - [MySQL](#mysql)
   - [Guacamole](#guacamole)
   - [Windows Server](#windows-server)
   - [Linux Desktop](#linux-desktop-opcional)
   - [Cloudflare Tunnel](#cloudflare-tunnel-opcional)
6. [Active Directory](#active-directory)
   - [Estrutura](#estrutura-do-ad)
   - [Automação](#automação-do-setup)
7. [Apache Guacamole](#apache-guacamole)
   - [Autenticação LDAP](#autenticação-ldap)
   - [Conexões](#configuração-de-conexões)
 8. [Mail Server (LDAP)](#mail-server)
 9. [Webmail (Roundcube)](#webmail)
 10. [Email Corporativo](#email-corporativo)
 11. [Rede](#rede)
 12. [Segurança](#segurança)
 13. [Manutenção](#manutenção)
 14. [Troubleshooting](#troubleshooting)
 15. [Roadmap](#roadmap)

---

## Visão Geral

O **laboratorio.local** é uma solução completa de infraestrutura de TI rodando inteiramente em contêineres Docker. Ideal para:

- **Estudos** — Ambiente controlado para aprender Active Directory, LDAP, Docker e administração Windows.
- **Homologação** — Teste de políticas de grupo, scripts de login, integração LDAP e aplicações corporativas.
- **Produtividade** — Acesso remoto a múltiplos desktops via navegador com Apache Guacamole + LDAP.
- **Email** — Servidor de email (Postfix/Dovecot) com autenticação LDAP e webmail Roundcube.

### Componentes Principais

| Componente            | Função                                      | Portas                |
|-----------------------|---------------------------------------------|-----------------------|
| **MySQL**             | Banco de dados do Apache Guacamole          | 3306                  |
| **Guacd**             | Proxy de protocolo remoto (RDP, VNC, SSH)   | 4822                  |
| **Guacamole**         | Interface web de acesso remoto              | 8080                  |
| **Windows Server 2022** | Domain Controller, DNS, LDAP             | 3389, 389, 88         |
| **Mail Server**       | Postfix + Dovecot com autenticação LDAP     | 25, 143, 587          |
| **Webmail**           | Roundcube (webmail com IMAP/SMTP)           | 8081                  |
| **Linux Desktop**     | Desktop Linux para acesso via Guacamole     | 5900 (VNC)            |
| **Cloudflare Tunnel** | Exposição segura via Cloudflare (opcional)  | —                     |

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────────┐
│                        Host Docker                            │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌─────────┐  │
│  │  MySQL   │  │  Guacd   │  │  Guacamole   │  │  Linux  │  │
│  │ :3306    │  │ :4822    │  │ :8080        │  │ :5900   │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  └─────────┘  │
│       │              │              │                         │
│       └──────────────┴──────────────┘                         │
│                        │ LDAP auth                            │
│  ┌─────────────────────▼──────────────────────────────────┐   │
│  │              Windows Server 2022                        │   │
│  │  ┌──────────┐  ┌──────────────┐                        │   │
│  │  │ AD DS    │  │    DNS       │                        │   │
│  │  │ :389     │  │    :53       │                        │   │
│  │  └──────────┘  └──────────────┘                        │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │    KVM (dockurr/windows)                         │   │   │
│  │  │    RDP :3389 | Web UI :8006                      │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                        │ LDAP auth                            │
│  ┌─────────────────────▼──────────────────────────────────┐   │
│  │  Mail Server (Postfix + Dovecot)                       │   │
│  │  :25 (SMTP)  :143 (IMAP)  :587 (SMTP TLS)             │   │
│  └─────────────────────┬──────────────────────────────────┘   │
│                        │ IMAP/SMTP                            │
│  ┌─────────────────────▼──────────────────────────────────┐   │
│  │  Roundcube (Webmail)                                   │   │
│  │  :8081                                                 │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  lab-network (bridge 172.19.0.0/16)                      │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### Fluxo de Autenticação

```
Usuário → Navegador → Guacamole (:8080) → LDAP (:389) → AD DS (valida credenciais)
                                                    ↓
                                              Grupo "G_Guacamole_Acesso"?
                                                    ↓
                                              Concede acesso às conexões
                                                    ↓
                                        RDP (:3389) | VNC (:5900) | SSH (:22)
```

---

## Pré-requisitos

### Hardware

| Recurso          | Mínimo     | Recomendado |
|------------------|------------|-------------|
| CPU              | 4 cores    | 8 cores     |
| RAM              | 8 GB       | 16 GB       |
| Disco            | 80 GB      | 120 GB SSD  |
| KVM              | Obrigatório | —           |

### Software

- **Linux** (testado em Ubuntu 22.04/24.04)
- **Docker Engine** 24+ com `docker compose` plugin
- **KVM** habilitado no kernel (`kvm-ok` deve retornar sucesso)
- **Git** (para clonar o repositório)

### Verificação Rápida

```bash
# Verificar KVM
sudo kvm-ok

# Verificar Docker
docker --version && docker compose version

# Instalar dependências (Ubuntu)
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git
```

---

## Quick Start

```bash
# 1. Clone o repositório
git clone https://github.com/TyagoAlves/laboratorio.local.git
cd laboratorio.local

# 2. (Opcional) Configure variáveis de ambiente
cp .env.example .env
# Edite .env com suas preferências

# 3. Inicie os serviços
docker compose up -d

# 4. Acompanhe os logs
docker compose logs -f

# 5. Aguarde o setup completar (10-18 minutos)
# O Windows Server irá reiniciar automaticamente durante a instalação do AD

# 6. Configure o Guacamole (grupo + conexões + permissões)
# Execute os comandos da seção "Configuração Pós-Setup"

# 7. Acesse o webmail
# http://localhost:8081 (administrator@laboratorio.local / SenhaForte@2026)
```

### Tempo Estimado

| Etapa                         | Tempo      |
|-------------------------------|------------|
| Download das imagens          | 2-5 min    |
| Boot do Windows Server        | 2-3 min    |
| Instalação do AD (fase 1)     | 1-2 min    |
| Reboot                        | 1 min      |
| Configuração (fase 2)         | 3-5 min    |
| **Total**                     | **10-12 min** |

### Acessos

| Serviço              | URL / Endpoint                | Credenciais                      |
|----------------------|-------------------------------|----------------------------------|
| Windows RDP          | `localhost:3389`              | `Administrator` / `SenhaForte@2026` |
| Windows Web UI (KVM) | `http://localhost:8006`       | —                                |
| Guacamole Web        | `http://localhost:8080/guacamole/` | Usuário AD + senha         |
| Webmail (Roundcube)  | `http://localhost:8081`       | `administrator@laboratorio.local` / `SenhaForte@2026` |
| Linux Desktop (VNC)  | `http://localhost:5900`       | `SenhaForte@2026`                |
| SMTP                 | `localhost:25`                | Usuário AD + senha (auth)        |
| IMAP                 | `localhost:143`               | Usuário AD + senha               |

> **Nota**: Substitua `localhost` pelo IP do servidor Docker se estiver acessando remotamente.

---

## Serviços

### MySQL

Banco de dados do Apache Guacamole. Armazena configurações de conexões, usuários e sessões.

```yaml
services:
  mysql:
    image: mysql:8
    container_name: lab-mysql
    volumes:
      - mysql_data:/var/lib/mysql
      - ./init/initdb.sql:/docker-entrypoint-initdb.d/initdb.sql
```

- Dados persistentes no volume `mysql_data`
- Health check automático a cada 10s
- Usuário `guacamole_user` com permissão total no banco `guacamole_db`
- Schema do Guacamole auto-inicializado via `init/initdb.sql` na primeira execução
  - Cria todas as tabelas (guacamole_user, guacamole_entity, etc.)
  - Cria o usuário admin padrão: `guacadmin` / `guacadmin`

### Guacamole

O Apache Guacamole fornece acesso remoto a desktops via navegador, sem necessidade de cliente RDP/VNC/SSH.

**Autenticação híbrida**: banco de dados MySQL + consulta LDAP ao Active Directory.

> ⚠️ O Guacamole requer que as tabelas do MySQL estejam inicializadas.
> Isso acontece automaticamente na primeira execução via `init/initdb.sql`.
> Se o banco já existir sem as tabelas, execute `./init/initdb.sh --apply` manualmente.

**Porta de acesso:** `8080` exposta no host para acesso via navegador.

```yaml
guacamole:
  image: guacamole/guacamole
  environment:
    LDAP_HOSTNAME: windows
    LDAP_PORT: "389"
    LDAP_USER_BASE_DN: DC=laboratorio,DC=local
    LDAP_USERNAME_ATTRIBUTE: sAMAccountName
    LDAP_GROUP_BASE_DN: DC=laboratorio,DC=local
    LDAP_GROUP_SEARCH_FILTER: "(objectClass=group)"
    LDAP_NESTED_GROUPS: "true"
```

#### Configuração Pós-Setup

Após o setup do Windows completar (10-18 min), execute os comandos abaixo para criar o grupo de acesso e as conexões no Guacamole automaticamente.

**Passo 1 — Registrar o grupo no MySQL:**

```bash
docker exec lab-mysql mysql -u root -prootpass guacamole_db <<-EOSQL
INSERT INTO guacamole_entity (name, type) VALUES ('G_Guacamole_Acesso', 'USER_GROUP');
INSERT INTO guacamole_user_group (entity_id, disabled)
  SELECT entity_id, 0 FROM guacamole_entity WHERE name = 'G_Guacamole_Acesso' AND type = 'USER_GROUP';
EOSQL
```

**Passo 2 — Criar conexões via API:**

```bash
# Obter token de autenticação
GUAC_TOKEN=$(curl -s -X POST http://localhost:8080/guacamole/api/tokens \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=guacadmin&password=guacadmin" | python3 -c "import json,sys; print(json.load(sys.stdin)['authToken'])")

# Criar conexão RDP para o Windows Server
curl -s -X POST "http://localhost:8080/guacamole/api/session/data/mysql/connections?token=$GUAC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "parentIdentifier":"ROOT",
    "name":"Windows Server 2022",
    "protocol":"rdp",
    "parameters":{
      "hostname":"windows","port":"3389",
      "username":"Administrator","password":"SenhaForte@2026",
      "domain":"laboratorio","ignore-cert":"true","security":"any",
      "resize-method":"display-update","color-depth":"32",
      "enable-wallpaper":"false","enable-theming":"false",
      "enable-font-smoothing":"true","disable-audio":"true"
    }
  }'

# Criar conexão SSH para o Linux Desktop
curl -s -X POST "http://localhost:8080/guacamole/api/session/data/mysql/connections?token=$GUAC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "parentIdentifier":"ROOT",
    "name":"Linux Desktop",
    "protocol":"ssh",
    "parameters":{
      "hostname":"linux-desktop","port":"22",
      "username":"ubuntu","password":"ubuntu"
    }
  }'
```

**Passo 3 — Conceder permissão READ ao grupo:**

```bash
docker exec lab-mysql mysql -u root -prootpass guacamole_db <<-EOSQL
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
  SELECT e.entity_id, c.connection_id, 'READ'
  FROM guacamole_entity e, guacamole_connection c
  WHERE e.name = 'G_Guacamole_Acesso' AND e.type = 'USER_GROUP';
EOSQL
```

Agora acesse `http://localhost:8080/guacamole/` e faça login como **Administrator** (senha: `SenhaForte@2026`). As conexões aparecerão automaticamente.

> Alternativamente, configure manualmente via GUI com `guacadmin` seguindo as instruções abaixo.

### Windows Server

O Windows Server 2022 roda via **dockurr/windows** — uma imagem que executa o Windows em uma máquina virtual KVM dentro de um contêiner Docker.

```yaml
windows:
  image: dockurr/windows
  devices:
    - /dev/kvm
    - /dev/net/tun
  cap_add:
    - NET_ADMIN
    - NET_RAW
  environment:
    VERSION: win2022
    USERNAME: Administrator
    PASSWORD: SenhaForte@2026
```

**Serviços internos do Windows:**

| Serviço       | Função                          | Porta |
|---------------|---------------------------------|-------|
| AD DS         | Active Directory Domain Services| 389   |
| DNS           | Servidor DNS                    | 53    |
| Kerberos      | Autenticação                    | 88    |
| WinRM         | Gerenciamento remoto            | 5985  |
| SMB           | Compartilhamento de arquivos    | 445   |

#### Arquivos de Setup

O diretório `oem/` contém scripts executados automaticamente dentro do Windows na primeira inicialização:

```
oem/
├── install.bat            # Entry point executado pelo dockurr/windows
├── setup.ps1              # Script principal (AD + grupos + mail attribute)
└── hMailServer-*.exe      # Instalador do hMailServer (opcional)
```

### Mail Server (Postfix + Dovecot com LDAP)

Servidor de email completo com autenticação integrada ao Active Directory. Substitui o hMailServer com uma solução Docker nativa.

```yaml
mailserver:
  image: docker.io/mailserver/docker-mailserver:latest
  environment:
    ACCOUNT_PROVISIONER: LDAP
    LDAP_SERVER_HOST: ldap://windows
    DOVECOT_AUTH_BIND: "yes"
```

- **Autenticação LDAP** — Usuários do AD autenticam SMTP e IMAP com login/senha do domínio
- **Sem contas locais** — `postfix-accounts.cf` é ignorado quando `ACCOUNT_PROVISIONER=LDAP`
- **Contas desabilitadas** — Usuários com conta desabilitada no AD são rejeitados automaticamente
- **Requer** que o atributo `mail` esteja populado no AD (feito automaticamente pelo `setup.ps1`)
- **Formato do email:** `sAMAccountName@laboratorio.local` (ex: `administrator@laboratorio.local`)

**Portas expostas:**

| Porta | Protocolo | Uso                    |
|-------|-----------|------------------------|
| 25    | SMTP      | Envio (com autenticação)|
| 143   | IMAP      | Recebimento            |
| 587   | SMTP TLS  | Envio autenticado (recomendado) |

### Webmail (Roundcube)

Interface web para acessar emails via navegador. Conecta no mail server via IMAP/SMTP.

```yaml
roundcube:
  image: roundcube/roundcubemail:latest
  ports:
    - "8081:80"
```

- Acesse: `http://localhost:8081`
- Login: `administrator@laboratorio.local` / `SenhaForte@2026`
- Qualquer usuário do AD com `mail` populado pode fazer login
- Certificados SSL auto-assinados são aceitos automaticamente

### Linux Desktop (opcional)

Desktop Ubuntu com ambiente LXDE acessível via VNC. Pode ser adicionado como conexão no Guacamole para acesso via navegador.

### Cloudflare Tunnel (opcional)

Expõe o Guacamole publicamente sem abrir portas no firewall. Ative com:

```bash
docker compose --profile tunnel up -d cloudflared
```

---

## Active Directory

### Estrutura do AD

```
DC=laboratorio,DC=local
├── OU=Usuarios
├── OU=Grupos
│   └── CN=G_Guacamole_Acesso (Global Security Group)
└── OU=Servidores
```

### Usuários

| Usuário          | Função                  | Senha           |
|------------------|-------------------------|-----------------|
| `Administrator`  | Admin do domínio        | `SenhaForte@2026` |

> Usuários adicionais podem ser criados via `dsadd` ou console ADUC.

### Grupos

| Grupo                | Descrição                                  |
|----------------------|--------------------------------------------|
| `G_Guacamole_Acesso` | Concede acesso às conexões do Guacamole    |

Para adicionar um usuário ao grupo:

```powershell
# No Windows Server
Add-ADGroupMember -Identity "G_Guacamole_Acesso" -Members "usuario"
```

### Automação do Setup

O script `oem/setup.ps1` executa em duas fases:

**Fase 1 — Primeiro boot:**
1. Desabilita Ctrl+Alt+Del e configura auto-logon do Administrator
2. Instala a feature AD-Domain-Services
3. Cria a floresta `laboratorio.local`
4. Configura DNS integrado
5. Agenda a Fase 2 via RunOnce
6. Reinicia o servidor

**Fase 2 — Após o reboot:**
1. Verifica se o domínio está operacional
2. Cria as OUs: Usuarios, Grupos, Servidores
3. Cria o grupo `G_Guacamole_Acesso`
4. Adiciona `Administrator` ao grupo `G_Guacamole_Acesso`
5. Habilita WinRM e libera a porta 5985
6. Cria um SMB share `Compartilhado`
7. Popula o atributo `mail` no AD para integração com o mail server

---

## Apache Guacamole

### Autenticação LDAP

O Guacamole consulta o Active Directory para autenticar usuários e resolver associações de grupo.

```
Variáveis de ambiente relevantes:

LDAP_HOSTNAME=windows              → Container do Windows Server
LDAP_PORT=389                      → Porta LDAP padrão
LDAP_USER_BASE_DN=DC=laboratorio,DC=local
LDAP_USERNAME_ATTRIBUTE=sAMAccountName
LDAP_SEARCH_BIND_DN=CN=Administrator,CN=Users,DC=laboratorio,DC=local
LDAP_SEARCH_BIND_PASSWORD=SenhaForte@2026
LDAP_GROUP_BASE_DN=DC=laboratorio,DC=local
LDAP_GROUP_NAME_ATTRIBUTE=cn
LDAP_MEMBER_ATTRIBUTE=member
LDAP_GROUP_SEARCH_FILTER=(objectClass=group)
LDAP_NESTED_GROUPS=true
```

### Fluxo de Autorização

1. Usuário faz login com `sAMAccountName` + senha
2. Guacamole vincula ao AD com as credenciais fornecidas
3. Guacamole busca grupos onde o usuário é membro do atributo `member`
4. Os grupos encontrados são usados para determinar quais conexões o usuário pode acessar
5. Com `LDAP_NESTED_GROUPS=true`, grupos aninhados (grupos dentro de grupos) são resolvidos recursivamente via `LDAP_MATCHING_RULE_IN_CHAIN`

### Configuração de Conexões

1. Acesse `http://localhost:8080/guacamole/` como **guacadmin**
2. Vá em **Settings → Connection Groups**
3. Crie conexões para os serviços desejados:

| Nome            | Protocolo | Hostname        | Porta |
|-----------------|-----------|-----------------|-------|
| WinLab-Client   | RDP       | `windows`       | 3389  |
| Linux-Desktop   | VNC       | `linux-desktop` | 5900  |

4. Atribua permissão **READ** ao grupo `G_Guacamole_Acesso` em cada conexão

> Após configurar, usuários do grupo `G_Guacamole_Acesso` veem apenas as conexões que lhes foram atribuídas.

---

## Email Corporativo

O laboratório usa **docker-mailserver** (Postfix + Dovecot) com autenticação integrada ao Active Directory via LDAP.

### Fluxo de Autenticação

```
Usuário → Cliente de email (Outlook/Thunderbird/Roundcube)
                ↓
         SMTP (:25) / IMAP (:143)
                ↓
       docker-mailserver consulta AD via LDAP
                ↓
         Bind com credenciais do usuário
                ↓
       Senha validada contra o AD → Acesso concedido/negado
```

- **Postfix** (SMTP) — faz bind LDAP como `Administrator` para consultar usuários
- **Dovecot** (IMAP) — `auth_bind = yes`: conecta como o próprio usuário final, validando a senha diretamente contra o AD
- **Filtro de segurança:** usuários com conta desabilitada no AD (`userAccountControl` bit 1) são rejeitados

### Criar Contas

Não é necessário criar contas manualmente. Todo usuário do AD com o atributo `mail` populado pode enviar e receber emails.

O `setup.ps1` popula automaticamente o `mail` de todos os usuários no formato `sAMAccountName@laboratorio.local`.

Para criar um novo usuário com email:

```powershell
# No Windows Server (RDP)
New-ADUser -Name "João Silva" -SamAccountName "joao" -UserPrincipalName "joao@laboratorio.local" -Enabled $true -PasswordNeverExpires $true -AccountPassword (ConvertTo-SecureString "Senha@2026" -AsPlainText -Force)
Set-ADUser joao -EmailAddress "joao@laboratorio.local"
Add-ADGroupMember -Identity "G_Guacamole_Acesso" -Members "joao"
```

### Clientes de Email

| Cliente       | SMTP         | IMAP         | Webmail              |
|---------------|--------------|--------------|----------------------|
| Outlook       | `localhost:25` | `localhost:143` | —                  |
| Thunderbird   | `localhost:587` TLS | `localhost:143` TLS | — |
| Roundcube     | —            | —            | `http://localhost:8081` |

### Diagnóstico

```bash
# Verificar mail attribute no AD
docker exec lab-windows powershell "Get-ADUser Administrator -Properties mail"

# Testar autenticação SMTP contra LDAP
docker exec lab-mailserver swaks --to administrator@laboratorio.local \
  --server localhost --auth LOGIN --auth-user administrator@laboratorio.local \
  --auth-password SenhaForte@2026

# Testar autenticação IMAP
echo -e 'A001 LOGIN administrator@laboratorio.local SenhaForte@2026\r\n' \
  | openssl s_client -connect localhost:143 -starttls imap -quiet 2>/dev/null

# Verificar portas
for p in 25 143 587; do
  echo > /dev/tcp/localhost/$p 2>/dev/null && echo "Porta $p: OK" || echo "Porta $p: FECHADA"
done
```

---

## Rede

### Topologia

| Sub-rede         | Descrição                          |
|------------------|------------------------------------|
| 172.19.0.0/16    | Docker bridge (`lab_lab-network`)  |
| 172.30.0.0/24    | Rede interna KVM (Windows ↔ Samba) |
| 192.168.0.0/24   | Rede local do host (exemplo)       |

### Nomes DNS

| Nome               | IP Interno     | Serviço               |
|--------------------|----------------|-----------------------|
| `windows`          | 172.19.0.x     | Windows Server        |
| `mysql`            | 172.19.0.x     | MySQL                 |
| `guacd`            | 172.19.0.x     | Guacd                 |
| `guacamole`        | 172.19.0.x     | Apache Guacamole      |
| `mailserver`       | 172.19.0.x     | Postfix + Dovecot     |
| `roundcube`        | 172.19.0.x     | Roundcube Webmail     |
| `linux-desktop`    | 172.19.0.x     | Linux Desktop         |
| `host.lan`         | 172.30.0.1     | Samba gateway         |

---

## Segurança

### Recomendações

1. **Altere as senhas padrão** — modifique `ADMIN_PASSWORD` no `.env` antes de expor o ambiente
2. **Firewall** — nunca exponha portas administrativas (3389, 8006, 5985) à internet
3. **Cloudflare Tunnel** — prefira o túnel para acesso externo ao Guacamole
4. **TLS** — configure certificados no Guacamole e no mail server para ambientes produtivos
5. **Backup** — faça backup regular dos volumes Docker: `mysql_data` e `windows_disk`

### Variáveis Sensíveis

Crie um arquivo `.env` na raiz do projeto:

```bash
# .env.example
ADMIN_PASSWORD=SenhaForte@2026
MYSQL_ROOT_PASSWORD=rootpass
GUACAMOLE_DB_PASSWORD=guacamole_pass
VNC_PASSWORD=SenhaForte@2026
RAM_SIZE=3G
CPU_CORES=2
DISK_SIZE=60G
```

---

## Manutenção

### Comandos Úteis

```bash
# Ver status dos serviços
docker compose ps

# Ver logs em tempo real
docker compose logs -f

# Reiniciar um serviço específico
docker compose restart guacamole

# Parar todos os serviços
docker compose down

# Parar e remover volumes (⚠️ destrutivo)
docker compose down -v

# Executar comando dentro do Windows
docker exec lab-windows powershell "Get-Service"

# Acessar o shell do container Windows
docker exec -it lab-windows sh
```

### Atualizações

```bash
# Atualizar imagens
docker compose pull

# Recriar containers
docker compose up -d --force-recreate
```

### Reinicializar o Banco do Guacamole

Caso o schema do MySQL não tenha sido criado automaticamente:

```bash
# Gerar e aplicar o schema manualmente
./init/initdb.sh

# Ou aplicar apenas se o initdb.sql já existir
./init/initdb.sh --apply
```

### Backup

```bash
# Backup dos volumes
docker run --rm -v mysql_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/mysql_data.tar.gz -C /data .

docker run --rm -v windows_disk:/data -v $(pwd):/backup alpine \
  tar czf /backup/windows_disk.tar.gz -C /data .
```

---

## Troubleshooting

### Windows não inicia

Verifique se KVM está habilitado:

```bash
sudo kvm-ok
# Saída esperada: KVM acceleration can be used
```

Caso negativo, habilite a virtualização na BIOS/UEFI do servidor.

### Guacamole não conecta ao LDAP (ERRO 3)

```bash
# Verificar se o Windows está acessível
docker exec lab-guacamole nc -zv windows 389

# Verificar logs do Guacamole
docker compose logs guacamole
```

**Causa provável:** O Windows Server ainda está em processo de instalação.
O setup do AD leva de 10 a 18 minutos. Acompanhe com:

```bash
docker compose logs -f windows
```

O LDAP funcionará automaticamente quando o `setup.ps1` concluir a configuração do Active Directory.

### Guacamole retorna "Table doesn't exist" (ERRO 2)

```bash
# Verificar se as tabelas foram criadas
docker exec lab-mysql mysql -u root -prootpass guacamole_db -e "SHOW TABLES;"

# Se vazio, aplicar o schema manualmente
./init/initdb.sh --apply
```

Isso acontece se o MySQL já existia antes da adição do `init/initdb.sql`.
Na primeira execução limpa o schema é criado automaticamente.

### Porta 8080 não responde (ERRO 1)

```bash
# Verificar se o container expõe a porta
docker ps --filter name=lab-guacamole --format "{{.Ports}}"

# Deve mostrar: 0.0.0.0:8080->8080/tcp
# Se não aparecer, verifique se o docker-compose.yml tem "ports:"
```

### E-mail não funciona

```bash
# Verificar status do mailserver
docker ps --filter name=lab-mailserver --format "{{.Status}}"

# Verificar logs
docker compose logs mailserver

# Verificar se o mail attribute está populado no AD
docker exec lab-windows powershell "Get-ADUser Administrator -Properties mail"

# Verificar banner SMTP
timeout 5 bash -c 'exec 3<>/dev/tcp/localhost/25; sleep 1; echo "EHLO test" >&3; cat <&3'

# Executar diagnóstico completo
bash diagnose-setup.sh
```

**Causa comum:** O `mail attribute` não foi populado no AD. Execute o `setup.ps1` novamente
ou população manual com: `Set-ADUser usuario -EmailAddress "usuario@laboratorio.local"`.

### OEM não executa (setup.ps1 não roda)

```bash
# Verificar se install.bat existe dentro do Windows
docker exec lab-windows cmd /c "dir C:\OEM\"

# Se vazio, o volume ./oem não está montado corretamente
docker inspect lab-windows | jq '.[].Mounts'

# Executar o diagnóstico completo
bash diagnose-setup.sh
```

**Causa:** O dockurr/windows só executa OEM se existir `install.bat` em `C:\OEM\`.
Sem o `install.bat`, o setup.ps1 nunca é chamado e o AD não é instalado.

### Senha do AD esquecida

Faça o bind com a senha de recuperação do modo DSRM:

```bash
# A senha DSRM é a mesma definida em ADMIN_PASSWORD
# Conecte via RDP e redefina:
net user Administrator NovaSenha@2026 /domain
```

### Container Windows lento

Aumente os recursos no `.env`:

```bash
RAM_SIZE=8G
CPU_CORES=4
```

Depois recrie:

```bash
docker compose up -d --force-recreate windows
```

---

## Roadmap

- [x] **Auto-configuração Guacamole** — SQL + API para criar grupo, conexões e permissões automaticamente
- [x] **Auto-configuração Email (LDAP)** — Postfix/Dovecot autenticam contra AD; Roundcube webmail
- [ ] **Backup automático** — Script de backup dos volumes Docker para armazenamento externo
- [ ] **Monitoramento** — Integração com Prometheus + Grafana
- [ ] **Ansible** — Playbook para deploy automatizado em servidores bare-metal
- [ ] **Multi-domínio** — Suporte a múltiplos domínios no AD

---

## Licença

Este projeto é distribuído sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

---

<p align="center">
  Feito com ☕ por <a href="https://github.com/TyagoAlves">Tyago Alves</a>
</p>
