import Foundation
import SwiftData
import Combine

@MainActor
final class AppRepository: ObservableObject {
    @Published private(set) var revision: Int = 0
    @Published private(set) var lastPersistenceError: String?

    private let context: ModelContext
    private let defaultBreakKeys = ["smoke-1", "lunch", "smoke-2"]

    init(context: ModelContext) {
        self.context = context
        bootstrap()
    }

    var preferences: AppPreferencesSnapshot {
        guard let entity = preferenceEntity() else {
            return AppPreferencesSnapshot(onboardingCompleted: false, workStartDay: nil, notificationsEnabled: false, counterMode: .regular)
        }
        return AppPreferencesSnapshot(
            onboardingCompleted: entity.onboardingCompleted,
            workStartDay: entity.workStartDayRaw.map { DayKey(rawValue: $0) },
            notificationsEnabled: entity.notificationsEnabled,
            counterMode: CounterMode(rawValue: entity.counterModeRaw) ?? .regular
        )
    }

    func earningsContext() -> EarningsContext {
        let configurations = configurationEntities()
            .map(snapshot(from:))
            .sorted(by: { $0.effectiveFrom < $1.effectiveFrom })

        var overrides: [DayKey: DayOverrideSnapshot] = [:]
        for entity in dayOverrideEntities() {
            let snapshot = DayOverrideSnapshot(
                day: DayKey(rawValue: entity.dayRaw),
                isDayOff: entity.isDayOff,
                overtimeMinutes: max(0, entity.overtimeMinutes),
                overtimeMultiplier: MoneyMath.parseDecimal(entity.overtimeMultiplierString) ?? 1
            )
            overrides[snapshot.day] = snapshot
        }

        var rules: [String: NotificationRuleSnapshot] = [:]
        for entity in notificationRuleEntities() {
            guard !entity.breakKey.isEmpty else { continue }
            let snapshot = NotificationRuleSnapshot(
                breakKey: entity.breakKey,
                beforeStartOffsets: parseSet(entity.beforeStartCSV),
                beforeEndOffsets: parseSet(entity.beforeEndCSV),
                customStartOffsets: parseSet(entity.customStartCSV),
                customEndOffsets: parseSet(entity.customEndCSV)
            )
            rules[entity.breakKey] = snapshot
        }

        return EarningsContext(
            configurations: configurations,
            dayOverrides: overrides,
            notificationRules: rules,
            preferences: preferences
        )
    }

    func currentConfiguration(at now: Date = Date()) -> WorkConfigurationSnapshot? {
        let context = earningsContext()
        return EarningsEngine().activeConfiguration(at: now, configurations: context.configurations)
    }

    func completeOnboarding(
        hourlyRate: Decimal,
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        workStartDay: DayKey,
        timeZoneOffsetSeconds: Int
    ) throws {
        guard hourlyRate > 0 else { throw ValidationError.invalidRate }
        try validateShift(startMinute: shiftStartMinute, durationMinutes: shiftDurationMinutes)
        guard let preference = preferenceEntity() else { throw RepositoryError.preferencesUnavailable }

        preference.workStartDayRaw = workStartDay.rawValue
        preference.onboardingCompleted = true

        try upsertWorkConfiguration(
            effectiveFrom: workStartDay,
            hourlyRate: hourlyRate,
            shiftStartMinute: shiftStartMinute,
            shiftDurationMinutes: shiftDurationMinutes,
            timeZoneOffsetSeconds: timeZoneOffsetSeconds,
            breaks: BreakSnapshot.defaults
        )
        try saveAndPublish()
    }

    func saveWorkConfiguration(
        effectiveFrom: DayKey,
        hourlyRate: Decimal,
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        timeZoneOffsetSeconds: Int,
        breaks: [BreakSnapshot]
    ) throws {
        guard hourlyRate > 0 else { throw ValidationError.invalidRate }
        try validateShift(startMinute: shiftStartMinute, durationMinutes: shiftDurationMinutes)
        try validateBreaks(breaks, shiftStartMinute: shiftStartMinute, shiftDurationMinutes: shiftDurationMinutes, timeZoneOffsetSeconds: timeZoneOffsetSeconds, effectiveFrom: effectiveFrom)
        try upsertWorkConfiguration(
            effectiveFrom: effectiveFrom,
            hourlyRate: hourlyRate,
            shiftStartMinute: shiftStartMinute,
            shiftDurationMinutes: shiftDurationMinutes,
            timeZoneOffsetSeconds: timeZoneOffsetSeconds,
            breaks: breaks
        )
        try saveAndPublish()
    }

