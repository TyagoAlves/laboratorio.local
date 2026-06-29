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
8. [Email Corporativo (hMailServer)](#email-corporativo)
9. [Rede](#rede)
10. [Segurança](#segurança)
11. [Manutenção](#manutenção)
12. [Troubleshooting](#troubleshooting)
13. [Roadmap](#roadmap)

---

## Visão Geral

O **laboratorio.local** é uma solução completa de infraestrutura de TI rodando inteiramente em contêineres Docker. Ideal para:

- **Estudos** — Ambiente controlado para aprender Active Directory, LDAP, Docker e administração Windows.
- **Homologação** — Teste de políticas de grupo, scripts de login, integração LDAP e aplicações corporativas.
- **Produtividade** — Acesso remoto a múltiplos desktops via navegador com Apache Guacamole + LDAP.
- **Email** — Servidor de email funcional com hMailServer para testes e comunicações internas.

### Componentes Principais

| Componente            | Função                                      | Portas        |
|-----------------------|---------------------------------------------|---------------|
| **MySQL**             | Banco de dados do Apache Guacamole          | 3306          |
| **Guacd**             | Proxy de protocolo remoto (RDP, VNC, SSH)   | 4822          |
| **Guacamole**         | Interface web de acesso remoto              | 8080          |
| **Windows Server 2022** | Domain Controller, DNS, LDAP, hMailServer | 3389, 389, 88 |
| **Linux Desktop**     | Desktop Linux para acesso via Guacamole     | 5900 (VNC)    |
| **Cloudflare Tunnel** | Exposição segura via Cloudflare (opcional)  | —             |

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
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────────┐  │   │
│  │  │ AD DS    │  │    DNS       │  │   hMailServer    │  │   │
│  │  │ :389     │  │    :53       │  │   :25, :143      │  │   │
│  │  └──────────┘  └──────────────┘  └──────────────────┘  │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │    KVM (dockurr/windows)                         │   │   │
│  │  │    RDP :3389 | Web UI :8006                      │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
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

# 5. Aguarde o setup completar (5-15 minutos)
# O Windows Server irá reiniciar automaticamente durante a instalação do AD
```

### Tempo Estimado

| Etapa                    | Tempo      |
|--------------------------|------------|
| Download das imagens     | 2-5 min    |
| Boot do Windows Server   | 2-3 min    |
| Instalação do AD (fase 1)| 1-2 min    |
| Reboot                   | 1 min      |
| Configuração (fase 2)    | 3-5 min    |
| Instalação hMailServer   | 1-2 min    |
| **Total**                | **10-18 min** |

### Acessos

| Serviço              | URL / Endpoint                | Credenciais                      |
|----------------------|-------------------------------|----------------------------------|
| Windows RDP          | `localhost:3389`              | `Administrator` / `SenhaForte@2026` |
| Windows Web UI (KVM) | `http://localhost:8006`       | —                                |
| Guacamole Web        | `http://localhost:8080/guacamole/` | Usuário AD + senha         |
| Linux Desktop (VNC)  | `http://localhost:5900`       | `SenhaForte@2026`                |

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
```

- Dados persistentes no volume `mysql_data`
- Health check automático a cada 10s
- Usuário `guacamole_user` com permissão total no banco `guacamole_db`

### Guacamole

O Apache Guacamole fornece acesso remoto a desktops via navegador, sem necessidade de cliente RDP/VNC/SSH.

**Autenticação híbrida**: banco de dados MySQL + consulta LDAP ao Active Directory.

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

Após o ambiente estar no ar, acesse o Guacamole como `guacadmin` (senha padrão: `guacadmin` — **altere imediatamente**) e configure:

1. **Conexões** que serão acessíveis via LDAP:
   - WinLab-Client (RDP → `windows:3389`)
   - Linux-Desktop (VNC → `linux-desktop:5900`)

2. **Permissões** — Associe cada conexão ao grupo `G_Guacamole_Acesso`:
   - Acesse **Settings → Users, Groups & Permissions**
   - Em **Connection Groups**, atribua permissão **READ** ao grupo

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
| hMailServer   | Servidor de email               | 25,143|
| WinRM         | Gerenciamento remoto            | 5985  |
| SMB           | Compartilhamento de arquivos    | 445   |

#### Arquivos de Setup

O diretório `oem/` contém scripts executados automaticamente dentro do Windows na primeira inicialização:

```
oem/
├── setup.ps1              # Script principal (AD + grupos + hMailServer)
└── hMailServer-*.exe      # Instalador do hMailServer (opcional)
```

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
1. Instala a feature AD-Domain-Services
2. Cria a floresta `laboratorio.local`
3. Configura DNS integrado
4. Agenda a Fase 2 via RunOnce
5. Reinicia o servidor

**Fase 2 — Após o reboot:**
1. Verifica se o domínio está operacional
2. Cria as OUs: Usuarios, Grupos, Servidores
3. Cria o grupo `G_Guacamole_Acesso`
4. Habilita WinRM e libera a porta 5985
5. Cria um SMB share `Compartilhado`
6. Instala e configura o hMailServer

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

O **hMailServer** é instalado automaticamente dentro do Windows Server durante o setup.

### Configuração Inicial

Após o setup, acesse o Windows via RDP e configure:

1. Abra **hMailServer Administrator** (Iniciar → hMailServer)
2. Conecte como `Administrator` (senha: `SenhaForte@2026`)
3. Adicione um domínio: **laboratorio.local**
4. Crie contas de email:
   - `admin@laboratorio.local`
   - `contato@laboratorio.local`
5. Configure DNS (registros MX e SPF) se for usar com domínio público

### Portas

| Porta | Protocolo | Uso           |
|-------|-----------|---------------|
| 25    | SMTP      | Envio         |
| 143   | IMAP      | Recebimento   |
| 587   | SMTP TLS  | Envio autenticado (recomendado) |

### Teste de Envio

```powershell
# No Windows Server
Send-MailMessage -From "admin@laboratorio.local" `
                 -To "contato@laboratorio.local" `
                 -Subject "Teste" `
                 -Body "Email funcionando!" `
                 -SmtpServer localhost
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

| Nome               | IP Interno     | Serviço           |
|--------------------|----------------|-------------------|
| `windows`          | 172.19.0.x     | Windows Server    |
| `mysql`            | 172.19.0.x     | MySQL             |
| `guacd`            | 172.19.0.x     | Guacd             |
| `guacamole`        | 172.19.0.x     | Apache Guacamole  |
| `linux-desktop`    | 172.19.0.x     | Linux Desktop     |
| `host.lan`         | 172.30.0.1     | Samba gateway     |

---

## Segurança

### Recomendações

1. **Altere as senhas padrão** — modifique `ADMIN_PASSWORD` no `.env` antes de expor o ambiente
2. **Firewall** — nunca exponha portas administrativas (3389, 8006, 5985) à internet
3. **Cloudflare Tunnel** — prefira o túnel para acesso externo ao Guacamole
4. **TLS** — configure certificados no Guacamole e hMailServer para ambientes produtivos
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

### Guacamole não conecta ao LDAP

```bash
# Verificar se o Windows está acessível
docker exec lab-guacamole nc -zv windows 389

# Verificar logs do Guacamole
docker compose logs guacamole
```

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

- [ ] **Auto-configuração hMailServer** — Script PowerShell para criar domínio e contas automaticamente
- [ ] **TLS/SSL** — Certificados auto-assinados para LDAPS, HTTPS e SMTPS
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
