# ShiftEarnings — отчёт финальной проверки

Дата проверки: 24 сентября 2026.

## Что проверено автоматически

- Все 32 Swift-файла проекта (`27` app + `5` tests) проходят `swiftc -frontend -parse` на Swift 6.2.1.
- Чистое доменное ядро (`EarningsEngine`, `WorkScheduleService`, `NotificationPlanBuilder`, модели и utilities) собирается как отдельный Swift-модуль.
- 32 исполняемых unit-теста доменного ядра проходят: **32/32, 0 failures**.
- В Xcode test target всего **40 XCTest-сценариев**. Дополнительно оба `NotificationSchedulerTests` проходят в отдельном Swift harness с API-совместимыми stubs `UserNotifications`: **2/2, 0 failures**. Шесть SwiftData/app-module тестов (`5` persistence + `1` dashboard) требуют Apple SDK.
- `project.pbxproj` проходит `plutil -lint`.
- Shared scheme XML корректно разбирается.
- В `project.pbxproj` 108 уникальных object ID, отсутствующих ссылок нет.
- Все 27 app Swift-файлов и все 5 test Swift-файлов присутствуют в Xcode project references/targets.
- Deployment target: iOS 17.0.
- Info.plist генерируется Xcode; display name, category, launch screen и portrait orientation заданы build settings.
- App icon asset catalog валиден: все указанные PNG существуют, имеют ожидаемые размеры и не содержат alpha-канал.
- Сторонних Swift Package dependencies нет.
- В Swift-исходниках нет незавершённых маркеров или аварийных заглушек.
- В приложении нет `UserDefaults` как хранилища бизнес-данных и не обнаружены SDK аналитики/рекламы.
- Единственные два места использования `URLSession` находятся в `TimeVerificationService.swift`; обычный запуск не инициирует сеть.

## Что покрывают исполняемые тесты

- начисление до/во время/после смены;
- оплачиваемый перекур;
- неоплачиваемый обед и возобновление начисления;
- объединение пересекающихся неоплачиваемых интервалов;
- выходной и выходной с переработкой;
- обычный день с переработкой;
- effective-dated смена ставки;
- сумма месяца и нижняя граница «За всё время»;
- ночная смена через полночь;
- live shift-anchor предыдущего календарного дня после полуночи;
- after-midnight notification carry-over для активной ночной смены;
- касание границы перерыва без положительного overlap;
- latest-request-wins при конкурентных reschedule;
- рабочий UTC+9 независимо от системного часового пояса;
- округление копеек;
- master notification switch;
- несколько и custom-интервалы;
- reset правил;
- выходные без уведомлений;
- отсутствие дубликатов;
- изменение времени перерыва;
- start/end правила обеда;
- дата начала работы;
- ограничение rolling window до 56 pending requests.

## Ограничение этой среды

Среда сборки — Linux со Swift 6.2.1. В ней отсутствуют Xcode, iOS SDK, SwiftUI/SwiftData/UIKit runtime и `xcodebuild`. Поэтому здесь нельзя выполнить окончательную iOS compiler/linker/code-signing сборку, запустить приложение в iPhone Simulator или исполнить 6 SwiftData/app-module integration-тестов. Настоящий disk-backed SwiftData test уже добавлен в Xcode target, но его выполнение требует Apple SwiftData runtime.

Для окончательной Apple-platform проверки откройте `ShiftEarnings.xcodeproj` в Xcode и выполните **Product → Test**, затем **Product → Build**. Для физического iPhone потребуется выбрать свою Apple Developer Team и уникальный Bundle Identifier; секретные ключи/сертификаты в проект не включены.