    func saveWorkSettings(
        workStartDay: DayKey,
        effectiveFrom: DayKey,
        hourlyRate: Decimal,
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        timeZoneOffsetSeconds: Int,
        breaks: [BreakSnapshot]
    ) throws {
        guard hourlyRate > 0 else { throw ValidationError.invalidRate }
        try validateShift(startMinute: shiftStartMinute, durationMinutes: shiftDurationMinutes)
        try validateBreaks(breaks, shiftStartMinute: shiftStartMinute, shiftDurationMinutes: shiftDurationMinutes, timeZoneOffsetSeconds: timeZoneOffsetSeconds, effectiveFrom: effectiveFrom)
        guard let preference = preferenceEntity() else { throw RepositoryError.preferencesUnavailable }
        preference.workStartDayRaw = workStartDay.rawValue
        try upsertWorkConfiguration(
            effectiveFrom: effectiveFrom,
            hourlyRate: hourlyRate,
            shiftStartMinute: shiftStartMinute,
            shiftDurationMinutes: shiftDurationMinutes,
            timeZoneOffsetSeconds: timeZoneOffsetSeconds,
            breaks: breaks
        )
        try saveAndPublish()
    }

    func updateWorkStartDay(_ day: DayKey) throws {
        guard let preference = preferenceEntity() else { throw RepositoryError.preferencesUnavailable }
        preference.workStartDayRaw = day.rawValue
        try saveAndPublish()
    }

    func setCounterMode(_ mode: CounterMode) throws {
        guard let preference = preferenceEntity() else { throw RepositoryError.preferencesUnavailable }
        preference.counterModeRaw = mode.rawValue
        try saveAndPublish()
    }

    func setNotificationsEnabled(_ enabled: Bool) throws {
        guard let preference = preferenceEntity() else { throw RepositoryError.preferencesUnavailable }
        preference.notificationsEnabled = enabled
        try saveAndPublish()
    }

    func dayOverride(for day: DayKey) -> DayOverrideSnapshot {
        if let entity = dayOverrideEntities().first(where: { $0.dayRaw == day.rawValue }) {
            return DayOverrideSnapshot(
                day: day,
                isDayOff: entity.isDayOff,
                overtimeMinutes: entity.overtimeMinutes,
                overtimeMultiplier: MoneyMath.parseDecimal(entity.overtimeMultiplierString) ?? 1
            )
        }
        return DayOverrideSnapshot(day: day, isDayOff: false, overtimeMinutes: 0, overtimeMultiplier: 1)
    }

    func setDayOff(_ isDayOff: Bool, for day: DayKey) throws {
        let current = dayOverride(for: day)
        try saveDayOverride(day: day, isDayOff: isDayOff, overtimeMinutes: current.overtimeMinutes)
    }

    func setOvertime(minutes: Int, for day: DayKey) throws {
        guard minutes >= 0 && minutes <= 24 * 60 else { throw ValidationError.invalidOvertime }
        let current = dayOverride(for: day)
        try saveDayOverride(day: day, isDayOff: current.isDayOff, overtimeMinutes: minutes)
    }

    func notificationRule(for breakKey: String) -> NotificationRuleSnapshot {
        guard let entity = notificationRuleEntities().first(where: { $0.breakKey == breakKey }) else {
            return .empty(for: breakKey)
        }
        return NotificationRuleSnapshot(
            breakKey: breakKey,
            beforeStartOffsets: parseSet(entity.beforeStartCSV),
            beforeEndOffsets: parseSet(entity.beforeEndCSV),
            customStartOffsets: parseSet(entity.customStartCSV),
            customEndOffsets: parseSet(entity.customEndCSV)
        )
    }

    func saveNotificationRule(_ rule: NotificationRuleSnapshot) throws {
        let entity = notificationRuleEntities().first(where: { $0.breakKey == rule.breakKey }) ?? NotificationRuleEntity(breakKey: rule.breakKey)
        if entity.modelContext == nil { context.insert(entity) }
        entity.beforeStartCSV = encodeSet(rule.beforeStartOffsets)
        entity.beforeEndCSV = encodeSet(rule.beforeEndOffsets)
        entity.customStartCSV = encodeSet(rule.customStartOffsets)
        entity.customEndCSV = encodeSet(rule.customEndOffsets)
        try saveAndPublish()
    }

