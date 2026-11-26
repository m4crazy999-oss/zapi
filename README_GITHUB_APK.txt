Zapi Android — Pacote pronto para GitHub Actions -> APK

Como gerar seu APK no GitHub:
1. Extraia TODO o conteudo deste ZIP na raiz do seu repositorio GitHub
   (a pasta .github/workflows/build-apk.yml precisa ficar na raiz).
2. No repositorio do GitHub:
   - Settings > Secrets and variables > Actions: cadastre os 5 Secrets
     (GOOGLE_SERVICES_JSON_BASE64, ANDROID_KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD).
   - Settings > Actions > General > Workflow permissions: marque "Read and write permissions".
3. Envie os arquivos para a branch "main" (git push origin main).
4. Acompanhe em Actions > "Build Zapi Android APK" e baixe o APK em Artifacts ou Releases.
