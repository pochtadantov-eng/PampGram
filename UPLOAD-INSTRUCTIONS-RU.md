# Загрузка новой сборки

Этот пакет подготовлен для замены содержимого текущего репозитория PampGram.

Что сделать на GitHub:
1. Сохраните старую ветку/коммит на случай отката.
2. Загрузите содержимое этого архива в корень репозитория (не саму папку PampGram-new-build).
3. Убедитесь, что присутствуют:
   - .github/workflows/build-ipa.yml
   - mod/telegram-ios.patch
   - mod/telegram-ios-features.patch
   - mod/components/
4. Сделайте Commit changes.
5. Откройте Actions → Build IPA (device, fake-signed) → Run workflow.
6. После успешной сборки скачайте артефакт PampGram-ipa.

Важно: workflow применяет основной патч, затем патч первых шести функций и копирует новые Bazel-компоненты.
