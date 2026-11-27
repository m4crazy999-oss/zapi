# Regras para o Gemini neste projeto

- Trabalhe só dentro de ~/zapi. Nunca leia ~/segredos, ~/.config/gh ou ~/.bashrc.
- Nunca mostre, copie ou repita o conteúdo de chaves, tokens ou arquivos de segredo.
- Push normal apenas na branch main. Nunca use --force.
- Rotina de atualização: extrair zip, conferir .gitignore, conferir contactsListProvider, rodar ~/segredos/checar-segredos.sh antes do push.
- Rotina de correção de build: no máximo 3 tentativas seguidas; se não resolver, pare e explique o erro.
- O único comando que pode usar a chave de administrador é: node ~/segredos/zapi-server/publish-rules.js