    func applyNotificationRuleToAll(_ source: NotificationRuleSnapshot) throws {
        let keys = Set(currentConfiguration()?.breaks.map(\.stableKey) ?? defaultBreakKeys)
        for key in keys {
            var rule = source
            rule.breakKey = key
            let entity = notificationRuleEntities().first(where: { $0.breakKey == key }) ?? NotificationRuleEntity(breakKey: key)
            if entity.modelContext == nil { context.insert(entity) }
            entity.beforeStartCSV = encodeSet(rule.beforeStartOffsets)
            entity.beforeEndCSV = encodeSet(rule.beforeEndOffsets)
            entity.customStartCSV = encodeSet(rule.customStartOffsets)
            entity.customEndCSV = encodeSet(rule.customEndOffsets)
        }
        try saveAndPublish()
    }

    func resetNotificationRules() throws {
        for entity in notificationRuleEntities() {
            entity.beforeStartCSV = ""
            entity.beforeEndCSV = ""
            entity.customStartCSV = ""
            entity.customEndCSV = ""
        }
        try saveAndPublish()
    }

    private func bootstrap() {
        if preferenceEntity() == nil {
            context.insert(AppPreferenceEntity())
        }
        let existing = Set(notificationRuleEntities().map(\.breakKey))
        for key in defaultBreakKeys where !existing.contains(key) {
            context.insert(NotificationRuleEntity(breakKey: key))
        }
        do {
            try context.save()
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func upsertWorkConfiguration(
        effectiveFrom: DayKey,
        hourlyRate: Decimal,
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        timeZoneOffsetSeconds: Int,
        breaks: [BreakSnapshot]
    ) throws {
        let breakEntities = breaks.sorted(by: { $0.sortOrder < $1.sortOrder }).map { item in
            BreakEntity(
                id: item.id,
                stableKey: item.stableKey,
                name: item.name,
                startMinute: item.startMinute,
                endMinute: item.endMinute,
                isPaid: item.isPaid,
                typeRaw: item.type.rawValue,
                sortOrder: item.sortOrder
            )
        }

        if let existing = configurationEntities().first(where: { $0.effectiveFromRaw == effectiveFrom.rawValue }) {
            let oldBreaks = existing.breaks
            existing.hourlyRateString = MoneyMath.canonicalString(hourlyRate)
            existing.shiftStartMinute = shiftStartMinute
            existing.shiftDurationMinutes = shiftDurationMinutes
            existing.timeZoneOffsetSeconds = timeZoneOffsetSeconds
            existing.breaks = breakEntities
            for old in oldBreaks { context.delete(old) }
        } else {
            context.insert(WorkConfigurationEntity(
                effectiveFromRaw: effectiveFrom.rawValue,
                hourlyRateString: MoneyMath.canonicalString(hourlyRate),
                shiftStartMinute: shiftStartMinute,
                shiftDurationMinutes: shiftDurationMinutes,
                timeZoneOffsetSeconds: timeZoneOffsetSeconds,
                breaks: breakEntities
            ))
        }

        let existingRules = Set(notificationRuleEntities().map(\.breakKey))
        for key in breaks.map(\.stableKey) where !existingRules.contains(key) {
            context.insert(NotificationRuleEntity(breakKey: key))
        }
    }

    private func saveDayOverride(day: DayKey, isDayOff: Bool, overtimeMinutes: Int) throws {
        if !isDayOff && overtimeMinutes == 0 {
            if let existing = dayOverrideEntities().first(where: { $0.dayRaw == day.rawValue }) {
                context.delete(existing)
            }
        } else if let existing = dayOverrideEntities().first(where: { $0.dayRaw == day.rawValue }) {
            existing.isDayOff = isDayOff
            existing.overtimeMinutes = overtimeMinutes
        } else {
            context.insert(DayOverrideEntity(dayRaw: day.rawValue, isDayOff: isDayOff, overtimeMinutes: overtimeMinutes))
        }
        try saveAndPublish()
    }

    private func validateShift(startMinute: Int, durationMinutes: Int) throws {
        guard (0..<24 * 60).contains(startMinute), (1...24 * 60).contains(durationMinutes) else {
            throw ValidationError.invalidShift
        }
    }

    private func validateBreaks(
        _ breaks: [BreakSnapshot],
        shiftStartMinute: Int,
        shiftDurationMinutes: Int,
        timeZoneOffsetSeconds: Int,
        effectiveFrom: DayKey
    ) throws {
        for item in breaks {
            guard (0..<24 * 60).contains(item.startMinute), (0..<24 * 60).contains(item.endMinute), item.startMinute != item.endMinute else {
                throw ValidationError.invalidBreak
            }
        }

        let configuration = WorkConfigurationSnapshot(
            id: UUID(),
            effectiveFrom: effectiveFrom,
            hourlyRate: 1,
            shiftStartMinute: shiftStartMinute,
            shiftDurationMinutes: shiftDurationMinutes,
            timeZoneOffsetSeconds: timeZoneOffsetSeconds,
            breaks: breaks
        )
        let service = WorkScheduleService()
        if breaks.contains(where: { !$0.isPaid && !service.breakIntersectsShift(day: effectiveFrom, break: $0, configuration: configuration) }) {
            throw ValidationError.unpaidBreakOutsideShift
        }
    }

    private func snapshot(from entity: WorkConfigurationEntity) -> WorkConfigurationSnapshot {
        WorkConfigurationSnapshot(
            id: entity.id,
            effectiveFrom: DayKey(rawValue: entity.effectiveFromRaw),
            hourlyRate: MoneyMath.parseDecimal(entity.hourlyRateString) ?? 0,
            shiftStartMinute: entity.shiftStartMinute,
            shiftDurationMinutes: entity.shiftDurationMinutes,
            timeZoneOffsetSeconds: entity.timeZoneOffsetSeconds,
            breaks: entity.breaks.map { item in
                BreakSnapshot(
                    id: item.id,
                    stableKey: item.stableKey,
                    name: item.name,
                    startMinute: item.startMinute,
                    endMinute: item.endMinute,
                    isPaid: item.isPaid,
                    type: BreakType(rawValue: item.typeRaw) ?? .custom,
                    sortOrder: item.sortOrder
                )
            }.sorted(by: { $0.sortOrder < $1.sortOrder })
        )
    }

    private func saveAndPublish() throws {
        do {
            try context.save()
            lastPersistenceError = nil
            revision &+= 1
        } catch {
            context.rollback()
            lastPersistenceError = error.localizedDescription
            throw error
        }
    }

    private func preferenceEntity() -> AppPreferenceEntity? {
        do {
            return try context.fetch(FetchDescriptor<AppPreferenceEntity>()).first
        } catch {
            lastPersistenceError = error.localizedDescription
            return nil
        }
    }

    private func configurationEntities() -> [WorkConfigurationEntity] {
        do { return try context.fetch(FetchDescriptor<WorkConfigurationEntity>()) }
        catch { lastPersistenceError = error.localizedDescription; return [] }
    }

    private func dayOverrideEntities() -> [DayOverrideEntity] {
        do { return try context.fetch(FetchDescriptor<DayOverrideEntity>()) }
        catch { lastPersistenceError = error.localizedDescription; return [] }
    }

    private func notificationRuleEntities() -> [NotificationRuleEntity] {
        do { return try context.fetch(FetchDescriptor<NotificationRuleEntity>()) }
        catch { lastPersistenceError = error.localizedDescription; return [] }
    }

    private func parseSet(_ csv: String) -> Set<Int> {
        Set(csv.split(separator: ",").compactMap { Int($0) }.filter { $0 >= 0 && $0 <= 720 })
    }

    private func encodeSet(_ values: Set<Int>) -> String {
        values.sorted().map(String.init).joined(separator: ",")
    }
}

enum ValidationError: LocalizedError {
    case invalidRate
    case invalidShift
    case invalidOvertime
    case invalidBreak
    case unpaidBreakOutsideShift
    case invalidNotificationOffset

    var errorDescription: String? {
        switch self {
        case .invalidRate: return "Ставка должна быть больше нуля."
        case .invalidShift: return "Длительность смены должна быть от 1 минуты до 24 часов, а время начала — корректным."
        case .invalidOvertime: return "Переработка должна быть от 0 до 24 часов."
        case .invalidBreak: return "Проверьте время начала и окончания перерыва."
        case .unpaidBreakOutsideShift: return "Неоплачиваемый перерыв полностью находится вне смены. Измените перерыв или границы смены."
        case .invalidNotificationOffset: return "Интервал уведомления должен быть от 1 до 720 минут."
        }
    }
}

enum RepositoryError: LocalizedError {
    case preferencesUnavailable

    var errorDescription: String? {
        switch self {
        case .preferencesUnavailable: return "Локальные настройки временно недоступны."
        }
    }
}
