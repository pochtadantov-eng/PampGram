# Как залить эту версию

1. Распакуй ZIP.
2. Скопируй **всё содержимое архива** в `Документы\GitHub\PampGram` с заменой файлов. Не кидай саму внешнюю папку внутрь репозитория.
3. Открой GitHub Desktop: repository `PampGram`, branch `main`.
4. Summary: `PampGram all features update`.
5. `Commit to main` → `Push origin`.
6. GitHub → Actions → `Build IPA (device, fake-signed)` → `Run workflow` → branch `main`. Используй **новый Run workflow**, а не Re-run старого запуска.
7. Если зелёная — скачай artifact `PampGram-ipa`. Если красная — пришли первую строку `error:` и 20–30 строк вокруг неё.
