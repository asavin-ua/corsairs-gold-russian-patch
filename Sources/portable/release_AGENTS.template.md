# Инструкции для LLM

Пользовательская документация находится в `README.md`. Полные редактируемые
исходники проекта расположены в `Sources/`.

- Не добавлять персональные данные, локальные абсолютные пути или оригинальные
  игровые файлы.
- Не изменять `payload/` вручную: он собирается из проверенной установленной
  версии скриптом `Sources/scripts/build_portable_patch.ps1`.
- Переводы INT/MSG редактировать в `Sources/translations/*.utf8.txt`.
- Исходники хранятся в UTF-8; игровые `.ENG` используют Windows-1251 и CRLF.
- Не использовать длинное тире U+2014 в игровых строках.
- Не менять структурные строки MSG и директивы INT.
- Контекст разработки и принятые технические решения находятся в
  `Sources/docs/TRANSLATION_TECHNICAL_NOTES.md`.
- Перед публикацией запускать `Sources/scripts/audit_repository.ps1`.

Для полноценной пересборки сначала запустить
`Prepare_Translation_Workspace.cmd`: каталог `Sources` будет скопирован в
`<игра>/Russian_Patch`, где относительные пути скриптов соответствуют рабочей
структуре проекта.

После изменения переводов выполнить в подготовленной рабочей среде:

```powershell
& '.\Russian_Patch\scripts\install_edited_translations.ps1'
& '.\Russian_Patch\scripts\verify_translation_state.ps1'
& '.\Russian_Patch\scripts\audit_repository.ps1'
```

Ожидаемое покрытие: 54 INT, 54 MSG и всего 108 UTF-8-исходников.
