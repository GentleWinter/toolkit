# 🧰 Dev Toolkit (.NET + Linux)

Este repositório contém alguns scripts e configurações que utilizo no dia a dia como desenvolvedor .NET em ambiente Linux, com foco em produtividade e automação de tarefas repetitivas.

## 📦 Conteúdo

- `run-tests.sh` → Script para execução automática de testes em projetos .NET
- `migrate.sh` → Script para criação e aplicação de migrations com Entity Framework
- `.bashrc` → Modelo de configuração do terminal com aliases e funções úteis

---

## ⚙️ Como configurar

### 1. Scripts

Os scripts devem estar localizados no diretório `home` do usuário para funcionar corretamente com os aliases definidos no `.bashrc`.

Exemplo:

```bash
~/scripts/run-tests.sh
~/scripts/migrate.sh
