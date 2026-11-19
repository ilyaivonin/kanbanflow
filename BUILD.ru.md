# Сборка KanbanFlow

Эта инструкция описывает сборку, запуск и устранение неполадок
macOS-приложения.

**English version:** [BUILD.md](BUILD.md)

---

## 1. Требования

- macOS 12 Monterey или новее.
- Xcode Command Line Tools. Полная установка Xcode не требуется.
- Интернет на этапе сборки **не нужен**.

Установите инструменты один раз:

```bash
xcode-select --install
```

Проверьте компилятор:

```bash
swiftc --version
```

Вы должны увидеть версию Apple Swift. Если появляется ошибка
`xcrun: error: unable to find utility clang`, выполните:

```bash
sudo xcode-select --switch /Library/Developer/CommandLineTools
```

## 2. Получение исходников

```bash
git clone https://github.com/ilyaivonin/kanbanflow
cd kanbanflow
```

Если вы скачали ZIP-архив, распакуйте его и откройте папку в Терминале.

## 3. Сборка приложения

Из корня репозитория:

```bash
chmod +x macos/build.sh macos/make-icon.sh
./macos/build.sh
```

Скрипт:

1. компилирует `macos/main.swift` через `swiftc`;
2. создаёт `dist/KanbanFlow.app`;
3. копирует `kanban.html`, `Info.plist` и `assets/AppIcon.icns` внутрь bundle;
4. ставит ad-hoc подпись, достаточную для локального запуска.

Ожидаемый вывод:

```text
Compiling native shell for arm64...
Built: /path/to/kanbanflow/dist/KanbanFlow.app
Run:   open "/path/to/kanbanflow/dist/KanbanFlow.app"
```

Архитектура определяется автоматически через `uname -m`. Чтобы собрать
приложение под конкретную архитектуру явно:

```bash
KANBANFLOW_ARCH=x86_64 ./macos/build.sh
# или
KANBANFLOW_ARCH=arm64 ./macos/build.sh
```

Скрипт создаёт сборку только под одну архитектуру. Для universal binary нужно
собрать обе версии и объединить их через `lipo`; автоматически это не делается.

## 4. Запуск

```bash
open dist/KanbanFlow.app
```

Либо дважды щёлкните `dist/KanbanFlow.app` в Finder. Чтобы приложение появилось
в Launchpad, переместите его в `/Applications`.

При первом запуске macOS автоматически создаёт базу:

```text
~/Library/Application Support/KanbanFlow/kanbanflow.sqlite
```

Пересборка приложения не изменяет ваши данные.

## 5. Проверка сборки

Запустите встроенный самотест базы:

```bash
./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow --selftest
```

Он использует временный файл SQLite, проверяет нормализованные таблицы и печатает
JSON-отчёт:

```json
{
  "appName": "Self Test",
  "backupRecorded": true,
  "boards": 1,
  "cards": 1,
  "columns": 2,
  "loadedMatches": true,
  "separators": 1
}
```

Чтобы запустить приложение с отдельной базой (удобно для тестов):

```bash
KANBANFLOW_DB_PATH=/tmp/kanbanflow-test.sqlite \
  ./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow
```

Основная база при этом не затрагивается.

## 6. Пересборка после изменений

- `kanban.html` — интерфейс и логика приложения.
- `macos/main.swift` — нативная оболочка, схема SQLite и мост WebKit.
- `macos/Info.plist` — метаданные bundle и версия.
- `assets/icon.png` — исходник иконки.

После правок повторите:

```bash
./macos/build.sh
open dist/KanbanFlow.app
```

Отдельной сборки фронтенда нет: HTML-файл копируется в app bundle как есть.
Если изменить `kanban.html` и не пересобрать приложение, оно продолжит
использовать старую копию внутри bundle.

## 7. Пересоздание иконки

`assets/AppIcon.icns` уже лежит в репозитории, поэтому обычной сборке не нужно
его создавать. После замены `assets/icon.png` (квадратный PNG, желательно
1024×1024):

```bash
./macos/make-icon.sh assets/icon.png
./macos/build.sh
```

Скрипт проверяет, что изображение квадратное, генерирует все нужные размеры
iconset и запускает `iconutil`. Если Finder показывает старую иконку,
переместите приложение в другую папку или выполните:

```bash
touch dist/KanbanFlow.app
```

macOS агрессивно кеширует иконки.

## 8. Подпись и распространение

`build.sh` ставит **ad-hoc** подпись (`codesign --sign -`). Этого достаточно для
запуска на машине, где приложение собрано. Для раздачи другим людям нужна
подпись Developer ID.

Если Gatekeeper блокирует скачанное приложение:

- правый клик по приложению → **Открыть** → **Открыть**; либо
- разрешите запуск в **Системные настройки → Конфиденциальность и безопасность**
  → **Всё равно открыть**; либо
- снимите атрибут карантина:

  ```bash
  xattr -dr com.apple.quarantine /path/to/KanbanFlow.app
  ```


## 9. Изменение идентификатора bundle

Перед публикацией форка обновите:

- `CFBundleIdentifier` в `macos/Info.plist` (например,
  `com.example.kanbanflow`);
- `CFBundleName` / `CFBundleDisplayName`, если нужно другое имя bundle;
- `APP_NAME` в `macos/build.sh`, если должно измениться имя исполняемого файла.

Видимое имя приложения меняется во время работы в **Настройках**. Это влияет на
шапку, заголовок окна и резервные копии, но не на идентификатор bundle.

## 10. Данные, бэкапы и сброс

Основная база:

```text
~/Library/Application Support/KanbanFlow/kanbanflow.sqlite
```

Чтобы начать с чистой базы, сохранив старые данные:

```bash
# Сначала закройте KanbanFlow
mv "$HOME/Library/Application Support/KanbanFlow" \
   "$HOME/Library/Application Support/KanbanFlow.backup"
open dist/KanbanFlow.app
```

Чтобы удалить всё безвозвратно:

```bash
rm -rf "$HOME/Library/Application Support/KanbanFlow"
```

Перед удалением сделайте **Настройки → Backup to File**. В таблице `backups`
хранятся последние 20 снимков, созданных при экспорте/импорте, но они находятся
в том же файле базы.

## 11. Устранение неполадок

| Симптом | Причина / решение |
| --- | --- |
| `swiftc: command not found` | Установите Xcode Command Line Tools: `xcode-select --install` |
| `xcrun: error: unable to find utility clang` | Укажите каталог CLT: `sudo xcode-select --switch /Library/Developer/CommandLineTools` |
| Сборка не проходит на старой macOS | Цель сборки — macOS 12.0; обновите macOS или измените `-target` в `macos/build.sh` |
| Приложение открывается с пустым окном | Проверьте структуру: `kanban.html` должен лежать в корне и копироваться через `build.sh` |
| Изменения интерфейса не видны | Пересоберите: `./macos/build.sh` |
| Заголовок окна не меняется после переименования | Используйте **Настройки** в приложении (или `Cmd+,`); заголовок обновляется через нативный мост |
| `database is locked` | Закройте все экземпляры KanbanFlow и откройте приложение заново |
| Нужны логи сборки и запуска | Запустите бинарник из Терминала: `./dist/KanbanFlow.app/Contents/MacOS/KanbanFlow` |

## 12. Что создаёт сборка

```text
dist/
└── KanbanFlow.app/
    └── Contents/
        ├── Info.plist
        ├── MacOS/KanbanFlow
        ├── PkgInfo
        ├── Resources/kanban.html
        └── Resources/AppIcon.icns
```

